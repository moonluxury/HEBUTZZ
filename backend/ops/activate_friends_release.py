"""Activate a tested friend-only release, preserving the baseline and rollback copies."""
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
FILES = {'domain.py', 'friend_note.py', 'requirements.txt', 'requirements.lock',
         'tests/test_backend.py', 'tests/test_friend_note.py'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def install(source, target):
    target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    temporary = target.with_name(target.name + '.friends-new')
    shutil.copyfile(source, temporary)
    temporary.chmod(0o644)
    os.replace(temporary, target)


def healthy():
    try:
        for endpoint, key, expected in [('/health', 'status', 'ok'), ('/v1/articles', 'ok', True)]:
            with urllib.request.urlopen('http://127.0.0.1:8000' + endpoint, timeout=3) as response:
                if json.load(response).get(key) != expected:
                    return False
        return True
    except Exception:
        return False


def wait_healthy():
    for _ in range(40):
        if healthy():
            return
        time.sleep(0.5)
    raise RuntimeError('Backend health check failed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--apply', action='store_true', required=True)
    args = parser.parse_args()
    assert os.geteuid() == 0
    os.umask(0o077)
    candidate = args.candidate.resolve()
    assert candidate.is_relative_to('/opt/hegong/releases')
    manifest_path = candidate / 'friends-release.json'
    manifest = json.loads(manifest_path.read_text())
    assert set(manifest['files']) == set(manifest['baseline_sha256']) == FILES
    receipt = json.loads((candidate / 'tests-passed.json').read_text())
    assert receipt['passed'] is True and receipt['manifest_sha256'] == digest(manifest_path)
    assert receipt['database'].endswith('_test')
    with open('/run/lock/hegong-deploy.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for name, expected in manifest['candidate_sha256'].items():
            assert (candidate / name).resolve().is_relative_to(candidate)
            assert digest(candidate / name) == expected, 'Candidate changed: ' + name

        def verify_baseline():
            for name, expected in {**manifest['baseline_sha256'], **manifest['guard_sha256']}.items():
                assert (TARGET / name).resolve().is_relative_to(TARGET)
                assert digest(TARGET / name) == expected, 'Server changed: ' + name

        verify_baseline()
        backup = Path('/var/backups/hegong') / ('friends-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
        backup.mkdir(mode=0o700)
        with (backup / 'database.dump').open('wb') as stream:
            subprocess.run(['runuser', '-u', 'hegong', '--', 'pg_dump', '-Fc', 'hegong'], stdout=stream, check=True)
        subprocess.run(['pg_restore', '--list', str(backup / 'database.dump')], stdout=subprocess.DEVNULL, check=True)
        for name, expected in manifest['baseline_sha256'].items():
            if expected is not None:
                (backup / name).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(TARGET / name, backup / name)
        shutil.copy2(manifest_path, backup / 'friends-release.json')
        shutil.copy2(candidate / 'tests-passed.json', backup / 'tests-passed.json')
        # Only add the already-tested pinned dependency; do not upgrade existing packages.
        # Backup files are private, but runtime packages must be readable by the
        # unprivileged service. A 077 installation can silently import a namespace
        # named regex instead of its inaccessible __init__.py.
        previous_umask = os.umask(0o022)
        try:
            subprocess.run([PYTHON, '-m', 'pip', 'install', '--disable-pip-version-check', '--force-reinstall', '--no-deps', 'regex==' + manifest['regex']], check=True)
        finally:
            os.umask(previous_umask)
        subprocess.run(['runuser', '-u', 'hegong', '--', PYTHON, '-c',
                        'import importlib.metadata, regex; assert importlib.metadata.version("regex") == "2026.9.29"; assert len(regex.findall(r"\\X", "e\\u0301")) == 1'], check=True)
        verify_baseline()
        installed = []
        try:
            for name in sorted(FILES):
                install(candidate / name, TARGET / name)
                installed.append(name)
            subprocess.run(['systemctl', 'restart', 'hegong-backend'], check=True)
            wait_healthy()
            subprocess.run([str(candidate / '.venv/bin/python'), str(candidate / 'ops/smoke_friends_release.py'),
                            '--output', str(backup / 'https')], check=True)
            for name, expected in manifest['files'].items():
                assert digest(TARGET / name) == expected, 'Installed file mismatch: ' + name
            for name, expected in manifest['guard_sha256'].items():
                assert digest(TARGET / name) == expected, 'Unrelated server file changed: ' + name
        except Exception:
            # Do not restore the database over real writes. This release has no migration.
            for name in installed:
                target = TARGET / name
                assert digest(target) == manifest['files'][name], 'Concurrent change prevents automatic rollback: ' + name
                if (backup / name).exists():
                    install(backup / name, target)
                else:
                    target.unlink()
            subprocess.run(['systemctl', 'restart', 'hegong-backend'], check=True)
            wait_healthy()
            (backup / 'activation.json').write_text(json.dumps({'status': 'rolled_back', 'backup': str(backup)}))
            raise
        result = {'status': 'activated', 'backup': str(backup), 'files': sorted(FILES),
                  'schema_change': False, 'https': json.loads((backup / 'https/https-checks.json').read_text())}
        (backup / 'activation.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result))


if __name__ == '__main__':
    main()
