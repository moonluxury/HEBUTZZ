"""Real PostgreSQL tests. Refuses to run against the production database."""
import os
import secrets
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient
from psycopg.conninfo import conninfo_to_dict

assert conninfo_to_dict(os.environ['DATABASE_URL']).get('dbname', '').endswith('_test'), 'Tests require a separate *_test database'
os.environ.setdefault('CURSOR_SECRET', secrets.token_hex(32))
os.environ['REGISTER_PER_MINUTE'] = '10000'
os.environ['LOGIN_PER_MINUTE'] = '10000'
os.environ['RPC_PER_MINUTE'] = '10000'

from app import app
from database import transaction, one, rows, lock_users
from domain import dispatch, DomainError, uid, project_event, get_transfer


@pytest.fixture(scope='session')
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture(autouse=True)
def empty_database(client):
    with transaction() as conn:
        conn.execute('TRUNCATE users,rate_limits RESTART IDENTITY CASCADE')


def register(client, name=None):
    name = name or 'test_' + secrets.token_hex(5)
    password = secrets.token_urlsafe(24)
    result = client.post('/v1/auth/register', json={'username': name, 'password': password})
    assert result.status_code == 200, result.text
    account = result.json()
    account.update(username=name, password=password)
    return account


def headers(a):
    return {'Authorization': 'Bearer ' + a['access_token']}


def rpc(client, a, action, **payload):
    if action in {'request_friend', 'respond_request', 'relationship', 'preferences', 'create_trade', 'trade_action', 'report', 'send_gift', 'mark_all_read'}:
        payload.setdefault('operation_id', uid())
    return client.post('/v1/rpc', headers=headers(a), json={'version': 1, 'action': action, 'payload': payload})


def befriend(client, a, b):
    req = rpc(client, a, 'request_friend', peer_id=b['account_id']).json()['request']
    result = rpc(client, b, 'respond_request', request_id=req['id'], decision='accept')
    assert result.status_code == 200, result.text
    return rpc(client, a, 'open_conversation', peer_id=b['account_id']).json()['conversation']['id']


def stock(a, card, count):
    with transaction() as conn:
        lock_users(conn, a['account_id'])
        conn.execute('INSERT INTO inventory(user_id,card_id,count) VALUES (%s,%s,%s) ON CONFLICT(user_id,card_id) DO UPDATE SET count=EXCLUDED.count', (a['account_id'], card, count))


def counts(a, card):
    with transaction() as conn:
        r = one(conn, 'SELECT count FROM inventory WHERE user_id=%s AND card_id=%s', (a['account_id'], card))
        return r['count'] if r else 0


def line(card='0001', quantity=1):
    return {'card_id': card, 'season_id': 'season-001', 'quantity': quantity}


def create_trade(client, a, b, give=None, receive=None):
    r = rpc(client, a, 'create_trade', peer_id=b['account_id'], give=give or [line()], receive=receive or [line('0002')], terms_version=1)
    assert r.status_code == 200, r.text
    return r.json()['trade']


def test_password_hash_session_logout_and_input_redaction(client):
    a = register(client)
    with transaction() as conn:
        row = one(conn, 'SELECT password_hash FROM users WHERE id=%s', (a['account_id'],))
        assert row['password_hash'].startswith('$argon2id$') and a['password'] not in row['password_hash']
        assert one(conn, 'SELECT count(*) n FROM sessions WHERE token_hash=%s', (a['access_token'],))['n'] == 0
    assert rpc(client, a, 'profile').json()['profile']['public_id'] == a['profile']['public_id']
    assert client.post('/v1/auth/login', json={'username': a['username'], 'password': 'wrong_password_1234'}).status_code == 401
    bad = client.post('/v1/auth/register', json={'username': 'x', 'password': 'secret_123'})
    assert bad.status_code == 422 and 'secret_123' not in bad.text
    assert client.post('/v1/auth/logout', headers=headers(a)).status_code == 200
    assert rpc(client, a, 'profile').status_code == 401


@pytest.mark.parametrize('password', ['123456', 'abcdef', '你好世界欢迎', '!@#$%^', '      ', ' abcde', 'abcde ', 'a' * 129])
def test_password_only_requires_six_characters(client, password):
    name = 'policy_' + secrets.token_hex(5)
    result = client.post('/v1/auth/register', json={'username': name, 'password': password})
    assert result.status_code == 200, result.text
    account = result.json()
    assert client.post('/v1/auth/login', json={'username': name, 'password': password}).status_code == 200
    replacement = '654321' if password != '654321' else 'abcdef'
    changed = client.post('/v1/auth/password', headers=headers(account), json={'current_password': password, 'new_password': replacement})
    assert changed.status_code == 200, changed.text
    assert client.post('/v1/auth/login', json={'username': name, 'password': replacement}).status_code == 200
    assert client.get('/v1/meta').json()['password_min_length'] == 6


