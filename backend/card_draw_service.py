"""One paid card draw: authoritative odds, wallet debit and inventory in one transaction."""
import secrets
from psycopg.types.json import Jsonb

from database import one, bump
from domain import CARDS, DomainError, require, string, uid, stamp, snapshot
from wallet_service import balance, post, digest

PRICE = 200
POOL_ID = 'season-001'
RULE_VERSION = 'card-draw-20261102-v1'
# Existing catalog IDs: astronaut, ringed planet, spaceplane, station, rocket,
# radio telescope, satellite. Duplicates increase the owned quantity.
ODDS = (('0004', 10), ('0007', 10), ('0005', 12), ('0003', 14),
        ('0001', 16), ('0006', 18), ('0002', 20))


def options():
    require(sum(weight for _, weight in ODDS) == 100 and all(
        card in CARDS and CARDS[card]['season_id'] == POOL_ID for card, _ in ODDS),
        'unavailable', '卡牌暂不可获取，请稍后重试。', 503)
    return {'price': PRICE, 'pool_id': POOL_ID, 'rule_version': RULE_VERSION,
            'duplicates': True, 'odds': [{'card_id': card, 'percent': weight} for card, weight in ODDS]}


def choose_card(ticket):
    assert type(ticket) is int and 0 <= ticket < 100
    boundary = 0
    for card, weight in ODDS:
        boundary += weight
        if ticket < boundary:
            return card
    raise AssertionError('Invalid card pool')


def result(conn, actor, receipt):
    # Always return current state. Reopening an old draw must not resurrect a
    # card that has since been transferred or an old wallet balance.
    body = receipt if receipt.get('state') == 'failed' else {'state': 'succeeded', 'draw': receipt}
    return {**body, **balance(conn, actor),
            'collection': {'account_id': actor, **snapshot(conn, actor)}}


def grant_card(conn, actor, card):
    old = one(conn, 'SELECT count FROM inventory WHERE user_id=%s AND card_id=%s', (actor, card))
    require(not old or old['count'] < 2147483647, 'inventory_limit', '该卡牌数量已达上限。', 409)
    conn.execute('INSERT INTO inventory(user_id,card_id,count) VALUES (%s,%s,1) ON CONFLICT(user_id,card_id) DO UPDATE SET count=inventory.count+1', (actor, card))
    bump(conn, actor)


def draw(conn, actor, payload):
    require(set(payload) == {'operation_id', 'pool_id', 'expected_price', 'rule_version'})
    operation = string(payload['operation_id'], 128, False)
    fingerprint = digest(payload)
    previous = one(conn, 'SELECT action,request_hash,response FROM operations WHERE actor=%s AND operation_id=%s', (actor, operation))
    if previous:
        require(previous['action'] == 'card_draw' and previous['request_hash'] == fingerprint,
                'idempotency_conflict', '本次操作与原获取请求不一致。', 409)
        return result(conn, actor, previous['response'])
    try:
        with conn.transaction():
            config = options()
            require(payload['pool_id'] == config['pool_id'] and payload['rule_version'] == RULE_VERSION,
                    'pool_changed', '卡牌获取规则已更新，请重新打开。', 409)
            require(type(payload['expected_price']) is int and payload['expected_price'] == PRICE,
                    'price_changed', '本次获取需要 200 电池。', 409)
            require(balance(conn, actor)['balance'] >= PRICE, 'insufficient_balance', '电池不足，本次需要 200 电池。', 409)
            card = choose_card(secrets.randbelow(100))
            receipt_id = uid()
            ledger_id = post(conn, actor, 'card_draw:' + operation, 'card_draw', -PRICE, receipt_id)
            grant_card(conn, actor, card)
            time = one(conn, 'SELECT now() AS value')['value']
            receipt = {'id': receipt_id, 'operation_id': operation, 'card_id': card, 'quantity': 1,
                       'price': PRICE, 'pool_id': POOL_ID, 'rule_version': RULE_VERSION,
                       'ledger_id': ledger_id, 'created_at': stamp(time)}
    except DomainError as error:
        if error.code not in {'insufficient_balance', 'inventory_limit', 'pool_changed', 'price_changed'}:
            raise
        # Persist terminal refusals too: a delayed retry of an insufficient-
        # balance request must not unexpectedly spend newly earned batteries.
        receipt = {'state': 'failed', 'ok': False, 'operation_id': operation,
                   'code': error.code, 'message': error.message, 'definitive': True}
    conn.execute('INSERT INTO operations(actor,operation_id,action,request_hash,response) VALUES (%s,%s,%s,%s,%s)',
                 (actor, operation, 'card_draw', fingerprint, Jsonb(receipt)))
    return result(conn, actor, receipt)


def handle(conn, actor, action, payload):
    # wallet_service has already locked the actor and revalidated the session.
    if action == 'card_draw_options':
        require(not payload)
        return options()
    if action == 'card_draw':
        return draw(conn, actor, payload)
    require(action == 'card_draw_status' and set(payload) == {'operation_id'})
    operation = string(payload['operation_id'], 128, False)
    previous = one(conn, "SELECT response FROM operations WHERE actor=%s AND operation_id=%s AND action='card_draw'", (actor, operation))
    if not previous:
        return {'state': 'not_found', 'operation_id': operation}
    return result(conn, actor, previous['response'])
