"""Host-owned PrismOS app engines.

Monocle stays a peripheral. These app engines keep state, timing, ranking,
pagination, and controls on the host, then emit bounded DRAW primitives.
"""

import time

from prism_display import (
    CYAN,
    DIM,
    GRAY,
    GREEN,
    RED,
    TEXT_ITEM_LIMIT,
    WHITE,
    YELLOW,
    bitmap_items,
    l_item,
    screen_items,
    wrap_text,
)
from prism_services import HostServices, clean_for_screen


def clamp(value, lo, hi):
    return max(lo, min(hi, value))


def progress_bar(pct, width=12):
    pct = clamp(int(pct), 0, 100)
    filled = int(round((pct / 100.0) * width))
    return "[" + ("#" * filled).ljust(width, "-") + "]"


def progress_label(pct):
    return "%d%%" % clamp(int(pct), 0, 100)


def audio_meter(level, width=5):
    level = clamp(int(level), 0, 10)
    filled = clamp(int(round((level / 10.0) * width)), 1, width)
    return "|" * filled


def page_lines(lines, page, per_page=5):
    if not lines:
        return [], 0, 1
    total = max(1, (len(lines) + per_page - 1) // per_page)
    page = clamp(int(page), 0, total - 1)
    start = page * per_page
    return lines[start:start + per_page], page, total


class HostApp:
    app_id = ""
    label = "APP"
    accent = WHITE

    def __init__(self, services=None):
        self.services = services or HostServices()
        self._actions = []

    def emit_action(self, kind, **data):
        self._actions.append({"kind": kind, "app": self.app_id, "data": data})

    def consume_actions(self):
        actions = list(getattr(self, "_actions", []))
        self._actions = []
        return actions

    def next_request_id(self):
        current = int(getattr(self, "request_id", 0)) + 1
        self.request_id = current
        return current

    def on_enter(self):
        pass

    def on_button(self, side, gesture, duration_ms=0):
        return False

    def on_tick(self, now):
        return False

    def widget(self):
        return ""

    def render(self, shapes=False):
        return screen_items(self.label, ["READY"], "LONG L EXIT", accent=self.accent)


class OracleApp(HostApp):
    app_id = "oracle"
    label = "ORACLE"
    accent = CYAN

    def __init__(self, services=None):
        super().__init__(services)
        self.mode = "READY"
        self.pin = False
        self.page = 0
        self.spin = 0
        self.last = time.time()
        self.query = ""
        self.source = ""
        self.answer = ""
        self.error = ""
        self.context = ""
        self.request_id = 0
        self.audio = 0
        self.listen_started = 0.0
        self.capture_timeout = 12.0

    def on_enter(self):
        self.mode = "READY"
        self.page = 0
        self.error = ""
        self.last = time.time()

    def on_tick(self, now):
        if self.mode not in ("LISTEN", "ASKING"):
            return False
        if now - self.last < 0.25:
            return False
        self.last = now
        self.spin = (self.spin + 1) % 4
        self.audio = (self.audio + 1) % 10
        if self.mode == "LISTEN" and self.listen_started and now - self.listen_started > self.capture_timeout:
            self.next_request_id()
            self.audio_failed("NO AUDIO")
        return True

    def on_button(self, side, gesture, duration_ms=0):
        if gesture == "TAP" and side == "L":
            if self.mode == "ANSWER" and self.page > 0:
                self.page -= 1
            elif self.mode in ("LISTEN", "ASKING"):
                self.next_request_id()
                self.mode = "READY"
                self.error = "CANCELLED"
            else:
                self.mode = "READY"
                self.page = 0
                self.error = ""
            return True
        if gesture == "TAP" and side == "R":
            if self.mode == "ANSWER":
                wrapped = wrap_text(self.answer, max_lines=40)
                _, self.page, total = page_lines(wrapped, self.page, per_page=5)
                if self.page < total - 1:
                    self.page += 1
                else:
                    self.pin = not self.pin
            elif self.mode in ("LISTEN", "ASKING"):
                return True
            else:
                self.start_voice_query()
            return True
        if gesture == "LONG" and side == "R":
            if self.mode == "ANSWER" and self.answer:
                self.context = self.answer[:900]
                self.query = "Give me the next useful follow-up or caution."
                self.source = "FOLLOW"
                self._begin_provider_query()
            else:
                self.query, self.source = self.services.data.oracle_prompt()
                self.context = "Outside conversation quick-assist mode."
                self._begin_provider_query()
            return True
        if gesture == "DOUBLE" and side == "L":
            if self.answer and self.services.data.write_clipboard(self.answer):
                self.error = "COPIED"
            elif self.answer:
                self.error = "COPY FAILED"
            return True
        return False

    def start_query(self):
        self.query, self.source = self.services.data.oracle_prompt()
        self.context = ""
        self._begin_provider_query()

    def start_voice_query(self):
        self.mode = "LISTEN"
        self.query = "Voice query"
        self.source = "AUDIO"
        self.answer = ""
        self.error = ""
        self.page = 0
        self.spin = 0
        self.audio = 0
        self.last = time.time()
        self.listen_started = self.last
        req_id = self.next_request_id()
        self.emit_action("oracle_audio_capture", request_id=req_id, seconds=4.0, sample_rate=8000, bit_depth=8)

    def _begin_provider_query(self):
        self.query = clean_for_screen(self.query, limit=1800)
        self.mode = "ASKING"
        self.answer = ""
        self.error = ""
        self.page = 0
        self.spin = 0
        self.last = time.time()
        req_id = self.next_request_id()
        self.emit_action("oracle_query", request_id=req_id, prompt=self.query, context=self.context, source=self.source)

    def audio_started(self):
        if self.mode == "LISTEN":
            self.error = "MIC ON"
            return True
        return False

    def audio_failed(self, error):
        self.mode = "READY"
        self.error = clean_for_screen(error, limit=160)
        self.listen_started = 0.0
        return True

    def audio_received(self, audio_bytes, sample_rate=8000):
        if self.mode != "LISTEN":
            return False
        self.mode = "ASKING"
        self.error = ""
        self.listen_started = 0.0
        self.emit_action(
            "oracle_audio",
            request_id=self.request_id,
            audio=audio_bytes,
            sample_rate=sample_rate,
            context=self.context,
        )
        return True

    def complete_answer(self, answer, error="", request_id=None):
        if request_id is not None and int(request_id) != int(self.request_id):
            return False
        self.answer = clean_for_screen(answer, limit=2400)
        self.error = clean_for_screen(error, limit=160)
        self.mode = "ANSWER" if self.answer else "READY"
        self.page = 0
        return True

    def widget(self):
        if self.mode == "LISTEN":
            return "MIC ..."
        if self.mode == "ASKING":
            return "AI ..."
        if self.mode == "ANSWER":
            return "AI ANS"
        return "AI " + self.services.status()

    def render(self, shapes=False):
        if self.mode == "READY":
            lines = ["ASK READY", self.services.status(), "R VOICE", "HOLD R PROMPT"]
            if self.error:
                lines.append(self.error)
            right = "HOST"
            footer = "R VOICE"
        elif self.mode == "LISTEN":
            lines = ["LISTENING", "SPEAK NOW", "MIC " + audio_meter(self.audio)]
            if self.error:
                lines.append(self.error)
            right = "MIC"
            footer = "L CANCEL"
        elif self.mode == "ASKING":
            marks = ["|", "/", "-", "\\"][self.spin]
            lines = ["THINKING " + marks, self.source or "HOST"]
            lines.extend(wrap_text(self.query, max_lines=3))
            right = "WAIT"
            footer = "L CANCEL"
        else:
            wrapped = wrap_text(self.answer, max_lines=40)
            visible, self.page, total = page_lines(wrapped, self.page, per_page=4)
            lines = ["KEPT" if self.pin else "ANSWER"] + visible
            if self.error and len(lines) < 5:
                lines.append(self.error)
            right = "%d/%d" % (self.page + 1, total)
            footer = "L BACK   R NEXT" if self.page < total - 1 else "R KEEP  HOLD R TIP"
        return screen_items("ORACLE", lines, footer, right=right, accent=self.accent, dense=True)


class VisionApp(HostApp):
    app_id = "vision"
    label = "VISION"
    accent = GREEN

    def __init__(self, services=None):
        super().__init__(services)
        self.mode = "IDENTIFY"
        self.state = "READY"
        self.progress = 0
        self.scan_phase = 0
        self.saved = 0
        self.result = ""
        self.last = time.time()
        self.error = ""
        self.capture_path = ""
        self.request_id = 0
        self.wait_started = 0.0
        self.capture_timeout = 18.0

    def on_enter(self):
        self.state = "READY"
        self.progress = 0
        self.error = ""

    def on_tick(self, now):
        if self.state not in ("CAPTURE", "UPLOAD", "ANALYZE", "WAIT_IMAGE"):
            return False
        if self.state == "WAIT_IMAGE" and self.wait_started and now - self.wait_started > self.capture_timeout:
            self.next_request_id()
            self.capture_failed("NO IMAGE")
            return True
        if now - self.last < 0.35:
            return False
        self.last = now
        self.scan_phase = (self.scan_phase + 1) % 4
        if self.state == "WAIT_IMAGE":
            self.progress = min(42, self.progress + 5)
        elif self.state == "ANALYZE":
            self.progress = min(95, self.progress + 9)
        else:
            self.progress = min(64, self.progress + 12)
        if self.progress >= 64 and self.state in ("CAPTURE", "UPLOAD"):
            self.state = "ANALYZE"
        elif self.progress >= 28 and self.state == "CAPTURE":
            self.state = "UPLOAD"
        return True

    def on_button(self, side, gesture, duration_ms=0):
        if gesture == "TAP" and side == "L":
            if self.state == "RESULT":
                self.state = "READY"
                self.progress = 0
            elif self.state in ("WAIT_IMAGE", "CAPTURE", "UPLOAD", "ANALYZE"):
                self.next_request_id()
                self.state = "READY"
                self.progress = 0
                self.error = "ABORTED"
            else:
                self.mode = "OCR" if self.mode == "IDENTIFY" else "IDENTIFY"
            return True
        if gesture == "TAP" and side == "R":
            if self.state == "READY":
                self.state = "WAIT_IMAGE"
                self.progress = 5
                self.error = ""
                self.result = ""
                self.capture_path = ""
                self.wait_started = time.time()
                req_id = self.next_request_id()
                self.emit_action("vision_capture", request_id=req_id)
            elif self.state == "RESULT":
                self.emit_action("oracle_from_vision", prompt=self.result)
                self.error = "SENT TO ORACLE"
            return True
        if gesture == "LONG" and side == "R":
            if self.state == "RESULT" and self.result:
                self.saved += 1
                self.error = "SAVING NOTE"
                self.emit_action(
                    "vision_save_note",
                    result=self.result,
                    capture_path=self.capture_path,
                    mode=self.mode,
                    note_id=self.saved,
                )
            return True
        if gesture == "DOUBLE" and side == "L" and self.mode == "OCR":
            if self.result and self.services.data.write_clipboard(self.result):
                self.error = "OCR COPIED"
            elif self.result:
                self.error = "COPY FAILED"
            return True
        return False

    def image_received(self, image_bytes, msg_id=None, capture_path=None):
        if self.state not in ("WAIT_IMAGE", "CAPTURE", "UPLOAD", "ANALYZE"):
            return False
        self.progress = 72
        self.state = "ANALYZE"
        self.error = ""
        if capture_path:
            self.capture_path = capture_path
        else:
            try:
                self.capture_path = self.services.data.save_capture(image_bytes, msg_id=msg_id, ext=".jpg")
            except Exception:
                self.capture_path = ""
        prompt = "Identify what matters in the image."
        if self.mode == "OCR":
            prompt = "Extract the readable text. Then summarize the useful meaning in one line."
        self.emit_action("vision_analyze", request_id=self.request_id, image=image_bytes, prompt=prompt, mime_type="image/jpeg")
        return True

    def complete_result(self, result, error="", request_id=None):
        if request_id is not None and int(request_id) != int(self.request_id):
            return False
        self.result = clean_for_screen(result, limit=1800)
        self.error = clean_for_screen(error, limit=160)
        self.state = "RESULT"
        self.progress = 100
        return True

    def capture_failed(self, error, request_id=None):
        if request_id is not None and int(request_id) != int(self.request_id):
            return False
        self.state = "READY"
        self.progress = 0
        self.error = clean_for_screen(error, limit=160)
        return True

    def note_saved(self, path="", note_id=0, error=""):
        if error:
            self.error = clean_for_screen(error, limit=160)
        else:
            label = "SAVED"
            if note_id:
                label += " %d" % int(note_id)
            self.error = label
        return True

    def widget(self):
        return self.mode[:3] + " " + self.state[:3]

    def render(self, shapes=False):
        footer = "L MODE   R CAPTURE"
        right = "READY"
        if self.state == "READY":
            lines = [self.mode, "ALIGN TARGET", "R CAPTURE"]
            if self.error:
                lines.extend(wrap_text(self.error, max_lines=2))
        elif self.state == "RESULT":
            lines = ["RESULT"] + wrap_text(self.result, max_lines=4)
            if self.error and len(lines) < 5:
                lines.append(self.error)
            footer = "L RETAKE   R ORACLE"
            right = self.mode[:3]
        elif self.error:
            lines = [self.mode, self.error, "R CAPTURE"]
        else:
            state = "WAIT IMAGE" if self.state == "WAIT_IMAGE" else self.state
            lines = [state, progress_label(self.progress), "MONOCLE CAMERA"]
            footer = "L CANCEL"
            right = "WAIT"
        items = screen_items("VISION", lines, footer, right=right, accent=self.accent)
        if shapes:
            items.extend([
                l_item(210, 110, 260, 110, WHITE, 1),
                l_item(380, 110, 430, 110, WHITE, 1),
                l_item(210, 290, 260, 290, WHITE, 1),
                l_item(380, 290, 430, 290, WHITE, 1),
            ])
        return items[:TEXT_ITEM_LIMIT]


class NavigateApp(HostApp):
    app_id = "navigate"
    label = "NAVIGATE"
    accent = GREEN

    def __init__(self):
        self.idx = 0
        self.details = False
        self.pinned = False
        self.rerouting = False
        self.last = time.time()
        self.steps = [
            {"icon": "^", "distance": 250, "street": "Broadway", "action": "Continue north", "eta": "08:42"},
            {"icon": ">", "distance": 80, "street": "Canal St", "action": "Turn right", "eta": "2 min"},
            {"icon": "*", "distance": 0, "street": "Arrived", "action": "Destination left", "eta": "done"},
        ]

    def _step(self):
        return self.steps[self.idx]

    def on_tick(self, now):
        if now - self.last < 1.0 or self.rerouting:
            return False
        self.last = now
        step = self._step()
        if step["distance"] <= 0:
            return False
        drop = 5 if step["distance"] > 30 else 2
        step["distance"] = max(0, step["distance"] - drop)
        if step["distance"] == 0 and self.idx < len(self.steps) - 1:
            self.idx += 1
        return True

    def on_button(self, side, gesture, duration_ms=0):
        if gesture == "TAP" and side == "L":
            self.details = not self.details
            return True
        if gesture == "TAP" and side == "R":
            self.idx = min(len(self.steps) - 1, self.idx + 1)
            return True
        if gesture == "LONG" and side == "R":
            self.pinned = not self.pinned
            return True
        if gesture == "DOUBLE" and side == "L":
            self.rerouting = not self.rerouting
            return True
        return False

    def widget(self):
        step = self._step()
        return step["icon"] + " " + str(step["distance"]) + "m"

    def render(self, shapes=False):
        step = self._step()
        dist = str(step["distance"]) + "m"
        if self.rerouting:
            lines = ["REROUTING", "HOST RECALC", "LAST STEP", step["street"]]
            right = "GPS"
        else:
            urgency = "TURN NOW" if 0 < step["distance"] <= 20 else ("ARRIVED" if step["distance"] == 0 else "ON ROUTE")
            lines = [urgency, step["icon"], dist, step["street"]]
            if self.details:
                lines.extend([step["action"], "ETA " + step["eta"], "PINNED" if self.pinned else "FULL"])
            right = "%d/%d" % (self.idx + 1, len(self.steps))
        return screen_items("NAVIGATE", lines, "L DETAIL  R PEEK  HOLD R PIN  DBL L REROUTE", right=right, accent=self.accent, dense=True)


class StreamApp(HostApp):
    app_id = "stream"
    label = "SIGNAL"
    accent = YELLOW

    def __init__(self, services=None):
        super().__init__(services)
        self.idx = 0
        self.privacy = False
        self.last_action = ""
        self.dismissed = set()
        self.cards = self.services.data.stream_cards()
        self._sort_cards()

    def on_enter(self):
        self.cards = [
            card for card in self.services.data.stream_cards()
            if self._signature(card) not in self.dismissed
        ]
        self._sort_cards()
        self.idx = min(self.idx, max(0, len(self.cards) - 1))

    def _sort_cards(self):
        rank = {"CRITICAL": 0, "IMPORTANT": 1, "INFO": 2}
        self.cards.sort(key=lambda card: rank.get(card.get("prio"), 9))

    def _signature(self, card):
        return "%s|%s|%s" % (card.get("source", ""), card.get("title", ""), card.get("body", ""))

    def _card(self):
        if not self.cards:
            return {"source": "SYS", "title": "EMPTY", "body": "NO CARDS", "prio": "INFO", "handoff": False}
        return self.cards[self.idx % len(self.cards)]

    def on_button(self, side, gesture, duration_ms=0):
        if gesture == "TAP" and side == "L" and self.cards:
            self.idx = (self.idx + 1) % len(self.cards)
            self.last_action = "OLDER"
            return True
        if gesture == "TAP" and side == "R" and self.cards:
            card = self._card()
            removed = card["title"]
            self.dismissed.add(self._signature(card))
            self.cards.pop(self.idx % len(self.cards))
            if self.cards:
                self.idx %= len(self.cards)
            self.last_action = "DISMISSED " + removed
            return True
        if gesture == "TAP" and side == "R" and not self.cards:
            self.dismissed = set()
            self.cards = self.services.data.stream_cards()
            self._sort_cards()
            self.idx = 0
            self.last_action = "RELOADED"
            return True
        if gesture == "LONG" and side == "R":
            card = self._card()
            self.last_action = "OPENED ON HOST" if card.get("handoff") else "NO HANDOFF"
            if card.get("handoff"):
                self.emit_action("stream_handoff", card=card)
            return True
        if gesture == "DOUBLE" and side == "L":
            self.privacy = not self.privacy
            self.last_action = "PRIVACY ON" if self.privacy else "PRIVACY OFF"
            return True
        return False

    def widget(self):
        if not self.cards:
            return "CLEAR"
        return str(len(self.cards)) + " CARDS"

    def render(self, shapes=False):
        card = self._card()
        title = "PRIVATE" if self.privacy else card.get("title", "CARD")
        body = "#### ####" if self.privacy else card.get("body", "")
        if self.cards:
            lines = [card.get("prio", "INFO"), title]
            lines.extend(wrap_text(body, max_lines=2))
            footer = "L NEXT   R DISMISS"
            if card.get("handoff"):
                footer = "R DISMISS HOLD R OPEN"
        else:
            lines = ["EMPTY STACK", "R RELOAD"]
            footer = "R RELOAD"
        if self.last_action:
            lines.extend(wrap_text(self.last_action, max_lines=1))
        count = "%d/%d" % (self.idx + 1 if self.cards else 0, len(self.cards))
        right = "PRIV" if self.privacy else card.get("source", "SYS")
        return screen_items("SIGNAL", lines, footer, left=count, right=right, accent=self.accent)


class ChronosApp(HostApp):
    app_id = "chronos"
    label = "CHRONOS"
    accent = YELLOW

    def __init__(self, services=None):
        super().__init__(services)
        self.mode = "TIMER"
        self.total = self.services.data.chronos_seconds()
        self.remaining = self.total
        self.stopwatch = 0
        self.running = False
        self.pinned = False
        self.alarm_seen = False
        self.last = time.time()

    def on_enter(self):
        self.last = time.time()

    def _format_seconds(self, value):
        sign = "-" if value < 0 else ""
        value = abs(int(value))
        return "%s%02d:%02d" % (sign, value // 60, value % 60)

    def _display_time(self):
        if self.mode == "STOPWATCH":
            return self._format_seconds(self.stopwatch)
        return self._format_seconds(self.remaining)

    def on_tick(self, now):
        if not self.running:
            self.last = now
            return False
        elapsed = int(now - self.last)
        if elapsed <= 0:
            return False
        self.last += elapsed
        if self.mode == "STOPWATCH":
            self.stopwatch += elapsed
        else:
            self.remaining = max(0, self.remaining - elapsed)
            if self.remaining <= 0:
                self.running = False
        return True

    def on_button(self, side, gesture, duration_ms=0):
        if self.remaining <= 0 and self.mode == "TIMER":
            if gesture in ("TAP", "LONG"):
                self.running = False
                self.remaining = self.total
                self.alarm_seen = True
                return True
        if gesture == "TAP" and side == "L":
            if self.running:
                self.pinned = not self.pinned
            elif self.mode == "TIMER":
                self.total = max(60, self.total - 60)
                self.remaining = min(self.remaining, self.total)
            else:
                self.stopwatch = max(0, self.stopwatch - 60)
            return True
        if gesture == "TAP" and side == "R":
            if self.running:
                self.pinned = not self.pinned
            elif self.mode == "TIMER":
                self.total = min(24 * 60 * 60, self.total + 60)
                self.remaining = min(self.total, self.remaining + 60)
            else:
                self.stopwatch += 60
            return True
        if gesture == "LONG" and side == "R":
            self.running = not self.running
            self.last = time.time()
            return True
        if gesture == "DOUBLE" and side == "L":
            if not self.running:
                self.mode = "STOPWATCH" if self.mode == "TIMER" else "TIMER"
            self.running = False
            self.remaining = self.total
            self.stopwatch = 0
            return True
        return False

    def widget(self):
        prefix = "SW " if self.mode == "STOPWATCH" else "T-"
        return prefix + self._display_time()

    def render(self, shapes=False):
        if self.mode == "STOPWATCH":
            pct = (self.stopwatch % 60) * 100 // 60
        else:
            elapsed = self.total - max(0, self.remaining)
            pct = 100 if self.total <= 0 else clamp(int((elapsed / float(self.total)) * 100), 0, 100)
        state = "ALARM" if self.mode == "TIMER" and self.remaining <= 0 else ("RUNNING" if self.running else "SETUP")
        lines = [self._display_time(), state, self.mode, progress_label(pct)]
        if self.pinned:
            lines.append("PINNED")
        if state == "ALARM":
            footer = "TAP DISMISS"
        elif self.running:
            footer = "L/R PIN  HOLD R PAUSE"
        else:
            footer = "L/R ADJ  HOLD R RUN"
        return screen_items("CHRONOS", lines, footer, right=progress_label(pct), accent=self.accent)


class TeleprompterApp(HostApp):
    app_id = "teleprompter"
    label = "TELEPROMPT"
    accent = CYAN

    def __init__(self, services=None):
        super().__init__(services)
        self.idx = 0
        self.mode = "MANUAL"
        self.wpm = 140
        self.last = time.time()
        self.bookmark = 0
        self.lines = self.services.data.teleprompter_lines()

    def _ensure_lines(self):
        if not self.lines:
            self.lines = ["NO SCRIPT"]
        self.idx = clamp(self.idx, 0, max(0, len(self.lines) - 1))
        self.bookmark = clamp(self.bookmark, 0, max(0, len(self.lines) - 1))

    def on_enter(self):
        old_len = len(self.lines)
        self.lines = self.services.data.teleprompter_lines()
        if len(self.lines) != old_len:
            self.idx = 0
            self.bookmark = 0
        self._ensure_lines()
        self.last = time.time()

    def on_tick(self, now):
        if self.mode != "AUTO":
            self.last = now
            return False
        if now - self.last >= max(1.0, 240.0 / float(self.wpm)):
            self.last = now
            old = self.idx
            self.idx = min(len(self.lines) - 1, self.idx + 1)
            return self.idx != old
        return False

    def on_button(self, side, gesture, duration_ms=0):
        self._ensure_lines()
        if gesture == "TAP" and side == "L":
            if self.mode == "AUTO":
                self.wpm = max(80, self.wpm - 10)
            else:
                self.idx = max(0, self.idx - 1)
            return True
        if gesture == "TAP" and side == "R":
            if self.mode == "AUTO":
                self.wpm = min(240, self.wpm + 10)
            else:
                self.idx = min(len(self.lines) - 1, self.idx + 1)
            return True
        if gesture == "LONG" and side == "R":
            self.mode = "MANUAL" if self.mode == "AUTO" else "AUTO"
            self.last = time.time()
            return True
        if gesture == "DOUBLE" and side == "L":
            if self.idx == self.bookmark:
                self.lines = self.services.data.teleprompter_lines()
                self.bookmark = 0
                self.idx = 0
            else:
                self.bookmark = self.idx
                self.idx = self.bookmark
            self.mode = "MANUAL"
            return True
        return False

    def widget(self):
        return "%d/%d" % (self.idx + 1, len(self.lines))

    def render(self, shapes=False):
        self._ensure_lines()
        prev2 = self.lines[max(0, self.idx - 1):self.idx]
        curr = self.lines[self.idx]
        next2 = self.lines[self.idx + 1:self.idx + 2]
        lines = ["  " + x for x in prev2] + ["> " + curr] + ["  " + x for x in next2]
        pct = int(((self.idx + 1) / float(len(self.lines))) * 100)
        lines.append(self.mode + " " + str(self.wpm) + " WPM")
        lines.append(progress_label(pct))
        footer = "L/R SPEED HOLD R MAN" if self.mode == "AUTO" else "L/R LINE  HOLD R AUTO"
        return screen_items("TELEPROMPT", lines, footer, left="%d/%d" % (self.idx + 1, len(self.lines)), accent=self.accent, dense=True)


class RecallApp(HostApp):
    app_id = "recall"
    label = "RECALL"
    accent = GREEN

    def __init__(self, services=None):
        super().__init__(services)
        self.view = "DECKS"
        self.deck = 0
        self.cursor = 0
        self.page = 0
        self.pinned = False
        self.decks = [
            {"name": "GROCERIES", "mode": "CHECK", "lines": [["Milk", False], ["Eggs", False], ["Bread", True], ["Apples", False]]},
            {"name": "CONFIG", "mode": "NOTE", "lines": ["IP 192.168.1.55", "PORT 8080", "USER admin", "VPN required", "Restart after change"]},
            {"name": "TALK POINTS", "mode": "NOTE", "lines": ["ROI up 14%", "Q3 churn down", "Ask for pilot", "Risk: migration time"]},
        ]

    def _deck(self):
        return self.decks[self.deck % len(self.decks)]

    def _sort_decks(self):
        self.decks.sort(key=lambda deck: 0 if deck["mode"] == "CHECK" else 1)

    def on_button(self, side, gesture, duration_ms=0):
        if self.view == "DECKS":
            if gesture == "TAP" and side == "L":
                self.deck = (self.deck - 1) % len(self.decks)
                return True
            if gesture == "TAP" and side == "R":
                self.deck = (self.deck + 1) % len(self.decks)
                return True
            if gesture == "LONG" and side == "R":
                self.view = "CARD"
                self.cursor = 0
                self.page = 0
                return True
            if gesture == "DOUBLE" and side == "L":
                self._sort_decks()
                self.deck = 0
                return True
        else:
            deck = self._deck()
            if gesture == "DOUBLE" and side == "L":
                self.view = "DECKS"
                return True
            if deck["mode"] == "CHECK":
                if gesture == "TAP" and side == "L":
                    self.cursor = max(0, self.cursor - 1)
                    return True
                if gesture == "TAP" and side == "R":
                    self.cursor = min(len(deck["lines"]) - 1, self.cursor + 1)
                    return True
                if gesture == "LONG" and side == "R":
                    item = deck["lines"][self.cursor]
                    item[1] = not item[1]
                    return True
            else:
                if gesture == "TAP" and side == "L":
                    self.page = max(0, self.page - 1)
                    return True
                if gesture == "TAP" and side == "R":
                    self.page += 1
                    return True
                if gesture == "LONG" and side == "R":
                    self.pinned = not self.pinned
                    return True
        return False

    def widget(self):
        return self._deck()["name"][:8]

    def render(self, shapes=False):
        deck = self._deck()
        if self.view == "DECKS":
            names = [self.decks[(self.deck - 1) % len(self.decks)]["name"], deck["name"], self.decks[(self.deck + 1) % len(self.decks)]["name"]]
            return screen_items("RECALL", ["< " + names[0], names[1], names[2] + " >", deck["mode"]], "L/R DECK  HOLD R OPEN  DBL L SORT", left="%d/%d" % (self.deck + 1, len(self.decks)), accent=self.accent)
        if deck["mode"] == "CHECK":
            lines = [deck["name"]]
            done = 0
            for i, item in enumerate(deck["lines"]):
                if item[1]:
                    done += 1
                mark = "[x]" if item[1] else "[ ]"
                prefix = "> " if i == self.cursor else "  "
                lines.append(prefix + mark + " " + item[0])
            lines.append(progress_bar((done * 100) // max(1, len(deck["lines"])), 10))
            left = str(done) + "/" + str(len(deck["lines"]))
        else:
            visible, self.page, total = page_lines(deck["lines"], self.page, per_page=5)
            lines = [deck["name"]] + visible + (["PINNED"] if self.pinned else [])
            left = "%d/%d" % (self.page + 1, total)
        return screen_items("RECALL", lines, "L/R MOVE/PAGE  HOLD R CHECK/PIN  DBL L BACK", left=left, accent=self.accent, dense=True)


class BabelApp(HostApp):
    app_id = "babel"
    label = "BABEL"
    accent = CYAN

    def __init__(self, services=None):
        super().__init__(services)
        self.src = "AUTO"
        self.dst = "EN"
        self.alt_dst = "JA"
        self.paused = False
        self.audio = 6
        self.tick_count = 0
        self.lines = []
        self.pending = False
        self.waiting_audio = False
        self.wait_started = 0.0
        self.capture_timeout = 12.0
        self.request_id = 0

    def on_button(self, side, gesture, duration_ms=0):
        if gesture == "TAP" and side == "L":
            self.paused = not self.paused
            return True
        if gesture == "TAP" and side == "R":
            self.start_audio_capture()
            return True
        if gesture == "LONG" and side == "R":
            if self.src == "AUTO":
                self.src = "EN"
                self.dst = self.alt_dst
            else:
                self.src, self.dst = self.dst, self.src
            self.lines.append(("SYS", "TARGET " + self.dst))
            return True
        if gesture == "DOUBLE" and side == "L":
            if self.lines:
                self.emit_action("babel_save_transcript", lines=list(self.lines), src=self.src, dst=self.dst)
            self.next_request_id()
            self.lines = [("SYS", "CLEARED")]
            self.pending = False
            self.waiting_audio = False
            return True
        return False

    def start_text_translation(self):
        if self.pending:
            return True
        text, source = self.services.data.babel_text()
        self.pending = True
        self.waiting_audio = False
        self.lines.append(("RAW", text))
        self.lines = self.lines[-12:]
        req_id = self.next_request_id()
        self.emit_action("babel_translate", request_id=req_id, text=text, src=self.src, dst=self.dst, source=source)
        return True

    def start_audio_capture(self):
        if self.pending:
            return True
        self.pending = True
        self.waiting_audio = True
        self.wait_started = time.time()
        self.lines.append(("SYS", "LISTENING"))
        self.lines = self.lines[-12:]
        req_id = self.next_request_id()
        self.emit_action("babel_audio_capture", request_id=req_id, seconds=4.0, sample_rate=8000, bit_depth=8)
        return True

    def on_tick(self, now):
        if self.waiting_audio and self.wait_started and now - self.wait_started > self.capture_timeout:
            self.next_request_id()
            self.waiting_audio = False
            self.pending = False
            self.lines.append(("ERR", "NO AUDIO"))
            self.lines = self.lines[-12:]
            return True
        if self.paused:
            return False
        self.audio = (self.audio + 1) % 10
        self.tick_count += 1
        return True

    def audio_started(self):
        if self.waiting_audio:
            self.lines.append(("SYS", "MIC ON"))
            self.lines = self.lines[-12:]
            return True
        return False

    def audio_failed(self, error):
        self.next_request_id()
        self.pending = False
        self.waiting_audio = False
        self.lines.append(("ERR", clean_for_screen(error, limit=160)))
        self.lines = self.lines[-12:]
        return True

    def audio_received(self, audio_bytes, sample_rate=8000):
        if self.paused and not self.waiting_audio:
            return False
        if self.pending and not self.waiting_audio:
            self.lines.append(("SYS", "BUSY DROP"))
            self.lines = self.lines[-12:]
            return False
        if self.waiting_audio:
            req_id = self.request_id
        else:
            req_id = self.next_request_id()
        self.pending = True
        self.waiting_audio = False
        self.lines.append(("SYS", "AUDIO %d BYTES" % len(audio_bytes)))
        self.lines = self.lines[-12:]
        self.emit_action("babel_audio", request_id=req_id, audio=audio_bytes, sample_rate=sample_rate, src=self.src, dst=self.dst)
        return True

    def complete_translation(self, raw, translated, source="", error="", request_id=None):
        if request_id is not None and int(request_id) != int(self.request_id):
            return False
        self.pending = False
        self.waiting_audio = False
        if raw:
            self.lines.append(("RAW", clean_for_screen(raw, limit=220)))
        if translated:
            self.lines.append(("FINAL", clean_for_screen(translated, limit=360)))
        if error:
            self.lines.append(("ERR", clean_for_screen(error, limit=160)))
        elif source:
            self.lines.append(("SYS", "SRC " + source))
        self.lines = self.lines[-16:]
        return True

    def widget(self):
        return ("..." if self.pending else self.src) + ">" + self.dst

    def render(self, shapes=False):
        status = "PAUSED" if self.paused else ("WAIT" if self.pending else "READY")
        visible = self.lines[-3:]
        lines = [status, self.src + ">" + self.dst, "MIC " + audio_meter(self.audio)]
        for kind, text in visible:
            prefix = "IN" if kind == "RAW" else ("!" if kind == "ERR" else ("-" if kind == "SYS" else "OUT"))
            lines.append(prefix + " " + text)
        footer = "L RESUME   R LISTEN" if self.paused else "L FREEZE   R LISTEN"
        return screen_items("BABEL", lines, footer, right=self.dst[:5], accent=self.accent, dense=True)


class HostAppSuite:
    def __init__(self, services=None):
        self.services = services or HostServices()
        self.apps = [
            OracleApp(self.services),
            VisionApp(self.services),
            StreamApp(self.services),
            ChronosApp(self.services),
            TeleprompterApp(self.services),
            BabelApp(self.services),
        ]
        self.archived_apps = [
            NavigateApp(),
            RecallApp(self.services),
        ]
        self.by_id = {app.app_id: app for app in self.apps}

    def app_list(self):
        return [(app.app_id, app.label) for app in self.apps]

    def get(self, app_id):
        return self.by_id.get(app_id)

    def widgets(self):
        return {app.app_id: app.widget() for app in self.apps}
