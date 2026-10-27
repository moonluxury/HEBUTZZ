"""Verify the workbench in isolated saves; --visual also captures real Godot frames."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--visual", action="store_true")
    parser.add_argument("--script", default="check_workbench.gd")
    parser.add_argument("--timeout", type=float, default=240, help="Maximum seconds for the selected suite")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    fixture = Path(tempfile.mkdtemp(prefix="workbench-check-", dir=root / ".godot_appdata"))
    env = os.environ.copy()
    for key in ["APPDATA", "LOCALAPPDATA"]:
        folder = fixture / key.lower()
        folder.mkdir()
        env[key] = str(folder)
    command = [str(args.godot), "--path", str(root), "--rendering-method", "gl_compatibility",
               "--script", "res://tools/" + args.script, "--log-file", str(fixture / "check.log")]
    if not args.visual:
        command.append("--headless")
    completed = subprocess.run(command, env=env, capture_output=True, timeout=args.timeout)
    output = (completed.stdout + completed.stderr).decode("utf-8", errors="replace")
    print(output)
    print(f"Isolated saves and log: {fixture}")
    if completed.returncode or "ERROR:" in output or "WORKBENCH CHECKS: PASS" not in output:
        raise SystemExit(completed.returncode or 1)


if __name__ == "__main__":
    main()
