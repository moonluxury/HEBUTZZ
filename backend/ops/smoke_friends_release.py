"""Exercise the deployed HTTPS friend flow with two temporary, contained accounts.

Passwords and tokens remain in process memory and are never printed or saved.
The exact temporary IDs are saved first so failed runs can still be cleaned up.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import secrets
import subprocess
import sys
import httpx


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url', default='https://39.107.44.18')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert args.base_url == 'https://39.107.44.18'
    args.output.mkdir(parents=True, exist_ok=True)
    accounts, checks = [], []
    credentials = []
    run_id = secrets.token_hex(6)
    cleanup = None

    def check(value, label):
        if not value:
            raise RuntimeError('HTTPS check failed: ' + label)
        checks.append(label)

    with httpx.Client(base_url=args.base_url, timeout=20, follow_redirects=False) as client:
        def rpc(actor, action, expected=200, **payload):
            if action in {'request_friend', 'respond_request'}:
                payload.setdefault('operation_id', secrets.token_hex(16))
            response = client.post('/v1/rpc', headers={'Authorization': 'Bearer ' + actor['access_token']},
                                   json={'version': 1, 'action': action, 'payload': payload})
            if response.status_code != expected:
                raise RuntimeError(f'HTTPS {action}: expected {expected}, received {response.status_code}')
            return response.json()

        try:
            check(client.get('/health').json().get('status') == 'ok', 'HTTPS certificate and health')
            for suffix in ['a', 'b']:
                username = 'friendcheck_' + run_id + suffix
                response = client.post('/v1/auth/register', json={'username': username, 'password': secrets.token_urlsafe(32)})
                check(response.status_code == 200, 'Temporary account registration ' + suffix)
                value = response.json()
                accounts.append({'id': value['account_id'], 'username': username})
                (args.output / 'temporary-accounts.json').write_text(json.dumps({'accounts': accounts}), encoding='utf-8')
                credentials.append(value)
            a, b = credentials
            aid, bid = a['account_id'], b['account_id']
            apub, bpub = a['profile']['public_id'], b['profile']['public_id']
            check(rpc(a, 'find_user', public_id=apub)['state'] == 'self', 'Self lookup')
            check(rpc(a, 'find_user', public_id='NO-' + run_id)['state'] == 'not_found', 'Missing exact ID')
            check(rpc(a, 'find_user', public_id=bpub)['state'] == 'available', 'Existing exact ID')
            rpc(a, 'request_friend', expected=400, peer_id=aid)
            checks.append('Self request refused')
            rpc(a, 'request_friend', expected=400, peer_id=bid, sender_id=bid)
            checks.append('Forged sender refused')
            rpc(a, 'request_friend', expected=400, peer_id=bid, note='你' * 101)
            rpc(a, 'request_friend', expected=400, peer_id=bid, note='👩🏽‍💻' * 101)
            checks.append('101 visible characters refused, including compound emoji')
            note = '  \n' + '👩🏽‍💻' * 94 + '\n  '
            operation = secrets.token_hex(16)
            sent = rpc(a, 'request_friend', peer_id=bid, note=note, operation_id=operation)
            rid = sent['request']['id']
            check(sent['request']['note'] == note, '100 graphemes accepted without trimming whitespace')
            check(rpc(a, 'request_friend', peer_id=bid, note=note, operation_id=operation) == sent, 'Identical retry returns the original receipt')
            with ThreadPoolExecutor(max_workers=5) as pool:
                ids = list(pool.map(lambda _: rpc(a, 'request_friend', peer_id=bid, note=note)['request']['id'], range(5)))
            check(set(ids) == {rid}, 'Five concurrent requests share one pending record')
            check(rpc(a, 'find_user', public_id=bpub)['state'] == 'outgoing', 'Outgoing state')
            check(rpc(b, 'find_user', public_id=apub)['state'] == 'incoming', 'Incoming state')
            requests = rpc(b, 'sync')['requests']
            check(len(requests) == 1 and requests[0]['note'] == note, 'Recipient sees one request with the exact note')
            rpc(a, 'respond_request', expected=403, request_id=rid, decision='accept')
            checks.append('Sender cannot accept its own application')
            rpc(b, 'respond_request', request_id=rid, decision='ignore')
            check(rpc(a, 'find_user', public_id=bpub)['state'] == 'available', 'Ignore does not create friendship')
            sent = rpc(a, 'request_friend', peer_id=bid, note='')
            operation = secrets.token_hex(16)
            accepted = rpc(b, 'respond_request', request_id=sent['request']['id'], decision='accept', operation_id=operation)
            check(rpc(b, 'respond_request', request_id=sent['request']['id'], decision='accept', operation_id=operation) == accepted, 'Acceptance is idempotent')
            check(len(rpc(a, 'friends')['friends']) == len(rpc(b, 'friends')['friends']) == 1, 'Acceptance updates both friend lists')
            check(rpc(a, 'find_user', public_id=bpub)['state'] == 'friend', 'Friend lookup state')
            check(rpc(a, 'request_friend', peer_id=bid)['state'] == 'friend', 'Already-friend race returns an explicit state')
            check(client.get('/v1/articles').json().get('ok') is True, 'Existing public article endpoint')
            comments = client.post('/v1/comments/query', json={'version': 1, 'action': 'comment_list', 'payload': {'target_type': 'bank', 'target_id': 'marxism', 'limit': 1}})
            check(comments.json().get('ok') is True, 'Existing comment endpoint')
        finally:
            if accounts:
                result = subprocess.run(['runuser', '-u', 'hegong', '--', sys.executable,
                                         str(Path(__file__).with_name('friends_smoke_cleanup.py'))],
                                        input=json.dumps({'accounts': accounts}), text=True, capture_output=True)
                if result.returncode:
                    raise RuntimeError('Temporary-account cleanup failed; exact IDs are in the private release evidence')
                cleanup = json.loads(result.stdout)
            report = {'checks_passed': len(checks), 'checks': checks, 'cleanup': cleanup}
            (args.output / 'https-checks.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({'status': 'passed', 'checks': len(checks), 'cleanup': cleanup}))


if __name__ == '__main__':
    main()