def test_password_rejects_five_characters(client):
    name = 'policy_' + secrets.token_hex(5)
    assert client.post('/v1/auth/register', json={'username': name, 'password': '12345'}).status_code == 422
    assert client.post('/v1/auth/login', json={'username': name, 'password': '12345'}).status_code == 422
    a = register(client)
    assert client.post('/v1/auth/password', headers=headers(a), json={'current_password': a['password'], 'new_password': '12345'}).status_code == 422


def test_password_change_revokes_every_session(client):
    a = register(client)
    b = client.post('/v1/auth/login', json={'username': a['username'], 'password': a['password']}).json()
    new = secrets.token_urlsafe(24)
    r = client.post('/v1/auth/password', headers=headers(a), json={'current_password': a['password'], 'new_password': new})
    assert r.status_code == 200
    assert rpc(client, a, 'profile').status_code == rpc(client, b, 'profile').status_code == 401
    assert client.post('/v1/auth/login', json={'username': a['username'], 'password': new}).status_code == 200


def test_profiles_avatar_ownership_and_identity_spoofing(client):
    a, b = register(client), register(client)
    assert rpc(client, a, 'save_profile', patch={'display_name': '测试同学', 'school': '河北工业大学'}).json()['persisted']
    assert rpc(client, a, 'save_profile', patch={'public_id': 'fake'}).status_code == 400
    assert rpc(client, a, 'profile', account_id=b['account_id']).status_code == 400
    assert rpc(client, a, 'save_profile', patch={}, avatar_card_id='0001').status_code == 403
    stock(a, '0001', 1)
    result = rpc(client, a, 'save_profile', patch={}, avatar_card_id='0001').json()
    assert result['persisted'] and result['profile']['avatar_card_id'] == '0001'
    assert rpc(client, b, 'profile').json()['profile']['avatar_card_id'] == ''
    # Existing text-only/legacy empty requests must keep the selected avatar.
    assert rpc(client, a, 'save_profile', patch={'bio': '保留头像'}, avatar_card_id='').json()['profile']['avatar_card_id'] == '0001'
    operation = uid()
    reset = rpc(client, a, 'save_profile', patch={}, avatar_card_id='', avatar_change=True, operation_id=operation).json()
    assert reset['persisted'] and reset['profile']['avatar_card_id'] == ''
    assert rpc(client, a, 'save_profile', patch={}, avatar_card_id='', avatar_change=True, operation_id=operation).json() == reset
    assert rpc(client, a, 'save_profile', patch={}, avatar_card_id='0001', avatar_change=True, operation_id=operation).status_code == 409
    assert rpc(client, a, 'save_profile', patch={}, avatar_card_id='', avatar_change='true').status_code == 400
    assert rpc(client, b, 'profile').json()['profile']['avatar_card_id'] == ''


def test_crossed_friend_requests_and_idempotency(client):
    a, b = register(client), register(client)
    op = uid()
    first = rpc(client, a, 'request_friend', peer_id=b['account_id'], note='你好', operation_id=op).json()
    assert rpc(client, a, 'request_friend', peer_id=b['account_id'], note='你好', operation_id=op).json() == first
    assert rpc(client, a, 'request_friend', peer_id=b['account_id'], note='修改', operation_id=op).status_code == 409
    crossed = rpc(client, b, 'request_friend', peer_id=a['account_id']).json()
    assert crossed['request']['id'] == first['request']['id']
    assert rpc(client, a, 'friends').json()['friends'] == []
    assert rpc(client, a, 'respond_request', request_id=first['request']['id'], decision='accept').status_code == 403
    assert rpc(client, b, 'respond_request', request_id=first['request']['id'], decision='accept').status_code == 200
    assert len(rpc(client, a, 'friends').json()['friends']) == len(rpc(client, b, 'friends').json()['friends']) == 1


