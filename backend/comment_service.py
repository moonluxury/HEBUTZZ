"""Bank-wide plain text discussions; reuse authentication, signed cursors and idempotency."""
import hashlib
import json
import os
import re
from datetime import datetime

from psycopg.types.json import Jsonb
from database import one, rows, lock_users
from domain import require, uid, string, integer, stamp, cursor_encode, cursor_decode

READS = {'comment_list', 'comment_replies'}
WRITES = {'comment_create', 'comment_like', 'comment_delete', 'comment_report', 'comment_moderate'}
FIELDS = {
    'comment_list': {'sort', 'limit', 'cursor'},
    'comment_replies': {'parent_id', 'limit', 'cursor'},
    'comment_create': {'body', 'parent_id'},
    'comment_like': {'comment_id', 'value'},
    'comment_delete': {'comment_id'},
    'comment_report': {'comment_id', 'reason'},
    'comment_moderate': {'comment_id', 'decision'},
}

# A page is projected in one database snapshot. Avoid per-comment SQL calls and
# reading an author after a concurrent account deletion has removed that author.
DISPLAY_COLUMNS = """u.profile AS author_profile,u.username AS author_username,
    (SELECT count(*) FROM bank_comment_likes l WHERE l.comment_id=c.id) AS like_count,
    EXISTS(SELECT 1 FROM bank_comment_likes l WHERE l.comment_id=c.id AND l.user_id=%s) AS liked,
    (SELECT count(*) FROM bank_comments r WHERE r.parent_id=c.id
     AND (r.status='published' OR (r.status='pending' AND r.author_id=%s))) AS reply_count"""


def target(conn, actor, p):
    require(p.get('target_type') == 'bank', message='仅支持公开题库讨论。')
    bank = string(p.get('target_id'), 64, False)
    record = one(conn, 'SELECT * FROM discussion_banks WHERE id=%s AND enabled', (bank,))
    require(record is not None, 'not_found', '此题库暂未开放讨论。', 404)
    require(record['public'] or (actor and one(conn, 'SELECT 1 FROM discussion_access WHERE bank_id=%s AND user_id=%s', (bank, actor))),
            'forbidden', '没有访问此题库讨论的权限。', 403)
    return bank


