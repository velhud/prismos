# apps/navigate.py
# Navigate application - The Spatial Guidance Interface
#
# Rules:
# - Strictly use ui.text_lines / ui.text_line which guarantees justification=display.MIDDLE_CENTER.
# - Fully implement all BaseApp lifecycle events.
# - Clean up and prevent memory leaks.

from prism.app import BaseApp
from prism import ids, ui, sys as psys, schema

import time

APP_ID = ids.APP_NAVIGATE
APP_LABEL = ids.LABEL_NAVIGATE

# Sci-Fi / Tactical visual glyph maps
_GLYPH_MAP = {
    "ARROW_RIGHT": ">>>",
    "ARROW_LEFT": "<<<",
    "ARROW_STRAIGHT": "▲",
    "FLAG": "⚑",
    "U_TURN": "↱↲",
}


def _safe_icon(v):
    s = "" if v is None else str(v)
    if s in _GLYPH_MAP:
        return s
    return "ARROW_STRAIGHT"


def _parse_distance_m(dist_str):
    """
    Parses distances like "50m" or "0.2km" to meters.
    Defaults to 100.0 on error.
    """
    try:
        s = dist_str.strip().lower()
        if s.endswith("km"):
            return float(s[:-2]) * 1000.0
        if s.endswith("m"):
            return float(s[:-1])
        return float(s)
    except Exception:
        return 100.0


class NavigateApp(BaseApp):
    def __init__(self):
        self.icon = "ARROW_STRAIGHT"
        self.distance = ""
        self.street = ""
        self.alert = False

        self.details = True
        self.pinned = False

        self._blink_on = True
        self._next_blink = time.ticks_ms()

        self._dirty = True

    def on_start(self):
        self.icon = "ARROW_STRAIGHT"
        self.distance = ""
        self.street = ""
        self.alert = False
        self.details = True
        self.pinned = False
        self._blink_on = True
        self._next_blink = time.ticks_ms()
        self._dirty = True
        
        try:
            psys.toast("NAVIGATE", ttl_ms=600)
        except Exception:
            pass
        return True

    def on_update(self, now_ms):
        dist_m = _parse_distance_m(self.distance)

        # Proximity-based blinking logic matching the specification:
        # - Immediate (<5m): blink fast (4Hz -> 125ms cycle)
        # - Near (<20m): blink slowly (1Hz -> 500ms cycle)
        # - Far (>50m): static or 2Hz alert blink if alert=True
        if dist_m < 5.0:
            blink_ms = 125
            blinking = True
        elif dist_m < 20.0:
            blink_ms = 500
            blinking = True
        else:
            blinking = self.alert
            blink_ms = 250  # 2Hz alert blink

        if not blinking:
            if not self._blink_on:
                self._blink_on = True
                return True
            return False

        if time.ticks_diff(now_ms, self._next_blink) >= 0:
            self._next_blink = time.ticks_add(now_ms, blink_ms)
            self._blink_on = not self._blink_on
            return True

        return False

    def _ghost_text(self):
        glyph = _GLYPH_MAP.get(self.icon, "▲")
        d = self.distance or ""
        return glyph + " " + d if d else glyph

    def on_input(self, event_name):
        if event_name == "TAP_L":
            self.details = not self.details
            try:
                psys.toast("DETAILS" if self.details else "SIMPLE", ttl_ms=600)
            except Exception:
                pass
            self._dirty = True
            return True

        if event_name == "TAP_R":
            try:
                psys.toast("NEXT STEP", ttl_ms=400)
            except Exception:
                pass
            return False  # Let host advance script preview

        if event_name == "LONG_R":
            self.pinned = not self.pinned
            if self.pinned:
                # Minimizes active nav to top-right corner
                psys.set_ghost(True, text=self._ghost_text(), flash=self.alert, icon="NAV")
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

        if event_name == "DOUBLE_L":
            try:
                psys.toast("STOP NAV", ttl_ms=600)
            except Exception:
                pass
            psys.request_exit()
            return True

        return False

    def on_data(self, payload):
        if not isinstance(payload, dict):
            return False

        self.icon = _safe_icon(payload.get("icon"))
        self.distance = schema.clamp_str(payload.get("distance", ""), 16)
        self.street = schema.clamp_str(payload.get("street", ""), 32)
        self.alert = bool(payload.get("alert", False))

        if self.pinned:
            psys.set_ghost(True, text=self._ghost_text(), flash=self.alert, icon="NAV")

        self._dirty = True
        return True

    def render(self):
        objs = []

        # 1) Tactical compass tape right under the HUD separator
        objs.extend(ui.text_lines("[ W .. NW .. N .. NE .. E ]", 320, 56, color=ui.GRAY, anchor="TC"))
        objs.extend(ui.text_lines("▲", 320, 92, color=ui.CYAN, anchor="TC"))

        glyph = _GLYPH_MAP.get(self.icon, "▲")
        show_glyph = (not self.alert) or self._blink_on

        # Massive centered directional glyph
        if show_glyph:
            objs.extend(ui.text_lines(glyph, 320, 154, color=ui.WHITE, anchor="MC"))

        # Distance Meter
        if self.distance:
            objs.extend(ui.text_lines(self.distance, 320, 210, color=ui.WHITE, anchor="MC"))

        # Street Label
        if self.details and self.street:
            objs.extend(ui.text_lines("ON: " + self.street.upper(), 320, 290, color=ui.YELLOW, anchor="MC"))

        # Bottom corner hints
        objs.extend(ui.text_lines("L: VIEW", 8, ui.HEIGHT, color=ui.GRAY, anchor="BL"))
        objs.extend(ui.text_lines("R: NEXT", ui.WIDTH - 8, ui.HEIGHT, color=ui.GRAY, anchor="BR"))
        return objs

    def on_exit(self):
        if not self.pinned:
            psys.clear_ghost()
        self._dirty = True


def create():
    return NavigateApp()
