"""Remove abandoned uploads older than one day, never referenced version assets."""
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from database import pool, transaction, rows, lock_users


def cleanup():
    with transaction() as conn:
        candidates=rows(conn,"SELECT a.id,a.owner_id FROM submission_assets a WHERE a.created_at<now()-interval '1 day' AND NOT EXISTS(SELECT 1 FROM submission_revision_assets r WHERE r.asset_id=a.id) ORDER BY a.created_at LIMIT 100")
        if not candidates:return 0
        lock_users(conn,*(a['owner_id'] for a in candidates))
        removed=rows(conn,"DELETE FROM submission_assets a WHERE a.id=ANY(%s) AND a.created_at<now()-interval '1 day' AND NOT EXISTS(SELECT 1 FROM submission_revision_assets r WHERE r.asset_id=a.id) RETURNING a.id",([a['id'] for a in candidates],))
        return len(removed)


if __name__=='__main__':
    pool.open(wait=True)
    try:print('Removed abandoned uploads:',cleanup())
    finally:pool.close()
