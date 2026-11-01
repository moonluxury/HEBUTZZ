"""Install the tested draw module and wallet entry with verified backup and automatic code rollback."""
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
PYTHON = '/opt/hegong/venv/bin/python'
PROTECTED = {'/etc/nginx/sites-available/hegong', '/etc/systemd/system/hegong-backend.service', '/etc/hegong/backend.env'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def install(source, target):
    stat = target.stat() if target.exists() else None
    temporary = target.with_name(target.name + '.card-draw-new')
    shutil.copyfile(source, temporary)
    temporary.chmod(stat.st_mode & 0o777 if stat else 0o644)
    if stat: os.chown(temporary, stat.st_uid, stat.st_gid)
    os.replace(temporary, target)


def wait_healthy():
    for attempt in range(40):
        try:
            for path, key, expected in [('/health', 'status', 'ok'), ('/v1/articles', 'ok', True)]:
                with urllib.request.urlopen('http://127.0.0.1:8000' + path, timeout=3) as response:
                    if json.load(response).get(key) != expected:
                        raise RuntimeError('Unexpected health response')
            return
        except Exception:
            time.sleep(.5)
    raise RuntimeError('Service failed readiness checks')


def database_state():
    code = """import json,psycopg
with psycopg.connect('dbname=hegong user=hegong host=/var/run/postgresql') as c:
 print(json.dumps({'users':c.execute('SELECT count(*) FROM users').fetchone()[0],
 'schema_versions':[r[0] for r in c.execute('SELECT version FROM schema_versions ORDER BY version')]}))
"""
    result = subprocess.run(['runuser', '-u', 'hegong', '--', PYTHON, '-c', code], capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--apply', action='store_true', required=True)
    args = parser.parse_args()
    assert os.geteuid() == 0
    os.umask(0o077)
    candidate = args.candidate.resolve()
    assert candidate.is_relative_to('/opt/hegong/releases')
    manifest_path = candidate / 'card-draw-release.json'
    manifest = json.loads(manifest_path.read_text())
    assert set(manifest['files']) == {'wallet_service.py', 'card_draw_service.py'}
    assert set(manifest['protected_sha256']) == PROTECTED
    receipt = json.loads((candidate / 'tests-passed.json').read_text())
    assert receipt['passed'] is True and receipt['manifest_sha256'] == digest(manifest_path)
    assert receipt['database'].startswith('hegong_draw_') and receipt['database'].endswith('_test')
    with open('/run/lock/hegong-deploy.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for name, value in manifest['candidate_sha256'].items():
            assert (candidate / name).resolve().is_relative_to(candidate)
            assert digest(candidate / name) == value, 'Candidate changed: ' + name

        def verify_baseline(updated=False):
            for name, original in manifest['baseline_sha256'].items():
                assert (TARGET / name).resolve().is_relative_to(TARGET)
                expected = manifest['files'].get(name, original) if updated else original
                actual = digest(TARGET / name) if (TARGET / name).exists() else None
                assert actual == expected, 'Production file changed: ' + name
            for name, value in manifest['protected_sha256'].items():
                assert digest(Path(name)) == value, 'Protected configuration changed'

        verify_baseline()
        before = database_state()
        backup = Path('/var/backups/hegong') / ('card-draw-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
        backup.mkdir(mode=0o700)
        with (backup / 'database.dump').open('wb') as stream:
            subprocess.run(['runuser', '-u', 'hegong', '--', 'pg_dump', '-Fc', 'hegong'], stdout=stream, check=True)
        subprocess.run(['pg_restore', '--list', str(backup / 'database.dump')], stdout=subprocess.DEVNULL, check=True)
        for name in manifest['files']:
            if (TARGET / name).exists(): shutil.copy2(TARGET / name, backup / name)
        shutil.copy2(manifest_path, backup / 'card-draw-release.json')
        shutil.copy2(candidate / 'tests-passed.json', backup / 'tests-passed.json')
        (backup / 'before.json').write_text(json.dumps(before))
        verify_baseline()
        installed = []
        try:
            for name in sorted(manifest['files']):
                install(candidate / name, TARGET / name)
                installed.append(name)
            subprocess.run(['systemctl', 'restart', 'hegong-backend'], check=True)
            wait_healthy()
            subprocess.run([PYTHON, str(candidate / 'ops/smoke_card_draw_release.py'),
                            '--output', str(backup / 'https')], check=True, timeout=180)
            verify_baseline(updated=True)
            after = database_state()
            assert after['schema_versions'] == before['schema_versions'], 'Unexpected schema migration'
        except Exception:
            if installed:
                for name in installed:
                    assert digest(TARGET / name) == manifest['files'][name], 'Concurrent edit prevents automatic rollback'
                    if (backup / name).exists(): install(backup / name, TARGET / name)
                    else: (TARGET / name).unlink()
                subprocess.run(['systemctl', 'restart', 'hegong-backend'], check=True)
                wait_healthy()
            (backup / 'activation.json').write_text(json.dumps({'status': 'rolled_back', 'backup': str(backup)}))
            # Never replace the database over concurrent real-user writes.
            raise
        result = {'status': 'activated', 'backup': str(backup), 'files': sorted(manifest['files']),
                  'schema_change': False, 'before': before, 'after': after,
                  'guarded_files': len(manifest['baseline_sha256']) - len(manifest['files']),
                  'https': json.loads((backup / 'https/https-checks.json').read_text())}
        (backup / 'activation.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result))


if __name__ == '__main__':
    main()
