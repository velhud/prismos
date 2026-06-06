# main.py - SYSTEM SANCTUARY (boot wrapper)
#
# Responsibilities:
# - Grace period (ignore the wake tap).
# - Maintain a boot-loop counter on the filesystem.
# - If boot-loop counter exceeds threshold, enter Safe Mode.
# - Run kernel.start() inside a global try/except.
#
# Notes:
# - Manual Safe Mode trigger is handled ONLY in boot.py.
# - main.py must remain simple and resilient.

import time

try:
    import gc
except Exception:
    gc = None

# ---- Boot-loop counter (root file) ----
BOOT_COUNT_FILE = "pm_boot_count.txt"
SAFE_REQUEST_FILE = "pm_safe_request.txt"
BOOT_COUNT_LIMIT = 3

# ---- Boot timing ----
GRACE_PERIOD_S = 1.5

def _read_int_file(path, default=0):
    try:
        with open(path, "r") as f:
            s = f.read().strip()
        if not s:
            return int(default)
        return int(s)
    except Exception:
        return int(default)


def _write_int_file(path, value):
    try:
        with open(path, "w") as f:
            f.write(str(int(value)))
    except Exception:
        pass


def _remove_file(path):
    try:
        import os
        os.remove(path)
    except Exception:
        pass


def _bump_boot_count():
    n = _read_int_file(BOOT_COUNT_FILE, 0) + 1
    _write_int_file(BOOT_COUNT_FILE, n)
    return n


def _adv_safe_name():
    # Keep the vendor BLE advertiser untouched so REPL/NUS and Raw Data
    # services remain discoverable in recovery.
    return


def _truncate(s, max_len=120):
    if s is None:
        return ""
    t = str(s)
    if len(t) <= max_len:
        return t
    return t[:max_len - 3] + "..."


def _safe_requested():
    try:
        with open(SAFE_REQUEST_FILE, "r") as f:
            f.read(1)
        _remove_file(SAFE_REQUEST_FILE)
        return True
    except Exception:
        return False


def safe_mode(reason):
    # Display is safe to use from main.py (post-grace) using the known-safe justify.
    try:
        import display
        display.clear()
        t1 = display.Text("SAFE MODE", 320, 160, display.WHITE, justify=display.MIDDLE_CENTER)
        t2 = display.Text(_truncate(reason, 120), 320, 240, display.WHITE, justify=display.MIDDLE_CENTER)
        t3 = display.Text("CONNECT: Monocle REPL", 320, 320, display.WHITE, justify=display.MIDDLE_CENTER)
        display.show(t1, t2, t3)
    except Exception:
        pass

    print("[MAIN] SAFE MODE:", reason)
    _adv_safe_name()
    # Important: return from main.py so the vendor firmware can enter the
    # built-in Bluetooth REPL. An infinite loop here keeps the user script
    # active and makes recovery depend on Ctrl-C interrupt behavior.
    return


def run():
    # 1) Grace period: ignore wake tap
    time.sleep(GRACE_PERIOD_S)

    if _safe_requested():
        safe_mode("MANUAL SAFE")
        return

    # 2) Boot-loop counter
    n = _bump_boot_count()
    if n >= BOOT_COUNT_LIMIT:
        safe_mode("BOOT LOOP")
        return

    if gc is not None:
        try:
            gc.collect()
        except Exception:
            pass

    try:
        import kernel
        kernel.start()
    except Exception as e:
        safe_mode("CRASH: " + _truncate(e, 90))


if __name__ == "__main__":
    try:
        run()
    except Exception as e:
        safe_mode("MAIN DIED: " + _truncate(e, 90))
