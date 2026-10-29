import base64
import hashlib
import hmac
import json
import os
import secrets
import uuid
from datetime import datetime, timezone
from pathlib import Path

from psycopg.types.json import Jsonb

from database import one, rows, lock_users, bump

CATALOG = json.loads(Path(os.environ.get('CATALOG_PATH', Path(__file__).with_name('collection_catalog.json'))).read_text(encoding='utf-8'))
CARDS = {c['id']: c for c in CATALOG['cards']}
CURSOR_KEY = os.environ['CURSOR_SECRET'].encode()
FIELDS = {'display_name': 40, 'school': 80, 'college': 80, 'major': 80, 'grade': 30, 'bio': 300}


class DomainError(Exception):
    def __init__(self, code, message, status=400):
        self.code, self.message, self.status = code, message, status


def require(condition, code='invalid_request', message='请求参数不正确。', status=400):
    if not condition:
        raise DomainError(code, message, status)


def uid():
    return uuid.uuid4().hex


def string(value, maximum, allow_empty=True):
    require(isinstance(value, str) and len(value) <= maximum)
    value = value.strip()
    require(allow_empty or bool(value))
    require('\x00' not in value)
    return value


def integer(value, low=0, high=1000000):
    require(type(value) is int and low <= value <= high)
    return value


def stamp(value):
    return value.astimezone(timezone.utc).isoformat() if value else ''


def cursor_encode(actor, kind, value):
    raw = json.dumps([actor, kind, value], separators=(',', ':')).encode()
    sig = hmac.new(CURSOR_KEY, raw, hashlib.sha256).digest()
    return base64.urlsafe_b64encode(sig + raw).decode().rstrip('=')


def cursor_decode(token, actor, kind):
    try:
        require(isinstance(token, str) and len(token) <= 2048)
        data = base64.urlsafe_b64decode(token + '=' * (-len(token) % 4))
        signature, raw = data[:32], data[32:]
        require(hmac.compare_digest(signature, hmac.new(CURSOR_KEY, raw, hashlib.sha256).digest()))
        a, k, value = json.loads(raw)
        require(a == actor and k == kind)
        return value
    except Exception:
        raise DomainError('invalid_cursor', '分页标记无效，请重新加载。') from None


def user(conn, user_id):
    value = one(conn, 'SELECT * FROM users WHERE id=%s AND NOT disabled', (user_id,))
    require(value is not None, 'not_found', '用户不存在或不可访问。', 404)
    return value


def public_user(conn, actor, user_id):
    u = user(conn, user_id)
    pref = one(conn, 'SELECT remark FROM preferences WHERE actor=%s AND peer=%s', (actor, user_id))
    return {'id': u['id'], 'public_id': u['public_id'], 'name': u['profile'].get('display_name') or u['username'],
            'avatar_card_id': u['profile'].get('avatar_card_id', ''), 'remark': pref['remark'] if pref else ''}


def relation(conn, actor, peer):
    a, b = sorted([actor, peer])
    r = one(conn, 'SELECT * FROM relationships WHERE a=%s AND b=%s', (a, b))
    if not r:
        return {'friends': False, 'blocked': False, 'by_me': False}
    return {'friends': r['friends'], 'blocked': r['blocked_a'] or r['blocked_b'],
            'by_me': r['blocked_a' if actor == a else 'blocked_b']}


def require_friend(conn, actor, peer):
    r = relation(conn, actor, peer)
    require(r['friends'] and not r['blocked'], 'forbidden', '操作需要双方仍为好友且未被屏蔽。', 403)


def conversation(conn, actor, peer, kind='direct'):
    a, b = sorted([actor, peer])
    row = one(conn, 'INSERT INTO conversations(id,kind,a,b) VALUES (%s,%s,%s,%s) ON CONFLICT(kind,a,b) DO UPDATE SET kind=EXCLUDED.kind RETURNING *', (uid(), kind, a, b))
    for member in set([a, b]):
        conn.execute('INSERT INTO conversation_members(conversation_id,user_id) VALUES (%s,%s) ON CONFLICT DO NOTHING', (row['id'], member))
    return row


def get_conversation(conn, actor, cid):
    c = one(conn, 'SELECT c.* FROM conversations c JOIN conversation_members m ON m.conversation_id=c.id WHERE c.id=%s AND m.user_id=%s', (cid, actor))
    require(c is not None, 'inaccessible', '无法访问该会话。', 403)
    return c


def peer_of(c, actor):
    return c['b'] if c['a'] == actor else c['a']


