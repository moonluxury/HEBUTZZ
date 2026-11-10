"""Bank-wide character budget and owner-only, deduplicated mail outbox."""
from database import one, transaction
from domain import DomainError, uid

BANK_CHAR_LIMIT = 1_000_000


class CapacityExceeded(DomainError):
    def __init__(self, bank, used, incoming):
        # No capacity notice is returned for display to ordinary users.
        super().__init__('discussion_full', '', 409)
        self.bank, self.used, self.incoming = bank, used, incoming


def used_chars(conn, bank):
    return one(conn, 'SELECT coalesce(sum(char_length(body)),0) AS n FROM bank_comments WHERE bank_id=%s', (bank,))['n']


def enqueue(conn, bank, used, incoming):
    # Concurrent retries update one incident, not one email per user/request.
    conn.execute('''INSERT INTO discussion_capacity_alerts(id,bank_id,used_chars,incoming_chars,limit_chars)
        VALUES (%s,%s,%s,%s,%s)
        ON CONFLICT(bank_id) WHERE resolved_at IS NULL DO UPDATE
        SET last_seen_at=now(),used_chars=EXCLUDED.used_chars,incoming_chars=EXCLUDED.incoming_chars''',
        (uid(), bank, used, incoming, BANK_CHAR_LIMIT))


def record_rejection(error):
    # Called by the HTTP exception handler AFTER the rejected write rolls back.
    # A transaction rollback must not discard the operator's notification.
    with transaction() as conn:
        exists = one(conn, 'SELECT id FROM discussion_banks WHERE id=%s FOR NO KEY UPDATE', (error.bank,))
        if not exists: return
        current = used_chars(conn, error.bank)
        if current + error.incoming > BANK_CHAR_LIMIT:
            enqueue(conn, error.bank, current, error.incoming)


def reserve(conn, bank, incoming):
    # All create/delete operations acquire this bank lock before changing text.
    current = used_chars(conn, bank)
    if current + incoming > BANK_CHAR_LIMIT:
        raise CapacityExceeded(bank, current, incoming)
    if current + incoming == BANK_CHAR_LIMIT:
        enqueue(conn, bank, current + incoming, incoming)


def released(conn, bank):
    conn.execute('UPDATE discussion_capacity_alerts SET resolved_at=now() WHERE bank_id=%s AND resolved_at IS NULL', (bank,))
