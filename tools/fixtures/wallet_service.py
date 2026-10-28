"""ISOLATED CONTRACT FIXTURE, not a deployable wallet/payment service.

Exercises the documented boundary against SQLite and concurrent connections.
The HMAC adapter below is a fabricated sandbox channel, NOT WeChat/Alipay
verification. There are no production keys, prices, users, or migration scripts.
"""
from contextlib import closing, contextmanager
import hashlib
import hmac
import json
from pathlib import Path
import sqlite3
import uuid

MAX_INTEGER = 2**53 - 1
SANDBOX_KEY = b"public-test-only-not-a-merchant-key"


class Rejected(ValueError):
    pass


def integer(value, minimum=0):
    return type(value) is int and minimum <= value <= MAX_INTEGER


class WalletFixture:
    def __init__(self, database):
        self.database = Path(database).resolve()
        if not any(part.startswith("workbench-check-") for part in self.database.parts):
            raise ValueError("Only an isolated workbench-check-* directory is allowed")
        with closing(self.connect()) as db:
            db.executescript("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS wallets(user TEXT PRIMARY KEY, balance INTEGER NOT NULL CHECK(balance>=0), revision INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS packages(id TEXT PRIMARY KEY, version TEXT NOT NULL, cents INTEGER NOT NULL CHECK(cents>0), amount INTEGER NOT NULL CHECK(amount>0), enabled INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS orders(id TEXT PRIMARY KEY, user TEXT NOT NULL REFERENCES wallets(user), request TEXT NOT NULL, fingerprint TEXT NOT NULL, package TEXT NOT NULL, version TEXT NOT NULL, cents INTEGER NOT NULL, amount INTEGER NOT NULL, channel TEXT NOT NULL, payment TEXT NOT NULL, credit TEXT NOT NULL, revision INTEGER NOT NULL, ledger_id TEXT, UNIQUE(user,request));
            CREATE TABLE IF NOT EXISTS payments(channel TEXT NOT NULL, transaction_id TEXT NOT NULL, order_id TEXT NOT NULL UNIQUE REFERENCES orders(id), UNIQUE(channel,transaction_id));
            CREATE TABLE IF NOT EXISTS ledger(id TEXT PRIMARY KEY, user TEXT NOT NULL REFERENCES wallets(user), event TEXT NOT NULL UNIQUE, delta INTEGER NOT NULL, source TEXT NOT NULL, reference TEXT NOT NULL, order_id TEXT REFERENCES orders(id));
            CREATE TABLE IF NOT EXISTS attempts(id TEXT PRIMARY KEY, user TEXT NOT NULL, question TEXT NOT NULL, expected TEXT NOT NULL, policy TEXT NOT NULL, amount INTEGER NOT NULL, policy_day TEXT NOT NULL, received TEXT, ledger_id TEXT);
            CREATE TABLE IF NOT EXISTS articles(id TEXT PRIMARY KEY, author TEXT NOT NULL, approved INTEGER NOT NULL, published INTEGER NOT NULL, amount INTEGER, ledger_id TEXT);
            """)
            for user in ("wallet-test-a", "wallet-test-b"):
                db.execute("INSERT OR IGNORE INTO wallets VALUES (?,0,0)", (user,))
            for amount in (300, 600, 1200, 3000):
                db.execute("INSERT OR IGNORE INTO packages VALUES (?, 'v1', ?, ?, 1)", (f"preview-{amount}", amount, amount))
        self.post("wallet-test-a", "opening:a", 1280, "opening", "isolated-fixture")
        self.post("wallet-test-b", "opening:b", 17, "opening", "isolated-fixture")

    def connect(self):
        db = sqlite3.connect(self.database, timeout=15, isolation_level=None)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        return db

    @contextmanager
    def transaction(self):
        db = self.connect()
        db.execute("BEGIN IMMEDIATE")
        try:
            yield db
            db.commit()
        except BaseException:
            db.rollback()
            raise
        finally:
            db.close()

    @staticmethod
    def post_in(db, user, event, delta, source, reference, order=None):
        if type(delta) is not int or not integer(abs(delta), 1):
            raise Rejected("invalid_amount")
        old = db.execute("SELECT * FROM ledger WHERE event=?", (event,)).fetchone()
        if old:
            if (old["user"], old["delta"], old["source"], old["reference"]) != (user, delta, source, reference):
                raise Rejected("conflict")
            return old["id"]
        wallet = db.execute("SELECT * FROM wallets WHERE user=?", (user,)).fetchone()
        if wallet is None or not integer(wallet["balance"] + delta):
            raise Rejected("balance_range")
        lid = uuid.uuid4().hex
        db.execute("UPDATE wallets SET balance=balance+?,revision=revision+1 WHERE user=?", (delta, user))
        db.execute("INSERT INTO ledger VALUES (?,?,?,?,?,?,?)", (lid, user, event, delta, source, reference, order))
        return lid

    def post(self, user, event, delta, source, reference):
        with self.transaction() as db:
            return self.post_in(db, user, event, delta, source, reference)

    def create(self, user, payload):
        if set(payload) != {"request_id", "package_id", "package_version", "channel"} or not all(type(v) is str and v for v in payload.values()):
            raise Rejected("invalid_request")
        fingerprint = json.dumps(payload, sort_keys=True)
        with self.transaction() as db:
            old = db.execute("SELECT * FROM orders WHERE user=? AND request=?", (user, payload["request_id"])).fetchone()
            if old:
                if old["fingerprint"] != fingerprint: raise Rejected("conflict")
                return self.order_row(old)
            if payload["channel"] != "sandbox": raise Rejected("disabled")
            p = db.execute("SELECT * FROM packages WHERE id=?", (payload["package_id"],)).fetchone()
            if p is None or not p["enabled"]: raise Rejected("disabled")
            if p["version"] != payload["package_version"]: raise Rejected("price_changed")
            if not integer(p["cents"], 1) or not integer(p["amount"], 1): raise Rejected("invalid_amount")
            oid = uuid.uuid4().hex
            db.execute("INSERT INTO orders VALUES (?,?,?,?,?,?,?,?,?,'pending','none',1,NULL)", (oid, user, payload["request_id"], fingerprint, p["id"], p["version"], p["cents"], p["amount"], payload["channel"]))
            return self.order_row(db.execute("SELECT * FROM orders WHERE id=?", (oid,)).fetchone())

    @staticmethod
    def order_row(row):
        return {"id": row["id"], "account_id": row["user"], "request_id": row["request"], "package_id": row["package"], "package_version": row["version"], "price_cents": row["cents"], "batteries": row["amount"], "currency": "CNY", "channel": row["channel"], "channel_label": "隔离回环测试", "payment_status": row["payment"], "credit_status": row["credit"], "revision": row["revision"], "ledger_id": row["ledger_id"] or "", "created_at": "2026-10-28T08:00:00Z"}

    def order(self, user, oid):
        with closing(self.connect()) as db:
            row = db.execute("SELECT * FROM orders WHERE user=? AND id=?", (user, oid)).fetchone()
            if row is None: raise Rejected("not_found")
            return self.order_row(row)

    @staticmethod
    def sign(fact):
        return hmac.new(SANDBOX_KEY, json.dumps(fact, sort_keys=True).encode(), hashlib.sha256).hexdigest()

    def sandbox_fact(self, oid, transaction_id=None):
        with closing(self.connect()) as db:
            row = db.execute("SELECT * FROM orders WHERE id=?", (oid,)).fetchone()
        return {"order_id": oid, "merchant": "fixture-merchant", "app": "fixture-app", "channel": "sandbox", "transaction_id": transaction_id or "tx-" + oid, "currency": "CNY", "order_total": row["cents"], "status": "paid"}

    def ingest_sandbox_fact(self, fact, signature, crash_before_credit=False):
        if not hmac.compare_digest(signature, self.sign(fact)):
            raise Rejected("signature")
        if fact.get("merchant") != "fixture-merchant" or fact.get("app") != "fixture-app" or fact.get("currency") != "CNY" or fact.get("status") != "paid" or fact.get("channel") != "sandbox" or not fact.get("transaction_id"):
            raise Rejected("invalid_fact")
        with self.transaction() as db:
            row = db.execute("SELECT * FROM orders WHERE id=?", (fact.get("order_id"),)).fetchone()
            if row is None or fact.get("order_total") != row["cents"] or not integer(fact.get("order_total"), 1):
                raise Rejected("amount_or_order")
            old = db.execute("SELECT * FROM payments WHERE order_id=? OR (channel=? AND transaction_id=?)", (row["id"], fact["channel"], fact["transaction_id"])).fetchone()
            if old and (old["order_id"] != row["id"] or old["transaction_id"] != fact["transaction_id"]):
                raise Rejected("transaction_conflict")
            if not old: db.execute("INSERT INTO payments VALUES (?,?,?)", (fact["channel"], fact["transaction_id"], row["id"]))
            if row["credit"] != "credited":
                db.execute("UPDATE orders SET payment='paid',credit='pending',revision=revision+1 WHERE id=?", (row["id"],))
        # Paid facts are durable even if the process exits before fulfillment.
        if crash_before_credit: return
        self.credit(fact["order_id"])

    def credit(self, oid, crash_inside=False):
        with self.transaction() as db:
            row = db.execute("SELECT * FROM orders WHERE id=?", (oid,)).fetchone()
            if row["payment"] != "paid" or not db.execute("SELECT 1 FROM payments WHERE order_id=?", (oid,)).fetchone(): raise Rejected("not_verified")
            lid = self.post_in(db, row["user"], "recharge:" + oid, row["amount"], "recharge", oid, oid)
            if crash_inside: raise RuntimeError("injected rollback")
            db.execute("UPDATE orders SET credit='credited',ledger_id=?,revision=revision+1 WHERE id=? AND credit!='credited'", (lid, oid))

    def recover(self):
        with closing(self.connect()) as db:
            ids = [r[0] for r in db.execute("SELECT id FROM orders WHERE payment='paid' AND credit!='credited'")]
        for oid in ids: self.credit(oid)

    def issue_attempt(self, user, expected, policy="each", question="q1", amount=5, policy_day="test-day-1"):
        # Called only by the test's trusted question/eligibility service.
        if policy not in ("each", "first", "daily") or not integer(amount, 1): raise Rejected("policy")
        aid = uuid.uuid4().hex
        with self.transaction() as db:
            db.execute("INSERT INTO attempts VALUES (?,?,?,?,?,?,?,NULL,NULL)", (aid, user, question, json.dumps(expected), policy, amount, policy_day))
        return aid

    def submit(self, user, aid, answer):
        encoded = json.dumps(answer)
        with self.transaction() as db:
            row = db.execute("SELECT * FROM attempts WHERE id=? AND user=?", (aid, user)).fetchone()
            if row is None: raise Rejected("forbidden")
            if row["received"] is not None and row["received"] != encoded: raise Rejected("conflict")
            if row["expected"] != encoded:
                db.execute("UPDATE attempts SET received=? WHERE id=?", (encoded, aid))
                return None
            suffix = aid if row["policy"] == "each" else user + ":" + row["question"] + (":" + row["policy_day"] if row["policy"] == "daily" else "")
            event = "quiz:" + row["policy"] + ":" + suffix
            # First/daily eligible business event is the reference, not a random retry ID.
            lid = self.post_in(db, user, event, row["amount"], "quiz", event)
            db.execute("UPDATE attempts SET received=?,ledger_id=? WHERE id=?", (encoded, lid, aid))
            return lid

    def publish(self, article):
        with self.transaction() as db:
            row = db.execute("SELECT * FROM articles WHERE id=?", (article,)).fetchone()
            if row is not None and row["ledger_id"]: return row["ledger_id"]
            if row is None or not row["approved"] or not row["published"] or row["amount"] is None: return None
            lid = self.post_in(db, row["author"], "publication:" + article, row["amount"], "publication", article)
            db.execute("UPDATE articles SET ledger_id=? WHERE id=?", (lid, article))
            return lid

    def request(self, user, action, payload):
        try:
            result = {"ok": True, "account_id": user}
            with closing(self.connect()) as db:
                if action == "balance":
                    result.update(dict(db.execute("SELECT balance,revision FROM wallets WHERE user=?", (user,)).fetchone()))
                elif action == "catalog":
                    result.update(packages=[{"id": r["id"], "version": r["version"], "price_cents": r["cents"], "batteries": r["amount"], "enabled": bool(r["enabled"]), "currency": "CNY"} for r in db.execute("SELECT * FROM packages")], channels=[{"id": "sandbox", "label": "隔离回环测试", "enabled": True}], rules={}, preview=True, recharge_enabled=True)
                elif action == "create_order": result["order"] = self.create(user, payload)
                elif action == "order": result["order"] = self.order(user, payload["order_id"])
                elif action in ("orders", "ledger"):
                    if action == "orders":
                        rows = [self.order_row(r) for r in db.execute("SELECT * FROM orders WHERE user=? ORDER BY rowid DESC", (user,))]
                        if payload.get("scope") == "unfinished": rows = [r for r in rows if r["credit_status"] != "credited"]
                    else:
                        rows = [{"id": r["id"], "account_id": user, "source": r["source"], "delta": r["delta"], "reference": r["reference"], "order_id": r["order_id"] or "", "created_at": "2026-10-28T08:00:00Z"} for r in db.execute("SELECT * FROM ledger WHERE user=? ORDER BY rowid DESC", (user,))]
                        if payload.get("filter") in ("income", "expense"): rows = [r for r in rows if (r["delta"] > 0) == (payload["filter"] == "income")]
                    start = int(payload.get("cursor") or "0")
                    limit = min(20, int(payload.get("limit", 20)))
                    result.update(items=rows[start:start + limit], next_cursor=str(start + limit) if start + limit < len(rows) else "")
                else: raise Rejected("unavailable")
            return result
        except (Rejected, KeyError, ValueError) as error:
            return {"ok": False, "account_id": user, "code": str(error), "definitive": str(error) in ("price_changed", "disabled")}
