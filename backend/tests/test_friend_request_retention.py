"""Real PostgreSQL retention tests, including retries and lock races."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from threading import Event

import pytest
from psycopg.types.json import Jsonb

from test_backend import client, empty_database, register, rpc
from database import one, rows, transaction
import domain
from domain import add_message, conversation, dispatch, notify, uid
from friend_request_retention import CLEANUP_LOCK, cleanup_batch, delete_expired_requests


def age(request_id, hours=73):
    with transaction() as conn:
        conn.execute("UPDATE friend_requests SET created_at=clock_timestamp()-(%s * interval '1 hour') WHERE id=%s", (hours, request_id))


def send(client, sender, recipient, **kwargs):
    result = rpc(client, sender, 'request_friend', peer_id=recipient['account_id'], **kwargs)
    assert result.status_code == 200, result.text
    return result.json()


def clean(**kwargs):
    with transaction() as conn:
        return cleanup_batch(conn, **kwargs)


@pytest.mark.parametrize('status', ['pending', 'accepted', 'ignored', 'invalidated'])
def test_boundary_and_all_statuses_preserve_new_requests(client, status):
    a, b = register(client), register(client)
    cutoff = datetime(2026, 1, 1, tzinfo=timezone.utc)
    with transaction() as conn:
        for request_id, offset in [('old', -1), ('edge', 0), ('new', 1)]:
            # Distinct peers keep the unique pending-pair invariant.
            peer = uid()
            conn.execute('INSERT INTO users(id,public_id,username,password_hash) VALUES (%s,%s,%s,%s)', (peer, peer, peer, 'unused'))
            conn.execute('INSERT INTO friend_requests(id,sender,recipient,note,status,created_at) VALUES (%s,%s,%s,%s,%s,%s)',
                         (request_id, a['account_id'], peer, 'retention-test', status, cutoff + timedelta(microseconds=offset)))
            notify(conn, peer, 'request', 'test', record_id=request_id)
    assert clean(cutoff=cutoff)['requests'] == 2
    with transaction() as conn:
        assert [r['id'] for r in rows(conn, 'SELECT id FROM friend_requests')] == ['new']
        assert one(conn, 'SELECT count(*) n FROM messages')['n'] == 1
    assert clean(cutoff=cutoff)['requests'] == 0


def test_expiry_hidden_both_directions_and_resend_before_timer(client):
    a, b, c = register(client), register(client), register(client)
    old = send(client, a, b)['request']['id']
    recent = send(client, c, b)['request']['id']
    age(old)
    for account in (a, b):
        sync = rpc(client, account, 'sync').json()
        assert old not in {r['id'] for r in sync['requests']}
    recipient = rpc(client, b, 'sync').json()
    assert recipient['pending_requests'] == recipient['request_unread'] == 1
    assert recipient['requests'][0]['id'] == recent
    assert rpc(client, a, 'find_user', public_id=b['profile']['public_id']).json()['state'] == 'available'
    result = rpc(client, b, 'respond_request', request_id=old, decision='accept')
    assert result.status_code == 410 and result.json()['definitive'] is True
    new = send(client, b, a)['request']['id']
    assert new != old
    with transaction() as conn:
        assert one(conn, 'SELECT id FROM friend_requests WHERE id=%s', (old,)) is None
        assert one(conn, 'SELECT count(*) n FROM messages WHERE record_id=%s', (old,))['n'] == 0


def test_cleanup_keeps_friendship_chat_and_unrelated_notifications(client):
    a, b = register(client), register(client)
    request_id = send(client, a, b)['request']['id']
    assert rpc(client, b, 'respond_request', request_id=request_id, decision='accept').status_code == 200
    with transaction() as conn:
        c = conversation(conn, a['account_id'], b['account_id'])
        text = add_message(conn, c, a['account_id'], 'text', 'keep chat', record_id=request_id)
        notify(conn, a['account_id'], 'keep', 'different event', event='other', record_id=request_id)
        revision = one(conn, 'SELECT revision FROM users WHERE id=%s', (a['account_id'],))['revision']
    age(request_id)
    result = clean()
    assert result['requests'] == 1 and result['notifications'] == 2
    with transaction() as conn:
        assert one(conn, 'SELECT friends FROM relationships')['friends'] is True
        assert one(conn, 'SELECT id FROM messages WHERE id=%s', (text['id'],))
        assert one(conn, 'SELECT count(*) n FROM messages')['n'] == 2
        assert one(conn, 'SELECT revision FROM users WHERE id=%s', (a['account_id'],))['revision'] > revision
    assert len(rpc(client, a, 'friends').json()['friends']) == 1
    assert rpc(client, b, 'respond_request', request_id=request_id, decision='accept').status_code == 403


def test_retries_compact_legacy_receipts_and_never_recreate_expired_request(client):
    a, b = register(client), register(client)
    operation_id = uid()
    response = send(client, a, b, note='private old note', operation_id=operation_id)
    request_id = response['request']['id']
    with transaction() as conn:
        marker = one(conn, 'SELECT response FROM operations WHERE operation_id=%s', (operation_id,))['response']
        assert marker == {'_friend_receipt': 1, 'request_id': request_id}
        conn.execute('UPDATE operations SET response=%s WHERE operation_id=%s', (Jsonb(response), operation_id))
    assert send(client, a, b, note='private old note', operation_id=operation_id) == response
    assert clean()['receipts'] == 1
    assert send(client, a, b, note='private old note', operation_id=operation_id) == response
    assert rpc(client, a, 'request_friend', peer_id=b['account_id'], note='changed', operation_id=operation_id).status_code == 409
    age(request_id)
    for after_cleanup in (False, True):
        if after_cleanup:
            assert clean()['requests'] == 1
        result = rpc(client, a, 'request_friend', peer_id=b['account_id'], note='private old note', operation_id=operation_id)
        assert result.status_code == 410 and result.json()['definitive'] is True
    with transaction() as conn:
        assert one(conn, 'SELECT count(*) n FROM friend_requests')['n'] == 0
        assert one(conn, 'SELECT response FROM operations WHERE operation_id=%s', (operation_id,))['response'] == marker
    assert send(client, a, b)['request']['id'] != request_id


def test_accept_replay_uses_fresh_sync_and_compacts_legacy_snapshot(client):
    a, b = register(client), register(client)
    request_id = send(client, a, b)['request']['id']
    operation_id = uid()
    accepted = rpc(client, b, 'respond_request', request_id=request_id, decision='accept', operation_id=operation_id).json()
    with transaction() as conn:
        assert one(conn, 'SELECT response FROM operations WHERE operation_id=%s', (operation_id,))['response'] == {'_friend_receipt': 1}
        conn.execute('UPDATE operations SET response=%s WHERE operation_id=%s', (Jsonb(accepted), operation_id))
    assert clean()['receipts'] == 1
    rpc(client, a, 'relationship', peer_id=b['account_id'], operation='remove')
    replay = rpc(client, b, 'respond_request', request_id=request_id, decision='accept', operation_id=operation_id)
    assert replay.status_code == 200 and replay.json()['sync']['friends'] == []
    age(request_id)
    assert rpc(client, b, 'respond_request', request_id=request_id, decision='accept', operation_id=operation_id).status_code == 410


def test_batches_rollback_and_worker_overlap(client):
    a, b, c = register(client), register(client), register(client)
    ids = [send(client, a, b)['request']['id'], send(client, a, c)['request']['id']]
    for request_id in ids:
        age(request_id)
    with pytest.raises(RuntimeError):
        with transaction() as conn:
            assert cleanup_batch(conn, 1)['requests'] == 1
            raise RuntimeError('simulate interrupted transaction')
    with transaction() as conn:
        assert one(conn, 'SELECT count(*) n FROM friend_requests')['n'] == 2
        conn.execute('SELECT pg_advisory_xact_lock(%s)', (CLEANUP_LOCK,))
        assert clean()['skipped'] is True
    assert clean(limit=1)['requests'] == 1
    assert clean(limit=1)['requests'] == 1
    assert clean()['requests'] == 0


def test_respond_rechecks_after_cleaner_wins_lock_race(client, monkeypatch):
    a, b = register(client), register(client)
    request_id = send(client, a, b)['request']['id']
    entered, cleaned = Event(), Event()
    original = domain.lock_users

    def delayed_lock(conn, *ids):
        entered.set()
        assert cleaned.wait(10)
        return original(conn, *ids)

    monkeypatch.setattr(domain, 'lock_users', delayed_lock)
    with ThreadPoolExecutor(max_workers=1) as executor:
        future = executor.submit(rpc, client, b, 'respond_request', request_id=request_id, decision='accept')
        try:
            assert entered.wait(10)
            age(request_id)
            assert clean()['requests'] == 1
        finally:
            cleaned.set()
        result = future.result(timeout=10)
    assert result.status_code == 410
    with transaction() as conn:
        assert one(conn, 'SELECT count(*) n FROM relationships WHERE friends')['n'] == 0


def test_cleanup_rechecks_age_after_select(client):
    a, b = register(client), register(client)
    request_id = send(client, a, b)['request']['id']
    age(request_id)
    with transaction() as conn:
        candidates = rows(conn, 'SELECT id,sender,recipient FROM friend_requests')
        conn.execute('UPDATE friend_requests SET created_at=clock_timestamp() WHERE id=%s', (request_id,))
        assert delete_expired_requests(conn, candidates, datetime.now(timezone.utc) - timedelta(hours=72))['requests'] == 0