def send_permission(conn, actor, c):
    if c['kind'] == 'system':
        return False, '系统通知仅供阅读。'
    peer = peer_of(c, actor)
    r = relation(conn, actor, peer)
    if r['blocked']:
        return False, '当前无法向该用户发送消息。'
    if r['friends']:
        return True, ''
    # The permanent conversation preserves the single unanswered greeting allowance.
    sent = one(conn, "SELECT count(*) n FROM messages WHERE conversation_id=%s AND sender=%s AND kind='text'", (c['id'], actor))['n']
    return (True, '') if sent == 0 else (False, '成为好友后才能继续发送消息。')


def message_view(m):
    result = {'id': m['id'], 'conversation_id': m['conversation_id'], 'sender_id': m['sender'] or '',
              'seq': m['seq'], 'type': m['kind'], 'text': m['text'], 'time_label': stamp(m['created_at']),
              'date_label': stamp(m['created_at'])[:10], 'record_id': m['record_id'] or ''}
    if m['client_id']:
        result['client_id'] = m['client_id']
    result.update(m['body'])
    return result


def add_message(conn, c, sender, kind, text='', record_id=None, client_id=None, body=None):
    return one(conn, 'INSERT INTO messages(id,conversation_id,sender,kind,text,record_id,client_id,body) VALUES (%s,%s,%s,%s,%s,%s,%s,%s) RETURNING *',
               (uid(), c['id'], sender, kind, text, record_id, client_id, Jsonb(body or {})))


def notify(conn, target, title, body, event='friend_request', record_id=None):
    c = conversation(conn, target, target, 'system')
    add_message(conn, c, None, 'notification', body= {'title': title, 'body': body, 'summary': title, 'event': event}, record_id=record_id)


def conversation_view(conn, actor, c):
    member = one(conn, 'SELECT read_seq FROM conversation_members WHERE conversation_id=%s AND user_id=%s', (c['id'], actor))
    last = one(conn, 'SELECT * FROM messages WHERE conversation_id=%s ORDER BY seq DESC LIMIT 1', (c['id'],))
    unread = one(conn, 'SELECT count(*) n FROM messages WHERE conversation_id=%s AND seq>%s AND sender IS DISTINCT FROM %s', (c['id'], member['read_seq'], actor))['n']
    can_send, reason = send_permission(conn, actor, c)
    result = {'id': c['id'], 'kind': c['kind'], 'can_send': can_send, 'send_reason': reason,
              'read_seq': member['read_seq'], 'unread': unread, 'activity_seq': last['seq'] if last else 0,
              'summary': (last['text'] or last['body'].get('summary', '')) if last else '',
              'time_label': stamp(last['created_at']) if last else '', 'muted': False}
    if c['kind'] == 'system':
        result['name'] = '系统通知'
    else:
        peer = peer_of(c, actor)
        r = relation(conn, actor, peer)
        pref = one(conn, 'SELECT muted FROM preferences WHERE actor=%s AND peer=%s', (actor, peer))
        result.update(peer=public_user(conn, actor, peer), is_friend=r['friends'], blocked_by_me=r['by_me'], muted=pref['muted'] if pref else False)
    return result


def friends(conn, actor, query=''):
    found = rows(conn, 'SELECT CASE WHEN a=%s THEN b ELSE a END peer FROM relationships WHERE (a=%s OR b=%s) AND friends AND NOT blocked_a AND NOT blocked_b', (actor, actor, actor))
    result = []
    for item in found:
        p = public_user(conn, actor, item['peer'])
        if query.lower() not in ' '.join([p['name'], p['remark'], p['public_id']]).lower():
            continue
        c = one(conn, "SELECT id FROM conversations WHERE kind='direct' AND a=%s AND b=%s", tuple(sorted([actor, item['peer']])))
        p.update(eligible=True, conversation_id=c['id'] if c else '')
        result.append(p)
    return result


def request_view(conn, actor, r):
    return {'id': r['id'], 'seq': r['seq'], 'direction': 'sent' if r['sender'] == actor else 'received',
            'peer': public_user(conn, actor, r['recipient'] if r['sender'] == actor else r['sender']),
            'note': r['note'], 'status': r['status'], 'time_label': stamp(r['created_at'])}


def transfer_view(conn, actor, t):
    return {'id': t['id'], 'initiator_id': t['initiator'], 'recipient_id': t['recipient'],
            'initiator': public_user(conn, actor, t['initiator']), 'recipient': public_user(conn, actor, t['recipient']),
            'give': t['give'], 'receive': t['receive'], 'terms_version': t['terms_version'], 'revision': t['revision'],
            'conversation_id': t['conversation_id'], 'status': t['status'], 'time_label': stamp(t['created_at']),
            'result_label': t['status']}


