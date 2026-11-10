"""Provision/clean exact temporary live-test identities in a private discussion bank.

Input is non-secret JSON {action,bank,accounts:[{id,username}]} on stdin.
Run as hegong with the normal PostgreSQL peer identity. Never truncate production.
"""
import json
import re
import sys
import psycopg


def main():
    request = json.load(sys.stdin)
    action, bank, accounts = request['action'], request['bank'], request['accounts']
    assert action in {'setup', 'cleanup'}
    assert re.fullmatch(r'commentcheck_[0-9a-f]{16}', bank)
    assert 0 < len(accounts) <= 2
    for account in accounts:
        assert re.fullmatch(r'[0-9a-f]{32}', account['id'])
        assert re.fullmatch(r'commentcheck_[0-9a-f]{16}[ab]', account['username'])
    with psycopg.connect('dbname=hegong user=hegong host=/var/run/postgresql') as conn:
        for account in accounts:
            row = conn.execute('SELECT username FROM users WHERE id=%s FOR UPDATE', (account['id'],)).fetchone()
            assert row is None and action == 'cleanup' or row and row[0] == account['username']
        if action == 'setup':
            conn.execute('INSERT INTO discussion_banks(id,public) VALUES (%s,false)', (bank,))
            for account in accounts:
                conn.execute('INSERT INTO discussion_access(bank_id,user_id) VALUES (%s,%s)', (bank, account['id']))
        else:
            row = conn.execute('SELECT public FROM discussion_banks WHERE id=%s FOR UPDATE', (bank,)).fetchone()
            if row:
                assert row[0] is False
                others = conn.execute('SELECT 1 FROM discussion_access WHERE bank_id=%s AND NOT(user_id=ANY(%s))', (bank, [a['id'] for a in accounts])).fetchone()
                assert others is None
                conn.execute('DELETE FROM bank_comments WHERE bank_id=%s', (bank,))
                conn.execute('DELETE FROM discussion_banks WHERE id=%s', (bank,))
            for account in accounts:
                conn.execute('DELETE FROM users WHERE id=%s AND username=%s', (account['id'], account['username']))
            assert conn.execute('SELECT count(*) FROM users WHERE id=ANY(%s)', ([a['id'] for a in accounts],)).fetchone()[0] == 0
    print(json.dumps({'ok':True, 'action':action, 'temporary_accounts':len(accounts)}))


if __name__ == '__main__': main()
