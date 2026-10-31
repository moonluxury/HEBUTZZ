"""Default-avatar persistence and compatibility against an isolated PostgreSQL database."""
from concurrent.futures import ThreadPoolExecutor

from test_backend import client, empty_database, register, rpc, stock, counts
from database import transaction, one
from domain import uid


def test_default_avatar_without_inventory_and_legacy_profile_save(client):
    account, other = register(client), register(client)
    assert account['editable_fields']['avatar_card_id']['reset_supported'] is True
    stock(account, '0001', 1)
    selected = rpc(client, account, 'save_profile', patch={}, avatar_card_id='0001').json()
    assert selected['persisted'] and selected['profile']['avatar_card_id'] == '0001'
    # Losing the last copy must not prevent returning to the built-in avatar.
    stock(account, '0001', 0)
    legacy = rpc(client, account, 'save_profile', patch={'bio': 'keep profile'}, avatar_card_id='').json()
    assert legacy['profile']['avatar_card_id'] == '0001'
    reset = rpc(client, account, 'save_profile', patch={}, avatar_card_id='', avatar_change=True, operation_id=uid()).json()
    assert reset['persisted'] and reset['profile']['avatar_card_id'] == ''
    assert reset['profile']['bio'] == 'keep profile'
    assert reset['profile']['public_id'] == selected['profile']['public_id']
    assert rpc(client, account, 'profile').json()['profile']['avatar_card_id'] == ''
    assert rpc(client, other, 'profile').json()['profile'] == other['profile']
    assert counts(account, '0001') == 0
    assert rpc(client, account, 'save_profile', patch={}, avatar_card_id='0001', avatar_change=True).status_code == 403
    assert rpc(client, account, 'save_profile', patch={}, avatar_card_id='', avatar_change='true').status_code == 400


def test_default_avatar_concurrent_retries_are_idempotent(client):
    account = register(client)
    stock(account, '0001', 1)
    rpc(client, account, 'save_profile', patch={}, avatar_card_id='0001')
    operation = uid()
    payload = dict(patch={}, avatar_card_id='', avatar_change=True, operation_id=operation)
    with transaction() as conn:
        before = one(conn, 'SELECT revision FROM users WHERE id=%s', (account['account_id'],))['revision']
    with ThreadPoolExecutor(max_workers=4) as pool:
        responses = list(pool.map(lambda _: rpc(client, account, 'save_profile', **payload), range(4)))
    assert all(response.status_code == 200 for response in responses)
    assert all(response.json() == responses[0].json() for response in responses)
    assert responses[0].json()['profile']['avatar_card_id'] == ''
    with transaction() as conn:
        assert one(conn, 'SELECT revision FROM users WHERE id=%s', (account['account_id'],))['revision'] == before + 1
        assert one(conn, 'SELECT count(*) n FROM operations WHERE actor=%s AND operation_id=%s', (account['account_id'], operation))['n'] == 1
    assert counts(account, '0001') == 1
    assert rpc(client, account, 'save_profile', **{**payload, 'avatar_card_id': '0001'}).status_code == 409