def get_transfer(conn, actor, tid):
    t = one(conn, 'SELECT * FROM transfers WHERE id=%s AND (initiator=%s OR recipient=%s)', (tid, actor, actor))
    require(t is not None, 'inaccessible', '无法访问该业务记录。', 403)
    return t


def snapshot(conn, actor):
    u = user(conn, actor)
    inventory = {c: {'count': 0, 'giftable_count': 0, 'exchangeable_count': 0} for c in CARDS}
    for row in rows(conn, 'SELECT card_id,count FROM inventory WHERE user_id=%s', (actor,)):
        if row['card_id'] in inventory:
            inventory[row['card_id']] = {'count': row['count'], 'giftable_count': max(0, row['count'] - 1), 'exchangeable_count': row['count'], 'gift_reason': '每种卡片需至少保留 1 张。'}
    return {'inventory_complete': True, 'revision': u['revision'], 'inventory': inventory}


def sync(conn, actor, token=''):
    u = user(conn, actor)
    last_seq = 0
    if token:
        last_seq = integer(cursor_decode(token, actor, 'sync'), high=2**63-1)
    convs = rows(conn, 'SELECT c.* FROM conversations c JOIN conversation_members m ON m.conversation_id=c.id WHERE m.user_id=%s', (actor,))
    reqs = rows(conn, "SELECT * FROM friend_requests WHERE sender=%s OR recipient=%s ORDER BY seq DESC LIMIT 300", (actor, actor))
    pending = one(conn, "SELECT count(*) n FROM friend_requests WHERE recipient=%s AND status='pending'", (actor,))['n']
    unseen = one(conn, 'SELECT count(*) n FROM friend_requests WHERE recipient=%s AND seq>%s', (actor, u['requests_read']))['n']
    if token:
        msgs = rows(conn, 'SELECT x.* FROM messages x JOIN conversation_members m ON m.conversation_id=x.conversation_id WHERE m.user_id=%s AND x.seq>%s ORDER BY x.seq LIMIT 2000', (actor, last_seq))
        # An overflow triggers a fresh snapshot; never advance past undelivered events.
        require(len(msgs) < 2000, 'cursor_expired', '增量较多，请重新同步。', 409)
    else:
        msgs = rows(conn, 'SELECT x.* FROM conversation_members m CROSS JOIN LATERAL (SELECT * FROM messages WHERE conversation_id=m.conversation_id ORDER BY seq DESC LIMIT 40) x WHERE m.user_id=%s ORDER BY x.seq', (actor,))
    watermark = max([last_seq] + [m['seq'] for m in msgs])
    trades = rows(conn, "SELECT * FROM transfers WHERE kind='trade' AND (initiator=%s OR recipient=%s) ORDER BY updated_at DESC LIMIT 200", (actor, actor))
    return {'revision': u['revision'], 'cursor': cursor_encode(actor, 'sync', watermark), 'friends': friends(conn, actor),
            'conversations': [conversation_view(conn, actor, c) for c in convs],
            'requests': [request_view(conn, actor, r) for r in reqs], 'pending_requests': pending, 'request_unread': unseen,
            'capabilities': {'exchange': True, 'reports': True}, 'messages': [message_view(m) for m in msgs],
            'trades': [transfer_view(conn, actor, t) for t in trades]}


def profile_view(conn, actor):
    u = user(conn, actor)
    return {'profile': {**{f: '' for f in FIELDS}, 'avatar_card_id': '', **u['profile'], 'public_id': u['public_id']},
            'editable_fields': {**{f: {'max_length': n} for f, n in FIELDS.items()}, 'avatar_card_id': {'owned_cards_only': True, 'reset_supported': True}}}


def save_profile(conn, actor, payload):
    patch = payload.get('patch', {})
    require(isinstance(patch, dict) and set(patch).issubset(FIELDS))
    changes = {f: string(v, FIELDS[f], allow_empty=f != 'display_name') for f, v in patch.items()}
    card = string(payload.get('avatar_card_id', ''), 64)
    avatar_change = payload.get('avatar_change', False)
    require(type(avatar_change) is bool)
    if card:
        require(card in CARDS)
        owned = one(conn, 'SELECT count FROM inventory WHERE user_id=%s AND card_id=%s', (actor, card))
        require(owned is not None and owned['count'] > 0, 'forbidden', '只能选择当前拥有的卡牌头像。', 403)
        changes['avatar_card_id'] = card
    elif avatar_change:
        # The existing empty value denotes the default avatar; no synthetic card ID.
        changes['avatar_card_id'] = ''
    conn.execute('UPDATE users SET profile=profile || %s WHERE id=%s', (Jsonb(changes), actor))
    bump(conn, actor)
    return {**profile_view(conn, actor), 'persisted': True}


