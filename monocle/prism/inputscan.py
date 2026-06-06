# prism/inputscan.py
# Polling input scanner for Monocle touch pads.
#
# MicroPython touch API used:
# - touch.state(touch.A) -> True/False
# - touch.state(touch.B) -> True/False
#
# Repository mapping:
# - LEFT pad  = touch.B
# - RIGHT pad = touch.A
#
# Output:
# - emits event name strings from prism/input.py to the provided callback

import time
import touch

from prism import input as inp


class InputScanner:
    """
    Stateless from kernel perspective:
    - kernel calls update(now_ms) regularly
    - scanner calls emit_fn(event_name) when an event is recognized
    """

    # Timing constants (milliseconds)
    DEBOUNCE_MS = inp.DEBOUNCE_MS
    LONG_MS = inp.LONG_MS
    DOUBLE_WINDOW_MS = inp.DOUBLE_WINDOW_MS

    def __init__(self, emit_fn):
        self._emit = emit_fn

        # Index 0 = Left, 1 = Right
        self._pads = (touch.B, touch.A)

        self._down = [False, False]
        self._down_since = [0, 0]
        self._long_fired = [False, False]

        self._tap_pending = [False, False]
        self._tap_deadline = [0, 0]

        self._tap_evt = (inp.TAP_L, inp.TAP_R)
        self._long_evt = (inp.LONG_L, inp.LONG_R)
        self._double_evt = (inp.DOUBLE_L, inp.DOUBLE_R)

    def update(self, now_ms=None):
        if now_ms is None:
            now_ms = time.ticks_ms()

        # Process both sides
        self._update_one(0, now_ms)
        self._update_one(1, now_ms)

    def _safe_state(self, pad):
        try:
            return bool(touch.state(pad))
        except Exception:
            return False

    def _emit_event(self, ev):
        try:
            self._emit(ev)
        except Exception:
            pass

    def _update_one(self, i, now):
        pad = self._pads[i]
        down = self._safe_state(pad)
        prev_down = self._down[i]

        # 1) Flush pending TAP if its window expired (even if a new press starts now)
        if self._tap_pending[i]:
            if time.ticks_diff(now, self._tap_deadline[i]) >= 0:
                self._tap_pending[i] = False
                self._emit_event(self._tap_evt[i])

        # 2) Edge: press
        if down and (not prev_down):
            self._down[i] = True
            self._down_since[i] = now
            self._long_fired[i] = False
            return

        # 3) While held: long press recognition
        if down and prev_down:
            if (not self._long_fired[i]) and (time.ticks_diff(now, self._down_since[i]) >= self.LONG_MS):
                self._long_fired[i] = True
                # long cancels any pending tap/double sequence
                self._tap_pending[i] = False
                self._emit_event(self._long_evt[i])
            return

        # 4) Edge: release
        if (not down) and prev_down:
            self._down[i] = False

            # Ignore if long already fired during this hold
            if self._long_fired[i]:
                return

            # Enforce a minimum press duration to filter very short glitches
            dur = time.ticks_diff(now, self._down_since[i])
            if dur < self.DEBOUNCE_MS:
                return

            # If a tap was pending, second tap completes DOUBLE
            if self._tap_pending[i]:
                self._tap_pending[i] = False
                self._emit_event(self._double_evt[i])
                return

            # Otherwise, start tap pending window (may become double)
            self._tap_pending[i] = True
            self._tap_deadline[i] = time.ticks_add(now, self.DOUBLE_WINDOW_MS)
            return
