"""One account wishlist shared by collection and friend views; actor lock held by dispatch."""
from psycopg.types.json import Jsonb
from database import one
from domain import CARDS, integer, require, require_friend, string, user


def read(conn, actor):
    value = one(conn, 'SELECT revision,card_ids FROM collection_wishlists WHERE user_id=%s', (actor,))
    return {'wishlist_revision': value['revision'] if value else 0,
            'initialized': value is not None,
            'card_ids': [card for card in CARDS if value and card in value['card_ids']]}


def handle(conn, actor, action, payload):
    if action == 'wishlist':
        peer = string(payload.get('peer_id'), 64, False)
        user(conn, peer)
        require_friend(conn, actor, peer)
        return {**read(conn, peer), 'visibility': 'accessible'}
    if action == 'wishlist_load':
        return read(conn, actor)
    require(action == 'wishlist_update')
    require(set(payload) <= {'operation_id', 'expected_revision', 'changes'})
    expected = integer(payload.get('expected_revision'), high=2**53-1)
    changes = payload.get('changes')
    require(isinstance(changes, dict) and len(changes) <= len(CARDS))
    require(all(card in CARDS and type(wanted) is bool for card, wanted in changes.items()))
    current = read(conn, actor)
    require(current['wishlist_revision'] == expected, 'wishlist_conflict', '清单已在其他设备更新，正在合并你的修改。', 409)
    wanted = set(current['card_ids'])
    for card, enabled in changes.items():
        if enabled:
            wanted.add(card)
        else:
            wanted.discard(card)
    cards = [card for card in CARDS if card in wanted]
    if not current['initialized'] or cards != current['card_ids']:
        conn.execute('INSERT INTO collection_wishlists(user_id,revision,card_ids) VALUES (%s,%s,%s) '
                     'ON CONFLICT(user_id) DO UPDATE SET revision=EXCLUDED.revision,card_ids=EXCLUDED.card_ids,updated_at=now()',
                     (actor, expected + 1, Jsonb(cards)))
    return read(conn, actor)
