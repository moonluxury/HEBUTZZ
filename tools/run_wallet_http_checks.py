"""Run the actual Godot HTTP transport against an isolated SQLite wallet fixture.

The server only binds loopback, and derives fixture identity from test tokens.
No official payment notifications or real accounts are involved.
"""
import argparse
from contextlib import closing
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
import tempfile
from threading import Thread
import time

from fixtures.wallet_service import WalletFixture


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        value = json.loads(body)
        assert value["version"] == 1
        action, payload = value["action"], value["payload"]
        actor = {"Bearer isolated-account-a": "wallet-test-a",
                 "Bearer isolated-account-b": "wallet-test-b"}.get(self.headers.get("Authorization"))
        status = 200
        if not actor or action == "denied":
            status, result = 401, {"ok": False}
        elif action == "redirect":
            status, result = 307, {"ok": False, "account_id": actor}
        elif action == "reject":
            status, result = 403, {"ok": False, "account_id": actor, "code": "forbidden"}
        elif action == "disconnect":
            self.close_connection = True
            return
        else:
            if action == "slow":
                time.sleep(0.3)
                action = "balance"
            result = self.server.wallet.request(actor, action, payload)
        encoded = b"invalid json" if action == "malformed" else json.dumps(result).encode()
        self.send_response(status)
        if status == 307:
            self.send_header("Location", "/must-not-follow")
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        try:
            self.wfile.write(encoded)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass  # The cancellation test deliberately disconnects.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="workbench-check-wallet-http-", dir=root / ".godot_appdata") as fixture:
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        server.wallet = WalletFixture(Path(fixture) / "wallet.sqlite3")
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        env = os.environ.copy()
        env["WALLET_TEST_PORT"] = str(server.server_port)
        try:
            result = subprocess.call([sys.executable, str(root / "tools/run_workbench_checks.py"),
                                      "--godot", args.godot, "--script", "check_wallet_http.gd"], cwd=root, env=env)
            with closing(server.wallet.connect()) as db:
                assert db.execute("SELECT count(*) FROM orders").fetchone()[0] == 1
                assert db.execute("SELECT balance FROM wallets WHERE user='wallet-test-a'").fetchone()[0] == 1280
                assert db.execute("SELECT count(*) FROM payments").fetchone()[0] == 0
            return result
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == "__main__":
    raise SystemExit(main())
