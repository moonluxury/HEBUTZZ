"""Server-local inventory grant. Defaults to preview; writes require --apply and a stable operation ID."""
import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from psycopg.types.json import Jsonb
from database import pool, transaction, one, rows, lock_users, bump


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--username', required=True)
    parser.add_argument('--quantity', type=int, required=True)
    parser.add_argument('--operation-id', required=True)
    parser.add_argument('--expected-user-id')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if not 1 <= args.quantity <= 1000000 or not 1 <= len(args.operation_id) <= 128:
        parser.error('Invalid quantity or operation ID')
    if args.apply and not args.expected_user_id:
        parser.error('--apply requires the user ID obtained from preview')
    catalog = json.loads((Path(__file__).resolve().parents[1] / 'collection_catalog.json').read_text(encoding='utf-8'))
    cards = catalog['cards']
    if not cards or len({c['id'] for c in cards}) != len(cards):
        raise RuntimeError('Empty or duplicate card catalog')
    payload = {'username': args.username.lower(), 'quantity': args.quantity,
               'card_ids': sorted(c['id'] for c in cards), 'reason': 'Manual inventory grant requested by the server owner'}
    digest = hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    pool.open(wait=True)
    try:
        with transaction() as conn:
            account = one(conn, 'SELECT id,public_id,username,disabled,revision FROM users WHERE username=%s', (args.username.lower(),))
            if account is None or account['disabled']:
                raise RuntimeError('Account not found or disabled; no inventory changed')
            if args.expected_user_id and account['id'] != args.expected_user_id:
                raise RuntimeError('Account identity changed; no inventory changed')
            lock_users(conn, account['id'])
            old = {r['card_id']: r['count'] for r in rows(conn, 'SELECT card_id,count FROM inventory WHERE user_id=%s', (account['id'],))}
            changes = [{'card_id': c['id'], 'name': c['name'], 'before': old.get(c['id'], 0),
                        'added': args.quantity, 'after': old.get(c['id'], 0) + args.quantity} for c in cards]
            previous = one(conn, 'SELECT action,request_hash,response FROM operations WHERE actor=%s AND operation_id=%s', (account['id'], args.operation_id))
            if previous:
                if previous['action'] != 'admin_grant_cards' or previous['request_hash'] != digest:
                    raise RuntimeError('Operation ID conflict; no inventory changed')
                result = {'state': 'already_applied', 'grant': previous['response'], 'current_inventory': old}
            elif not args.apply:
                result = {'state': 'preview', 'account': account, 'changes': changes,
                          'total_added': len(cards) * args.quantity, 'operation_id': args.operation_id}
            else:
                for change in changes:
                    conn.execute('INSERT INTO inventory(user_id,card_id,count) VALUES (%s,%s,%s) ON CONFLICT(user_id,card_id) DO UPDATE SET count=inventory.count+EXCLUDED.count',
                                 (account['id'], change['card_id'], args.quantity))
                bump(conn, account['id'])
                after = {r['card_id']: r['count'] for r in rows(conn, 'SELECT card_id,count FROM inventory WHERE user_id=%s', (account['id'],))}
                if any(after.get(c['card_id']) != c['after'] for c in changes):
                    raise RuntimeError('Inventory verification failed; transaction rolled back')
                revision = one(conn, 'SELECT revision FROM users WHERE id=%s', (account['id'],))['revision']
                result = {'state': 'applied', 'account_id': account['id'], 'public_id': account['public_id'],
                          'username': account['username'], 'operation_id': args.operation_id,
                          'changes': changes, 'total_added': len(cards) * args.quantity, 'revision': revision,
                          'reason': payload['reason']}
                conn.execute('INSERT INTO operations(actor,operation_id,action,request_hash,response) VALUES (%s,%s,%s,%s,%s)',
                             (account['id'], args.operation_id, 'admin_grant_cards', digest, Jsonb(result)))
        # Print only after the transaction has committed successfully.
        print(json.dumps(result, ensure_ascii=False))
    finally:
        pool.close()


if __name__ == '__main__':
    main()
