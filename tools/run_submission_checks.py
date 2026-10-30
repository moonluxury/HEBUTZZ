"""Run the five submission screens against disposable loopback PostgreSQL data.

Requires the existing local test cluster, backend dependencies and Windows CEF.
Never uses production credentials, live users, or a production database.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

import httpx
from psycopg.conninfo import conninfo_to_dict

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--manual', action='store_true', help='Open the native input probe with an isolated account')
    args = parser.parse_args()
    env = os.environ.copy()
    env.setdefault('DATABASE_URL', 'host=127.0.0.1 port=55439 dbname=hegong_submission_test user=hegong_test_owner')
    db = conninfo_to_dict(env['DATABASE_URL'])
    if db.get('host') != '127.0.0.1' or not db.get('dbname', '').endswith('_test'):
        raise SystemExit('Only an explicit loopback *_test database is permitted')
    env['HEGONG_BACKEND_DISABLED'] = '1'
    env['PYTHONUTF8'] = '1'
    # Do not attach to an unrelated/stale service or overwrite its session file.
    import socket
    with socket.socket() as probe:
        if probe.connect_ex(('127.0.0.1', 8059)) == 0:
            raise SystemExit('Port 8059 is in use; stop the old test server first')
    log_path = ROOT / '.godot_appdata/submission-http.log'
    with log_path.open('w', encoding='utf-8') as log:
        server = subprocess.Popen([sys.executable, str(ROOT / 'tools/serve_submission_checks.py')],
                                  cwd=ROOT, env=env, stdout=log, stderr=log,
                                  creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        try:
            with httpx.Client(timeout=2) as client:
                for _ in range(150):
                    if server.poll() is not None:
                        raise RuntimeError(f'Isolated backend failed; see {log_path}')
                    try:
                        if client.get('http://127.0.0.1:8059/health').status_code == 200: break
                    except httpx.TransportError: pass
                    time.sleep(.2)
                else: raise RuntimeError('Isolated backend did not become ready')
            if args.manual:
                fixture = Path(tempfile.mkdtemp(prefix='workbench-check-input-', dir=ROOT / '.godot_appdata'))
                for key in ['APPDATA','LOCALAPPDATA']:
                    folder = fixture / key.lower();folder.mkdir();env[key] = str(folder)
                command = [args.godot, '--path', str(ROOT), '--rendering-method', 'gl_compatibility',
                           '--script', 'res://tools/submission_input_probe.gd', '--log-file', str(fixture / 'check.log')]
                print('Manual probe only: inspect input and close the window when done. No automatic PASS is implied.', flush=True)
            else:
                command = [sys.executable, str(ROOT / 'tools/run_workbench_checks.py'), '--godot', args.godot,
                           '--script', 'check_submissions.gd', '--visual', '--timeout', '240']
            result = subprocess.run(command, cwd=ROOT, env=env)
            if result.returncode: raise SystemExit(result.returncode)
        finally:
            server.terminate()
            server.wait(timeout=15)
            # Session is test-only but still a bearer credential: never keep it in evidence.
            session_path = ROOT / '.godot_appdata/submission-check-session.json'
            if session_path.exists(): session_path.unlink()


if __name__ == '__main__': main()
