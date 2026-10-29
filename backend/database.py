import os
from contextlib import contextmanager
from pathlib import Path

from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

pool = ConnectionPool(
    os.environ.get('DATABASE_URL', 'dbname=hegong user=hegong host=/var/run/postgresql'),
    min_size=1, max_size=8, timeout=10, open=False,
    kwargs={'row_factory': dict_row, 'options': '-c statement_timeout=10000 -c lock_timeout=5000'},
)


def migrate():
    with pool.connection() as conn:
        conn.execute('SELECT pg_advisory_xact_lock(72810429)')
        conn.execute(Path(__file__).with_name('schema.sql').read_text(encoding='utf-8'))


@contextmanager
def transaction():
    with pool.connection() as conn:
        with conn.transaction():
            yield conn


def one(conn, sql, args=()):
    return conn.execute(sql, args).fetchone()


def rows(conn, sql, args=()):
    return conn.execute(sql, args).fetchall()


def lock_users(conn, *ids):
    # Every inventory/relationship/transfer writer uses this common lock order.
    for user_id in sorted(set(ids)):
        conn.execute('SELECT id FROM users WHERE id=%s FOR UPDATE', (user_id,)).fetchone()


def bump(conn, *ids):
    conn.execute('UPDATE users SET revision=revision+1 WHERE id=ANY(%s)', (list(set(ids)),))