def body_text(value):
    require(isinstance(value, str))
    value = value.strip()
    require(bool(value), message='请输入评论内容。')
    require(re.search(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\ud800-\udfff]', value) is None, message='评论含不支持的控制字符。')
    return value


def comment(conn, bank, id, lock=False):
    row = one(conn, 'SELECT * FROM bank_comments WHERE id=%s AND bank_id=%s' + (' FOR UPDATE' if lock else ''), (string(id, 64, False), bank))
    require(row is not None, 'not_found', '评论不存在或不可访问。', 404)
    return row


def serialize(actor, row):
    readable = row['status'] == 'published' or (row['status'] == 'pending' and actor == row['author_id'])
    return {'id': row['id'], 'bank_id': row['bank_id'], 'parent_id': row['parent_id'] or '',
            'body': row['body'] if readable else '', 'status': row['status'], 'created_at': stamp(row['created_at']),
            'author': {'id': row['author_id'], 'name': row['author_profile'].get('display_name') or row['author_username'], 'avatar_card_id': row['author_profile'].get('avatar_card_id', ''), 'college': row['author_profile'].get('college', '')},
            'like_count': row['like_count'], 'reply_count': row['reply_count'], 'liked': row['liked'],
            'can_delete': row['author_id'] == actor and row['status'] not in {'deleted', 'hidden'}}


def view(conn, actor, row):
    projected = one(conn, f'SELECT c.*, {DISPLAY_COLUMNS} FROM bank_comments c JOIN users u ON u.id=c.author_id WHERE c.id=%s', (actor, actor, row['id']))
    return serialize(actor, projected)


def listing(conn, actor, action, p, bank):
    from comment_capacity import BANK_CHAR_LIMIT, used_chars
    parent = string(p.get('parent_id', ''), 64)
    if action == 'comment_replies':
        root = comment(conn, bank, parent)
        require(root['parent_id'] is None and (root['status'] != 'pending' or root['author_id'] == actor), 'not_found', '无法查看此评论的回复。', 404)
    else:
        require(not parent)
    sort = p.get('sort', 'latest') if not parent else 'latest'
    require(isinstance(sort, str) and sort in {'latest', 'hot'})
    limit = integer(p.get('limit', 20), 1, 20)
    kind = f'bank-comments:{bank}:{parent}:{sort}'
    # Only fixed ordering clauses enter SQL; cursor is authenticated and scoped.
    after, args = '', [bank, parent or None, actor, actor, actor]
    if p.get('cursor'):
        value = cursor_decode(p['cursor'], actor or '', kind)
        require(isinstance(value, list) and len(value) == 3, 'invalid_cursor', '分页标记无效。')
        score, created, id = value
        require(type(score) is int and isinstance(created, str) and isinstance(id, str), 'invalid_cursor', '分页标记无效。')
        try: datetime.fromisoformat(created)
        except ValueError: require(False, 'invalid_cursor', '分页标记无效。')
        if sort == 'hot': after = 'WHERE (c.score,c.created_at,c.id)<(%s,%s::timestamptz,%s)'; args += [score, created, id]
        else: after = 'WHERE (c.created_at,c.id)<(%s::timestamptz,%s)'; args += [created, id]
    order = 'c.score DESC,c.created_at DESC,c.id DESC' if sort == 'hot' else 'c.created_at DESC,c.id DESC'
    score_sql = '(SELECT count(*) FROM bank_comment_likes l WHERE l.comment_id=c.id)' if sort == 'hot' else '0::bigint'
    args.append(limit + 1)
    page = rows(conn, f"""WITH ranked AS (
        SELECT c.*, {score_sql} AS score
        FROM bank_comments c WHERE bank_id=%s AND parent_id IS NOT DISTINCT FROM %s
        AND (status<>'pending' OR author_id=%s))
        SELECT c.*, {DISPLAY_COLUMNS} FROM ranked c JOIN users u ON u.id=c.author_id
        {after} ORDER BY {order} LIMIT %s""", tuple(args))
    selected = page[:limit]
    cursor = ''
    if len(page) > limit:
        last = selected[-1]
        cursor = cursor_encode(actor or '', kind, [last['score'], stamp(last['created_at']), last['id']])
    return {'items': [serialize(actor, row) for row in selected], 'cursor': cursor, 'can_publish': used_chars(conn, bank) < BANK_CHAR_LIMIT}


def handle(conn, actor, action, p, bank):
    from comment_capacity import reserve, released
    if action in READS: return listing(conn, actor, action, p, bank)
    if action == 'comment_create':
        parent = string(p.get('parent_id', ''), 64)
        text = body_text(p.get('body'))
        reserve(conn, bank, len(text))
        if parent:
            root = comment(conn, bank, parent, True)
            require(root['parent_id'] is None and root['status'] == 'published', 'unavailable', '仅可回复可见的一级评论。', 409)
        status = 'pending' if os.environ.get('BANK_COMMENTS_REVIEW_REQUIRED') == '1' else 'published'
        row = one(conn, 'INSERT INTO bank_comments(id,bank_id,author_id,parent_id,body,status) VALUES (%s,%s,%s,%s,%s,%s) RETURNING *',
                  (uid(), bank, actor, parent or None, text, status))
        return {'comment': view(conn, actor, row)}
    row = comment(conn, bank, p.get('comment_id'), True)
    if action == 'comment_delete':
        require(row['author_id'] == actor, 'forbidden', '只能删除自己的评论。', 403)
        if row['body']: released(conn, bank)
        row = one(conn, "UPDATE bank_comments SET status='deleted',body='',updated_at=now() WHERE id=%s RETURNING *", (row['id'],))
    elif action == 'comment_moderate':
        require(one(conn, 'SELECT 1 FROM bank_comment_moderators WHERE user_id=%s', (actor,)), 'forbidden', '没有评论审核权限。', 403)
        require(isinstance(p.get('decision'), str) and p['decision'] in {'published', 'hidden'} and row['status'] != 'deleted')
        row = one(conn, 'UPDATE bank_comments SET status=%s,updated_at=now() WHERE id=%s RETURNING *', (p['decision'], row['id']))
        conn.execute("UPDATE bank_comment_reports SET state='resolved' WHERE comment_id=%s", (row['id'],))
    else:
        require(row['status'] == 'published', 'unavailable', '评论已删除、隐藏或尚未公开。', 409)
        if action == 'comment_like':
            require(type(p.get('value')) is bool)
            if p['value']: conn.execute('INSERT INTO bank_comment_likes(comment_id,user_id) VALUES (%s,%s) ON CONFLICT DO NOTHING', (row['id'], actor))
            else: conn.execute('DELETE FROM bank_comment_likes WHERE comment_id=%s AND user_id=%s', (row['id'], actor))
        elif action == 'comment_report':
            reason = string(p.get('reason'), 300, False)
            conn.execute('INSERT INTO bank_comment_reports(id,comment_id,actor_id,reason) VALUES (%s,%s,%s,%s) ON CONFLICT(comment_id,actor_id) DO NOTHING', (uid(), row['id'], actor, reason))
            return {'message': '举报已记录，等待处理。'}
    return {'comment': view(conn, actor, row)}


def dispatch(conn, actor, action, p, before_action=None):
    require(action in READS | WRITES)
    require(isinstance(p, dict))
    allowed = {'target_type', 'target_id'} | FIELDS[action] | ({'operation_id'} if action in WRITES else set())
    require(not set(p) - allowed, message='评论身份、状态和计数必须由服务器确定。')
    require(action in READS or actor, 'unauthenticated', '请先登录。', 401)
    if actor:
        lock_users(conn, actor)
        if before_action: before_action()
    bank = target(conn, actor, p)
    if action in READS: return {'ok': True, **handle(conn, actor, action, p, bank)}
    operation = string(p.get('operation_id'), 128, False)
    digest = hashlib.sha256(json.dumps(p, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()
    prior = one(conn, 'SELECT * FROM operations WHERE actor=%s AND operation_id=%s', (actor, operation))
    if prior:
        require(prior['action'] == action and prior['request_hash'] == digest, 'idempotency_conflict', '操作编号已用于其他内容。', 409)
        return prior['response']
    if action in {'comment_create', 'comment_delete'}:
        conn.execute('SELECT id FROM discussion_banks WHERE id=%s FOR NO KEY UPDATE', (bank,))
    result = {'ok': True, 'account_id': actor, **handle(conn, actor, action, p, bank)}
    conn.execute('INSERT INTO operations(actor,operation_id,action,request_hash,response) VALUES (%s,%s,%s,%s,%s)', (actor, operation, action, digest, Jsonb(result)))
    return result
