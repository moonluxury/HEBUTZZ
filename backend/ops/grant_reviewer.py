"""Explicit server-operator role management; never called by the desktop app."""
import argparse
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from database import pool, transaction, one

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('user_id')
    parser.add_argument('--can-publish',action='store_true')
    parser.add_argument('--revoke',action='store_true')
    args=parser.parse_args()
    pool.open(wait=True)
    try:
        with transaction() as conn:
            if one(conn,'SELECT 1 FROM users WHERE id=%s AND NOT disabled',(args.user_id,)) is None: raise SystemExit('Unknown account')
            if args.revoke: conn.execute('DELETE FROM publication_reviewers WHERE user_id=%s',(args.user_id,))
            else: conn.execute('INSERT INTO publication_reviewers(user_id,can_publish) VALUES (%s,%s) ON CONFLICT(user_id) DO UPDATE SET can_publish=EXCLUDED.can_publish',(args.user_id,args.can_publish))
        print('Reviewer role updated for the specified account')
    finally: pool.close()
