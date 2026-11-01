"""Real PostgreSQL checks for fixed odds, atomic spending and recoverable receipts."""
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import pytest
from psycopg import errors

from test_backend import client, empty_database, register, headers
from database import transaction, lock_users, one
from domain import uid, DomainError
from wallet_service import post
import card_draw_service as draws


def wallet(client, actor, action, **payload):
    return client.post('/v1/wallet', headers=headers(actor), json={'version': 1, 'action': action, 'payload': payload})


def fund(actor, amount):
    with transaction() as conn:
        lock_users(conn, actor['account_id'])
        post(conn, actor['account_id'], 'isolated:' + uid(), 'opening', amount, 'isolated-test')


def request():
    return {'operation_id': uid(), 'pool_id': draws.POOL_ID, 'expected_price': 200, 'rule_version': draws.RULE_VERSION}


def total(actor):
    with transaction() as conn:
        return one(conn, 'SELECT COALESCE(sum(count),0) AS n FROM inventory WHERE user_id=%s', (actor['account_id'],))['n']


def test_config_and_exact_probability_buckets(client):
    actor = register(client)
    value = wallet(client, actor, 'card_draw_options').json()
    expected = {'0004': 10, '0007': 10, '0005': 12, '0003': 14, '0001': 16, '0006': 18, '0002': 20}
    assert value['price'] == 200 and value['duplicates'] is True
    assert {x['card_id']: x['percent'] for x in value['odds']} == expected
    assert Counter(draws.choose_card(n) for n in range(100)) == expected
    assert wallet(client, actor, 'balance').json()['balance'] == 0 and total(actor) == 0


def test_insufficient_balance_never_grants_or_charges(client):
    actor = register(client)
    fund(actor, 199)
    result = wallet(client, actor, 'card_draw', **request())
    assert result.status_code == 200 and not result.json()['ok'] and result.json()['code'] == 'insufficient_balance'
    assert wallet(client, actor, 'balance').json()['balance'] == 199 and total(actor) == 0
    assert wallet(client, actor, 'ledger', filter='expense').json()['items'] == []
    with transaction() as conn:
        assert one(conn, "SELECT count(*) n FROM operations WHERE action='card_draw'")['n'] == 1


def test_one_draw_debits_200_and_duplicate_card_increases_inventory(client, monkeypatch):
    actor = register(client)
    fund(actor, 400)
    monkeypatch.setattr(draws.secrets, 'randbelow', lambda _n: 0)
    first = wallet(client, actor, 'card_draw', **request()).json()
    second = wallet(client, actor, 'card_draw', **request()).json()
    assert first['balance'] == 200 and second['balance'] == 0
    assert first['draw']['card_id'] == second['draw']['card_id'] == '0004'
    assert second['collection']['inventory']['0004']['count'] == 2 and total(actor) == 2
    ledger = wallet(client, actor, 'ledger', filter='expense').json()['items']
    assert len(ledger) == 2 and all(x['delta'] == -200 and x['source'] == 'card_draw' for x in ledger)


def test_concurrent_identical_retry_returns_one_card_and_one_charge(client):
    actor = register(client)
    fund(actor, 600)
    payload = request()
    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(lambda _: wallet(client, actor, 'card_draw', **payload), range(6)))
    assert all(r.status_code == 200 for r in results)
    assert all(r.json()['draw'] == results[0].json()['draw'] for r in results)
    assert total(actor) == 1 and wallet(client, actor, 'balance').json()['balance'] == 400
    assert len(wallet(client, actor, 'ledger', filter='expense').json()['items']) == 1


def test_concurrent_different_draws_cannot_overdraw(client):
    actor = register(client)
    fund(actor, 400)
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda _: wallet(client, actor, 'card_draw', **request()), range(4)))
    assert all(r.status_code == 200 for r in results)
    assert sum(r.json()['ok'] for r in results) == 2
    assert total(actor) == 2 and wallet(client, actor, 'balance').json()['balance'] == 0


def test_recovery_is_owner_scoped_and_returns_current_inventory(client):
    actor, outsider = register(client), register(client)
    fund(actor, 200)
    payload = request()
    initial = wallet(client, actor, 'card_draw', **payload).json()
    assert wallet(client, outsider, 'card_draw_status', operation_id=payload['operation_id']).json()['state'] == 'not_found'
    with transaction() as conn:
        lock_users(conn, actor['account_id'])
        conn.execute('UPDATE inventory SET count=0 WHERE user_id=%s', (actor['account_id'],))
        conn.execute('UPDATE users SET revision=revision+1 WHERE id=%s', (actor['account_id'],))
    recovered = wallet(client, actor, 'card_draw_status', operation_id=payload['operation_id']).json()
    assert recovered['draw'] == initial['draw'] and recovered['collection']['inventory'][initial['draw']['card_id']]['count'] == 0
    assert wallet(client, actor, 'card_draw', **payload).json()['draw'] == initial['draw']
    assert total(actor) == 0 and wallet(client, actor, 'balance').json()['balance'] == 0


@pytest.mark.parametrize('patch', [{'expected_price': 0}, {'expected_price': True}, {'card_id': '0004'},
                                  {'account_id': 'someone'}, {'pool_id': 'fake'}, {'rule_version': 'fake'}])
def test_client_cannot_choose_price_card_actor_or_pool(client, patch):
    actor = register(client)
    fund(actor, 200)
    response = wallet(client, actor, 'card_draw', **{**request(), **patch})
    assert response.status_code in [200, 400, 409] and not response.json()['ok']
    assert wallet(client, actor, 'balance').json()['balance'] == 200 and total(actor) == 0


def test_idempotency_key_cannot_be_rebound(client):
    actor = register(client)
    fund(actor, 400)
    payload = request()
    assert wallet(client, actor, 'card_draw', **payload).status_code == 200
    result = wallet(client, actor, 'card_draw', **{**payload, 'expected_price': 201})
    assert result.status_code == 409 and result.json()['code'] == 'idempotency_conflict'
    assert total(actor) == 1 and wallet(client, actor, 'balance').json()['balance'] == 200


def test_inventory_failure_rolls_back_wallet_and_receipt(client, monkeypatch):
    actor = register(client)
    fund(actor, 200)
    def fail(*_args):
        raise DomainError('inventory_limit', 'Isolated stock failure', 409)
    monkeypatch.setattr(draws, 'grant_card', fail)
    payload = request()
    assert wallet(client, actor, 'card_draw', **payload).json()['state'] == 'failed'
    assert wallet(client, actor, 'balance').json()['balance'] == 200 and total(actor) == 0
    assert wallet(client, actor, 'ledger', filter='expense').json()['items'] == []
    assert wallet(client, actor, 'card_draw_status', operation_id=payload['operation_id']).json()['state'] == 'failed'


def test_late_retry_of_refused_draw_cannot_spend_new_funds(client):
    actor = register(client)
    payload = request()
    assert wallet(client, actor, 'card_draw', **payload).json()['state'] == 'failed'
    fund(actor, 200)
    assert wallet(client, actor, 'card_draw', **payload).json()['state'] == 'failed'
    assert wallet(client, actor, 'balance').json()['balance'] == 200 and total(actor) == 0
    assert wallet(client, actor, 'card_draw', **request()).json()['state'] == 'succeeded'


def test_unauthenticated_draw_is_rejected(client):
    response = client.post('/v1/wallet', json={'version': 1, 'action': 'card_draw', 'payload': request()})
    assert response.status_code == 401
