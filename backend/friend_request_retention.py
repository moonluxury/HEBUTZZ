"""72-hour friend request retention; callers commit each bounded cleanup batch."""
from psycopg.types.json import Jsonb

from database import bump, lock_users, one, rows

FRIEND_ACTIONS = {'request_friend', 'respond_request'}
CLEANUP_LOCK = 72810437


def retention_cutoff(conn):
    # Wall clock, including time spent waiting for account locks; exactly 72 hours.
    return one(conn, "SELECT clock_timestamp() - interval '72 hours' AS cutoff")['cutoff']


def compact_receipt(action, response):
    if action not in FRIEND_ACTIONS or response.get('_friend_receipt') == 1:
        return response
    result = {'_friend_receipt': 1}
    if action == 'request_friend':
        result['request_id'] = response.get('request', {}).get('id', '')
        if response.get('state') == 'friend':
            result['already_friend'] = True
    return result


def delete_expired_requests(conn, candidates, cutoff):
    """Use the API's sorted account lock order, then recheck before deleting."""
    if not candidates:
        return {'requests': 0, 'notifications': 0}
    lock_users(conn, *(r[k] for r in candidates for k in ('sender', 'recipient')))
    deleted = rows(conn, '''DELETE FROM friend_requests
        WHERE id=ANY(%s) AND created_at<=%s RETURNING id,sender,recipient''',
        ([r['id'] for r in candidates], cutoff))
    notifications = conn.execute('''DELETE FROM messages
        WHERE record_id=ANY(%s) AND kind='notification'
          AND body->>'event'='friend_request' ''', ([r['id'] for r in deleted],)).rowcount
    if deleted:
        bump(conn, *(r[k] for r in deleted for k in ('sender', 'recipient')))
    return {'requests': len(deleted), 'notifications': notifications}


def cleanup_batch(conn, limit=200, *, cutoff=None):
    if not 1 <= limit <= 1000:
        raise ValueError('Batch size must be between 1 and 1000')
    if not one(conn, 'SELECT pg_try_advisory_xact_lock(%s) AS acquired', (CLEANUP_LOCK,))['acquired']:
        return {'skipped': True, 'requests': 0, 'notifications': 0, 'receipts': 0}
    cutoff = retention_cutoff(conn) if cutoff is None else cutoff
    candidates = rows(conn, '''SELECT id,sender,recipient FROM friend_requests
        WHERE created_at<=%s ORDER BY created_at,id LIMIT %s''', (cutoff, limit))
    result = delete_expired_requests(conn, candidates, cutoff)
    # Keep small idempotency keys, not old request/profile/sync snapshots. Deleting
    # keys would allow a delayed retry of a sent request to create it again.
    receipts = rows(conn, '''SELECT actor,operation_id,action,response FROM operations
        WHERE action IN ('request_friend','respond_request')
          AND NOT response @> '{"_friend_receipt":1}'::jsonb
        ORDER BY created_at,actor,operation_id LIMIT %s FOR UPDATE SKIP LOCKED''', (limit,))
    for receipt in receipts:
        conn.execute('UPDATE operations SET response=%s WHERE actor=%s AND operation_id=%s',
                     (Jsonb(compact_receipt(receipt['action'], receipt['response'])),
                      receipt['actor'], receipt['operation_id']))
    return {**result, 'receipts': len(receipts), 'skipped': False}