def test_messages_greeting_history_cursor_and_system_authority(client):
    a, b, outsider = register(client), register(client), register(client)
    cid = rpc(client, a, 'open_conversation', peer_id=b['account_id']).json()['conversation']['id']
    m = rpc(client, a, 'send_text', conversation_id=cid, client_id='one', text='你好')
    assert m.status_code == 200
    assert rpc(client, a, 'send_text', conversation_id=cid, client_id='one', text='你好').json() == m.json()
    assert rpc(client, a, 'send_text', conversation_id=cid, client_id='one', text='changed').status_code == 409
    assert rpc(client, a, 'send_text', conversation_id=cid, client_id='two', text='again').status_code == 403
    befriend(client, a, b)
    for n in range(3):
        assert rpc(client, a, 'send_text', conversation_id=cid, client_id='m' + str(n), text=str(n)).status_code == 200
    page = rpc(client, b, 'history', conversation_id=cid, limit=2).json()
    assert len(page['messages']) == 2 and page['next_before']
    assert rpc(client, a, 'history', conversation_id=cid, before=page['next_before']).status_code == 400
    assert rpc(client, outsider, 'history', conversation_id=cid).status_code == 403
    system = next(c for c in rpc(client, a, 'sync').json()['conversations'] if c['kind'] == 'system')
    assert rpc(client, a, 'send_text', conversation_id=system['id'], client_id='forged', text='官方通知').status_code == 403
    assert rpc(client, a, 'send_text', conversation_id=cid, client_id='forged2', text='hi', type='gift').status_code == 400


def test_gift_last_copy_replay_and_failure_recovery(client):
    a, b = register(client), register(client)
    cid = befriend(client, a, b)
    stock(a, '0001', 2)
    op = uid()
    first = rpc(client, a, 'send_gift', friend_id=b['account_id'], card_id='0001', quantity=1, operation_id=op).json()
    assert first['state'] == 'succeeded'
    assert rpc(client, a, 'send_gift', friend_id=b['account_id'], card_id='0001', quantity=1, operation_id=op).json() == first
    assert counts(a, '0001') == counts(b, '0001') == 1
    failed_op = uid()
    failed = rpc(client, a, 'send_gift', friend_id=b['account_id'], card_id='0001', quantity=1, operation_id=failed_op).json()
    assert failed['state'] == 'failed' and failed['inventory_complete']
    assert rpc(client, a, 'gift_status', operation_id=failed_op).json()['state'] == 'failed'
    assert rpc(client, a, 'gift_status', operation_id=op).json()['state'] == 'succeeded'
    history = rpc(client, a, 'history', conversation_id=cid).json()['messages']
    assert len([m for m in history if m['type'] == 'gift']) == 1


def test_trade_same_card_uses_gross_outgoing_stock(client):
    a, b = register(client), register(client)
    befriend(client, a, b)
    stock(a, '0001', 2)
    stock(b, '0001', 0)
    t = create_trade(client, a, b, [line(quantity=2)], [line(quantity=2)])
    r = rpc(client, b, 'trade_action', trade_id=t['id'], terms_version=1, decision='confirm')
    assert r.status_code == 409
    assert counts(a, '0001') == 2 and counts(b, '0001') == 0
    assert rpc(client, b, 'trade_detail', record_id=t['id']).json()['trade']['status'] == 'pending'


def concurrent_dispatch(actor, action, payload):
    try:
        with transaction() as conn:
            return dispatch(conn, actor, action, payload)
    except DomainError as e:
        return {'ok': False, 'code': e.code}


def test_concurrent_confirmation_delivers_once_and_outbox_replay(client):
    a, b = register(client), register(client)
    befriend(client, a, b)
    stock(a, '0001', 3)
    stock(b, '0002', 3)
    t = create_trade(client, a, b)
    with ThreadPoolExecutor(max_workers=6) as executor:
        results = list(executor.map(lambda _: concurrent_dispatch(b['account_id'], 'trade_action', {'trade_id': t['id'], 'terms_version': 1, 'decision': 'confirm', 'operation_id': uid()}), range(6)))
    assert all(r['ok'] for r in results)
    assert (counts(a, '0001'), counts(b, '0001'), counts(a, '0002'), counts(b, '0002')) == (2, 1, 1, 2)
    with transaction() as conn:
        lock_users(conn, a['account_id'], b['account_id'])
        transfer = get_transfer(conn, a['account_id'], t['id'])
        project_event(conn, transfer, 'completed')
        assert one(conn, 'SELECT count(*) n FROM inventory_ledger WHERE record_id=%s', (t['id'],))['n'] == 4
        assert one(conn, "SELECT count(*) n FROM outbox WHERE record_id=%s AND event='completed'", (t['id'],))['n'] == 1


