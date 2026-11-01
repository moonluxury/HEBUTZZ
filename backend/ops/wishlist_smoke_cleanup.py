"""Delete only the exact isolated wishlist-check identities, with graph guards."""
import json
import re
import sys
import psycopg


def main():
    accounts = json.load(sys.stdin)['accounts']
    assert 0 < len(accounts) <= 2
    for account in accounts:
        assert re.fullmatch('[0-9a-f]{32}', account['id'])
        assert re.fullmatch('wishcheck_[0-9a-f]{12}[ab]', account['username'])
    ids = [a['id'] for a in accounts]
    with psycopg.connect('dbname=hegong user=hegong host=/var/run/postgresql') as conn:
        for account in accounts:
            row = conn.execute('SELECT username FROM users WHERE id=%s FOR UPDATE', (account['id'],)).fetchone()
            assert row is None or row[0] == account['username'], 'Identity mismatch'
        for table, a, b in [('friend_requests', 'sender', 'recipient'), ('relationships', 'a', 'b')]:
            assert not conn.execute(f'SELECT 1 FROM {table} WHERE ({a}=ANY(%s) OR {b}=ANY(%s)) AND NOT ({a}=ANY(%s) AND {b}=ANY(%s))', (ids, ids, ids, ids)).fetchone()
        assert not conn.execute('SELECT 1 FROM submissions WHERE author_id=ANY(%s)', (ids,)).fetchone()
        for account in accounts:
            conn.execute('DELETE FROM users WHERE id=%s AND username=%s', (account['id'], account['username']))
        assert conn.execute('SELECT count(*) FROM users WHERE id=ANY(%s)', (ids,)).fetchone()[0] == 0
    print(json.dumps({'ok': True, 'temporary_accounts_removed': len(ids)}))


if __name__ == '__main__':
    main()
