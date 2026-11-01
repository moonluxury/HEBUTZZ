from concurrent.futures import ThreadPoolExecutor
import pytest
from test_backend import client, empty_database, register, headers, befriend, rpc, stock
from database import transaction, one
from domain import dispatch, uid, DomainError


def call(client, account, action='wishlist_load', **payload):
    if action == 'wishlist_update': payload.setdefault('operation_id', uid())
    return client.post('/v1/rpc', headers=headers(account) if account else {},
                       json={'version': 1, 'action': action, 'payload': payload})


def write(client, account, revision, changes, **extra):
    return call(client, account, 'wishlist_update', expected_revision=revision, changes=changes, **extra)


def test_cloud_roundtrip_and_second_session(client):
    a = register(client)
    assert call(client, a).json()['initialized'] is False
    saved = write(client, a, 0, {'0001': True, '0003': True}).json()
    assert saved['card_ids'] == ['0001', '0003'] and saved['wishlist_revision'] == 1
    other = client.post('/v1/auth/login', json={'username': a['username'], 'password': a['password']}).json()
    assert call(client, other).json()['card_ids'] == saved['card_ids']
    assert write(client, other, 1, {'0001': False, '0002': True}).json()['card_ids'] == ['0002', '0003']
    assert call(client, a).json()['card_ids'] == ['0002', '0003']


def test_empty_initialization_and_unchanged_no_revision_bump(client):
    a = register(client)
    assert write(client, a, 0, {}).json()['wishlist_revision'] == 1
    assert write(client, a, 1, {}).json()['wishlist_revision'] == 1
    assert call(client, a).json()['initialized'] is True


def test_friend_projection_permissions_and_no_inventory_leak(client):
    a, b = register(client), register(client)
    write(client, a, 0, {'0002': True})
    assert call(client, b, 'wishlist', peer_id=a['account_id']).status_code == 403
    befriend(client, a, b)
    projected = call(client, b, 'wishlist', peer_id=a['account_id']).json()
    assert projected['card_ids'] == ['0002'] and projected['visibility'] == 'accessible'
    assert set(projected) == {'ok','account_id','card_ids','wishlist_revision','initialized','visibility'}
    rpc(client, a, 'relationship', peer_id=b['account_id'], operation='block')
    assert call(client, b, 'wishlist', peer_id=a['account_id']).status_code == 403
    assert call(client, a, 'wishlist', peer_id=b['account_id']).status_code == 403
    assert call(client, None).status_code == 401


def test_invalid_changes_and_actor_spoofing(client):
    a = register(client)
    for changes in [{'unknown': True}, {'0001': 1}, {'0001': 'true'}, [], None]:
        assert write(client, a, 0, changes).status_code == 400
    assert write(client, a, -1, {}).status_code == 400
    assert write(client, a, 0, {}, peer_id='someone').status_code == 400
    assert write(client, a, 0, {}, account_id='someone').status_code == 400
    assert call(client, a).json()['initialized'] is False


def test_conflict_and_per_card_rebase_preserve_other_device(client):
    a = register(client)
    assert write(client, a, 0, {'0001': True}).status_code == 200
    rejected = write(client, a, 0, {'0002': True})
    assert rejected.status_code == 409 and rejected.json()['code'] == 'wishlist_conflict'
    assert write(client, a, 1, {'0002': True}).json()['card_ids'] == ['0001','0002']


def test_replay_never_resurrects_a_later_removal(client):
    a = register(client)
    operation = uid()
    first = write(client, a, 0, {'0001': True}, operation_id=operation).json()
    write(client, a, 1, {'0001': False})
    assert write(client, a, 0, {'0001': True}, operation_id=operation).json() == first
    assert call(client, a).json()['card_ids'] == []
    assert write(client, a, 0, {'0002': True}, operation_id=operation).status_code == 409


def test_gift_does_not_clear_either_wishlist(client):
    a, b = register(client), register(client)
    befriend(client, a, b)
    stock(a, '0001', 3)
    for account in [a,b]: write(client, account, 0, {'0001': True})
    assert rpc(client, a, 'send_gift', card_id='0001', friend_id=b['account_id'], quantity=1).json()['state'] == 'succeeded'
    for account in [a,b]: assert call(client, account).json()['card_ids'] == ['0001']


def test_concurrent_writers_and_account_isolation(client):
    a, b = register(client), register(client)
    def change(card):
        try:
            with transaction() as conn:
                return dispatch(conn, a['account_id'], 'wishlist_update', {'operation_id':uid(),'expected_revision':0,'changes':{card:True}})
        except DomainError as error:
            return {'code':error.code}
    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(change, ['0001','0002']))
    assert sum(r.get('ok',False) for r in results) == 1
    assert sum(r.get('code') == 'wishlist_conflict' for r in results) == 1
    assert call(client, b).json()['card_ids'] == []
    with transaction() as conn:
        assert one(conn, 'SELECT count(*) n FROM collection_wishlists')['n'] == 1
