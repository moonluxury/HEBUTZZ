"""Fund or remove only the exact disposable draw-check identities."""
import json
import re
import secrets
import sys
import psycopg


def main():
    data = json.load(sys.stdin)
    accounts = data['accounts']
    assert 0 < len(accounts) <= 2 and data['action'] in {'fund', 'cleanup'}
    for account in accounts:
        assert re.fullmatch('[0-9a-f]{32}', account['id'])
        assert re.fullmatch('drawcheck_[0-9a-f]{12}[ab]', account['username'])
    ids = [a['id'] for a in accounts]
    with psycopg.connect('dbname=hegong user=hegong host=/var/run/postgresql') as conn:
        for account in accounts:
            row = conn.execute("SELECT username,created_at>now()-interval '1 hour' FROM users WHERE id=%s FOR UPDATE", (account['id'],)).fetchone()
            assert row is not None and row[0] == account['username'] and row[1], 'Temporary identity mismatch'
        for table, a, b in [('friend_requests', 'sender', 'recipient'), ('relationships', 'a', 'b'), ('transfers', 'initiator', 'recipient')]:
            assert not conn.execute(f'SELECT 1 FROM {table} WHERE ({a}=ANY(%s) OR {b}=ANY(%s)) AND NOT ({a}=ANY(%s) AND {b}=ANY(%s))', (ids, ids, ids, ids)).fetchone()
        assert not conn.execute('SELECT 1 FROM submissions WHERE author_id=ANY(%s)', (ids,)).fetchone()
        if data['action'] == 'fund':
            for account in accounts:
                event = 'isolated-draw-check:' + account['username']
                if conn.execute('SELECT 1 FROM battery_ledger WHERE user_id=%s AND event_key=%s', (account['id'], event)).fetchone():
                    continue
                conn.execute('INSERT INTO battery_wallets(user_id) VALUES (%s) ON CONFLICT DO NOTHING', (account['id'],))
                current = conn.execute('SELECT balance FROM battery_wallets WHERE user_id=%s FOR UPDATE', (account['id'],)).fetchone()[0]
                assert current == 0
                conn.execute("INSERT INTO battery_ledger(id,user_id,event_key,source,delta,reference,balance_after) VALUES (%s,%s,%s,'opening',400,'isolated-draw-check',400)", (secrets.token_hex(16), account['id'], event))
                conn.execute('UPDATE battery_wallets SET balance=400,revision=revision+1 WHERE user_id=%s', (account['id'],))
        else:
            for account in accounts:
                conn.execute('DELETE FROM users WHERE id=%s AND username=%s', (account['id'], account['username']))
            assert conn.execute('SELECT count(*) FROM users WHERE id=ANY(%s)', (ids,)).fetchone()[0] == 0
    print(json.dumps({'ok': True, 'action': data['action'], 'temporary_accounts': len(accounts)}))


if __name__ == '__main__':
    main()
