# prism/input.py
# Canonical input event names + helpers.
#
# Hardware mapping (repository baseline):
# - Physical LEFT pad  -> touch.B
# - Physical RIGHT pad -> touch.A
#
# This file defines:
# - event name constants used by kernel/apps
# - event_parts(...) helper used by kernel uplink envelope

from prism import ids

# Event names (strings) - keep these stable
TAP_L = "TAP_L"
TAP_R = "TAP_R"
LONG_L = "LONG_L"
LONG_R = "LONG_R"
DOUBLE_L = "DOUBLE_L"
DOUBLE_R = "DOUBLE_R"

# Gesture timing (canonical, milliseconds)
DEBOUNCE_MS = 30
LONG_MS = 800
DOUBLE_WINDOW_MS = 300

ALL_EVENTS = (TAP_L, TAP_R, LONG_L, LONG_R, DOUBLE_L, DOUBLE_R)

def event_parts(event_name):
    """
    Converts event name -> (side, gesture) for device->host BTN envelope.

    Returns:
      side: "L" or "R"
      gesture: "TAP" | "LONG" | "DOUBLE"
    """
    if event_name == TAP_L:
        return ids.BTN_ID_L, ids.GEST_TAP
    if event_name == TAP_R:
        return ids.BTN_ID_R, ids.GEST_TAP
    if event_name == LONG_L:
        return ids.BTN_ID_L, ids.GEST_LONG
    if event_name == LONG_R:
        return ids.BTN_ID_R, ids.GEST_LONG
    if event_name == DOUBLE_L:
        return ids.BTN_ID_L, ids.GEST_DOUBLE
    if event_name == DOUBLE_R:
        return ids.BTN_ID_R, ids.GEST_DOUBLE
    return None, None
