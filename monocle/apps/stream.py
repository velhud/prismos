# apps/stream.py
# Stream application - Host-curated Event Stream (Attention Firewall)
#
# Rules:
# - Strictly use ui.text_lines / ui.text_line which guarantees justification=display.MIDDLE_CENTER.
# - Fully implement all BaseApp lifecycle events.
# - Clean up and prevent memory leaks.

from prism.app import BaseApp
from prism import ids, ui, sys as psys, schema

APP_ID = ids.APP_STREAM
APP_LABEL = ids.LABEL_STREAM

_PRIO_COLOR = {
    "INFO": ui.GRAY,
    "IMPORTANT": ui.YELLOW,
    "CRITICAL": ui.RED,
}

_SRC_MAX = 6


class StreamApp(BaseApp):
    def __init__(self):
        self.count = 0
        self.index = 0
        self.privacy = False

        self.card_id = ""
        self.source = ""
        self.title = ""
        self.body = ""
        self.prio = "INFO"
        self.handoff = None

        self._dirty = True

    def on_start(self):
        self.count = 0
        self.index = 0
        self.privacy = False
        self.card_id = ""
        self.source = ""
        self.title = ""
        self.body = ""
        self.prio = "INFO"
        self.handoff = None
        self._dirty = True
        
        try:
            psys.toast("STREAM", ttl_ms=600)
        except Exception:
            pass
        return True

    def on_update(self, now_ms):
        return False

    def on_input(self, event_name):
        if event_name == "TAP_L":
            try:
                psys.toast("OLDER CARD", ttl_ms=400)
            except Exception:
                pass
            return False  # Let host receive tap to traverse older cards

        if event_name == "TAP_R":
            try:
                psys.toast("DISMISSING", ttl_ms=400)
            except Exception:
                pass
            return False  # Let host receive tap to dismiss

        if event_name == "LONG_R":
            if self.handoff and self.handoff.get("kind") != "NONE":
                try:
                    psys.toast("HANDING OFF", ttl_ms=600)
                except Exception:
                    pass
            return False  # Let host process handoff action

        if event_name == "DOUBLE_L":
            self.privacy = not self.privacy
            try:
                psys.toast("PRIVACY ON" if self.privacy else "PRIVACY OFF", ttl_ms=600)
            except Exception:
                pass
            self._dirty = True
            return True

        return False

    def on_data(self, payload):
        if not isinstance(payload, dict):
            return False

        try:
            self.count = int(payload.get("count", 0))
        except Exception:
            self.count = 0
        try:
            self.index = int(payload.get("index", 0))
        except Exception:
            self.index = 0

        self.privacy = bool(payload.get("privacy", self.privacy))

        card = payload.get("card")
        if isinstance(card, dict):
            self.card_id = schema.clamp_str(card.get("id", ""), 48)
            self.source = schema.clamp_str(card.get("source", ""), _SRC_MAX)
            self.title = schema.clamp_str(card.get("title", ""), 24)
            self.body = schema.clamp_str(card.get("body", ""), 32)
            pr = card.get("prio", "INFO")
            pr = str(pr) if pr is not None else "INFO"
            if pr not in ("INFO", "IMPORTANT", "CRITICAL"):
                pr = "INFO"
            self.prio = pr
            self.handoff = card.get("handoff")
        else:
            self.card_id = ""
            self.source = ""
            self.title = ""
            self.body = ""
            self.prio = "INFO"
            self.handoff = None

        self._dirty = True
        return True

    def render(self):
        objs = []

        if self.count <= 0 or (not self.title and not self.body):
            objs.extend(ui.text_lines("NO EVENTS", 320, 200, color=ui.WHITE, anchor="MC"))
            objs.extend(ui.text_lines("TAP L: REFRESH", 320, 260, color=ui.GRAY, anchor="MC"))
            return objs

        # 1) Top-Left: Source Badge
        if self.source:
            objs.extend(ui.text_lines(self.source, 48, 64, color=ui.GRAY, anchor="TL"))

        # 2) Top-Right: Card Index Status ('1 of 3')
        idx_status = str(self.index + 1) + " of " + str(self.count)
        objs.extend(ui.text_lines(idx_status, ui.WIDTH - 48, 64, color=ui.GRAY, anchor="TR"))

        # 3) Top-Center: Priority emblem
        col = _PRIO_COLOR.get(self.prio, ui.GRAY)
        if self.prio == "CRITICAL":
            objs.extend(ui.text_lines("[!CRIT]", 320, 64, color=ui.RED, anchor="TC"))
        elif self.prio == "IMPORTANT":
            objs.extend(ui.text_lines("[!IMPORTANT]", 320, 64, color=ui.YELLOW, anchor="TC"))

        # 4) Card body (2-line layout)
        if self.privacy:
            # Privacy mask obfuscation
            objs.extend(ui.text_lines("••••••••", 320, 140, color=ui.GRAY, anchor="MC"))
            objs.extend(ui.text_lines("••••••••••••", 320, 220, color=ui.GRAY, anchor="MC"))
        else:
            objs.extend(ui.text_lines(self.title, 320, 140, color=col, anchor="MC"))
            objs.extend(ui.text_lines(self.body, 320, 220, color=ui.WHITE, anchor="MC"))

        # Handoff indicator
        if self.handoff and self.handoff.get("kind") != "NONE":
            objs.extend(ui.text_lines("R HOLD: OPEN LINK", 320, 310, color=ui.CYAN, anchor="MC"))

        # Operational Hints
        objs.extend(ui.text_lines("L: NEXT", 8, ui.HEIGHT, color=ui.GRAY, anchor="BL"))
        objs.extend(ui.text_lines("R: DISMISS", ui.WIDTH - 8, ui.HEIGHT, color=ui.GRAY, anchor="BR"))
        
        return objs

    def on_exit(self):
        self._dirty = True


def create():
    return StreamApp()
