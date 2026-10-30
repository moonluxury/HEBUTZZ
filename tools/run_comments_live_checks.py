"""Explicit live HTTPS check with private test data and exact-identity cleanup."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--host', required=True)
    parser.add_argument('--identity', type=Path, required=True)
    parser.add_argument('--known-hosts', type=Path, required=True)
    parser.add_argument('--remote-fixture', required=True)
    args = parser.parse_args()
    ssh = ['ssh','-i',str(args.identity),'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile='+str(args.known_hosts),args.host,
           'runuser','-u','hegong','--','/opt/hegong/venv/bin/python',args.remote_fixture]
    fixture = Path(tempfile.mkdtemp(prefix='comments-live-', dir=ROOT/'.godot_appdata'))
    env = os.environ.copy()
    for name in ['APPDATA','LOCALAPPDATA']:
        path = fixture/name.lower(); path.mkdir(); env[name] = str(path)
    env['HEGONG_BACKEND_LIVE_TEST'] = '1'
    env['HEGONG_COMMENTS_LIVE_CONTROL'] = str(fixture)
    env.pop('HEGONG_BACKEND_DISABLED', None)
    # Always exercise the configured production default, not a prior loopback override.
    env.pop('HEGONG_API_URL', None)
    output_path = fixture/'process.log'
    identities = None
    with output_path.open('w', encoding='utf-8') as log:
        process = subprocess.Popen([args.godot,'--headless','--path',str(ROOT),'--script','res://tools/check_comments_live.gd',
                                    '--log-file',str(fixture/'godot.log')], env=env, stdout=log, stderr=log)
        try:
            deadline = time.monotonic()+45
            while time.monotonic()<deadline and process.poll() is None:
                path = fixture/'identities.json'
                if path.exists():
                    try: identities = json.loads(path.read_text(encoding='utf-8'))
                    except json.JSONDecodeError: pass
                    if identities and len(identities.get('accounts',[])) == 2: break
                time.sleep(.1)
            if not identities or len(identities.get('accounts',[])) != 2:
                raise RuntimeError('Disposable registrations did not complete; see isolated log')
            result = subprocess.run(ssh, input=json.dumps({'action':'setup',**identities}), text=True, capture_output=True, timeout=30)
            if result.returncode: raise RuntimeError('Private fixture setup failed: '+result.stderr)
            (fixture/'ready').write_text('ready', encoding='utf-8')
            process.wait(timeout=120)
        finally:
            if process.poll() is None: process.terminate(); process.wait(timeout=10)
            path = fixture/'identities.json'
            if path.exists(): identities = json.loads(path.read_text(encoding='utf-8'))
            if identities and identities.get('accounts'):
                result = subprocess.run(ssh, input=json.dumps({'action':'cleanup',**identities}), text=True, capture_output=True, timeout=30)
                if result.returncode: raise RuntimeError('Exact-identity cleanup requires attention: '+result.stderr)
                print('Private fixture and temporary accounts removed.')
    output = output_path.read_text(encoding='utf-8', errors='replace')
    print(output)
    print('Isolated log:', fixture)
    if process.returncode or 'ERROR:' in output or 'COMMENTS LIVE: PASS' not in output: raise SystemExit(1)


if __name__ == '__main__': main()
