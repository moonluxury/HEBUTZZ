"""Validate real HTTPS draws using two funded test users; never use a real wallet."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import secrets
import subprocess
import sys
import httpx

ODDS = {'0004': 10, '0007': 10, '0005': 12, '0003': 14, '0001': 16, '0006': 18, '0002': 20}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    accounts, actors, checks = [], [], []
    cleanup = None
    token = secrets.token_hex(6)

    def check(value, label):
        if not value: raise RuntimeError('Draw HTTPS check failed: ' + label)
        checks.append(label)

    def manage(action):
        result = subprocess.run(['runuser', '-u', 'hegong', '--', sys.executable,
                                 str(Path(__file__).with_name('card_draw_smoke_accounts.py'))],
                                input=json.dumps({'action': action, 'accounts': accounts}), text=True, capture_output=True, timeout=30)
        if result.returncode: raise RuntimeError('Contained test identity operation failed: ' + action)
        return json.loads(result.stdout)

    with httpx.Client(base_url='https://39.107.44.18', timeout=25, follow_redirects=False) as client:
        def wallet(actor, action, expected=200, **payload):
            response = client.post('/v1/wallet', headers={'Authorization': 'Bearer ' + actor['access_token']},
                                   json={'version': 1, 'action': action, 'payload': payload})
            if response.status_code != expected: raise RuntimeError(f'{action}: HTTP {response.status_code}, expected {expected}')
            return response.json()

        def count(response): return sum(x['count'] for x in response['collection']['inventory'].values())

        try:
            check(client.get('/health').json().get('status') == 'ok', 'HTTPS certificate and health')
            for suffix in ['a', 'b']:
                username = 'drawcheck_' + token + suffix
                response = client.post('/v1/auth/register', json={'username': username, 'password': secrets.token_urlsafe(32)})
                check(response.status_code == 200, 'Register isolated account ' + suffix)
                actor = response.json()
                accounts.append({'id': actor['account_id'], 'username': username})
                (args.output / 'temporary-accounts.json').write_text(json.dumps({'accounts': accounts}))
                actors.append(actor)
            a, b = actors
            options = wallet(a, 'card_draw_options')
            check(options['price'] == 200 and options['duplicates'] is True, 'One card costs exactly 200 and duplicates are allowed')
            check({x['card_id']: x['percent'] for x in options['odds']} == ODDS, 'All seven configured probabilities match the requested distribution')

            def payload(): return {'operation_id': secrets.token_hex(16), 'pool_id': options['pool_id'], 'rule_version': options['rule_version'], 'expected_price': 200}

            anonymous = client.post('/v1/wallet', json={'version': 1, 'action': 'card_draw', 'payload': payload()})
            check(anonymous.status_code == 401, 'Anonymous draw is rejected')
            refused = payload()
            result = wallet(a, 'card_draw', **refused)
            check(not result['ok'] and result['state'] == 'failed' and result['code'] == 'insufficient_balance', 'Zero-balance draw is a terminal refusal')
            check(result['balance'] == 0 and count(result) == 0, 'Refused draw neither charges nor grants')
            manage('fund')
            result = wallet(a, 'card_draw', **refused)
            check(not result['ok'] and result['balance'] == 400 and count(result) == 0, 'Old refused request cannot spend newly credited test funds')
            request = payload()
            with ThreadPoolExecutor(max_workers=4) as pool:
                results = list(pool.map(lambda _: wallet(a, 'card_draw', **request), range(4)))
            first = results[0]
            check(all(r['ok'] and r['draw'] == first['draw'] for r in results), 'Four concurrent retries return the same draw receipt')
            check(first['balance'] == 200 and count(first) == 1 and first['draw']['card_id'] in ODDS, 'One successful draw atomically spends 200 and grants one catalog card')
            check(wallet(a, 'card_draw_status', operation_id=request['operation_id'])['draw'] == first['draw'], 'Original result can be recovered without another draw')
            check(wallet(b, 'card_draw_status', operation_id=request['operation_id'])['state'] == 'not_found', 'Another account cannot recover this receipt')
            second = wallet(a, 'card_draw', **payload())
            check(second['balance'] == 0 and count(second) == 2, 'A new deliberate draw produces exactly one additional copy')
            ledger = wallet(a, 'ledger', filter='expense')['items']
            check(len(ledger) == 2 and all(x['source'] == 'card_draw' and x['delta'] == -200 for x in ledger), 'Expense ledger records the two 200-battery purchases')
            result = wallet(a, 'card_draw', **payload())
            check(result['state'] == 'failed' and result['balance'] == 0 and count(result) == 2, 'Exhausted balance cannot overdraw')
            with ThreadPoolExecutor(max_workers=3) as pool:
                concurrent = list(pool.map(lambda _: wallet(b, 'card_draw', **payload()), range(3)))
            check(sum(r['ok'] for r in concurrent) == 2 and wallet(b, 'balance')['balance'] == 0, 'Three different concurrent requests can spend only the available 400')
            forged = wallet(b, 'card_draw', expected=400, **{**payload(), 'card_id': '0004'})
            check(not forged['ok'], 'Client-supplied winning card is rejected')
            check(client.get('/v1/articles').json().get('ok') is True, 'Existing article route remains healthy')
            comments = client.post('/v1/comments/query', json={'version': 1, 'action': 'comment_list', 'payload': {'target_type': 'bank', 'target_id': 'marxism', 'limit': 1}})
            check(comments.json().get('ok') is True, 'Existing comment route remains healthy')
        finally:
            if accounts: cleanup = manage('cleanup')
            report = {'checks_passed': len(checks), 'checks': checks, 'cleanup': cleanup}
            (args.output / 'https-checks.json').write_text(json.dumps(report, indent=2))
    print(json.dumps({'status': 'passed', 'checks': len(checks), 'cleanup': cleanup}))


if __name__ == '__main__':
    main()
