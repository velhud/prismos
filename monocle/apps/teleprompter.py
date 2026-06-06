# apps/teleprompter.py
# Teleprompter application - The Presentation Interface
#
# Rules:
# - Strictly use ui.text_lines / ui.text_line which guarantees justification=display.MIDDLE_CENTER.
# - Fully implement all BaseApp lifecycle events.
# - Clean up and prevent memory leaks.

from prism.app import BaseApp
from prism import ids, ui, sys as psys, schema

import time

APP_ID = ids.APP_TELEPROMPTER
APP_LABEL = ids.LABEL_TELEPROMPTER


class TeleprompterApp(BaseApp):
    def __init__(self):
        self.prev_line = ""
        self.curr_line = ""
        self.next_line = ""
        self.wpm = 0
        self.is_playing = False
        
        # Local progress tracker
        self.progress = 0.0  # 0.0 to 1.0 representing script progress

        self._dirty = True

    def on_start(self):
        self.prev_line = ""
        self.curr_line = ""
        self.next_line = ""
        self.wpm = 0
        self.is_playing = False
        self.progress = 0.0
        self._dirty = True
        
        try:
            psys.toast("TELEPROMPTER", ttl_ms=700)
        except Exception:
            pass
        return True

    def on_update(self, now_ms):
        # The teleprompter updates are entirely host-driven.
        # Returning False since no local CPU animations are needed.
        return False

    def on_input(self, event_name):
        # 1) Double Left resets script to top (host handles script offset, device provides feedback)
        if event_name == "DOUBLE_L":
            try:
                psys.toast("RESET TO TOP", ttl_ms=600)
            except Exception:
                pass
            return False

        # 2) Long Right toggles play/pause or manual scroll mode
        if event_name == "LONG_R":
            try:
                psys.toast("PAUSE" if self.is_playing else "PLAY", ttl_ms=600)
            except Exception:
                pass
            return False

        # 3) Tap Left: Scroll Up (manual) or Decrease speed (auto)
        if event_name == "TAP_L":
            try:
                if self.is_playing:
                    psys.toast("-10 WPM", ttl_ms=400)
                else:
                    psys.toast("SCROLL UP", ttl_ms=400)
            except Exception:
                pass
            return False

        # 4) Tap Right: Scroll Down (manual) or Increase speed (auto)
        if event_name == "TAP_R":
            try:
                if self.is_playing:
                    psys.toast("+10 WPM", ttl_ms=400)
                else:
                    psys.toast("SCROLL DOWN", ttl_ms=400)
            except Exception:
                pass
            return False

        return False

    def on_data(self, payload):
        if not isinstance(payload, dict):
            return False

        self.prev_line = schema.clamp_str(payload.get("prev_line", ""), 80)
        self.curr_line = schema.clamp_str(payload.get("curr_line", ""), 80)
        self.next_line = schema.clamp_str(payload.get("next_line", ""), 80)

        try:
            self.wpm = int(payload.get("wpm", 0))
        except Exception:
            self.wpm = 0
            
        self.is_playing = bool(payload.get("is_playing", False))
        
        try:
            self.progress = float(payload.get("progress", 0.0))
        except Exception:
            self.progress = 0.0

        self._dirty = True
        return True

    def _render_progress_bar(self):
        """
        Renders a clean text-based progress indicator at the bottom.
        E.g. "------o--------"
        """
        bar_len = 16
        idx = int(self.progress * bar_len)
        if idx < 0:
            idx = 0
        if idx >= bar_len:
            idx = bar_len - 1
        
        left = "-" * idx
        right = "-" * (bar_len - 1 - idx)
        return "[" + left + "o" + right + "]"

    def render(self):
        objs = []

        # Previous Line (Dimmed Context above active line)
        if self.prev_line:
            objs.extend(ui.text_lines(self.prev_line, 320, 110, color=ui.GRAY, anchor="MC", max_width_px=560))
            
        # Active Line Highlighter Flanking Pointers on screen boundaries
        objs.extend(ui.text_lines(">", 24, 200, color=ui.WHITE, anchor="ML"))
        objs.extend(ui.text_lines("<", ui.WIDTH - 24, 200, color=ui.WHITE, anchor="MR"))

        # Highlighted Active Line (Pure White, Centered)
        if self.curr_line:
            objs.extend(ui.text_lines(self.curr_line, 320, 200, color=ui.WHITE, anchor="MC", max_width_px=520))
        else:
            objs.extend(ui.text_lines("...", 320, 200, color=ui.GRAY, anchor="MC"))

        # Upcoming Line (Dimmed Context below active line)
        if self.next_line:
            objs.extend(ui.text_lines(self.next_line, 320, 290, color=ui.GRAY, anchor="MC", max_width_px=560))

        # Pacer / Speed indicator
        if self.is_playing:
            mode = (str(self.wpm) + " WPM") if self.wpm > 0 else "AUTO"
        else:
            mode = "MANUAL"

        # Mode Widget at Bottom Right
        objs.extend(ui.text_lines(mode, ui.WIDTH - 8, ui.HEIGHT - 48, color=ui.GRAY, anchor="BR"))

        # Text-based Speech Progress Bar at Bottom Center
        objs.extend(ui.text_lines(self._render_progress_bar(), 320, ui.HEIGHT - 12, color=ui.GRAY, anchor="BC"))

        # Operational Hints
        objs.extend(ui.text_lines("L: PREV", 8, ui.HEIGHT, color=ui.GRAY, anchor="BL"))
        objs.extend(ui.text_lines("R: NEXT", ui.WIDTH - 8, ui.HEIGHT, color=ui.GRAY, anchor="BR"))
        
        return objs

    def on_exit(self):
        self.is_playing = False
        self._dirty = True


def create():
    return TeleprompterApp()
