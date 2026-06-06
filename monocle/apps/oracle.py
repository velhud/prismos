# apps/oracle.py
# Oracle application - Voice Fact Synthesizer Interface
#
# Rules:
# - Strictly use ui.text_lines / ui.text_line which guarantees justification=display.MIDDLE_CENTER.
# - Fully implement all BaseApp lifecycle events.
# - Clean up and prevent memory leaks.

from prism.app import BaseApp
from prism import ids, ui, sys as psys, schema

import time

APP_ID = ids.APP_ORACLE
APP_LABEL = ids.LABEL_ORACLE

_MODE_LISTENING = "LISTENING"
_MODE_THINKING = "THINKING"
_MODE_ANSWER = "ANSWER"

_SPIN = ("|", "/", "-", "\\")
_MAX_TEXT = 240


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


def _wave_bar(level):
    """
    Generates a high-fidelity visualizer bar representation of audio input.
    E.g. "---|||||---"
    """
    max_height = 8
    n = int(_clamp_f01(level) * max_height)
    if n < 1:
        n = 1
    bars = "|" * (2 * n)
    dashes = "-" * (max_height - n)
    return dashes + bars + dashes


class OracleApp(BaseApp):
    def __init__(self):
        self.mode = _MODE_LISTENING
        self.audio_level = 0.0
        self.text = ""
        self.is_final = False

        # Local KEEP status preventing auto-dim and auto-exit
        self.keep = False

        # Local animation timing
        self._spin_i = 0
        self._next_anim = time.ticks_ms()

        # Passive timeout state
        self._last_activity_ms = time.ticks_ms()

        self._dirty = True

    def on_start(self):
        self.mode = _MODE_LISTENING
        self.audio_level = 0.0
        self.text = ""
        self.is_final = False
        self.keep = False
        self._last_activity_ms = time.ticks_ms()
        self._dirty = True

        try:
            psys.toast("ORACLE", ttl_ms=600)
        except Exception:
            pass
        return True

    def on_update(self, now_ms):
        # 1) Thinking animation
        if self.mode == _MODE_THINKING:
            if time.ticks_diff(now_ms, self._next_anim) >= 0:
                self._next_anim = time.ticks_add(now_ms, 200)
                self._spin_i = (self._spin_i + 1) % len(_SPIN)
                self._dirty = True
                return True

        # 2) Passive timeout (20s) in Answer mode if not pinned (keep=False)
        if self.mode == _MODE_ANSWER and not self.keep:
            if time.ticks_diff(now_ms, self._last_activity_ms) >= 20000:
                # Passive exit back to Orbit
                psys.request_exit()
                return True

        return False

    def on_input(self, event_name):
        self._last_activity_ms = time.ticks_ms()

        # Single Tap Left dismisses
        if event_name == "TAP_L":
            psys.request_exit()
            return True

        if event_name == "TAP_R":
            if self.mode == _MODE_LISTENING:
                try:
                    psys.toast("END", ttl_ms=400)
                except Exception:
                    pass
                return False

            if self.mode == _MODE_ANSWER:
                self.keep = not self.keep
                try:
                    psys.toast("KEEP" if self.keep else "UNKEEP", ttl_ms=500)
                except Exception:
                    pass
                self._dirty = True
                return True

        if event_name == "LONG_R":
            if self.mode == _MODE_ANSWER:
                try:
                    psys.toast("FOLLOW-UP", ttl_ms=600)
                except Exception:
                    pass
                return False

        if event_name == "DOUBLE_L":
            if self.mode == _MODE_ANSWER:
                try:
                    psys.toast("COPIED", ttl_ms=600)
                except Exception:
                    pass
                return False

        return False

    def on_data(self, payload):
        if not isinstance(payload, dict):
            return False

        self._last_activity_ms = time.ticks_ms()

        mode = payload.get("mode")
        if isinstance(mode, str) and mode in (_MODE_LISTENING, _MODE_THINKING, _MODE_ANSWER):
            self.mode = mode

        self.audio_level = _clamp_f01(payload.get("audio_level", self.audio_level))

        t = payload.get("text")
        if t is None:
            t = ""
        self.text = schema.clamp_str(t, _MAX_TEXT)

        self.is_final = bool(payload.get("is_final", False))

        self._dirty = True
        return True

    def render(self):
        objs = []

        if self.mode == _MODE_LISTENING:
            objs.extend(ui.text_lines("LISTENING", 320, 72, color=ui.WHITE, anchor="TC"))
            objs.extend(ui.text_lines(_wave_bar(self.audio_level), 320, 150, color=ui.WHITE, anchor="MC"))
            if self.text:
                objs.extend(ui.text_lines(self.text, 320, 230, color=ui.GRAY, anchor="MC", max_width_px=540))
            objs.extend(ui.text_lines("TAP L: EXIT", 8, ui.HEIGHT, color=ui.GRAY, anchor="BL"))
            objs.extend(ui.text_lines("TAP R: END", ui.WIDTH - 8, ui.HEIGHT, color=ui.GRAY, anchor="BR"))
            return objs

        if self.mode == _MODE_THINKING:
            spin = _SPIN[self._spin_i]
            blink = (time.ticks_ms() // 500) % 2 == 0
            label_color = ui.GRAY if blink else ui.GRAY_DARK
            objs.extend(ui.text_lines("SYNTHESIZING...", 320, 120, color=label_color, anchor="TC"))
            objs.extend(ui.text_lines("[" + spin + "]", 320, 200, color=ui.WHITE, anchor="MC"))
            objs.extend(ui.text_lines("TAP L: EXIT", 8, ui.HEIGHT, color=ui.GRAY, anchor="BL"))
            return objs

        # ANSWER State
        # Expanding tactile reticle brackets at the far edges
        objs.extend(ui.text_lines("[", 16, 176, color=ui.GRAY_DARK, anchor="ML"))
        objs.extend(ui.text_lines("]", ui.WIDTH - 16, 176, color=ui.GRAY_DARK, anchor="MR"))

        if self.text:
            # High-fidelity multiline text container
            objs.extend(ui.text_lines(self.text, 48, 80, color=ui.WHITE, anchor="TL", max_width_px=544))
        else:
            objs.extend(ui.text_lines("...", 320, 200, color=ui.GRAY, anchor="MC"))

        # Technical/Tactical bottom corner hints matching the specification
        objs.extend(ui.text_lines("L: CLEAR", 8, ui.HEIGHT, color=ui.GRAY, anchor="BL"))
        objs.extend(ui.text_lines("R: " + ("KEEP" if not self.keep else "UNKEEP"), ui.WIDTH - 8, ui.HEIGHT, color=ui.GRAY, anchor="BR"))

        return objs

    def on_exit(self):
        self.keep = False
        self._dirty = True


def create():
    return OracleApp()
