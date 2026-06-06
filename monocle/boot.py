# boot.py - Minimal Safety Gate (runs before main.py)
#
# Rules for boot.py:
# - No display usage (display pipeline may be unavailable here).
# - No imports from prism/ or apps/.
# - Only minimal modules: touch, time, (optional) led.
#
# Behavior:
# - If LEFT pad (touch.B) is held continuously for SAFE_HOLD_MS, request Safe Mode.
# - Otherwise return immediately and allow main.py to execute.

import time
import touch

try:
    import led
except Exception:
    led = None

# Hardware mapping (Physical LEFT pad is touch.B)
BTN_LEFT = touch.B

SAFE_HOLD_MS = 3000
POLL_MS = 50
SAFE_REQUEST_FILE = "pm_safe_request.txt"


def _adv_safe_name():
    # Do not replace the vendor advertiser here.
    #
    # The documented recovery path depends on the built-in REPL/NUS service
    # remaining connectable. Earlier code attempted to use a low-level BLE
    # advertiser, but that API is not part of the Monocle bluetooth module
    # reference and may drop service UUIDs from advertising.
    return


def _led_heartbeat():
    if led is None:
        return
    try:
        led.on(led.RED)
        time.sleep_ms(300)
        led.off(led.RED)
        time.sleep_ms(700)
    except Exception:
        pass


def _held_continuously(ms):
    # Require continuous hold for full duration.
    # If released at any point, returns False.
    start = time.ticks_ms()
    while time.ticks_diff(time.ticks_ms(), start) < ms:
        try:
            if not touch.state(BTN_LEFT):
                return False
        except Exception:
            return False
        time.sleep_ms(POLL_MS)
    return True


def enter_safe_mode():
    print("[BOOT] SAFE MODE REQUESTED. main.py will return to Monocle REPL.")
    _adv_safe_name()
    try:
        with open(SAFE_REQUEST_FILE, "w") as f:
            f.write("1")
    except Exception:
        pass
    _led_heartbeat()


# ---- Execution ----
try:
    # Only verifying hold if the pad is already down at boot time.
    if touch.state(BTN_LEFT):
        if _held_continuously(SAFE_HOLD_MS):
            enter_safe_mode()
except Exception:
    # Never block normal boot because boot.py failed.
    pass