def lines(value):
    require(isinstance(value, list) and 0 < len(value) <= 50)
    counts = {}
    for line in value:
        require(isinstance(line, dict) and set(line) == {'card_id', 'season_id', 'quantity'})
        card_id = string(line['card_id'], 64, False)
        require(card_id in CARDS and line['season_id'] == CARDS[card_id]['season_id'])
        counts[card_id] = counts.get(card_id, 0) + integer(line['quantity'], 1)
        integer(counts[card_id], 1)
    return [{'card_id': c, 'season_id': CARDS[c]['season_id'], 'quantity': n} for c, n in sorted(counts.items())]


def ensure_stock(conn, owner, items, keep_one=False):
    for line in items:
        owned = one(conn, 'SELECT count FROM inventory WHERE user_id=%s AND card_id=%s', (owner, line['card_id']))
        require(owned is not None and owned['count'] >= line['quantity'] + int(keep_one), 'insufficient_stock', '可转出卡牌不足；赠送时每种卡片至少保留 1 张。', 409)


def transfer_stock(conn, t):
    # Called after both user locks, sharing the same boundary with relationships and avatars.
    require_friend(conn, t['initiator'], t['recipient'])
    ensure_stock(conn, t['initiator'], t['give'], keep_one=t['kind'] == 'gift')
    if t['receive']:
        ensure_stock(conn, t['recipient'], t['receive'])
    for leg, sender, receiver, items in [('give', t['initiator'], t['recipient'], t['give']), ('receive', t['recipient'], t['initiator'], t['receive'])]:
        for line in items:
            cid, qty = line['card_id'], line['quantity']
            conn.execute('UPDATE inventory SET count=count-%s WHERE user_id=%s AND card_id=%s', (qty, sender, cid))
            conn.execute('INSERT INTO inventory(user_id,card_id,count) VALUES (%s,%s,%s) ON CONFLICT(user_id,card_id) DO UPDATE SET count=inventory.count+EXCLUDED.count', (receiver, cid, qty))
            for person, delta in [(sender, -qty), (receiver, qty)]:
                conn.execute('INSERT INTO inventory_ledger(record_id,user_id,card_id,delta,leg) VALUES (%s,%s,%s,%s,%s)', (t['id'], person, cid, delta, leg))
    conn.execute("UPDATE transfers SET status='completed',revision=revision+1,updated_at=now() WHERE id=%s", (t['id'],))
    project_event(conn, t, 'completed')
    bump(conn, t['initiator'], t['recipient'])


def project_event(conn, t, event):
    event_id = t['id'] + ':' + event
    inserted = one(conn, 'INSERT INTO outbox(event_id,record_id,event) VALUES (%s,%s,%s) ON CONFLICT DO NOTHING RETURNING event_id', (event_id, t['id'], event))
    if not inserted:
        return
    # Message projection is atomic with the outbox and inventory commit; no external delivery side effect.
    c = get_conversation(conn, t['initiator'], t['conversation_id'])
    add_message(conn, c, t['initiator'], t['kind'], record_id=t['id'], body={'summary': ('卡牌赠送' if t['kind'] == 'gift' else '卡牌交换') + ' · ' + event})


MUTATIONS = {'open_conversation', 'send_text', 'request_friend', 'respond_request', 'preferences', 'relationship', 'mark_read', 'mark_all_read', 'mark_requests_read', 'create_trade', 'trade_action', 'report', 'save_profile', 'send_gift', 'study_save'}
IDEMPOTENT = {'request_friend', 'respond_request', 'preferences', 'relationship', 'mark_all_read', 'create_trade', 'trade_action', 'report', 'send_gift'}


