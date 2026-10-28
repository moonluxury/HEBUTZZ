"""Real SQLite contract tests; no official payment channel or production service."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import unittest

from fixtures.wallet_service import WalletFixture, Rejected, MAX_INTEGER


class WalletContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="workbench-check-wallet-", dir=Path(__file__).resolve().parents[1] / ".godot_appdata")
        self.service = WalletFixture(Path(self.temp.name) / "test.sqlite3")
        self.user = "wallet-test-a"

    def tearDown(self):
        self.temp.cleanup()

    def payload(self, request="one"):
        return dict(request_id=request, package_id="preview-600", package_version="v1", channel="sandbox")

    def create(self, request="one"):
        return self.service.create(self.user, self.payload(request))

    def balance(self):
        return self.service.request(self.user, "balance", {})["balance"]

    def assert_consistent(self):
        with closing(self.service.connect()) as db:
            for row in db.execute("SELECT * FROM wallets"):
                total = db.execute("SELECT coalesce(sum(delta),0) FROM ledger WHERE user=?", (row["user"],)).fetchone()[0]
                self.assertEqual(row["balance"], total)
            self.assertEqual(db.execute("SELECT count(*) FROM orders o LEFT JOIN ledger l ON l.id=o.ledger_id WHERE o.credit='credited' AND (l.id IS NULL OR l.delta!=o.amount OR l.user!=o.user OR l.order_id!=o.id)").fetchone()[0], 0)

    def test_concurrent_create_timeout_retry_and_payload_conflict(self):
        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda _: self.create(), range(24)))
        self.assertEqual(len({r["id"] for r in results}), 1)
        self.assertEqual(self.create()["id"], results[0]["id"])
        changed = self.payload()
        changed["package_id"] = "preview-300"
        with self.assertRaisesRegex(Rejected, "conflict"): self.service.create(self.user, changed)
        spoofed = self.payload("spoof") | {"account_id": "wallet-test-b", "batteries": 9999, "price_cents": 1}
        with self.assertRaisesRegex(Rejected, "invalid_request"): self.service.create(self.user, spoofed)
        self.assert_consistent()

    def test_snapshot_repricing_and_ownership(self):
        order = self.create()
        with self.service.transaction() as db:
            db.execute("UPDATE packages SET version='v2',cents=700,amount=900 WHERE id='preview-600'")
        self.assertEqual((self.create()["price_cents"], self.create()["batteries"]), (600, 600))
        with self.assertRaisesRegex(Rejected, "price_changed"): self.create("new")
        with self.assertRaisesRegex(Rejected, "not_found"): self.service.order("wallet-test-b", order["id"])

    def test_forged_signature_and_business_fields_never_credit(self):
        order = self.create()
        fact = self.service.sandbox_fact(order["id"])
        with self.assertRaisesRegex(Rejected, "signature"): self.service.ingest_sandbox_fact(fact, "forged")
        for field, value in [("merchant", "wrong"), ("app", "wrong"), ("order_id", "wrong"), ("currency", "USD"), ("order_total", 599), ("order_total", 600.0), ("status", "pending"), ("transaction_id", "")]:
            with self.subTest(field=field, value=value):
                wrong = fact | {field: value}
                with self.assertRaises(Rejected): self.service.ingest_sandbox_fact(wrong, self.service.sign(wrong))
        self.assertEqual(self.balance(), 1280)
        with self.assertRaisesRegex(Rejected, "not_verified"): self.service.credit(order["id"])
        self.assert_consistent()

    def test_callback_query_duplicates_discount_and_late_paid_fact(self):
        order = self.create()
        # A local close hint cannot suppress an authoritative late payment.
        with self.service.transaction() as db: db.execute("UPDATE orders SET payment='closed' WHERE id=?", (order["id"],))
        fact = self.service.sandbox_fact(order["id"]) | {"payer_total": 550}
        signature = self.service.sign(fact)
        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda _: self.service.ingest_sandbox_fact(fact, signature), range(24)))
        self.assertEqual(self.balance(), 1880)
        self.assertEqual(self.service.order(self.user, order["id"])["credit_status"], "credited")
        second = self.create("second")
        conflict = self.service.sandbox_fact(second["id"], fact["transaction_id"])
        with self.assertRaisesRegex(Rejected, "transaction_conflict"): self.service.ingest_sandbox_fact(conflict, self.service.sign(conflict))
        self.assert_consistent()

    def test_durable_paid_fact_atomic_rollback_restart_and_lost_response(self):
        order = self.create()
        fact = self.service.sandbox_fact(order["id"])
        self.service.ingest_sandbox_fact(fact, self.service.sign(fact), crash_before_credit=True)
        self.assertEqual(self.balance(), 1280)
        self.assertEqual(self.service.order(self.user, order["id"])["credit_status"], "pending")
        with self.assertRaisesRegex(RuntimeError, "rollback"): self.service.credit(order["id"], crash_inside=True)
        self.assertEqual(self.balance(), 1280)
        self.assert_consistent()
        restarted = WalletFixture(self.service.database)
        restarted.recover()
        restarted.recover()
        self.assertEqual(self.balance(), 1880)
        self.assertEqual(restarted.order(self.user, order["id"])["credit_status"], "credited")
        self.assert_consistent()

    def test_quiz_trusted_attempt_correctness_retry_and_repeat_policy(self):
        with self.assertRaisesRegex(Rejected, "forbidden"): self.service.submit(self.user, "invented", {"correct": True})
        wrong = self.service.issue_attempt(self.user, ["A"])
        self.assertIsNone(self.service.submit(self.user, wrong, ["B"]))
        with self.assertRaisesRegex(Rejected, "conflict"): self.service.submit(self.user, wrong, ["A"])
        first = self.service.issue_attempt(self.user, ["A"])
        with self.assertRaisesRegex(Rejected, "forbidden"): self.service.submit("wallet-test-b", first, ["A"])
        with ThreadPoolExecutor(max_workers=8) as pool:
            ids = list(pool.map(lambda _: self.service.submit(self.user, first, ["A"]), range(16)))
        self.assertEqual(len(set(ids)), 1)
        second = self.service.issue_attempt(self.user, ["A"])
        self.service.submit(self.user, second, ["A"])
        self.assertEqual(self.balance(), 1290)  # each-attempt permits a later real attempt
        for policy in ("first", "daily"):
            ids = [self.service.issue_attempt(self.user, ["A"], policy=policy) for _ in range(2)]
            self.assertEqual(self.service.submit(self.user, ids[0], ["A"]), self.service.submit(self.user, ids[1], ["A"]))
        self.assertEqual(self.balance(), 1300)
        next_day = self.service.issue_attempt(self.user, ["A"], policy="daily", policy_day="test-day-2")
        self.service.submit(self.user, next_day, ["A"])
        self.assertEqual(self.balance(), 1305)  # daily dedup does not block the next eligible day
        self.assert_consistent()

    def test_publication_requires_approval_and_publication_and_policy(self):
        with self.service.transaction() as db:
            db.execute("INSERT INTO articles VALUES ('paper',?,0,0,25,NULL)", (self.user,))
        self.assertIsNone(self.service.publish("paper"))
        with self.service.transaction() as db: db.execute("UPDATE articles SET approved=1 WHERE id='paper'")
        self.assertIsNone(self.service.publish("paper"))
        with self.service.transaction() as db: db.execute("UPDATE articles SET published=1,amount=NULL WHERE id='paper'")
        self.assertIsNone(self.service.publish("paper"))
        with self.service.transaction() as db: db.execute("UPDATE articles SET amount=25 WHERE id='paper'")
        with ThreadPoolExecutor(max_workers=8) as pool:
            ids = list(pool.map(lambda _: self.service.publish("paper"), range(16)))
        self.assertEqual(len(set(ids)), 1)
        self.assertEqual(self.balance(), 1305)
        with self.service.transaction() as db: db.execute("UPDATE articles SET amount=30 WHERE id='paper'")
        self.assertEqual(self.service.publish("paper"), ids[0])
        self.assertEqual(self.balance(), 1305)  # editing a published article is not another reward
        self.assert_consistent()

    def test_simultaneous_recharge_rewards_consumption_and_range_checks(self):
        order = self.create()
        fact = self.service.sandbox_fact(order["id"])
        tasks = [lambda: self.service.ingest_sandbox_fact(fact, self.service.sign(fact))]
        for index in range(20):
            tasks.append(lambda i=index: self.service.post(self.user, f"reward:{i}", 5, "quiz", f"attempt:{i}"))
            tasks.append(lambda i=index: self.service.post(self.user, f"spend:{i}", -3, "spend", f"purchase:{i}"))
        with ThreadPoolExecutor(max_workers=8) as pool: list(pool.map(lambda task: task(), tasks))
        self.assertEqual(self.balance(), 1920)
        for invalid in (0, True, 1.5, MAX_INTEGER + 1):
            with self.assertRaises(Rejected): self.service.post(self.user, "bad", invalid, "quiz", "invalid")
        with self.assertRaises(Rejected): self.service.post(self.user, "too-much", -1921, "spend", "invalid")
        self.assert_consistent()


if __name__ == "__main__":
    unittest.main(verbosity=2)
