"""Run one editor draft in its own process and working directory.

This is a local Python interpreter, not a security sandbox. The Godot owner
enforces the time/output limits and terminates this process when leaving a question.
"""
import json
import os
from pathlib import Path
import sys
import traceback


def main():
    directory = Path(sys.argv[1]).resolve()
    os.chdir(directory)
    sys.stdin = open("stdin.txt", encoding="utf-8")
    stream = open("output.txt", "w", encoding="utf-8", buffering=1)
    sys.stdout = stream
    sys.stderr = stream
    # Make imported standard-library code and ordinary relative file exercises work.
    sys.argv = ["main.py"]
    result = {"exit_code": 0}
    try:
        source = Path("main.py").read_text(encoding="utf-8")
        exec(compile(source, "main.py", "exec"), {"__name__": "__main__", "__file__": "main.py"})
    except SystemExit as error:
        result["exit_code"] = error.code if isinstance(error.code, int) else (0 if error.code is None else 1)
        if error.code is not None and not isinstance(error.code, int):
            print(error.code, file=stream)
    except BaseException as error:
        result["exit_code"] = 1
        traceback.print_exception(type(error), error, error.__traceback__.tb_next, file=stream)
    finally:
        stream.flush()
        # Atomic publication: Godot never reads a partially written result.
        pending = directory / "result.tmp"
        pending.write_text(json.dumps(result), encoding="utf-8")
        pending.replace(directory / "result.json")


if __name__ == "__main__":
    main()
