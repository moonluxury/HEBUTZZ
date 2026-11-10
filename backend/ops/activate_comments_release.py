"""Activate a tested comments-only release; pin the server baseline and keep rollback copies.

Run as root on the application host, after candidate tests have passed in a *_test DB.
This script never replaces credentials, nginx configuration or unrelated application files.
"""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import urllib.request

TARGET = Path('/opt/hegong/backend')
FILES = {'app.py', 'domain.py', 'database.py', 'comment_service.py', 'migrations/003_bank_comments.sql'}


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def healthy():
    try:
        with urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3) as response:
            if json.load(response).get('status') != 'ok': return False
        payload = {'version': 1, 'action': 'comment_list', 'payload': {'target_type':'bank','target_id':'marxism','limit':1}}
        request = urllib.request.Request('http://127.0.0.1:8000/v1/comments/query', data=json.dumps(payload).encode(), headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(request, timeout=3) as response: return json.load(response).get('ok') is True
    except Exception: return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--apply', action='store_true', required=True)
    args = parser.parse_args()
    assert os.geteuid() == 0
    os.umask(0o077)
    candidate = args.candidate.resolve()
    assert candidate.is_relative_to('/opt/hegong/releases')
    manifest = json.loads((candidate / 'comments-release.json').read_text())
    assert set(manifest['files']) == FILES
    assert set(manifest['baseline_sha256']) == {'app.py','domain.py','database.py'}
    with open('/run/lock/hegong-comments-deploy.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for name, expected in manifest['files'].items():
            assert (candidate / name).resolve().is_relative_to(candidate)
            assert digest(candidate / name) == expected, f'Candidate mismatch: {name}'
        def verify_baseline():
            for name, expected in manifest['baseline_sha256'].items():
                assert digest(TARGET / name) == expected, f'Server changed since review: {name}'
            for name in FILES - set(manifest['baseline_sha256']):
                assert not (TARGET / name).exists(), f'New target already exists: {name}'
        verify_baseline()
        stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        backup = Path('/var/backups/hegong') / ('comments-' + stamp)
        backup.mkdir(mode=0o700)
        with (backup / 'database.dump').open('wb') as output:
            subprocess.run(['runuser','-u','hegong','--','pg_dump','-Fc','hegong'], stdout=output, check=True)
        subprocess.run(['pg_restore','--list',str(backup / 'database.dump')], stdout=subprocess.DEVNULL, check=True)
        for name in manifest['baseline_sha256']: shutil.copy2(TARGET / name, backup / name)
        shutil.copy2(candidate / 'comments-release.json', backup / 'comments-release.json')
        verify_baseline()
        installed = []
        try:
            for name in sorted(FILES):
                target = TARGET / name
                if not target.parent.exists():
                    target.parent.mkdir(mode=0o755)
                    target.parent.chmod(0o755)
                temporary = target.with_name(target.name + '.comments-new')
                shutil.copyfile(candidate / name, temporary)
                temporary.chmod(0o644)
                os.replace(temporary, target)
                installed.append(name)
            subprocess.run(['systemctl','restart','hegong-backend'], check=True)
            for _ in range(30):
                if healthy(): break
                time.sleep(0.5)
            else: raise RuntimeError('Post-activation comment route health check failed')
        except Exception:
            # The migration only adds tables. Keep it in place on rollback; never
            # restore the whole production database over newer user writes.
            for name in installed:
                target = TARGET / name
                assert digest(target) == manifest['files'][name], f'Concurrent update prevents automatic rollback: {name}'
                if (backup / name).exists(): shutil.copy2(backup / name, target)
                else: target.unlink()
            subprocess.run(['systemctl','restart','hegong-backend'], check=True)
            raise
        print(json.dumps({'status':'activated','backup':str(backup),'files':sorted(FILES)}))


if __name__ == '__main__': main()
