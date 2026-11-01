"""Install one tested runtime file with verified backup and automatic code rollback."""
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
    stat = target.stat()
    temporary = target.with_name(target.name + '.public-profile-new')
    shutil.copyfile(source, temporary)
    temporary.chmod(stat.st_mode & 0o777)
    os.chown(temporary, stat.st_uid, stat.st_gid)
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
    manifest_path = candidate / 'public-profile-release.json'
    manifest = json.loads(manifest_path.read_text())
    assert set(manifest['files']) == {'domain.py'}
    assert set(manifest['protected_sha256']) == PROTECTED
    receipt = json.loads((candidate / 'tests-passed.json').read_text())
    assert receipt['passed'] is True and receipt['manifest_sha256'] == digest(manifest_path)
    assert receipt['database'].startswith('hegong_profile_') and receipt['database'].endswith('_test')
    with open('/run/lock/hegong-deploy.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for name, value in manifest['candidate_sha256'].items():
            assert (candidate / name).resolve().is_relative_to(candidate)
            assert digest(candidate / name) == value, 'Candidate changed: ' + name

        def verify_baseline(updated=False):
            for name, original in manifest['baseline_sha256'].items():
                assert (TARGET / name).resolve().is_relative_to(TARGET)
                expected = manifest['files'].get(name, original) if updated else original
                assert digest(TARGET / name) == expected, 'Production file changed: ' + name
            for name, value in manifest['protected_sha256'].items():
                assert digest(Path(name)) == value, 'Protected configuration changed'

        verify_baseline()
        before = database_state()
        backup = Path('/var/backups/hegong') / ('public-profile-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
        backup.mkdir(mode=0o700)
        with (backup / 'database.dump').open('wb') as stream:
            subprocess.run(['runuser', '-u', 'hegong', '--', 'pg_dump', '-Fc', 'hegong'], stdout=stream, check=True)
        subprocess.run(['pg_restore', '--list', str(backup / 'database.dump')], stdout=subprocess.DEVNULL, check=True)
        shutil.copy2(TARGET / 'domain.py', backup / 'domain.py')
        shutil.copy2(manifest_path, backup / 'public-profile-release.json')
        shutil.copy2(candidate / 'tests-passed.json', backup / 'tests-passed.json')
        (backup / 'before.json').write_text(json.dumps(before))
        verify_baseline()
        installed = False
        try:
            install(candidate / 'domain.py', TARGET / 'domain.py')
            installed = True
            subprocess.run(['systemctl', 'restart', 'hegong-backend'], check=True)
            wait_healthy()
            subprocess.run([PYTHON, str(candidate / 'ops/smoke_public_profile_release.py'),
                            '--output', str(backup / 'https')], check=True, timeout=180)
            verify_baseline(updated=True)
            after = database_state()
            assert after['schema_versions'] == before['schema_versions'], 'Unexpected schema migration'
        except Exception:
            if installed:
                assert digest(TARGET / 'domain.py') == manifest['files']['domain.py'], 'Concurrent edit prevents automatic rollback'
                install(backup / 'domain.py', TARGET / 'domain.py')
                subprocess.run(['systemctl', 'restart', 'hegong-backend'], check=True)
                wait_healthy()
            (backup / 'activation.json').write_text(json.dumps({'status': 'rolled_back', 'backup': str(backup)}))
            # Never replace the database over concurrent real-user writes.
            raise
        result = {'status': 'activated', 'backup': str(backup), 'files': ['domain.py'],
                  'schema_change': False, 'before': before, 'after': after,
                  'guarded_files': len(manifest['baseline_sha256']) - 1,
                  'https': json.loads((backup / 'https/https-checks.json').read_text())}
        (backup / 'activation.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result))


if __name__ == '__main__':
    main()
