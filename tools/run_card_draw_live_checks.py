"""Real Godot HTTPS draw using one disposable account; credentials stay in memory."""
import argparse
import json
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import sys
import httpx


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--host', required=True)
    parser.add_argument('--identity', required=True)
    parser.add_argument('--known-hosts', required=True)
    parser.add_argument('--account-helper', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert args.host == 'root@39.107.44.18' and args.account_helper.startswith('/opt/hegong/releases/card-draw-')
    root = Path(__file__).resolve().parents[1]
    accounts = []
    args.output.mkdir(parents=True, exist_ok=True)
    ssh = ['ssh', '-i', args.identity, '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
           '-o', 'UserKnownHostsFile=' + args.known_hosts, args.host,
           shlex.join(['runuser', '-u', 'hegong', '--', '/opt/hegong/venv/bin/python', args.account_helper])]

    def manage(action):
        result = subprocess.run(ssh, input=json.dumps({'action': action, 'accounts': accounts}), capture_output=True, text=True, timeout=40)
        if result.returncode: raise RuntimeError('Temporary account ' + action + ' failed')
        return json.loads(result.stdout)

    try:
        username = 'drawcheck_' + secrets.token_hex(6) + 'a'
        with httpx.Client(base_url='https://39.107.44.18', timeout=25, follow_redirects=False) as client:
            response = client.post('/v1/auth/register', json={'username': username, 'password': secrets.token_urlsafe(32)})
            assert response.status_code == 200, 'Temporary registration failed'
            account = response.json()
        accounts.append({'id': account['account_id'], 'username': username})
        (args.output / 'temporary-account.json').write_text(json.dumps({'accounts': accounts}))
        manage('fund')
        env = os.environ.copy()
        env.update(HEGONG_DRAW_LIVE_TEST='1', HEGONG_DRAW_TEST_USERNAME=username,
                   HEGONG_DRAW_TEST_ACCOUNT=account['account_id'], HEGONG_DRAW_TEST_TOKEN=account['access_token'])
        result = subprocess.run([sys.executable, str(root / 'tools/run_workbench_checks.py'), '--godot', args.godot,
                                 '--script', 'check_card_draw_live.gd', '--timeout', '120'],
                                cwd=root, env=env, capture_output=True, timeout=140)
        (args.output / 'godot-live.log').write_bytes(result.stdout + result.stderr)
        print((result.stdout + result.stderr).decode('utf-8', errors='replace'))
        if result.returncode: raise RuntimeError('Godot live draw checks failed')
    finally:
        if accounts:
            cleanup = manage('cleanup')
            (args.output / 'cleanup.json').write_text(json.dumps(cleanup))
            print(json.dumps(cleanup))


if __name__ == '__main__':
    main()
