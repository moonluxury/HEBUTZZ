"""Verify the actual HTTPS profile response with disposable, mutually isolated users."""
import argparse
import json
from pathlib import Path
import secrets
import subprocess
import sys
import httpx

FIELDS = {'school', 'college', 'major', 'grade', 'bio'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    accounts, credentials, checks = [], [], []
    cleanup = None
    run_id = secrets.token_hex(6)

    def check(condition, label):
        if not condition:
            raise RuntimeError('HTTPS check failed: ' + label)
        checks.append(label)

    with httpx.Client(base_url='https://39.107.44.18', timeout=20, follow_redirects=False) as client:
        def rpc(actor, action, expected=200, **payload):
            if action in {'save_profile', 'request_friend', 'respond_request', 'preferences', 'relationship'}:
                payload.setdefault('operation_id', secrets.token_hex(16))
            response = client.post('/v1/rpc', headers={'Authorization': 'Bearer ' + actor['access_token']},
                                   json={'version': 1, 'action': action, 'payload': payload})
            if response.status_code != expected:
                raise RuntimeError(f'HTTPS {action}: expected {expected}, received {response.status_code}')
            return response.json()

        try:
            check(client.get('/health').json().get('status') == 'ok', 'HTTPS certificate and health')
            for suffix in ['a', 'b']:
                username = 'profilecheck_' + run_id + suffix
                response = client.post('/v1/auth/register', json={'username': username, 'password': secrets.token_urlsafe(32)})
                check(response.status_code == 200, 'Temporary identity registration ' + suffix)
                value = response.json()
                accounts.append({'id': value['account_id'], 'username': username})
                (args.output / 'temporary-accounts.json').write_text(json.dumps({'accounts': accounts}))
                credentials.append(value)
            viewer, peer = credentials
            lookup = {'public_id': peer['profile']['public_id']}
            anonymous = client.post('/v1/rpc', json={'version': 1, 'action': 'find_user', 'payload': lookup})
            check(anonymous.status_code == 401, 'Anonymous profile lookup denied')
            public = rpc(viewer, 'find_user', **lookup)['user']
            check({key: public.get(key) for key in FIELDS} == dict.fromkeys(FIELDS, ''), 'Unfilled profile returns all five empty fields')
            details = {'school': '部署校验学校', 'college': '部署校验学院', 'major': '计算机科学与技术',
                       'grade': '2024级', 'bio': '仅用于本次部署验证。\n验证完成后清理。'}
            check(rpc(peer, 'save_profile', patch=details).get('persisted') is True, 'Peer saves profile through the real API')
            public = rpc(viewer, 'find_user', **lookup)['user']
            for field in sorted(FIELDS):
                check(public.get(field) == details[field], 'Persisted field returned: ' + field)
            check(set(public) == {'id', 'public_id', 'name', 'avatar_card_id', 'remark'} | FIELDS, 'Response contains only declared public fields')
            request = rpc(viewer, 'request_friend', peer_id=peer['account_id'])['request']
            rpc(peer, 'respond_request', request_id=request['id'], decision='accept')
            check(rpc(viewer, 'find_user', **lookup)['state'] == 'friend', 'Friend profile is accessible')
            rpc(viewer, 'preferences', peer_id=peer['account_id'], remark='部署验证备注')
            check(rpc(viewer, 'find_user', **lookup)['user']['remark'] == '部署验证备注', 'Private remark remains scoped to the viewer')
            check(not (FIELDS & set(rpc(viewer, 'friends')['friends'][0])), 'Friend list still uses compact identities')
            conversation = next(c for c in rpc(viewer, 'sync')['conversations'] if c.get('peer', {}).get('id') == peer['account_id'])
            check(not (FIELDS & set(conversation['peer'])), 'Polling does not broadcast full profiles')
            updated = '简' * 300
            rpc(peer, 'save_profile', patch={'bio': updated})
            check(rpc(viewer, 'find_user', **lookup)['user']['bio'] == updated, 'Updated 300-character biography is not truncated')
            rpc(peer, 'save_profile', patch=dict.fromkeys(FIELDS, ''))
            public = rpc(viewer, 'find_user', **lookup)['user']
            check({key: public[key] for key in FIELDS} == dict.fromkeys(FIELDS, ''), 'Cleared profile returns empty fields without stale data')
            rpc(viewer, 'relationship', peer_id=peer['account_id'], operation='block')
            for actor, target in [(viewer, peer), (peer, viewer)]:
                result = rpc(actor, 'find_user', public_id=target['profile']['public_id'])
                check(result.get('state') == 'inaccessible' and 'user' not in result, 'Blocked profile is withheld in both directions')
            rpc(viewer, 'relationship', peer_id=peer['account_id'], operation='unblock')
            check(rpc(viewer, 'find_user', **lookup)['state'] == 'available', 'Unblock restores lookup without recreating friendship')
            check(client.get('/v1/articles').json().get('ok') is True, 'Existing article endpoint remains healthy')
            comments = client.post('/v1/comments/query', json={'version': 1, 'action': 'comment_list', 'payload': {'target_type': 'bank', 'target_id': 'marxism', 'limit': 1}})
            check(comments.json().get('ok') is True, 'Existing comment endpoint remains healthy')
        finally:
            if accounts:
                result = subprocess.run(['runuser', '-u', 'hegong', '--', sys.executable,
                                         str(Path(__file__).with_name('public_profile_smoke_cleanup.py'))],
                                        input=json.dumps({'accounts': accounts}), text=True, capture_output=True, timeout=30)
                if result.returncode:
                    raise RuntimeError('Exact temporary-account cleanup failed; private evidence retains the IDs')
                cleanup = json.loads(result.stdout)
            report = {'checks_passed': len(checks), 'checks': checks, 'cleanup': cleanup}
            (args.output / 'https-checks.json').write_text(json.dumps(report, indent=2))
    print(json.dumps({'status': 'passed', 'checks': len(checks), 'cleanup': cleanup}))


if __name__ == '__main__':
    main()
