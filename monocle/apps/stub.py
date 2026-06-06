# apps/stub.py
# A repository-standard placeholder app implementation.
#
# This app:
# - shows its label
# - records last input event and last received STATE keys
# - never calls display.show() directly (kernel owns display.show)

from prism.app import BaseApp
from prism import ui
from prism import sys as psys


class StubApp(BaseApp):
    def __init__(self, app_id, label):
        self.app_id = "" if app_id is None else str(app_id)
        self.label = "" if label is None else str(label)

        self.last_event = ""
        self.last_state_keys = ""

        self._dirty = True

    def on_start(self):
        self._dirty = True
        psys.toast(self.label, ttl_ms=800)
        return True

    def on_update(self, now_ms):
        # No animations by default.
        return False

    def on_input(self, event_name):
        self.last_event = "" if event_name is None else str(event_name)
        self._dirty = True
        return True

    def on_data(self, payload):
        if isinstance(payload, dict):
            # Store only keys (string) to avoid heavy rendering or deep copies.
            try:
                keys = list(payload.keys())
            except Exception:
                keys = []
            # Limit string length to keep allocations bounded.
            s = ",".join([str(k) for k in keys])
            if len(s) > 120:
                s = s[:117] + "..."
            self.last_state_keys = s
        else:
            self.last_state_keys = ""
        self._dirty = True
        return True

    def render(self):
        objs = []

        objs.extend(ui.text_lines(self.label, 320, 120, color=ui.WHITE, anchor="MC"))
        objs.extend(ui.text_lines("STUB APP", 320, 180, color=ui.GRAY, anchor="MC"))

        if self.last_event:
            objs.extend(ui.text_lines("EV:", 80, 260, color=ui.GRAY, anchor="ML"))
            objs.extend(ui.text_lines(self.last_event, 120, 260, color=ui.WHITE, anchor="ML", max_width_px=520))

        if self.last_state_keys:
            objs.extend(ui.text_lines("STATE:", 80, 320, color=ui.GRAY, anchor="ML"))
            objs.extend(ui.text_lines(self.last_state_keys, 160, 320, color=ui.WHITE, anchor="ML", max_width_px=480))

        return objs

    def on_exit(self):
        # No hardware resources held by stub.
        pass
