import importlib.util
import asyncio
import json
import os
import struct
import sys
import tempfile
import types
import unittest
from pathlib import Path


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
HOST_FILE = os.path.join(ROOT, "host", "prism_host.py")
HOST_DIR = os.path.dirname(HOST_FILE)
if HOST_DIR not in sys.path:
    sys.path.insert(0, HOST_DIR)


if "bleak" not in sys.modules:
    bleak = types.ModuleType("bleak")
    bleak.BleakClient = object
    bleak.BleakScanner = object
    sys.modules["bleak"] = bleak


spec = importlib.util.spec_from_file_location("prism_host_under_test", HOST_FILE)
prism_host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prism_host)
from prism_apps import BabelApp, ChronosApp, HostAppSuite, OracleApp, RecallApp, StreamApp, TeleprompterApp, VisionApp
from prism_services import HostData, pcm_s8_to_wav16


class FakeData:
    def oracle_prompt(self):
        return "What is the next useful move?", "TEST"

    def babel_text(self):
        return "bonjour", "TEST"

    def write_clipboard(self, text):
        return True

    def stream_cards(self):
        return [{"source": "T", "title": "TEST", "body": "Card body", "prio": "INFO", "handoff": False}]

    def teleprompter_lines(self):
        return ["one", "two"]

    def chronos_seconds(self):
        return 120

    def save_capture(self, image_bytes, msg_id=None, ext=".jpg"):
        return "/tmp/capture.jpg"

    def save_oracle_history(self, prompt, answer, source=""):
        return "/tmp/oracle_history.jsonl"

    def save_vision_note(self, result, capture_path="", mode="IDENTIFY"):
        return "/tmp/vision_notes.jsonl"

    def save_babel_transcript(self, lines, src="AUTO", dst="EN"):
        return "/tmp/babel_transcripts.jsonl"


class FakeProvider:
    last_error = ""

    def available(self):
        return True


class FakeServices:
    def __init__(self):
        self.data = FakeData()
        self.provider = FakeProvider()

    def status(self):
        return "TEST"

    def answer_oracle(self, prompt, context=""):
        return "answer: " + prompt

    def translate_text(self, text, src="AUTO", dst="EN"):
        return "hello"

    def analyze_image(self, image_bytes, prompt=None, mime_type="image/jpeg"):
        return "image answer"

    def transcribe_audio(self, audio_bytes, sample_rate=8000):
        return "what is this"


class CountingData(FakeData):
    def __init__(self):
        self.capture_count = 0

    def save_capture(self, image_bytes, msg_id=None, ext=".jpg"):
        self.capture_count += 1
        return "/tmp/capture_%s%s" % (msg_id, ext)


class CountingServices(FakeServices):
    def __init__(self):
        super().__init__()
        self.data = CountingData()


class EmptyTeleprompterData(FakeData):
    def teleprompter_lines(self):
        return []


class EmptyTeleprompterServices(FakeServices):
    def __init__(self):
        super().__init__()
        self.data = EmptyTeleprompterData()


class PriorityData(FakeData):
    def stream_cards(self):
        return [
            {"source": "I", "title": "info", "body": "later", "prio": "INFO", "handoff": False},
            {"source": "C", "title": "critical", "body": "now", "prio": "CRITICAL", "handoff": True},
            {"source": "M", "title": "mid", "body": "soon", "prio": "IMPORTANT", "handoff": False},
        ]


class PriorityServices(FakeServices):
    def __init__(self):
        super().__init__()
        self.data = PriorityData()


class FakeClient:
    def __init__(self):
        self.writes = []

    async def write_gatt_char(self, char, data, response=False):
        self.writes.append((char, bytes(data), bool(response)))


FONT_W = 24
FONT_H = 48


def _text_box(item):
    text = str(item.get("v", ""))[:int(item.get("n", 26))]
    anchor = str(item.get("a", "MC")).upper()
    x = int(item.get("x", 320))
    y = int(item.get("y", 200))
    width = len(text) * FONT_W
    if anchor.endswith("L"):
        cx = x + width // 2
    elif anchor.endswith("R"):
        cx = x - width // 2
    else:
        cx = x
    if anchor.startswith("T"):
        cy = y + FONT_H // 2
    elif anchor.startswith("B"):
        cy = y - FONT_H // 2
    else:
        cy = y
    return cx - width // 2, cx + width // 2, cy - FONT_H // 2, cy + FONT_H // 2, text


