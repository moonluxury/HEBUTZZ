"""Delete only exact temporary HTTPS smoke identities; never publish test articles."""
import json
import re
import sys
import psycopg

request=json.load(sys.stdin);accounts=request['accounts']
assert 0<len(accounts)<=2
for a in accounts:
    assert re.fullmatch(r'[0-9a-f]{32}',a['id'])
    assert re.fullmatch(r'submissioncheck_[0-9a-f]{12}[ab]',a['username'])
ids=[a['id'] for a in accounts]
with psycopg.connect('dbname=hegong user=hegong host=/var/run/postgresql') as conn:
    for a in accounts:
        row=conn.execute('SELECT username FROM users WHERE id=%s FOR UPDATE',(a['id'],)).fetchone()
        assert row is None or row[0]==a['username'],'Identity changed; refuse cleanup'
    assert not conn.execute('SELECT 1 FROM published_articles a JOIN submissions s ON s.id=a.submission_id WHERE s.author_id=ANY(%s)',(ids,)).fetchone(),'Test account unexpectedly published'
    assert not conn.execute('SELECT 1 FROM publication_reviews WHERE reviewer_id=ANY(%s)',(ids,)).fetchone()
    conn.execute('DELETE FROM submission_revision_assets WHERE revision_id IN (SELECT r.id FROM submission_revisions r JOIN submissions s ON s.id=r.submission_id WHERE s.author_id=ANY(%s))',(ids,))
    for a in accounts:conn.execute('DELETE FROM users WHERE id=%s AND username=%s',(a['id'],a['username']))
    assert conn.execute('SELECT count(*) FROM users WHERE id=ANY(%s)',(ids,)).fetchone()[0]==0
print(json.dumps({'ok':True,'temporary_accounts_removed':len(ids)}))
