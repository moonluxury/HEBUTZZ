"""Run Godot quiz integration checks in an isolated copy without learner saves.

Usage: python tools/run_quiz_checks.py --godot /path/to/Godot_console --course python
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--course", choices=["python", "matlab", "cpp"], default="python")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    test_root = root / ".godot_appdata"
    test_root.mkdir(exist_ok=True)
    fixture = Path(tempfile.mkdtemp(prefix=f"{args.course}-check-", dir=test_root))
    for name in ["scenes", "scripts", "themes", "fonts", "materials", "shaders", "data", "assets", "runtime"]:
        shutil.copytree(root / name, fixture / name)
    for name in ["project.godot", "icon.svg"]:
        shutil.copy2(root / name, fixture / name)
    (fixture / "tools").mkdir()
    (fixture / "test_saves").mkdir()
    test_script = f"check_{args.course}_questions.gd"
    shutil.copy2(root / "tools" / test_script, fixture / "tools" / test_script)
    state = fixture / "scripts/app_state.gd"
    content = state.read_text(encoding="utf-8").replace("user://", "res://test_saves/")
    content = content.replace("\t_migrate_legacy_user_data()\n", "\t# Test fixture: do not import learner records.\n")
    state.write_text(content, encoding="utf-8")
    runner = fixture / "scripts/python_runner.gd"
    runner.write_text(runner.read_text(encoding="utf-8").replace("user://", "res://test_saves/"), encoding="utf-8")
    config = fixture / "project.godot"
    config.write_text(config.read_text(encoding="utf-8").replace('config/name="河工开物"', 'config/name="Quiz integration check"'), encoding="utf-8")
    environment = os.environ.copy()
    for key in ["APPDATA", "LOCALAPPDATA"]:
        location = fixture / key.lower()
        location.mkdir()
        environment[key] = str(location)
    print(f"Fixture: {fixture}", flush=True)
    steps = [
        ["--editor", "--import", "--log-file", str(fixture / "import.log")],
        ["--script", f"res://tools/{test_script}", "--log-file", str(fixture / "check.log")],
    ]
    for step in steps:
        result = subprocess.run([str(args.godot), "--headless", "--path", str(fixture), *step],
                                env=environment, capture_output=True, timeout=90)
        output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
        if "--script" in step or result.returncode or "ERROR:" in output:
            print(output, flush=True)
        if result.returncode or "ERROR:" in output:
            raise SystemExit(result.returncode or 1)
    print("Checks passed. Fixture retained for inspection.")


if __name__ == "__main__":
    main()