def prepare_locks(conn, actor, action, p):
    peers = [actor]
    if action in {'open_conversation', 'request_friend', 'preferences', 'relationship', 'create_trade', 'report'}:
        peer = string(p.get('peer_id'), 64, False)
        require(peer != actor, 'self', '不能对自己执行该操作。')
        user(conn, peer)
        peers.append(peer)
    elif action == 'send_gift':
        peer = string(p.get('friend_id'), 64, False)
        require(peer != actor)
        user(conn, peer)
        peers.append(peer)
    elif action in {'send_text', 'mark_read'}:
        c = get_conversation(conn, actor, string(p.get('conversation_id'), 64, False))
        peers.append(peer_of(c, actor))
    elif action == 'respond_request':
        r = one(conn, 'SELECT * FROM friend_requests WHERE id=%s AND recipient=%s', (string(p.get('request_id'), 64, False), actor))
        require(r is not None, 'inaccessible', '无法处理该申请。', 403)
        peers.append(r['sender'])
    elif action == 'trade_action':
        t = get_transfer(conn, actor, string(p.get('trade_id'), 64, False))
        peers += [t['initiator'], t['recipient']]
    if action in MUTATIONS:
        lock_users(conn, *peers)
    else:
        conn.execute('SELECT id FROM users WHERE id=%s FOR SHARE', (actor,)).fetchone()


