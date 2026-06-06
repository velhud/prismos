# apps/chronos.py
# Chronos application - The Temporal Interface
#
# Rules:
# - Strictly use ui.text_lines / ui.text_line which guarantees justification=display.MIDDLE_CENTER.
# - Fully implement all BaseApp lifecycle events.
# - Clean up and prevent memory leaks.

from prism.app import BaseApp
from prism import ids, ui, sys as psys, schema, bridge

import time

APP_ID = ids.APP_CHRONOS
APP_LABEL = ids.LABEL_CHRONOS

_BLINK_MS = 250  # 2Hz blinking frequency


def _clamp_f01(v):
    try:
        f = float(v)
    except Exception:
        f = 0.0
    if f < 0.0:
        return 0.0
    if f > 1.0:
        return 1.0
    return f


def _bar(p, width_chars):
    p = _clamp_f01(p)
    filled = int(p * float(width_chars))
    if filled < 0:
        filled = 0
    if filled > width_chars:
        filled = width_chars
    return "[" + ("#" * filled) + ("." * (width_chars - filled)) + "]"


def _parse_time_text(t_str):
    try:
        parts = t_str.split(":")
        if len(parts) == 2:
            return int(parts[0]) * 60 + int(parts[1])
        return 0
    except Exception:
        return 0


def _format_time_text(secs):
    mm = secs // 60
    ss = secs % 60
    return "{:02d}:{:02d}".format(mm, ss)