@pytest.mark.parametrize('competing', ['cancel', 'block', 'gift'])
def test_transfer_competes_with_cancel_block_and_gift(client, competing):
    a, b = register(client), register(client)
    befriend(client, a, b)
    stock(a, '0001', 2)
    stock(b, '0002', 1)
    t = create_trade(client, a, b, [line(quantity=2)], [line('0002')])
    confirm = lambda: concurrent_dispatch(b['account_id'], 'trade_action', {'trade_id': t['id'], 'terms_version': 1, 'decision': 'confirm', 'operation_id': uid()})
    if competing == 'cancel':
        other = lambda: concurrent_dispatch(a['account_id'], 'trade_action', {'trade_id': t['id'], 'terms_version': 1, 'decision': 'cancel', 'operation_id': uid()})
    elif competing == 'block':
        other = lambda: concurrent_dispatch(a['account_id'], 'relationship', {'peer_id': b['account_id'], 'operation': 'block', 'operation_id': uid()})
    else:
        other = lambda: concurrent_dispatch(a['account_id'], 'send_gift', {'friend_id': b['account_id'], 'card_id': '0001', 'quantity': 1, 'operation_id': uid()})
    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [executor.submit(f) for f in (confirm, other)]
        for f in futures:
            f.result(timeout=20)
    assert counts(a, '0001') + counts(b, '0001') == 2
    assert counts(a, '0002') + counts(b, '0002') == 1
    with transaction() as conn:
        assert one(conn, 'SELECT min(count) n FROM inventory')['n'] >= 0
        status = get_transfer(conn, a['account_id'], t['id'])['status']
    if status == 'completed':
        assert counts(b, '0001') == 2 and counts(a, '0002') == 1
    else:
        assert counts(b, '0002') == 1 and counts(a, '0002') == 0


def test_block_invalidates_invitation_and_unblock_does_not_restore(client):
    a, b, outsider = register(client), register(client), register(client)
    befriend(client, a, b)
    stock(a, '0001', 2)
    t = create_trade(client, a, b)
    assert rpc(client, outsider, 'trade_detail', record_id=t['id']).status_code == 403
    assert rpc(client, a, 'trade_action', trade_id=t['id'], terms_version=1, decision='confirm').status_code == 403
    rpc(client, a, 'relationship', peer_id=b['account_id'], operation='block')
    rpc(client, a, 'relationship', peer_id=b['account_id'], operation='unblock')
    assert rpc(client, a, 'friends').json()['friends'] == []
    assert rpc(client, a, 'trade_detail', record_id=t['id']).json()['trade']['status'] == 'invalidated'


def test_read_watermarks_reports_and_study_compare_and_swap(client):
    a, b, outsider = register(client), register(client), register(client)
    cid = befriend(client, a, b)
    first = rpc(client, a, 'send_text', conversation_id=cid, client_id=uid(), text='第一条').json()['message_record']
    op = uid()
    rpc(client, b, 'mark_all_read', operation_id=op)
    second = rpc(client, a, 'send_text', conversation_id=cid, client_id=uid(), text='第二条').json()['message_record']
    rpc(client, b, 'mark_all_read', operation_id=op)
    state = rpc(client, b, 'sync').json()
    assert next(c for c in state['conversations'] if c['id'] == cid)['unread'] == 1
    assert rpc(client, b, 'report', peer_id=a['account_id'], reason='other', note='测试', message_ids=[first['id']]).json()['report_id']
    assert rpc(client, outsider, 'report', peer_id=a['account_id'], reason='other', message_ids=[second['id']]).status_code == 403
    assert rpc(client, a, 'study_save', device_id='desktop', expected_version=0, data={'course': 4}).json()['version'] == 1
    assert rpc(client, a, 'study_save', device_id='desktop', expected_version=0, data={}).status_code == 409
    assert rpc(client, b, 'study_load').json()['saves'] == []
    assert rpc(client, a, 'study_load').json()['saves'][0]['data'] == {'course': 4}


def test_external_login_disabled_and_expired_sessions(client):
    a = register(client)
    assert client.get('/v1/meta').json()['auth'] == {'password': True, 'wechat': False, 'steam': False}
    assert client.post('/v1/auth/wechat', json={'openid': 'untrusted'}).status_code == 503
    assert client.post('/v1/auth/steam', json={'steam_id': 'untrusted'}).status_code == 503
    with transaction() as conn:
        conn.execute("UPDATE sessions SET expires_at=now()-interval '1 day' WHERE user_id=%s", (a['account_id'],))
    assert rpc(client, a, 'profile').status_code == 401