def dispatch(conn, actor, action, p, before_action=None):
    require(isinstance(p, dict))
    require(not (set(p) & {'account_id', 'actor_id', 'sender_id', 'type', 'status'}), message='身份和业务类型必须由服务器确定。')
    prepare_locks(conn, actor, action, p)
    if before_action:
        before_action()
    operation_id = None
    request_hash = hashlib.sha256(json.dumps(p, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()
    if action in IDEMPOTENT or (action == 'save_profile' and 'operation_id' in p):
        operation_id = string(p.get('operation_id'), 128, False)
        previous = one(conn, 'SELECT * FROM operations WHERE actor=%s AND operation_id=%s', (actor, operation_id))
        if previous:
            require(previous['action'] == action and previous['request_hash'] == request_hash, 'idempotency_conflict', '操作编号已经用于不同的请求。', 409)
            return previous['response']
    try:
        with conn.transaction():
            result = handle(conn, actor, action, p)
    except DomainError as error:
        if action != 'send_gift':
            raise
        result = {**snapshot(conn, actor), 'ok': False, 'code': error.code, 'message': error.message,
                  'operation_id': p['operation_id'], 'state': 'failed', 'definitive': True}
    result = {'ok': True, 'account_id': actor, **result}
    if operation_id:
        conn.execute('INSERT INTO operations(actor,operation_id,action,request_hash,response) VALUES (%s,%s,%s,%s,%s)', (actor, operation_id, action, request_hash, Jsonb(result)))
    return result


def handle(conn, actor, action, p):
    if action == 'profile':
        return profile_view(conn, actor)
    if action == 'save_profile':
        return save_profile(conn, actor, p)
    if action == 'account':
        return {'login_method': '账号密码', 'username': user(conn, actor)['username']}
    if action == 'snapshot':
        return snapshot(conn, actor)
    if action == 'friends':
        return {'friends': friends(conn, actor, string(p.get('query', ''), 120))}
    if action == 'sync':
        return sync(conn, actor, p.get('cursor', ''))
    if action == 'find_user':
        found = one(conn, 'SELECT id FROM users WHERE public_id=%s AND NOT disabled', (string(p.get('public_id'), 32, False),))
        if not found:
            return {'state': 'not_found'}
        peer = found['id']
        r = relation(conn, actor, peer)
        if r['blocked']:
            return {'state': 'inaccessible'}
        req = one(conn, "SELECT sender FROM friend_requests WHERE LEAST(sender,recipient)=%s AND GREATEST(sender,recipient)=%s AND status='pending'", tuple(sorted([actor, peer])))
        state = 'self' if peer == actor else 'friend' if r['friends'] else ('outgoing' if req['sender'] == actor else 'incoming') if req else 'available'
        return {'state': state, 'user': public_user(conn, actor, peer)}
    if action == 'open_conversation':
        require(not relation(conn, actor, p['peer_id'])['blocked'], 'inaccessible', '当前无法访问该用户。', 403)
        c = conversation(conn, actor, p['peer_id'])
        bump(conn, actor, p['peer_id'])
        return {'conversation': conversation_view(conn, actor, c)}
    if action == 'history':
        c = get_conversation(conn, actor, string(p.get('conversation_id'), 64, False))
        limit = integer(p.get('limit', 40), 1, 100)
        before = cursor_decode(p['before'], actor, 'history:' + c['id']) if p.get('before') else 2**63-1
        page = rows(conn, 'SELECT * FROM messages WHERE conversation_id=%s AND seq<%s ORDER BY seq DESC LIMIT %s', (c['id'], integer(before, high=2**63-1), limit + 1))
        has_more = len(page) > limit
        page = page[:limit]
        return {'messages': [message_view(m) for m in reversed(page)], 'next_before': cursor_encode(actor, 'history:' + c['id'], page[-1]['seq']) if has_more else ''}
    if action == 'send_text':
        c = get_conversation(conn, actor, p['conversation_id'])
        client_id = string(p.get('client_id'), 128, False)
        string(p.get('text'), 2000, False)
        text = p['text']  # Idempotency binds the original text, including whitespace.
        previous = one(conn, 'SELECT * FROM messages WHERE sender=%s AND client_id=%s', (actor, client_id))
        if previous:
            require(previous['conversation_id'] == c['id'] and previous['text'] == text, 'idempotency_conflict', '消息编号已经用于其他内容。', 409)
            return {'message_record': message_view(previous)}
        allowed, reason = send_permission(conn, actor, c)
        require(allowed, 'forbidden', reason, 403)
        m = add_message(conn, c, actor, 'text', text, client_id=client_id)
        bump(conn, c['a'], c['b'])
        return {'message_record': message_view(m)}
    if action == 'request_friend':
        peer = p['peer_id']
        note = string(p.get('note', ''), 120)
        r = relation(conn, actor, peer)
        require(not r['blocked'], 'inaccessible', '当前无法向该用户申请好友。', 403)
        if r['friends']:
            return {'message': '你们已经是好友。'}
        existing = one(conn, "SELECT * FROM friend_requests WHERE LEAST(sender,recipient)=%s AND GREATEST(sender,recipient)=%s AND status='pending'", tuple(sorted([actor, peer])))
        if not existing:
            existing = one(conn, "INSERT INTO friend_requests(id,sender,recipient,note,status) VALUES (%s,%s,%s,%s,'pending') RETURNING *", (uid(), actor, peer, note))
            notify(conn, peer, '收到好友申请', '有新的好友申请，请前往好友申请查看。', record_id=existing['id'])
            bump(conn, actor, peer)
        return {'request': request_view(conn, actor, existing), 'message': '已有待处理的好友申请。'}
    if action == 'respond_request':
        decision = p.get('decision')
        require(decision in {'accept', 'ignore'})
        r = one(conn, 'SELECT * FROM friend_requests WHERE id=%s AND recipient=%s', (p['request_id'], actor))
        if r['status'] == 'pending':
            require(not relation(conn, actor, r['sender'])['blocked'], 'forbidden', '当前无法处理该申请。', 403)
            conn.execute('UPDATE friend_requests SET status=%s WHERE id=%s', ('accepted' if decision == 'accept' else 'ignored', r['id']))
            if decision == 'accept':
                a, b = sorted([actor, r['sender']])
                conn.execute('INSERT INTO relationships(a,b,friends) VALUES (%s,%s,true) ON CONFLICT(a,b) DO UPDATE SET friends=true', (a, b))
                conversation(conn, actor, r['sender'])
                notify(conn, r['sender'], '好友申请已通过', '你们现在可以发送消息和交换卡牌。', record_id=r['id'])
            bump(conn, actor, r['sender'])
        return {'sync': sync(conn, actor), 'message': '申请处理完成。'}
    if action == 'preferences':
        peer = p['peer_id']
        require_friend(conn, actor, peer)
        old = one(conn, 'SELECT * FROM preferences WHERE actor=%s AND peer=%s', (actor, peer)) or {'remark': '', 'muted': False}
        remark = string(p.get('remark', old['remark']), 40)
        muted = p.get('muted', old['muted'])
        require(type(muted) is bool)
        conn.execute('INSERT INTO preferences(actor,peer,remark,muted) VALUES (%s,%s,%s,%s) ON CONFLICT(actor,peer) DO UPDATE SET remark=EXCLUDED.remark,muted=EXCLUDED.muted', (actor, peer, remark, muted))
        bump(conn, actor)
        return {'sync': sync(conn, actor)}
    if action == 'relationship':
        peer, operation = p['peer_id'], p.get('operation')
        require(operation in {'remove', 'block', 'unblock'})
        a, b = sorted([actor, peer])
        conn.execute('INSERT INTO relationships(a,b) VALUES (%s,%s) ON CONFLICT DO NOTHING', (a, b))
        if operation == 'remove':
            conn.execute('UPDATE relationships SET friends=false WHERE a=%s AND b=%s', (a, b))
        else:
            field = 'blocked_a' if actor == a else 'blocked_b'
            conn.execute(f'UPDATE relationships SET {field}=%s,friends=false WHERE a=%s AND b=%s', (operation == 'block', a, b))
        if operation != 'unblock':
            conn.execute("UPDATE friend_requests SET status='invalidated' WHERE LEAST(sender,recipient)=%s AND GREATEST(sender,recipient)=%s AND status='pending'", (a, b))
            pending = rows(conn, "UPDATE transfers SET status='invalidated',revision=revision+1,updated_at=now() WHERE LEAST(initiator,recipient)=%s AND GREATEST(initiator,recipient)=%s AND status='pending' RETURNING *", (a, b))
            for t in pending:
                project_event(conn, t, 'invalidated')
        bump(conn, actor, peer)
        return {'sync': sync(conn, actor)}
    if action == 'blacklist':
        found = rows(conn, 'SELECT CASE WHEN a=%s THEN b ELSE a END peer FROM relationships WHERE (a=%s AND blocked_a) OR (b=%s AND blocked_b)', (actor, actor, actor))
        return {'users': [public_user(conn, actor, r['peer']) for r in found]}
    if action == 'mark_read':
        c = get_conversation(conn, actor, p['conversation_id'])
        through = integer(p.get('through_seq'), high=2**63-1)
        actual = one(conn, 'SELECT COALESCE(max(seq),0) n FROM messages WHERE conversation_id=%s AND seq<=%s', (c['id'], through))['n']
        conn.execute('UPDATE conversation_members SET read_seq=GREATEST(read_seq,%s) WHERE conversation_id=%s AND user_id=%s', (actual, c['id'], actor))
        bump(conn, actor)
        return {'sync': sync(conn, actor)}
    if action in {'mark_requests_read', 'mark_all_read'}:
        through = integer(p.get('through_seq', 2**63-1), high=2**63-1)
        actual = one(conn, 'SELECT COALESCE(max(seq),0) n FROM friend_requests WHERE recipient=%s AND seq<=%s', (actor, through))['n']
        conn.execute('UPDATE users SET requests_read=GREATEST(requests_read,%s) WHERE id=%s', (actual, actor))
        if action == 'mark_all_read':
            conn.execute('UPDATE conversation_members m SET read_seq=GREATEST(read_seq,COALESCE((SELECT max(seq) FROM messages WHERE conversation_id=m.conversation_id),0)) WHERE user_id=%s', (actor,))
        bump(conn, actor)
        return {'sync': sync(conn, actor)}
    if action == 'wishlist':
        require_friend(conn, actor, string(p.get('peer_id'), 64, False))
        raise DomainError('unavailable', '收藏想要目前保存在对方设备，尚未开启云端同步。', 409)
    if action in {'create_trade', 'send_gift'}:
        peer = p['peer_id'] if action == 'create_trade' else p['friend_id']
        require_friend(conn, actor, peer)
        if action == 'create_trade':
            require(integer(p.get('terms_version'), 1, 1) == 1)
            give, receive = lines(p.get('give')), lines(p.get('receive'))
        else:
            card_id = string(p.get('card_id'), 64, False)
            require(card_id in CARDS)
            give, receive = lines([{'card_id': card_id, 'season_id': CARDS[card_id]['season_id'], 'quantity': p.get('quantity')}]), []
        ensure_stock(conn, actor, give, keep_one=action == 'send_gift')
        c = conversation(conn, actor, peer)
        kind = 'gift' if action == 'send_gift' else 'trade'
        t = one(conn, "INSERT INTO transfers(id,kind,initiator,recipient,give,receive,status,conversation_id) VALUES (%s,%s,%s,%s,%s,%s,'pending',%s) RETURNING *", (uid(), kind, actor, peer, Jsonb(give), Jsonb(receive), c['id']))
        if action == 'send_gift':
            transfer_stock(conn, t)
            return {**snapshot(conn, actor), 'operation_id': p['operation_id'], 'state': 'succeeded', 'record_id': t['id']}
        project_event(conn, t, 'pending')
        bump(conn, actor, peer)
        return {'trade': transfer_view(conn, actor, t)}
    if action == 'gift_status':
        op = one(conn, "SELECT response FROM operations WHERE actor=%s AND operation_id=%s AND action='send_gift'", (actor, string(p.get('operation_id'), 128, False)))
        if op:
            return {**op['response'], **snapshot(conn, actor)}
        return {'operation_id': p['operation_id'], 'state': 'unknown', 'ok': False, 'code': 'unknown', 'message': '尚未找到已提交的赠送结果，请重试原操作。'}
    if action == 'trade_action':
        t = get_transfer(conn, actor, p['trade_id'])
        decision = p.get('decision')
        require(decision in {'confirm', 'cancel', 'reject'})
        require(actor == (t['initiator'] if decision == 'cancel' else t['recipient']), 'forbidden', '你无权执行该交易操作。', 403)
        require(integer(p.get('terms_version'), 1, 1) == t['terms_version'], 'terms_changed', '交换条款版本不一致。', 409)
        if t['status'] == 'pending':
            if decision == 'confirm':
                transfer_stock(conn, t)
            else:
                status = 'cancelled' if decision == 'cancel' else 'rejected'
                conn.execute('UPDATE transfers SET status=%s,revision=revision+1,updated_at=now() WHERE id=%s', (status, t['id']))
                project_event(conn, t, status)
                bump(conn, t['initiator'], t['recipient'])
        return {'trade': transfer_view(conn, actor, get_transfer(conn, actor, t['id']))}
    if action in {'trade_detail', 'gift_detail'}:
        t = get_transfer(conn, actor, string(p.get('record_id'), 64, False))
        require(t['kind'] == ('trade' if action == 'trade_detail' else 'gift'))
        view = transfer_view(conn, actor, t)
        return {'trade': view} if action == 'trade_detail' else {'gift': {**view, 'summary': '卡牌赠送已完成。'}}
    if action == 'trade_records':
        limit = integer(p.get('limit', 40), 1, 100)
        peer = string(p.get('peer_id', ''), 64)
        kind = 'trades:' + peer
        boundary = cursor_decode(p['before'], actor, kind) if p.get('before') else ['9999-12-31T00:00:00+00:00', 'z']
        page = rows(conn, "SELECT * FROM transfers WHERE kind='trade' AND (initiator=%s OR recipient=%s) AND (%s='' OR initiator=%s OR recipient=%s) AND (created_at,id)<(%s::timestamptz,%s) ORDER BY created_at DESC,id DESC LIMIT %s", (actor, actor, peer, peer, peer, boundary[0], boundary[1], limit + 1))
        has_more = len(page) > limit
        page = page[:limit]
        return {'trades': [transfer_view(conn, actor, t) for t in page], 'next_before': cursor_encode(actor, kind, [stamp(page[-1]['created_at']), page[-1]['id']]) if has_more else ''}
    if action == 'report':
        peer = p['peer_id']
        require(p.get('reason') in {'harassment', 'fraud', 'content', 'other'})
        note = string(p.get('note', ''), 500)
        ids = p.get('message_ids', [])
        require(isinstance(ids, list) and len(ids) <= 20 and all(isinstance(i, str) and len(i) <= 64 for i in ids))
        for mid in ids:
            found = one(conn, 'SELECT c.a,c.b FROM messages m JOIN conversations c ON c.id=m.conversation_id WHERE m.id=%s', (mid,))
            require(found is not None and set([found['a'], found['b']]) == set([actor, peer]), 'inaccessible', '举报只能包含你与对方会话中的消息。', 403)
        rid = uid()
        conn.execute('INSERT INTO reports(id,actor,peer,reason,note,message_ids) VALUES (%s,%s,%s,%s,%s,%s)', (rid, actor, peer, p['reason'], note, Jsonb(ids)))
        return {'report_id': rid, 'message': '举报已保存，等待处理。'}
    if action == 'study_save':
        device = string(p.get('device_id'), 64, False)
        expected = integer(p.get('expected_version'), high=2**63-1)
        data = p.get('data')
        require(isinstance(data, dict) and len(json.dumps(data).encode()) <= 180000)
        previous = one(conn, 'SELECT version FROM study_saves WHERE user_id=%s AND device_id=%s', (actor, device))
        require(expected == (previous['version'] if previous else 0), 'version_conflict', '学习存档版本已更新，请先读取再保存。', 409)
        conn.execute('INSERT INTO study_saves(user_id,device_id,version,payload) VALUES (%s,%s,%s,%s) ON CONFLICT(user_id,device_id) DO UPDATE SET version=EXCLUDED.version,payload=EXCLUDED.payload,updated_at=now()', (actor, device, expected + 1, Jsonb(data)))
        bump(conn, actor)
        return {'version': expected + 1}
    if action == 'study_load':
        return {'saves': [{'device_id': s['device_id'], 'version': s['version'], 'data': s['payload'], 'updated_at': stamp(s['updated_at'])} for s in rows(conn, 'SELECT * FROM study_saves WHERE user_id=%s ORDER BY updated_at DESC', (actor,))]}
    raise DomainError('unavailable', '此项服务尚未开放。', 404)