class ChronosApp(BaseApp):
    def __init__(self):
        self.mode = "TIMER"       # TIMER | STOPWATCH
        self.time_text = "00:00"
        self.progress = 0.0
        self.alarm = False
        
        self.pinned = False
        self.is_running = False

        self._blink_on = True
        self._next_blink = time.ticks_ms()

        self._dirty = True

    def on_start(self):
        self.mode = "TIMER"
        self.time_text = "00:00"
        self.progress = 0.0
        self.alarm = False
        self.pinned = False
        self.is_running = False
        self._blink_on = True
        self._next_blink = time.ticks_ms()
        self._dirty = True
        
        try:
            psys.toast("CHRONOS", ttl_ms=600)
        except Exception:
            pass
        return True

    def on_update(self, now_ms):
        if not self.alarm:
            if not self._blink_on:
                self._blink_on = True
                return True
            return False

        # Flash at 2Hz during alarm
        if time.ticks_diff(now_ms, self._next_blink) >= 0:
            self._next_blink = time.ticks_add(now_ms, _BLINK_MS)
            self._blink_on = not self._blink_on
            return True

        return False

    def _ghost_text(self):
        tag = "T-" if self.mode == "TIMER" else "SW "
        return tag + (self.time_text or "")

    def on_input(self, event_name):
        # 1) If alarm is ringing, ANY button tap dismisses it
        if self.alarm:
            self.alarm = False
            try:
                bridge.send_json({"event": "ALARM_DISMISS", "app": APP_ID})
            except Exception:
                pass
            self._dirty = True
            return True

        # 2) Paused/Setup state: Tap L/R adjusts timer limit
        if not self.is_running and self.mode == "TIMER":
            if event_name == "TAP_L":
                secs = _parse_time_text(self.time_text)
                secs = max(0, secs - 60)
                self.time_text = _format_time_text(secs)
                try:
                    bridge.send_json({"event": "TIMER_ADJUST", "secs": secs})
                except Exception:
                    pass
                self._dirty = True
                return True

            if event_name == "TAP_R":
                secs = _parse_time_text(self.time_text)
                secs = min(5940, secs + 60)
                self.time_text = _format_time_text(secs)
                try:
                    bridge.send_json({"event": "TIMER_ADJUST", "secs": secs})
                except Exception:
                    pass
                self._dirty = True
                return True

        # 3) Running state: Tap L/R toggles Ghost Pinning
        if self.is_running:
            if event_name in ("TAP_L", "TAP_R"):
                self.pinned = not self.pinned
                if self.pinned:
                    psys.set_ghost(True, text=self._ghost_text(), flash=self.alarm, icon="TMR")
                    psys.request_exit()
                    try:
                        psys.toast("PINNED HUD", ttl_ms=500)
                    except Exception:
                        pass
                else:
                    psys.clear_ghost()
                    try:
                        psys.toast("UNPINNED", ttl_ms=500)
                    except Exception:
                        pass
                self._dirty = True
                return True

        # 4) Hold Right: Start/Pause toggle (relied on host syncing)
        if event_name == "LONG_R":
            try:
                bridge.send_json({"event": "TIMER_TOGGLE", "app": APP_ID})
            except Exception:
                pass
            return False

        # 5) Double Left: Reset
        if event_name == "DOUBLE_L":
            try:
                bridge.send_json({"event": "TIMER_RESET", "app": APP_ID})
            except Exception:
                pass
            return False

        return False

    def on_data(self, payload):
        if not isinstance(payload, dict):
            return False

        m = payload.get("mode")
        if isinstance(m, str) and m in ("TIMER", "STOPWATCH"):
            self.mode = m

        self.time_text = schema.clamp_str(payload.get("time", self.time_text), 12)
        self.progress = _clamp_f01(payload.get("progress", self.progress))
        self.alarm = bool(payload.get("alarm", False))
        self.is_running = bool(payload.get("is_playing", payload.get("is_running", self.is_running)))

        if self.pinned:
            psys.set_ghost(True, text=self._ghost_text(), flash=self.alarm, icon="TMR")

        self._dirty = True
        return True

    def render(self):
        objs = []

        # Mode Indicator
        objs.extend(ui.text_lines(self.mode, 320, 64, color=ui.GRAY, anchor="TC"))

        # Alarm complete urgent flashing
        if self.alarm:
            blink_col = ui.RED if self._blink_on else ui.GRAY_DARK
            objs.extend(ui.text_lines("!!! ALARM !!!", 320, 100, color=blink_col, anchor="TC"))
            objs.extend(ui.text_lines("!!! ALARM !!!", 320, 280, color=blink_col, anchor="BC"))

        # Large high-fidelity visual digital clock frame
        objs.extend(ui.text_lines("+-----------------+", 320, 120, color=ui.WHITE, anchor="TC"))
        if (not self.alarm) or self._blink_on:
            objs.extend(ui.text_lines("|  " + self.time_text + "  |", 320, 168, color=ui.WHITE, anchor="TC"))
        else:
            objs.extend(ui.text_lines("|                 |", 320, 168, color=ui.WHITE, anchor="TC"))
        objs.extend(ui.text_lines("+-----------------+", 320, 216, color=ui.WHITE, anchor="TC"))

        # Progress bar
        if ui.ENABLE_SHAPES:
            # Draw thin background slider in GRAY_DARK
            objs.extend(ui.rect(200, 260, 440, 264, color=ui.GRAY_DARK))
            # Draw thin foreground filled progress in WHITE
            w = int(240 * self.progress)
            if w > 0:
                objs.extend(ui.rect(200, 260, 200 + w, 264, color=ui.WHITE))
        else:
            objs.extend(ui.text_lines(_bar(self.progress, 16), 320, 260, color=ui.GRAY, anchor="MC"))

        # Operational Hints based on current state
        if self.alarm:
            objs.extend(ui.text_lines("TAP ANY BUTTON TO DISMISS", 320, ui.HEIGHT, color=ui.WHITE, anchor="BC"))
        else:
            if self.is_running:
                objs.extend(ui.text_lines("TAP: PIN HUD", 8, ui.HEIGHT, color=ui.GRAY, anchor="BL"))
                objs.extend(ui.text_lines("HOLD R: PAUSE", ui.WIDTH - 8, ui.HEIGHT, color=ui.GRAY, anchor="BR"))
            else:
                objs.extend(ui.text_lines("L/R: ADJUST TIME", 8, ui.HEIGHT, color=ui.GRAY, anchor="BL"))
                objs.extend(ui.text_lines("HOLD R: START", ui.WIDTH - 8, ui.HEIGHT, color=ui.GRAY, anchor="BR"))

        return objs

    def on_exit(self):
        if not self.pinned:
            psys.clear_ghost()
        self._dirty = True


def create():
    return ChronosApp()