def _overlaps(a, b):
    # Matches the inclusive overlap test in Brilliant's display.py.
    return a[0] <= b[1] and a[1] >= b[0] and a[2] <= b[3] and a[3] >= b[2]


def _frame(kind, flags, msg_id, seq, total, payload=b""):
    return struct.pack(prism_host.HEADER_FMT, prism_host.MAGIC, prism_host.VERSION, kind, flags, msg_id, seq, total) + bytes(payload)


class TestHostRenderedDraw(unittest.TestCase):
    def test_screen_items_are_bounded_for_device_renderer(self):
        lines = ["line %02d with text that should be clipped tightly" % i for i in range(20)]
        items = prism_host.screen_items("ORACLE", lines, "TAP R", left="1/8", right="HOST", dense=True)

        self.assertLessEqual(len(items), prism_host.TEXT_ITEM_LIMIT)
        for item in items:
            self.assertEqual(item["k"], "t")
            self.assertLessEqual(len(item["v"]), item["n"])
            self.assertLessEqual(len(item["v"]), prism_host.TEXT_COLS)
        self.assert_no_text_overlap(items)

    def assert_no_text_overlap(self, items):
        boxes = [_text_box(item) for item in items if item.get("k") == "t"]
        for i, left in enumerate(boxes):
            for right in boxes[i + 1:]:
                self.assertFalse(_overlaps(left, right), "%r overlaps %r" % (left, right))

    def test_binary_draw_payload_stays_inside_monocle_rx_budget(self):
        items = prism_host.screen_items(
            "RECALL",
            ["important project memory row %02d" % i for i in range(7)],
            "TAP L/R ITEM LONG R TOGGLE",
            left="4/9",
            right="HOST",
            dense=True,
        )
        payload = prism_host.pack_draw("recall", items, shapes=False)

        self.assertLessEqual(len(payload), prism_host.DRAW_MAX_BYTES)
        self.assertEqual(payload[0], prism_host.DRAW_VERSION)
        self.assertEqual(payload[1], 0)
        self.assertEqual(payload[2], len(b"recall"))
        self.assertGreater(payload[3], 0)
        self.assertEqual(payload[4:10], b"recall")
        self.assert_no_text_overlap(items)

    def test_worst_case_header_text_does_not_touch_title(self):
        items = prism_host.screen_items(
            "12345678901234",
            ["body"],
            "footer",
            left="123456",
            right="ABCDEF",
        )

        self.assert_no_text_overlap(items)
        self.assertLessEqual(len(items[0]["v"]), prism_host.HEADER_SIDE_COLS)
        self.assertLessEqual(len(items[2]["v"]), prism_host.HEADER_SIDE_COLS)

    def test_bitmap_picture_primitives_are_capped(self):
        items = prism_host.bitmap_items(["10101010"] * 10, 0, 0, cell=4, max_items=7)

        self.assertEqual(len(items), 7)
        self.assertTrue(all(item["k"] == "r" for item in items))

    def test_all_host_apps_render_bounded_draw_payloads(self):
        suite = prism_host.HostAppSuite()
        for app_id, _label in suite.app_list():
            app = suite.get(app_id)
            app.on_enter()
            app.on_button("R", "TAP", duration_ms=80)
            items = app.render(shapes=False)
            payload = prism_host.pack_draw(app_id, items, shapes=False)

            self.assertLessEqual(len(items), prism_host.TEXT_ITEM_LIMIT, app_id)
            self.assertLessEqual(len(payload), prism_host.DRAW_MAX_BYTES, app_id)
            self.assertTrue(all(item.get("k") in {"t", "l", "r", "f"} for item in items), app_id)
            self.assert_no_text_overlap(items)

    def test_app_suite_widgets_cover_orbit_apps(self):
        suite = prism_host.HostAppSuite()
        widgets = suite.widgets()

        self.assertEqual(set(widgets), {app_id for app_id, _label in suite.app_list()})
        self.assertTrue(all(isinstance(value, str) for value in widgets.values()))

    def test_all_host_apps_survive_controls_and_ticks(self):
        suite = prism_host.HostAppSuite()
        gestures = [
            ("R", "TAP"),
            ("R", "TAP"),
            ("L", "TAP"),
            ("R", "LONG"),
            ("L", "DOUBLE"),
        ]
        for app_id, _label in suite.app_list():
            app = suite.get(app_id)
            app.on_enter()
            for side, gesture in gestures:
                app.on_button(side, gesture, duration_ms=120)
            for now in (1000.0, 1001.5, 1003.0):
                app.on_tick(now)

            items = app.render(shapes=True)
            payload = prism_host.pack_draw(app_id, items, shapes=True)

            self.assertLessEqual(len(items), prism_host.TEXT_ITEM_LIMIT, app_id)
            self.assertLessEqual(len(payload), prism_host.DRAW_MAX_BYTES, app_id)
            self.assert_no_text_overlap(items)

    def test_binary_draw_payload_decodes_text_header(self):
        items = prism_host.screen_items("ORACLE", ["READY"], "TAP R", left="1/8", right="HOST")
        payload = prism_host.pack_draw("oracle", items, shapes=False)
        pos = 4 + payload[2]
        self.assertEqual(payload[pos], 1)
        x, y, color, anchor, text_len = struct.unpack_from("<HHIBB", payload, pos + 1)
        self.assertEqual((x, y, color, anchor), (8, 4, prism_host.DIM, prism_host.ANCHOR_CODES["TL"]))
        text = payload[pos + 11:pos + 11 + text_len]
        self.assertEqual(text, b"1/8")

    def test_host_requires_explicit_address_by_default(self):
        host = prism_host.PrismHost()

        with self.assertRaisesRegex(RuntimeError, "Refusing to auto-select"):
            asyncio.run(host.resolve_device())

        self.assertEqual(
            asyncio.run(host.resolve_device("KNOWN-DEVICE-ID")),
            "KNOWN-DEVICE-ID",
        )

    def test_host_reassembler_rejects_known_oversized_payload_before_allocation(self):
        reasm = prism_host.Reassembler()
        frame = _frame(
            prism_host.KIND_CTRL_JSON,
            prism_host.FLAG_START,
            10,
            0,
            prism_host.MAX_CTRL_JSON_BYTES + 1,
            b"{}",
        )

        self.assertEqual(reasm.on_frame(frame), [])
        self.assertEqual(reasm._msgs, {})

    def test_host_reassembler_caps_unknown_length_audio_streams(self):
        reasm = prism_host.Reassembler()
        old_limit = prism_host.MAX_AUDIO_STREAM_BYTES
        prism_host.MAX_AUDIO_STREAM_BYTES = 4
        try:
            first = _frame(
                prism_host.KIND_STREAM_AUDIO,
                prism_host.FLAG_START,
                11,
                0,
                prism_host.TOTAL_LEN_UNKNOWN,
                b"abc",
            )
            second = _frame(
                prism_host.KIND_STREAM_AUDIO,
                prism_host.FLAG_END,
                11,
                1,
                prism_host.TOTAL_LEN_UNKNOWN,
                b"de",
            )

            self.assertEqual(reasm.on_frame(first), [])
            self.assertEqual(reasm.on_frame(second), [])
            self.assertEqual(reasm._msgs, {})
        finally:
            prism_host.MAX_AUDIO_STREAM_BYTES = old_limit

    def test_host_reassembler_times_out_incomplete_streams(self):
        reasm = prism_host.Reassembler()
        start = _frame(
            prism_host.KIND_STREAM_IMAGE,
            prism_host.FLAG_START,
            12,
            0,
            prism_host.TOTAL_LEN_UNKNOWN,
            b"abc",
        )
        end = _frame(
            prism_host.KIND_STREAM_IMAGE,
            prism_host.FLAG_END,
            12,
            1,
            prism_host.TOTAL_LEN_UNKNOWN,
            b"def",
        )

        self.assertEqual(reasm.on_frame(start), [])
        reasm._msgs[(prism_host.KIND_STREAM_IMAGE, 12)]["started"] -= prism_host.STREAM_TIMEOUT_S + 1.0
        self.assertEqual(reasm.on_frame(end), [])
        self.assertEqual(reasm._msgs, {})

    def test_chronos_stopwatch_and_timer_modes_are_host_state(self):
        app = ChronosApp()
        app.on_enter()

        self.assertEqual(app.mode, "TIMER")
        app.on_button("L", "DOUBLE", duration_ms=100)
        self.assertEqual(app.mode, "STOPWATCH")
        app.on_button("R", "LONG", duration_ms=900)
        app.on_tick(time_value := 1000.0)
        app.last = time_value - 3
        self.assertTrue(app.on_tick(time_value))
        self.assertGreaterEqual(app.stopwatch, 3)

    def test_recall_checklist_toggle_mutates_host_deck_only(self):
        app = RecallApp()
        app.on_enter()
        app.on_button("R", "LONG", duration_ms=900)
        before = app._deck()["lines"][0][1]
        app.on_button("R", "LONG", duration_ms=900)
        after = app._deck()["lines"][0][1]

        self.assertNotEqual(before, after)

    def test_chronos_timer_stops_at_zero(self):
        app = ChronosApp(FakeServices())
        app.total = 2
        app.remaining = 2
        app.running = True
        app.last = 10.0

        self.assertTrue(app.on_tick(13.0))
        self.assertEqual(app.remaining, 0)
        self.assertFalse(app.running)

    def test_chronos_timer_adjustment_is_bounded(self):
        app = ChronosApp(FakeServices())
        app.total = 24 * 60 * 60
        app.remaining = app.total

        app.on_button("R", "TAP", duration_ms=80)

        self.assertEqual(app.total, 24 * 60 * 60)
        self.assertEqual(app.remaining, 24 * 60 * 60)

    def test_signal_dismiss_persists_for_session_and_reload_restores(self):
        app = StreamApp(FakeServices())

        app.on_button("R", "TAP", duration_ms=80)
        self.assertEqual(app.cards, [])
        app.on_enter()
        self.assertEqual(app.cards, [])

        app.on_button("R", "TAP", duration_ms=80)
        self.assertEqual(len(app.cards), 1)
        self.assertEqual(app.last_action, "RELOADED")

    def test_signal_handoff_only_emits_for_handoff_cards(self):
        app = StreamApp(FakeServices())

        app.on_button("R", "LONG", duration_ms=900)
        self.assertEqual(app.consume_actions(), [])

        app.cards[0]["handoff"] = True
        app.on_button("R", "LONG", duration_ms=900)
        self.assertEqual(app.consume_actions()[0]["kind"], "stream_handoff")

    def test_signal_sorts_priority_and_privacy_masks_body(self):
        app = StreamApp(PriorityServices())
        app.on_enter()

        self.assertEqual([card["prio"] for card in app.cards], ["CRITICAL", "IMPORTANT", "INFO"])
        app.on_button("L", "DOUBLE", duration_ms=80)
        items = app.render()
        values = [item["v"] for item in items if item.get("k") == "t"]

        self.assertIn("PRIVATE", values)
        self.assertIn("#### ####", values)
        self.assertNotIn("critical", values)
        self.assertNotIn("now", values)

    def test_active_suite_excludes_archived_navigate_and_recall(self):
        suite = HostAppSuite(FakeServices())

        self.assertEqual(
            [app_id for app_id, _label in suite.app_list()],
            ["oracle", "vision", "stream", "chronos", "teleprompter", "babel"],
        )
        self.assertIsNone(suite.get("navigate"))
        self.assertIsNone(suite.get("recall"))

    def test_oracle_tap_emits_audio_capture(self):
        app = OracleApp(FakeServices())

        app.on_button("R", "TAP", duration_ms=80)
        actions = app.consume_actions()

        self.assertEqual(app.mode, "LISTEN")
        self.assertEqual(actions[0]["kind"], "oracle_audio_capture")
        self.assertEqual(actions[0]["data"]["sample_rate"], 8000)
        self.assertIn("request_id", actions[0]["data"])

    def test_oracle_audio_received_emits_host_transcription_query(self):
        app = OracleApp(FakeServices())

        app.on_button("R", "TAP", duration_ms=80)
        capture_request_id = app.consume_actions()[0]["data"]["request_id"]
        self.assertTrue(app.audio_received(b"\x00\x01", sample_rate=8000))
        actions = app.consume_actions()

        self.assertEqual(app.mode, "ASKING")
        self.assertEqual(actions[0]["kind"], "oracle_audio")
        self.assertEqual(actions[0]["data"]["audio"], b"\x00\x01")
        self.assertEqual(actions[0]["data"]["request_id"], capture_request_id)

    def test_oracle_hold_emits_silent_host_provider_query(self):
        app = OracleApp(FakeServices())

        app.on_button("R", "LONG", duration_ms=900)
        actions = app.consume_actions()

        self.assertEqual(app.mode, "ASKING")
        self.assertEqual(actions[0]["kind"], "oracle_query")
        self.assertEqual(actions[0]["data"]["prompt"], "What is the next useful move?")

    def test_oracle_ignores_stale_answer_after_cancel(self):
        app = OracleApp(FakeServices())

        app.on_button("R", "TAP", duration_ms=80)
        request_id = app.consume_actions()[0]["data"]["request_id"]
        app.on_button("L", "TAP", duration_ms=80)

        self.assertFalse(app.complete_answer("late answer", request_id=request_id))
        self.assertEqual(app.mode, "READY")
        self.assertEqual(app.answer, "")

    def test_vision_capture_then_image_received_emits_analysis(self):
        app = VisionApp(FakeServices())

        app.on_button("R", "TAP", duration_ms=80)
        capture_actions = app.consume_actions()
        app.image_received(b"\xff\xd8test\xff\xd9", msg_id=7)
        analyze_actions = app.consume_actions()

        self.assertEqual(capture_actions[0]["kind"], "vision_capture")
        self.assertEqual(analyze_actions[0]["kind"], "vision_analyze")
        self.assertEqual(app.state, "ANALYZE")
        self.assertEqual(capture_actions[0]["data"]["request_id"], analyze_actions[0]["data"]["request_id"])

    def test_host_image_stream_is_saved_once_and_passed_to_vision(self):
        host = prism_host.PrismHost()
        host.services = CountingServices()
        host.app_suite = HostAppSuite(host.services)
        host.apps = host.app_suite.app_list()
        host.mode = "FOCUS"
        host.active_app = "vision"
        host._image_target = "vision"
        vision = host.app_suite.get("vision")
        vision.on_button("R", "TAP", duration_ms=80)
        vision.consume_actions()

        asyncio.run(host.handle_complete(FakeClient(), prism_host.KIND_STREAM_IMAGE, 77, b"\xff\xd8test\xff\xd9"))

        self.assertEqual(host.services.data.capture_count, 1)
        self.assertEqual(vision.capture_path, "/tmp/capture_77.jpg")

    def test_vision_ignores_late_image_after_cancel(self):
        app = VisionApp(FakeServices())

        app.on_button("R", "TAP", duration_ms=80)
        app.consume_actions()
        app.on_button("L", "TAP", duration_ms=80)

        self.assertFalse(app.image_received(b"\xff\xd8late\xff\xd9", msg_id=3))
        self.assertEqual(app.state, "READY")

    def test_vision_capture_timeout_returns_to_ready(self):
        app = VisionApp(FakeServices())

        app.on_button("R", "TAP", duration_ms=80)
        app.wait_started = 10.0

        self.assertTrue(app.on_tick(29.5))
        self.assertEqual(app.state, "READY")
        self.assertEqual(app.error, "NO IMAGE")

    def test_babel_tap_requests_monocle_audio_capture(self):
        app = BabelApp(FakeServices())

        app.on_button("R", "TAP", duration_ms=80)
        actions = app.consume_actions()

        self.assertTrue(app.pending)
        self.assertTrue(app.waiting_audio)
        self.assertEqual(actions[0]["kind"], "babel_audio_capture")
        self.assertEqual(actions[0]["data"]["sample_rate"], 8000)
        self.assertIn("request_id", actions[0]["data"])

    def test_babel_audio_received_emits_host_transcription_translation(self):
        app = BabelApp(FakeServices())

        app.on_button("R", "TAP", duration_ms=80)
        capture_request_id = app.consume_actions()[0]["data"]["request_id"]
        self.assertTrue(app.audio_received(b"\x01\x02", sample_rate=8000))
        actions = app.consume_actions()

        self.assertTrue(app.pending)
        self.assertFalse(app.waiting_audio)
        self.assertEqual(actions[0]["kind"], "babel_audio")
        self.assertEqual(actions[0]["data"]["request_id"], capture_request_id)

    def test_babel_freeze_does_not_drop_inflight_audio_capture(self):
        app = BabelApp(FakeServices())

        app.on_button("R", "TAP", duration_ms=80)
        capture_request_id = app.consume_actions()[0]["data"]["request_id"]
        app.on_button("L", "TAP", duration_ms=80)
        self.assertTrue(app.paused)
        self.assertTrue(app.audio_received(b"\x01\x02", sample_rate=8000))
        actions = app.consume_actions()

        self.assertEqual(actions[0]["kind"], "babel_audio")
        self.assertEqual(actions[0]["data"]["request_id"], capture_request_id)
        self.assertFalse(app.waiting_audio)

    def test_babel_freeze_still_times_out_inflight_audio_capture(self):
        app = BabelApp(FakeServices())

        app.on_button("R", "TAP", duration_ms=80)
        app.consume_actions()
        app.on_button("L", "TAP", duration_ms=80)
        app.wait_started = 10.0

        self.assertTrue(app.on_tick(23.0))
        self.assertFalse(app.pending)
        self.assertFalse(app.waiting_audio)
        self.assertIn(("ERR", "NO AUDIO"), app.lines)

    def test_babel_double_right_is_reserved_for_oracle(self):
        app = BabelApp(FakeServices())

        handled = app.on_button("R", "DOUBLE", duration_ms=80)
        actions = app.consume_actions()

        self.assertFalse(handled)
        self.assertFalse(app.pending)
        self.assertEqual(actions, [])

    def test_babel_ignores_stale_translation_after_clear(self):
        app = BabelApp(FakeServices())

        app.start_text_translation()
        request_id = app.consume_actions()[0]["data"]["request_id"]
        app.on_button("L", "DOUBLE", duration_ms=80)

        self.assertFalse(app.complete_translation("bonjour", "hello", request_id=request_id))
        self.assertEqual(app.lines, [("SYS", "CLEARED")])

    def test_vision_save_note_emits_host_persistence_action(self):
        app = VisionApp(FakeServices())
        app.state = "RESULT"
        app.result = "A green circuit board."
        app.capture_path = "/tmp/capture.jpg"

        app.on_button("R", "LONG", duration_ms=900)
        actions = app.consume_actions()

        self.assertEqual(actions[0]["kind"], "vision_save_note")
        self.assertEqual(actions[0]["data"]["result"], "A green circuit board.")
        self.assertEqual(app.error, "SAVING NOTE")

    def test_babel_clear_emits_transcript_save_action(self):
        app = BabelApp(FakeServices())
        app.lines = [("RAW", "bonjour"), ("FINAL", "hello")]

        app.on_button("L", "DOUBLE", duration_ms=80)
        actions = app.consume_actions()

        self.assertEqual(actions[0]["kind"], "babel_save_transcript")
        self.assertEqual(actions[0]["data"]["lines"], [("RAW", "bonjour"), ("FINAL", "hello")])
        self.assertEqual(app.lines, [("SYS", "CLEARED")])

    def test_host_audio_capture_actions_send_monocle_media_commands(self):
        host = prism_host.PrismHost()
        host.services = FakeServices()
        host.app_suite = HostAppSuite(host.services)
        host.apps = host.app_suite.app_list()
        host._max_write = 180
        client = FakeClient()

        asyncio.run(host._run_app_action(client, {
            "kind": "oracle_audio_capture",
            "app": "oracle",
            "data": {"request_id": 1, "seconds": 4.0, "sample_rate": 8000, "bit_depth": 8},
        }))

        ctrl_payloads = []
        for _char, frame, _response in client.writes:
            _magic, _ver, kind, _flags, _mid, _seq, _total = struct.unpack_from(prism_host.HEADER_FMT, frame, 0)
            if kind == prism_host.KIND_CTRL_JSON:
                ctrl_payloads.append(frame[prism_host.HEADER_LEN:])
        self.assertTrue(ctrl_payloads)
        command = json.loads(ctrl_payloads[0].decode("utf-8"))
        self.assertEqual(command["cmd"], "CAPTURE_AUDIO")
        self.assertEqual(command["app"], "oracle")
        self.assertEqual(command["sample_rate"], 8000)

    def test_focus_double_right_quick_launches_oracle(self):
        host = prism_host.PrismHost()
        host.services = FakeServices()
        host.app_suite = HostAppSuite(host.services)
        host.apps = host.app_suite.app_list()
        host.mode = "FOCUS"
        host.active_app = "babel"
        host._max_write = 180
        client = FakeClient()

        asyncio.run(host.handle_btn(client, {"id": "R", "gesture": "DOUBLE", "dur": 160}))

        self.assertEqual(host.mode, "FOCUS")
        self.assertEqual(host.active_app, "oracle")
        self.assertTrue(client.writes)

    def test_host_data_persists_app_records_as_jsonl(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = HostData()
            data.data_dir = Path(tmp)

            oracle_path = data.save_oracle_history("prompt", "answer", source="TEST")
            vision_path = data.save_vision_note("result", capture_path="/tmp/capture.jpg", mode="OCR")
            babel_path = data.save_babel_transcript([("RAW", "hola"), ("FINAL", "hello")], src="ES", dst="EN")

            with open(oracle_path, "r", encoding="utf-8") as f:
                oracle = json.loads(f.readline())
            with open(vision_path, "r", encoding="utf-8") as f:
                vision = json.loads(f.readline())
            with open(babel_path, "r", encoding="utf-8") as f:
                babel = json.loads(f.readline())

            self.assertEqual(oracle["answer"], "answer")
            self.assertEqual(vision["mode"], "OCR")
            self.assertEqual(babel["lines"][1]["text"], "hello")

    def test_teleprompter_file_lines_are_wrapped_for_monocle_width(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "teleprompter.txt"
            p.write_text(
                "This is a much longer real teleprompter paragraph that should not be clipped on the lens.",
                encoding="utf-8",
            )
            data = HostData()
            data.data_dir = Path(tmp)

            lines = data.teleprompter_lines()

            self.assertGreater(len(lines), 1)
            self.assertTrue(all(len(line) <= 24 for line in lines))

    def test_teleprompter_empty_host_source_stays_renderable(self):
        app = TeleprompterApp(EmptyTeleprompterServices())

        app.on_enter()
        app.on_button("R", "TAP", duration_ms=80)
        items = app.render()

        self.assertEqual(app.lines, ["NO SCRIPT"])
        self.assertEqual(app.idx, 0)
        self.assertTrue(items)

    def test_signed_monocle_pcm_is_wrapped_as_signed_16_bit_wav(self):
        wav = pcm_s8_to_wav16(bytes([0x00, 0x7F, 0x80, 0xFF]), sample_rate=8000)

        self.assertEqual(wav[:4], b"RIFF")
        self.assertEqual(int.from_bytes(wav[34:36], "little"), 16)
        self.assertEqual(int.from_bytes(wav[40:44], "little"), 8)
        samples = [
            int.from_bytes(wav[44 + i:46 + i], "little", signed=True)
            for i in range(0, 8, 2)
        ]
        self.assertEqual(samples, [0, 32512, -32768, -256])


if __name__ == "__main__":
    unittest.main()
