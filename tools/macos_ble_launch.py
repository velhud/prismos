#!/usr/bin/env python3
"""Launch BLE Python scripts through the macOS Python.app bundle.

CoreBluetooth requires an app bundle with Bluetooth usage strings on recent
macOS versions. This wrapper runs repo scripts through Python.app and tails a
log so command-line BLE tools can still be used from Terminal.
"""

import argparse
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path


PYTHON_APP = Path(
    "/opt/homebrew/Cellar/python@3.12/3.12.11/Frameworks/"
    "Python.framework/Versions/3.12/Resources/Python.app"
)
ROOT = Path(__file__).resolve().parents[1]


def make_wrapper(target, args, log_path):
    fd, path = tempfile.mkstemp(prefix="prismos_ble_runner_", suffix=".py")
    os.close(fd)
    wrapper = Path(path)
    code = f"""
import contextlib
import runpy
import sys
import traceback
from pathlib import Path

target = {str(target)!r}
log_path = Path({str(log_path)!r})
sys.argv = [{str(target)!r}] + {list(args)!r}

code = 0
with log_path.open("a", buffering=1) as log:
    with contextlib.redirect_stdout(log), contextlib.redirect_stderr(log):
        print("__PRISMOS_BLE_START__")
        try:
            runpy.run_path(target, run_name="__main__")
        except SystemExit as exc:
            code = int(exc.code or 0) if isinstance(exc.code, int) else 1
        except BaseException:
            code = 1
            traceback.print_exc()
        print("__PRISMOS_BLE_DONE__", code)
raise SystemExit(code)
"""
    wrapper.write_text(code)
    return wrapper


def follow_log(log_path, timeout):
    start = time.monotonic()
    pos = 0
    done = False
    code = None
    while True:
        if log_path.exists():
            text = log_path.read_text(errors="replace")
            if len(text) > pos:
                chunk = text[pos:]
                pos = len(text)
                sys.stdout.write(chunk)
                sys.stdout.flush()
                for line in chunk.splitlines():
                    if line.startswith("__PRISMOS_BLE_DONE__"):
                        done = True
                        parts = line.split()
                        if len(parts) >= 2:
                            try:
                                code = int(parts[1])
                            except ValueError:
                                code = 1
        if done:
            return int(code or 0)
        if timeout is not None and time.monotonic() - start > timeout:
            print("Log follow timeout; process may still be running. Log:", log_path)
            return 124
        time.sleep(0.25)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=120.0)
    parser.add_argument("--log")
    parser.add_argument("script")
    parser.add_argument("script_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    target = Path(args.script)
    if not target.is_absolute():
        target = (ROOT / target).resolve()
    if not target.exists():
        raise SystemExit("script not found: %s" % target)
    if not PYTHON_APP.exists():
        raise SystemExit("Python.app not found: %s" % PYTHON_APP)

    log_path = Path(args.log) if args.log else Path(tempfile.mktemp(prefix="prismos_ble_", suffix=".log"))
    wrapper = make_wrapper(target, args.script_args, log_path)
    print("Launching via Python.app")
    print("Log:", log_path)
    subprocess.run(["open", str(PYTHON_APP), "--args", "-u", str(wrapper)], check=True)
    raise SystemExit(follow_log(log_path, args.timeout))


if __name__ == "__main__":
    main()
