# prism/sys.py
# Intra-device signaling between apps and the kernel.
#
# This module is intentionally simple and allocation-light:
# - apps set flags / small strings here
# - kernel polls/consumes them in its loop
#
# No BLE is performed here. This is device-local only.

import time

_dirty = False

_exit_requested = False

_toast_msg = ""
_toast_deadline = 0  # ticks_ms timestamp when toast expires

_ghost_active = False
_ghost_text = ""
_ghost_flash = False
_ghost_icon = ""


def _set_dirty():
    global _dirty
    _dirty = True


def consume_dirty():
    """
    Returns True once when anything user-visible changed through this module.
    """
    global _dirty
    if _dirty:
        _dirty = False
        return True
    return False


# -------------------------
# Exit requests
# -------------------------

def request_exit():
    """
    App requests exit to Orbit. Kernel must decide whether to honor it.
    """
    global _exit_requested
    _exit_requested = True
    _set_dirty()


def consume_exit_request():
    """
    Kernel consumes an exit request (one-shot).
    """
    global _exit_requested
    if _exit_requested:
        _exit_requested = False
        return True
    return False


# -------------------------
# Toasts (short-lived message)
# -------------------------

def toast(msg, ttl_ms=1500):
    """
    Store a toast message that expires automatically.
    ttl_ms is in milliseconds and uses ticks_ms arithmetic.
    """
    global _toast_msg, _toast_deadline
    _toast_msg = "" if msg is None else str(msg)
    try:
        ttl = int(ttl_ms)
    except Exception:
        ttl = 1500
    _toast_deadline = time.ticks_add(time.ticks_ms(), ttl)
    _set_dirty()


def clear_toast():
    global _toast_msg, _toast_deadline
    _toast_msg = ""
    _toast_deadline = 0
    _set_dirty()


def get_toast(now_ms=None):
    """
    Returns toast string if active; otherwise returns None.
    Clears automatically when expired.
    """
    global _toast_msg, _toast_deadline

    if not _toast_msg:
        return None

    if now_ms is None:
        now_ms = time.ticks_ms()

    # If deadline reached/passed -> expire
    if time.ticks_diff(_toast_deadline, now_ms) <= 0:
        _toast_msg = ""
        _toast_deadline = 0
        _set_dirty()
        return None

    return _toast_msg


# -------------------------
# Ghost (device-local overlay)
# -------------------------

def set_ghost(active, text="", flash=False, icon=""):
    """
    Set device-local ghost overlay.
    Kernel may choose precedence relative to host-driven GHOST messages.
    """
    global _ghost_active, _ghost_text, _ghost_flash, _ghost_icon
    _ghost_active = bool(active)
    _ghost_text = "" if text is None else str(text)
    _ghost_flash = bool(flash)
    _ghost_icon = "" if icon is None else str(icon)
    _set_dirty()


def clear_ghost():
    set_ghost(False, "", False)


def get_ghost():
    """
    Returns (active:bool, text:str, flash:bool, icon:str)
    """
    return _ghost_active, _ghost_text, _ghost_flash, _ghost_icon
