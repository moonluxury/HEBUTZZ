"""Activate a tested, narrowly scoped retention release with baseline guards."""
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
SYSTEMD = Path('/etc/systemd/system')
UNITS = ('hegong-friend-requests.service', 'hegong-friend-requests.timer')
FILES = {
    'domain.py', 'friend_request_retention.py', 'migrations/007_friend_request_retention.sql',
    'ops/cleanup_friend_requests.py', 'ops/hegong-friend-requests.service',
    'ops/hegong-friend-requests.timer', 'tests/test_friend_request_retention.py',
    'FRIEND_REQUEST_RETENTION.md',
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def install(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + '.retention-new')
    shutil.copyfile(source, temporary)
    temporary.chmod(0o644)
    os.replace(temporary, target)


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def healthy():
    for _ in range(40):
        try:
            with urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3) as response:
                if json.load(response).get('status') == 'ok':
                    return
        except Exception:
            pass
        time.sleep(0.5)
    raise RuntimeError('Backend readiness failed')


def counts():
    sql = """SELECT json_build_object(
      'requests', (SELECT count(*) FROM friend_requests),
      'expired', (SELECT count(*) FROM friend_requests WHERE created_at<=clock_timestamp()-interval '72 hours'),
      'friendships', (SELECT count(*) FROM relationships WHERE friends),
      'ordinary_messages', (SELECT count(*) FROM messages WHERE kind='text'),
      'legacy_receipts', (SELECT count(*) FROM operations WHERE action IN ('request_friend','respond_request')
           AND NOT response @> '{"_friend_receipt":1}'::jsonb))"""
    return json.loads(run('runuser', '-u', 'hegong', '--', 'psql', '-XAt', '-d', 'hegong', '-c', sql,
                          capture_output=True, text=True).stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--apply', action='store_true', required=True)
    args = parser.parse_args()
    assert os.geteuid() == 0
    os.umask(0o077)
    candidate = args.candidate.resolve()
    assert candidate.is_relative_to('/opt/hegong/releases')
    manifest_path = candidate / 'retention-release.json'
    manifest = json.loads(manifest_path.read_text())
    receipt = json.loads((candidate / 'tests-passed.json').read_text())
    assert receipt['passed'] and receipt['tests'] == 38
    assert receipt['database'] == 'hegong_friend_retention_20261104_test'
    assert receipt['manifest_sha256'] == digest(manifest_path)
    assert set(manifest['files']) == set(manifest['baseline']) == FILES
    with open('/run/lock/hegong-deploy.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for name, expected in manifest['candidate_sha256'].items():
            assert (candidate / name).resolve().is_relative_to(candidate)
            assert digest(candidate / name) == expected, 'Tested candidate changed: ' + name

        def verify_baseline():
            for name, expected in {**manifest['baseline'], **manifest['guards']}.items():
                assert (TARGET / name).resolve().is_relative_to(TARGET)
                assert digest(TARGET / name) == expected, 'Live source changed: ' + name
            for unit in UNITS:
                assert not (SYSTEMD / unit).exists(), 'Existing timer must not be overwritten'
            assert sorted(p.name for p in (TARGET / 'migrations').glob('*.sql')) == manifest['migration_names']

        verify_baseline()
        backup = Path('/var/backups/hegong') / ('friend-retention-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
        backup.mkdir(mode=0o700)
        with (backup / 'database.dump').open('wb') as stream:
            run('runuser', '-u', 'hegong', '--', 'pg_dump', '-Fc', 'hegong', stdout=stream)
        run('pg_restore', '--list', str(backup / 'database.dump'), stdout=subprocess.DEVNULL)
        for name, expected in manifest['baseline'].items():
            if expected is not None:
                (backup / name).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(TARGET / name, backup / name)
        shutil.copy2(manifest_path, backup / manifest_path.name)
        shutil.copy2(candidate / 'tests-passed.json', backup / 'tests-passed.json')
        before = counts()
        (backup / 'counts-before.json').write_text(json.dumps(before))
        verify_baseline()
        installed, installed_units = [], []
        try:
            for name in sorted(FILES):
                install(candidate / name, TARGET / name)
                installed.append(name)
            run('systemctl', 'restart', 'hegong-backend.service')
            healthy()
            for unit in UNITS:
                install(candidate / 'ops' / unit, SYSTEMD / unit)
                installed_units.append(unit)
            run('systemd-analyze', 'verify', *(str(SYSTEMD / unit) for unit in UNITS))
            run('systemctl', 'daemon-reload')
            run('systemctl', 'enable', '--now', UNITS[1])
            run('systemctl', 'start', UNITS[0])
            run('systemctl', 'is-active', '--quiet', UNITS[1])
            run('systemctl', 'is-enabled', '--quiet', UNITS[1])
            assert run('systemctl', 'show', '-p', 'Result', '--value', UNITS[0], capture_output=True, text=True).stdout.strip() == 'success'
            for endpoint, key, value in [('/health', 'status', 'ok'), ('/v1/articles', 'ok', True)]:
                with urllib.request.urlopen('https://39.107.44.18' + endpoint, timeout=10) as response:
                    assert json.load(response).get(key) == value
            for name, expected in {**manifest['files'], **manifest['guards']}.items():
                assert digest(TARGET / name) == expected, 'Unexpected source change: ' + name
        except Exception:
            subprocess.run(['systemctl', 'disable', '--now', UNITS[1]], check=False, capture_output=True)
            subprocess.run(['systemctl', 'stop', UNITS[0]], check=False, capture_output=True)
            for unit in installed_units:
                assert digest(SYSTEMD / unit) == digest(candidate / 'ops' / unit)
                (SYSTEMD / unit).unlink()
            for name in installed:
                assert digest(TARGET / name) == manifest['files'][name], 'Concurrent edit prevents rollback'
                if (backup / name).exists():
                    install(backup / name, TARGET / name)
                else:
                    (TARGET / name).unlink()
            run('systemctl', 'daemon-reload')
            run('systemctl', 'restart', 'hegong-backend.service')
            healthy()
            # Additive indexes can remain; never replace the DB over concurrent writes.
            (backup / 'activation.json').write_text(json.dumps({'status': 'rolled_back_code', 'backup': str(backup)}))
            raise
        result = {'status': 'activated', 'backup': str(backup), 'before': before, 'after': counts(),
                  'tests': receipt['tests'], 'retention_hours': 72, 'cleanup_minutes': 30}
        (backup / 'activation.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result))


if __name__ == '__main__':
    main()
