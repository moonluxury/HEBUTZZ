"""Exercise Godot HTTPRequest against an isolated loopback server; no real credentials."""
import argparse
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
from threading import Thread


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        value = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        assert value["version"] == 1
        assert self.headers.get("Authorization") == "Bearer isolated-not-a-real-key"
        action = value["action"]
        status = {"denied": 401, "reject": 403, "redirect": 307}.get(action, 200)
        result = {"ok": action == "sync", "account_id": "http-test-account",
                  "cursor": value["payload"].get("cursor", ""), "code": "forbidden"}
        body = b"malformed response" if action == "malformed" else json.dumps(result).encode()
        self.send_response(status)
        if action == "redirect":
            self.send_header("Location", "/must-not-follow")
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env = os.environ.copy()
    env["SOCIAL_TEST_PORT"] = str(server.server_port)
    try:
        return subprocess.call([sys.executable, str(root / "tools/run_workbench_checks.py"),
                                "--godot", args.godot, "--script", "check_social_http.gd"],
                               cwd=root, env=env)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    raise SystemExit(main())
