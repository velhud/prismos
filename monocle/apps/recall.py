# apps/recall.py
# Recall application - The External Memory Interface
#
# Rules:
# - Strictly use ui.text_lines / ui.text_line which guarantees justification=display.MIDDLE_CENTER.
# - Fully implement all BaseApp lifecycle events.
# - Clean up and prevent memory leaks.

from prism.app import BaseApp
from prism import ids, ui, sys as psys, schema, store

APP_ID = ids.APP_RECALL
APP_LABEL = ids.LABEL_RECALL

_MAX_LINES_RENDER = 5
_MAX_LINE_CHARS = 32


def _clamp_i(v, default=0):
    try:
        return int(v)
    except Exception:
        return int(default)


class RecallApp(BaseApp):
    def __init__(self):
        self.view = "DECKS"  # DECKS | CARD
        self.deck_title = ""
        self.deck_index = 0
        self.deck_count = 0
        self.card_index = 0
        self.card_count = 0
        self.mode = "NOTE"   # NOTE | CHECKLIST
        self.cursor = 0
        self.lines = []
        self.pinned = False

        self._dirty = True

    def on_start(self):
        self.view = "DECKS"
        self.deck_title = ""
        self.deck_index = 0
        self.deck_count = 0
        self.card_index = 0
        self.card_count = 0
        self.mode = "NOTE"
        self.cursor = 0
        self.lines = []
        self.pinned = False
        self._dirty = True
        try:
            psys.toast("RECALL", ttl_ms=600)
        except Exception:
            pass
        return True

    def on_update(self, now_ms):
        # Recall is purely static rendering on change; return the dirty flag status.
        if self._dirty:
            self._dirty = False
            return True
        return False

    def on_input(self, event_name):
        # Return False to let these inputs propagate to the Host so the system stays synchronized.
        
        if self.view == "DECKS":
            if event_name == "TAP_L":
                try:
                    psys.toast("PREV DECK", ttl_ms=400)
                except Exception:
                    pass
                return False
            elif event_name == "TAP_R":
                try:
                    psys.toast("NEXT DECK", ttl_ms=400)
                except Exception:
                    pass
                return False
            elif event_name == "LONG_R":
                try:
                    psys.toast("OPENING", ttl_ms=500)
                except Exception:
                    pass
                return False
            elif event_name == "DOUBLE_L":
                try:
                    psys.toast("RECALL", ttl_ms=400)
                except Exception:
                    pass
                return False

        # CARD View
        if self.mode == "CHECKLIST":
            if event_name == "TAP_L":
                # Scroll selection up locally for immediate feedback
                if self.cursor > 0:
                    self.cursor -= 1
                    self._dirty = True
                try:
                    psys.toast("UP", ttl_ms=300)
                except Exception:
                    pass
                return False

            elif event_name == "TAP_R":
                # Scroll selection down locally for immediate feedback
                if self.cursor < len(self.lines) - 1:
                    self.cursor += 1
                    self._dirty = True
                try:
                    psys.toast("DOWN", ttl_ms=300)
                except Exception:
                    pass
                return False

            elif event_name == "LONG_R":
                # Toggle checklist checkbox locally for instant feel
                if 0 <= self.cursor < len(self.lines):
                    ln = self.lines[self.cursor]
                    if ln.startswith("[ ]"):
                        self.lines[self.cursor] = "[x]" + ln[3:]
                    elif ln.startswith("[x]"):
                        self.lines[self.cursor] = "[ ]" + ln[3:]
                    self._dirty = True
                    self._save_checklist_state()
                try:
                    psys.toast("TOGGLE", ttl_ms=400)
                except Exception:
                    pass
                return False

            elif event_name == "DOUBLE_L":
                try:
                    psys.toast("TO DECKS", ttl_ms=400)
                except Exception:
                    pass
                return False

        else:
            # NOTE Mode
            if event_name == "TAP_L":
                try:
                    psys.toast("PREV CARD", ttl_ms=400)
                except Exception:
                    pass
                return False
            elif event_name == "TAP_R":
                try:
                    psys.toast("NEXT CARD", ttl_ms=400)
                except Exception:
                    pass
                return False
            elif event_name == "LONG_R":
                # Pin/Unpin Ghost Mode
                if self.pinned:
                    psys.clear_ghost()
                    self.pinned = False
                    try:
                        psys.toast("UNPINNED", ttl_ms=600)
                    except Exception:
                        pass
                else:
                    text = f"{self.deck_title} {self.card_index + 1}/{self.card_count}"
                    psys.set_ghost(True, text=schema.clamp_str(text, 48), icon="RCL")
                    self.pinned = True
                    try:
                        psys.toast("PINNED", ttl_ms=600)
                    except Exception:
                        pass
                self._dirty = True
                return False
            elif event_name == "DOUBLE_L":
                try:
                    psys.toast("TO DECKS", ttl_ms=400)
                except Exception:
                    pass
                return False

        return False

    def on_data(self, payload):
        if not isinstance(payload, dict):
            return False

        v = payload.get("view")
        if isinstance(v, str) and v in ("DECKS", "CARD"):
            self.view = v

        self.deck_title = schema.clamp_str(payload.get("deck_title", ""), 24)
        self.deck_index = _clamp_i(payload.get("deck_index", 0), 0)
        self.deck_count = _clamp_i(payload.get("deck_count", 0), 0)
        self.card_index = _clamp_i(payload.get("card_index", 0), 0)
        self.card_count = _clamp_i(payload.get("card_count", 0), 0)

        m = payload.get("mode")
        if isinstance(m, str) and m in ("NOTE", "CHECKLIST"):
            self.mode = m

        self.cursor = _clamp_i(payload.get("cursor", 0), 0)

        ls = payload.get("lines")
        if isinstance(ls, list):
            out = []
            for x in ls:
                out.append(schema.clamp_str(x, _MAX_LINE_CHARS))
            self.lines = out
            if self.mode == "CHECKLIST":
                self._load_checklist_state()
        else:
            self.lines = []

        self._dirty = True
        return True

    def render(self):
        objs = []

        # Standard physical index-card style header
        objs.extend(ui.text_lines("— RECALL —", 320, 42, color=ui.GRAY, anchor="TC"))

        if self.view == "DECKS":
            # Gorgeous Deck Carousel View
            deck_name = self.deck_title if self.deck_title else "NO DECKS"
            objs.extend(ui.text_lines(deck_name, 320, 160, color=ui.WHITE, anchor="MC"))
            
            idx_str = f"DECK {self.deck_index + 1} OF {self.deck_count}" if self.deck_count > 0 else "0 OF 0"
            objs.extend(ui.text_lines(idx_str, 320, 220, color=ui.YELLOW, anchor="MC"))
            
            objs.extend(ui.text_lines("L/R: CHOOSE   HOLD R: OPEN", 320, 320, color=ui.GRAY, anchor="MC"))
            return objs

        # CARD View
        # Sub-header detailing deck context
        meta_title = f"[ {self.deck_title.upper()} ]"
        objs.extend(ui.text_lines(meta_title, 320, 80, color=ui.YELLOW, anchor="TC"))

        card_meta = ""
        if self.card_count > 0:
            card_meta = f"CARD {self.card_index + 1} OF {self.card_count} • {self.mode}"
        else:
            card_meta = self.mode
        objs.extend(ui.text_lines(card_meta, 320, 120, color=ui.GRAY, anchor="MC"))

        # Empty checklist completeness handler
        all_checked = (self.mode == "CHECKLIST" and len(self.lines) > 0 and all(ln.startswith("[x]") for ln in self.lines))
        if all_checked:
            objs.extend(ui.text_lines("✔ COMPLETE", 320, 210, color=ui.GREEN, anchor="MC"))
            objs.extend(ui.text_lines("ALL ITEMS DONE!", 320, 260, color=ui.GRAY, anchor="MC"))
            objs.extend(ui.text_lines("DOUBLE L: DECKS", 320, 320, color=ui.GRAY, anchor="MC"))
            return objs

        # Content lines
        y = 170
        shown = 0
        for i, ln in enumerate(self.lines):
            if shown >= _MAX_LINES_RENDER:
                break
            
            if self.mode == "CHECKLIST":
                is_selected = (i == self.cursor)
                is_checked = ln.startswith("[x]")
                
                # Active checklist cursor uses solid white block character
                prefix = "█ " if is_selected else "  "
                
                # Ensure the line starts with a checkbox indicator
                line_content = ln
                if not (line_content.startswith("[ ]") or line_content.startswith("[x]")):
                    line_content = "[ ] " + line_content
                
                full_text = prefix + line_content
                color = ui.WHITE if is_selected else (ui.GRAY_DARK if is_checked else ui.GRAY)
                objs.extend(ui.text_lines(full_text, 40, y, color=color, anchor="TL", max_width_px=560))
            else:
                # Note mode
                objs.extend(ui.text_lines(ln, 40, y, color=ui.WHITE, anchor="TL", max_width_px=560))
                
            y += ui.FONT_H
            shown += 1

        # Interactive controls footer hints
        if self.mode == "CHECKLIST":
            objs.extend(ui.text_lines("L/R: SCROLL • HOLD R: TOGGLE • DOUBLE L: BACK", 320, 360, color=ui.GRAY, anchor="MC"))
        else:
            objs.extend(ui.text_lines("L/R: CARDS • HOLD R: PIN GHOST • DOUBLE L: BACK", 320, 360, color=ui.GRAY, anchor="MC"))

        return objs

    def _save_checklist_state(self):
        if not self.deck_title:
            return
        try:
            data = store.load_json("pm_recall_checked.json", default={})
            if not isinstance(data, dict):
                data = {}
            data[self.deck_title] = self.lines
            store.save_json("pm_recall_checked.json", data)
        except Exception:
            pass

    def _load_checklist_state(self):
        if not self.deck_title:
            return
        try:
            data = store.load_json("pm_recall_checked.json", default={})
            if isinstance(data, dict) and self.deck_title in data:
                saved_lines = data[self.deck_title]
                if isinstance(saved_lines, list) and len(saved_lines) == len(self.lines):
                    match = True
                    for i in range(len(self.lines)):
                        s_item = saved_lines[i]
                        c_item = self.lines[i]
                        s_raw = s_item[3:] if (s_item.startswith("[ ]") or s_item.startswith("[x]")) else s_item
                        c_raw = c_item[3:] if (c_item.startswith("[ ]") or c_item.startswith("[x]")) else c_item
                        if s_raw != c_raw:
                            match = False
                            break
                    if match:
                        self.lines = saved_lines
        except Exception:
            pass

    def on_exit(self):
        self._dirty = True


def create():
    return RecallApp()
