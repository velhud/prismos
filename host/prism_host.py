"""
PrismMind Host Simulator (desktop) for Brilliant Labs Monocle.

Dependency:
  pip install bleak

What it does:
- Connects to Monocle Raw Data Service (e570...)
- Receives framed messages (CTRL_JSON, STREAM_IMAGE, STREAM_AUDIO, LOG_TEXT)
- Prints BTN/FOCUS events
- Sends host-composed binary DRAW frames for Orbit and focused apps.

This is a dev harness, not a production host.
"""

import asyncio
import argparse
import json
import os
import struct
import sys
import time as pytime
from datetime import datetime, timezone
from pathlib import Path

HOST_DIR = Path(__file__).resolve().parent
if str(HOST_DIR) not in sys.path:
    sys.path.insert(0, str(HOST_DIR))

from bleak import BleakClient, BleakScanner
from prism_apps import HostAppSuite
from prism_services import HostServices
from prism_display import (
    CYAN,
    DIM,
    GRAY,
    GREEN,
    HEADER_SIDE_COLS,
    TEXT_COLS,
    TEXT_ITEM_LIMIT,
    WHITE,
    YELLOW,
    bitmap_items,
    l_item,
    r_item,
    screen_items,
    wrap_text,
)

# Raw Data Service UUIDs (canonical)
SERVICE_UUID = "e5700001-7bac-429a-b4ce-57ff900f479d"
RX_UUID = "e5700002-7bac-429a-b4ce-57ff900f479d"  # Host -> Monocle (write)
TX_UUID = "e5700003-7bac-429a-b4ce-57ff900f479d"  # Monocle -> Host (notify)

MAGIC = b"PM"
VERSION = 1

KIND_CTRL_JSON = 0x01
KIND_STREAM_AUDIO = 0x02
KIND_STREAM_IMAGE = 0x03
KIND_LOG_TEXT = 0x04
KIND_DRAW = 0x05

FLAG_START = 0x01
FLAG_END = 0x02

TOTAL_LEN_UNKNOWN = 0xFFFFFFFF
MAX_CTRL_JSON_BYTES = 4096
MAX_LOG_TEXT_BYTES = 8192
MAX_AUDIO_STREAM_BYTES = 128 * 1024
MAX_IMAGE_STREAM_BYTES = 1024 * 1024
STREAM_TIMEOUT_S = 30.0

HEADER_FMT = "<2sBBBHHI"
HEADER_LEN = 13

# Conservative write size; will be clamped using characteristic max if available.
DEFAULT_MAX_WRITE = 180
WRITE_PAUSE_S = 0.012
DRAW_VERSION = 1
DRAW_MAX_BYTES = 1536
DRAW_TEXT_LIMIT = 32
ANCHOR_CODES = {
    "MC": 0,
    "TL": 1,
    "TC": 2,
    "TR": 3,
    "ML": 4,
    "MR": 5,
    "BL": 6,
    "BC": 7,
    "BR": 8,
}


def tz_offset_str():
    # "+HH:MM" style
    now = datetime.now().astimezone()
    off = now.utcoffset()
    if off is None:
        return "+00:00"
    secs = int(off.total_seconds())
    sign = "+" if secs >= 0 else "-"
    secs = abs(secs)
    hh = secs // 3600
    mm = (secs % 3600) // 60
    return "%s%02d:%02d" % (sign, hh, mm)


def min_json(obj) -> bytes:
    return json.dumps(obj, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def _u16(value, default=0):
    try:
        n = int(value)
    except Exception:
        n = int(default)
    return max(0, min(65535, n))


def _u32(value, default=WHITE):
    try:
        n = int(value)
    except Exception:
        n = int(default)
    return max(0, min(0xFFFFFFFF, n))


def _text_bytes(value, limit=DRAW_TEXT_LIMIT):
    try:
        limit = int(limit)
    except Exception:
        limit = DRAW_TEXT_LIMIT
    limit = max(0, min(DRAW_TEXT_LIMIT, limit))
    text = "" if value is None else str(value)
    return text.encode("ascii", "replace")[:limit]


def pack_draw(app, items, shapes=False) -> bytes:
    app_bytes = _text_bytes(app or "", limit=16)
    payload = bytearray([DRAW_VERSION, 1 if shapes else 0, len(app_bytes), 0])
    payload.extend(app_bytes)
    count = 0
    for item in list(items or [])[:TEXT_ITEM_LIMIT]:
        if not isinstance(item, dict):
            continue
        start = len(payload)
        kind = item.get("k")
        try:
            if kind == "t":
                raw = _text_bytes(item.get("v"), item.get("n", TEXT_COLS))
                anchor = ANCHOR_CODES.get(str(item.get("a", "MC")).upper(), 0)
                payload.extend(struct.pack(
                    "<BHHIBB",
                    1,
                    _u16(item.get("x"), 320),
                    _u16(item.get("y"), 200),
                    _u32(item.get("c"), WHITE),
                    anchor,
                    len(raw),
                ))
                payload.extend(raw)
            elif shapes and kind == "l":
                payload.extend(struct.pack(
                    "<BHHHHIB",
                    2,
                    _u16(item.get("x1")),
                    _u16(item.get("y1")),
                    _u16(item.get("x2")),
                    _u16(item.get("y2")),
                    _u32(item.get("c"), WHITE),
                    max(1, min(8, int(item.get("w", 1)))),
                ))
            elif shapes and kind == "r":
                payload.extend(struct.pack(
                    "<BHHHHI",
                    3,
                    _u16(item.get("x1")),
                    _u16(item.get("y1")),
                    _u16(item.get("x2")),
                    _u16(item.get("y2")),
                    _u32(item.get("c"), WHITE),
                ))
            elif shapes and kind == "f":
                payload.extend(struct.pack("<BI", 4, _u32(item.get("c"), WHITE)))
            else:
                continue
        except Exception:
            del payload[start:]
            continue
        if len(payload) > DRAW_MAX_BYTES:
            del payload[start:]
            break
        count += 1
    payload[3] = count
    return bytes(payload)


class Reassembler:
    """
    Host-side reassembler supporting multiple in-flight messages.
    """
    def __init__(self):
        self._msgs = {}  # (kind,msg_id) -> state

    def _limit_for_kind(self, kind):
        if kind == KIND_CTRL_JSON:
            return MAX_CTRL_JSON_BYTES
        if kind == KIND_LOG_TEXT:
            return MAX_LOG_TEXT_BYTES
        if kind == KIND_STREAM_AUDIO:
            return MAX_AUDIO_STREAM_BYTES
        if kind == KIND_STREAM_IMAGE:
            return MAX_IMAGE_STREAM_BYTES
        return 0

    def on_frame(self, data: bytes):
        if not data or len(data) < HEADER_LEN:
            return []

        try:
            magic, ver, kind, flags, msg_id, seq, total_len = struct.unpack_from(HEADER_FMT, data, 0)
        except Exception:
            return []

        if magic != MAGIC or ver != VERSION:
            return []

        frag = data[HEADER_LEN:]
        is_start = (flags & FLAG_START) != 0
        is_end = (flags & FLAG_END) != 0

        key = (kind, msg_id)
        limit = self._limit_for_kind(kind)
        if limit <= 0:
            return []

        if is_start:
            # Start new message
            if total_len != TOTAL_LEN_UNKNOWN:
                if int(total_len) > limit:
                    self._msgs.pop(key, None)
                    return []
                buf = bytearray(int(total_len))
                st = {"known": True, "total": int(total_len), "buf": buf, "written": 0, "next": 0, "started": pytime.time(), "limit": limit}
            else:
                st = {"known": False, "parts": [], "size": 0, "next": 0, "started": pytime.time(), "limit": limit}
            self._msgs[key] = st

        st = self._msgs.get(key)
        if st is None:
            return []

        if pytime.time() - float(st.get("started", pytime.time())) > STREAM_TIMEOUT_S:
            self._msgs.pop(key, None)
            return []

        # Enforce ordering
        if int(seq) != int(st.get("next", 0)):
            # Drop this message
            self._msgs.pop(key, None)
            return []

        st["next"] = int(seq) + 1

        # Append/copy fragment
        if st["known"]:
            w = st["written"]
            end_i = w + len(frag)
            if end_i > st["total"]:
                self._msgs.pop(key, None)
                return []
            st["buf"][w:end_i] = frag
            st["written"] = end_i
        else:
            if frag:
                if st["size"] + len(frag) > st.get("limit", 0):
                    self._msgs.pop(key, None)
                    return []
                st["parts"].append(bytes(frag))
                st["size"] += len(frag)

        if not is_end:
            return []

        # Complete
        self._msgs.pop(key, None)

        if st["known"]:
            if st["written"] != st["total"]:
                return []
            payload = bytes(st["buf"])
        else:
            payload = b"".join(st["parts"])

        return [(kind, msg_id, payload)]


async def ensure_services(client):
    try:
        return client.services
    except Exception:
        pass
    backend = getattr(client, "_backend", None)
    getter = getattr(backend, "_get_services", None)
    if getter is not None:
        result = getter()
        if hasattr(result, "__await__"):
            await result
        else:
            return result
    return client.services


class PrismHost:
    def __init__(self, shapes=False, scan_timeout=8.0, allow_scan=False):
        self._msg_id = 1
        self._rx_char = None
        self._max_write = DEFAULT_MAX_WRITE
        self._reasm = Reassembler()
        self.shapes = bool(shapes)
        self.services = HostServices()
        self.app_suite = HostAppSuite(self.services)
        self.apps = self.app_suite.app_list()
        self.mode = "ORBIT"
        self.sel = 0
        self.active_app = None
        self.last_btn = None
        self._client = None
        self.scan_timeout = float(scan_timeout)
        self.allow_scan = bool(allow_scan)
        self._tasks = set()
        self._audio_target = None
        self._image_target = None

    def _next_msg_id(self):
        mid = self._msg_id
        self._msg_id = (self._msg_id + 1) & 0xFFFF
        if self._msg_id == 0:
            self._msg_id = 1
        return mid

    def _pack_header(self, kind, flags, msg_id, seq, total_len):
        return struct.pack(HEADER_FMT, MAGIC, VERSION, kind & 0xFF, flags & 0xFF, msg_id & 0xFFFF, seq & 0xFFFF, total_len & 0xFFFFFFFF)

    async def send_bytes(self, client: BleakClient, kind: int, payload: bytes, known_len=True):
        if payload is None:
            payload = b""

        rx_char = self._rx_char if self._rx_char is not None else RX_UUID
        msg_id = self._next_msg_id()
        total_len = len(payload) if known_len else TOTAL_LEN_UNKNOWN

        frag_max = max(1, int(self._max_write) - HEADER_LEN)
        seq = 0
        off = 0

        if len(payload) == 0:
            flags = FLAG_START | FLAG_END
            frame = self._pack_header(kind, flags, msg_id, 0, total_len)
            await client.write_gatt_char(rx_char, frame, response=False)
            await asyncio.sleep(WRITE_PAUSE_S)
            return msg_id

        while off < len(payload):
            frag = payload[off:off + frag_max]
            flags = 0
            if off == 0:
                flags |= FLAG_START
            if off + len(frag) >= len(payload):
                flags |= FLAG_END
            frame = self._pack_header(kind, flags, msg_id, seq, total_len) + frag
            await client.write_gatt_char(rx_char, frame, response=False)
            await asyncio.sleep(WRITE_PAUSE_S)
            off += len(frag)
            seq += 1

        return msg_id

    async def send_ctrl_json(self, client: BleakClient, obj: dict):
        return await self.send_bytes(client, KIND_CTRL_JSON, min_json(obj), known_len=True)

    def _line(self, value, limit=18):
        s = "" if value is None else str(value)
        s = s.replace('"', "'").replace("\\", "/")
        return s[:limit]

    async def send_layout(self, client: BleakClient, app, items):
        await self.send_bytes(client, KIND_DRAW, pack_draw(app or "", items[:TEXT_ITEM_LIMIT], self.shapes), known_len=True)

    async def send_draw(self, client: BleakClient, title, a="", b="", c="", h="", app=None):
        lines = [x for x in (a, b, c) if x]
        await self.send_layout(client, app, screen_items(title, lines, h))

    async def send_time(self, client: BleakClient):
        epoch = int(pytime.time())
        tz = tz_offset_str()
        await self.send_ctrl_json(client, {"type": "SYS", "cmd": "TIME", "data": {"epoch": epoch, "tz": tz}})

    async def send_widgets(self, client: BleakClient):
        widgets = self.app_suite.widgets()
        await self.send_ctrl_json(client, {
            "type": "SYS",
            "cmd": "WIDGETS",
            "data": widgets,
        })

    async def send_orbit(self, client: BleakClient):
        app_id, label = self.apps[self.sel]
        widgets = self.app_suite.widgets()
        prev_label = self.apps[(self.sel - 1) % len(self.apps)][1]
        next_label = self.apps[(self.sel + 1) % len(self.apps)][1]
        lines = [
            "< " + prev_label,
            label,
            next_label + " >",
        ]
        widget = widgets.get(app_id)
        if widget:
            lines.append(widget)
        await self.send_layout(
            client,
            "",
            screen_items("PRISM OS", lines, "L/R SELECT  HOLD R ENTER", left="%d/%d" % (self.sel + 1, len(self.apps)), right="HOST", accent=YELLOW),
        )

    async def send_current_screen(self, client: BleakClient):
        if self.mode == "ORBIT" or not self.active_app:
            await self.send_orbit(client)
        else:
            await self.send_app_state(client)

    async def send_app_state(self, client: BleakClient):
        app = self.active_app
        if not app:
            return
        engine = self.app_suite.get(app)
        if engine is None:
            await self.send_layout(client, app, screen_items("APP", ["UNKNOWN", app], "LONG L EXIT"))
            return
        await self.send_layout(client, app, engine.render(shapes=self.shapes))

    async def handle_btn(self, client: BleakClient, obj: dict):
        side = obj.get("id")
        gesture = obj.get("gesture")
        duration_ms = obj.get("dur", 0)
        self.last_btn = (side, gesture)
        print("[BTN]", obj)

        if self.mode == "ORBIT":
            if gesture == "TAP" and side == "L":
                self.sel = (self.sel - 1) % len(self.apps)
            elif gesture == "TAP" and side == "R":
                self.sel = (self.sel + 1) % len(self.apps)
            elif gesture == "LONG" and side == "R":
                self.active_app = self.apps[self.sel][0]
                self.mode = "FOCUS"
                self._on_enter_app(self.active_app)
            elif gesture == "DOUBLE" and side == "R":
                self.active_app = "oracle"
                self.mode = "FOCUS"
                self._on_enter_app(self.active_app)
            await self.send_current_screen(client)
            return

        if gesture == "LONG" and side == "L":
            self.mode = "ORBIT"
            self.active_app = None
            await self.send_orbit(client)
            return

        if gesture == "DOUBLE" and side == "R":
            self.active_app = "oracle"
            self.mode = "FOCUS"
            self._on_enter_app(self.active_app)
            await self.send_current_screen(client)
            return

        self._handle_app_input(client, side, gesture, duration_ms=duration_ms)
        await self.send_current_screen(client)

    def _on_enter_app(self, app):
        engine = self.app_suite.get(app)
        if engine is not None:
            engine.on_enter()

    def _handle_app_input(self, client, side, gesture, duration_ms=0):
        engine = self.app_suite.get(self.active_app)
        if engine is not None:
            engine.on_button(side, gesture, duration_ms=duration_ms)
            self._drain_actions(client, engine)

    def _drain_actions(self, client, engine):
        for action in engine.consume_actions():
            task = asyncio.create_task(self._run_app_action(client, action))
            self._tasks.add(task)
            task.add_done_callback(self._tasks.discard)

    async def _run_app_action(self, client, action):
        kind = action.get("kind")
        app_id = action.get("app")
        data = action.get("data", {})
        try:
            if kind == "oracle_query":
                engine = self.app_suite.get("oracle")
                req_id = data.get("request_id")
                text = await asyncio.to_thread(
                    self.services.answer_oracle,
                    data.get("prompt", ""),
                    data.get("context", ""),
                )
                if engine is not None:
                    if engine.complete_answer(text, error=self.services.provider.last_error, request_id=req_id):
                        await asyncio.to_thread(
                            self.services.data.save_oracle_history,
                            data.get("prompt", ""),
                            text,
                            data.get("source", ""),
                        )

            elif kind == "oracle_audio_capture":
                engine = self.app_suite.get("oracle")
                req_id = data.get("request_id")
                self._audio_target = "oracle"
                try:
                    await self.send_ctrl_json(client, {
                        "type": "MEDIA",
                        "cmd": "CAPTURE_AUDIO",
                        "app": "oracle",
                        "seconds": data.get("seconds", 4.0),
                        "sample_rate": data.get("sample_rate", 8000),
                        "bit_depth": data.get("bit_depth", 8),
                    })
                except Exception as exc:
                    self._audio_target = None
                    if engine is not None and int(req_id or 0) == int(engine.request_id):
                        engine.audio_failed("CMD FAILED")
                    raise exc

            elif kind == "oracle_audio":
                engine = self.app_suite.get("oracle")
                req_id = data.get("request_id")
                audio = data.get("audio", b"")
                sample_rate = int(data.get("sample_rate", 8000) or 8000)
                raw = await asyncio.to_thread(self.services.transcribe_audio, audio, sample_rate)
                if raw:
                    text = await asyncio.to_thread(
                        self.services.answer_oracle,
                        raw,
                        data.get("context", ""),
                    )
                    err = self.services.provider.last_error
                else:
                    text = "I did not catch that. Try again closer to the mic."
                    err = self.services.provider.last_error or "TRANSCRIBE FAILED"
                if engine is not None and int(req_id or 0) == int(engine.request_id):
                    engine.query = raw or "Voice query"
                    engine.source = "AUDIO"
                    if engine.complete_answer(text, error=err, request_id=req_id) and raw:
                        await asyncio.to_thread(
                            self.services.data.save_oracle_history,
                            raw,
                            text,
                            "AUDIO",
                        )

            elif kind == "oracle_from_vision":
                engine = self.app_suite.get("oracle")
                context = data.get("prompt", "")
                req_id = None
                if engine is not None:
                    req_id = engine.next_request_id()
                text = await asyncio.to_thread(
                    self.services.answer_oracle,
                    "What should I notice or do from this visual result?",
                    context,
                )
                if engine is not None:
                    engine.query = "Vision follow-up"
                    engine.source = "VISION"
                    engine.complete_answer(text, error=self.services.provider.last_error, request_id=req_id)
                    self.active_app = "oracle"
                    self.mode = "FOCUS"

            elif kind == "vision_capture":
                engine = self.app_suite.get("vision")
                req_id = data.get("request_id")
                try:
                    self._image_target = "vision"
                    await self.send_ctrl_json(client, {
                        "type": "MEDIA",
                        "cmd": "CAPTURE_IMAGE",
                        "app": "vision",
                    })
                except Exception as exc:
                    self._image_target = None
                    if engine is not None:
                        engine.capture_failed("CMD FAILED", request_id=req_id)
                    raise exc

            elif kind == "vision_analyze":
                engine = self.app_suite.get("vision")
                req_id = data.get("request_id")
                text = await asyncio.to_thread(
                    self.services.analyze_image,
                    data.get("image", b""),
                    data.get("prompt", ""),
                    data.get("mime_type", "image/jpeg"),
                )
                if engine is not None:
                    engine.complete_result(text, error=self.services.provider.last_error, request_id=req_id)

            elif kind == "babel_translate":
                engine = self.app_suite.get("babel")
                req_id = data.get("request_id")
                raw = data.get("text", "")
                translated = await asyncio.to_thread(
                    self.services.translate_text,
                    raw,
                    data.get("src", "AUTO"),
                    data.get("dst", "EN"),
                )
                if engine is not None:
                    engine.complete_translation(
                        raw,
                        translated,
                        source=data.get("source", ""),
                        error=self.services.provider.last_error,
                        request_id=req_id,
                    )

            elif kind == "babel_audio_capture":
                engine = self.app_suite.get("babel")
                req_id = data.get("request_id")
                self._audio_target = "babel"
                try:
                    await self.send_ctrl_json(client, {
                        "type": "MEDIA",
                        "cmd": "CAPTURE_AUDIO",
                        "app": "babel",
                        "seconds": data.get("seconds", 4.0),
                        "sample_rate": data.get("sample_rate", 8000),
                        "bit_depth": data.get("bit_depth", 8),
                    })
                except Exception as exc:
                    self._audio_target = None
                    if engine is not None and int(req_id or 0) == int(engine.request_id):
                        engine.audio_failed("CMD FAILED")
                    raise exc

            elif kind == "babel_audio":
                engine = self.app_suite.get("babel")
                req_id = data.get("request_id")
                audio = data.get("audio", b"")
                sample_rate = int(data.get("sample_rate", 8000) or 8000)
                raw = await asyncio.to_thread(self.services.transcribe_audio, audio, sample_rate)
                if raw:
                    translated = await asyncio.to_thread(
                        self.services.translate_text,
                        raw,
                        data.get("src", "AUTO"),
                        data.get("dst", "EN"),
                    )
                    err = self.services.provider.last_error
                else:
                    translated = ""
                    err = self.services.provider.last_error or "TRANSCRIBE FAILED"
                if engine is not None:
                    engine.complete_translation(raw, translated, source="AUDIO", error=err, request_id=req_id)

            elif kind == "stream_handoff":
                card = data.get("card", {})
                text = "%s\n%s\n%s" % (card.get("source", ""), card.get("title", ""), card.get("body", ""))
                await asyncio.to_thread(self.services.data.write_clipboard, text)

            elif kind == "vision_save_note":
                engine = self.app_suite.get("vision")
                try:
                    path = await asyncio.to_thread(
                        self.services.data.save_vision_note,
                        data.get("result", ""),
                        data.get("capture_path", ""),
                        data.get("mode", "IDENTIFY"),
                    )
                    if engine is not None:
                        engine.note_saved(path=path, note_id=data.get("note_id", 0))
                except Exception:
                    if engine is not None:
                        engine.note_saved(error="SAVE FAILED")

            elif kind == "babel_save_transcript":
                await asyncio.to_thread(
                    self.services.data.save_babel_transcript,
                    data.get("lines", []),
                    data.get("src", "AUTO"),
                    data.get("dst", "EN"),
                )

            if client is not None:
                await self.send_current_screen(client)
        except Exception as exc:
            print("[ACTION ERROR]", kind, exc)

    async def _tick_host_state(self, client: BleakClient):
        engine = self.app_suite.get(self.active_app)
        if engine is not None:
            if engine.on_tick(pytime.time()):
                await self.send_current_screen(client)

    async def handle_complete(self, client: BleakClient, kind: int, msg_id: int, payload: bytes):
        if kind == KIND_CTRL_JSON:
            try:
                obj = json.loads(payload.decode("utf-8"))
            except Exception:
                print("[CTRL_JSON] decode failed len=%d" % (len(payload),))
                return

            ev = obj.get("event")
            if ev == "BTN":
                await self.handle_btn(client, obj)
            elif ev == "FOCUS":
                print("[FOCUS]", obj)
                mode = obj.get("mode")
                if mode == "FOCUS":
                    self.active_app = obj.get("app")
                    self.last_btn = None
                else:
                    self.active_app = None
            elif ev == "MEDIA":
                print("[MEDIA META]", obj)
                await self._handle_media_meta(client, obj)
            else:
                print("[JSON]", obj)

        elif kind == KIND_STREAM_IMAGE:
            path = self.services.data.save_capture(payload, msg_id=msg_id, ext=".jpg")
            print("[IMAGE] saved", path, "bytes=", len(payload))

            target = self._image_target or "vision"
            self._image_target = None
            vision = self.app_suite.get(target)
            if vision is not None:
                if vision.image_received(payload, msg_id=msg_id, capture_path=path):
                    self._drain_actions(client, vision)
                if self.active_app == target:
                    await self.send_current_screen(client)

        elif kind == KIND_STREAM_AUDIO:
            print("[AUDIO] bytes=", len(payload))
            target = self._audio_target or self.active_app
            self._audio_target = None
            engine = self.app_suite.get(target)
            if target in ("oracle", "babel") and engine is not None:
                if engine.audio_received(payload, sample_rate=8000):
                    self._drain_actions(client, engine)
                elif target == "babel":
                    self._drain_actions(client, engine)
                if self.active_app == target:
                    await self.send_current_screen(client)

        elif kind == KIND_LOG_TEXT:
            try:
                s = payload.decode("utf-8", "ignore")
            except Exception:
                s = "<decode error>"
            print("[LOG]", s)

    async def _handle_media_meta(self, client, obj):
        media_kind = str(obj.get("kind", "")).upper()
        status = str(obj.get("status", "")).upper()
        if media_kind == "IMAGE":
            vision = self.app_suite.get("vision")
            if vision is None:
                return
            if status == "ERROR":
                vision.next_request_id()
                vision.capture_failed(obj.get("detail") or "CAPTURE ERROR")
            elif status == "START" and vision.state == "WAIT_IMAGE":
                vision.state = "UPLOAD"
                vision.progress = max(28, vision.progress)
            elif status == "END" and vision.state in ("WAIT_IMAGE", "UPLOAD"):
                vision.state = "ANALYZE"
                vision.progress = max(70, vision.progress)
            if self.active_app == "vision":
                await self.send_current_screen(client)
        elif media_kind == "AUDIO":
            target = self._audio_target or self.active_app
            engine = self.app_suite.get(target)
            if target not in ("oracle", "babel") or engine is None:
                return
            if status == "ERROR":
                self._audio_target = None
                if hasattr(engine, "audio_failed"):
                    engine.audio_failed(obj.get("detail") or "AUDIO ERROR")
            elif status == "START":
                if hasattr(engine, "audio_started"):
                    engine.audio_started()
            if self.active_app == target:
                await self.send_current_screen(client)

    async def resolve_device(self, address=None):
        if address:
            return address
        if not self.allow_scan:
            raise RuntimeError(
                "Refusing to auto-select a Monocle. Pass --address for the known-good "
                "device, or use --allow-scan only when exactly one Monocle-like device "
                "is advertising."
            )
        return await self.find_device()

    async def run(self, duration=None, address=None):
        dev = await self.resolve_device(address)
        if dev is None:
            raise RuntimeError("No Monocle found (name/service).")

        try:
            async with BleakClient(dev) as client:
                self._client = client
                await ensure_services(client)

                # Get a conservative max write size
                try:
                    ch = client.services.get_characteristic(RX_UUID)
                    self._rx_char = ch
                    mx = getattr(ch, "max_write_without_response_size", DEFAULT_MAX_WRITE)
                    if mx is None:
                        mx = DEFAULT_MAX_WRITE
                    self._max_write = int(mx)
                    if self._max_write < 23:
                        self._max_write = DEFAULT_MAX_WRITE
                except Exception:
                    mx = DEFAULT_MAX_WRITE
                    self._max_write = DEFAULT_MAX_WRITE

                print("Connected:", dev)
                print("max_write_without_response_size =", self._max_write)

                await client.start_notify(TX_UUID, lambda _c, data: asyncio.create_task(self._on_notify(client, data)))

                await self.send_orbit(client)

                # Loops
                last_orbit = 0
                started = pytime.time()

                while True:
                    now = pytime.time()
                    if duration is not None and now - started >= duration:
                        print("Duration reached; disconnecting.")
                        return

                    if self.mode == "ORBIT" and now - last_orbit >= 5:
                        last_orbit = now
                        await self.send_orbit(client)

                    await self._tick_host_state(client)

                    await asyncio.sleep(0.05)
        finally:
            self._client = None

    async def _on_notify(self, client: BleakClient, data: bytearray):
        done = self._reasm.on_frame(bytes(data))
        for kind, msg_id, payload in done:
            await self.handle_complete(client, kind, msg_id, payload)

    async def find_device(self):
        # Only used when --allow-scan is explicitly set. Prefer name, then service UUID.
        devices = await BleakScanner.discover(timeout=self.scan_timeout)
        best = None
        for d in devices:
            name = (d.name or "")
            if "monocle" in name.lower():
                return d
            # Metadata UUIDs may exist on some platforms
            uuids = []
            md = getattr(d, "metadata", None)
            if isinstance(md, dict):
                uuids = md.get("uuids") or []
            if isinstance(uuids, list) and SERVICE_UUID.lower() in [str(u).lower() for u in uuids]:
                best = d
        return best


def dry_run_host(shapes=False):
    suite = HostAppSuite()
    print("PrismOS host dry run")
    print("active apps:", ", ".join(app_id for app_id, _label in suite.app_list()))
    for app_id, label in suite.app_list():
        app = suite.get(app_id)
        app.on_enter()
        items = app.render(shapes=shapes)
        payload = pack_draw(app_id, items, shapes=shapes)
        print("%s %-12s items=%02d bytes=%04d widget=%s" % (
            app_id,
            label,
            len(items),
            len(payload),
            app.widget(),
        ))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--duration", type=float, default=None)
    parser.add_argument("--address", default=None)
    parser.add_argument("--allow-scan", action="store_true", help="Permit auto-selecting a Monocle-like BLE device when --address is omitted.")
    parser.add_argument("--scan-timeout", type=float, default=8.0)
    parser.add_argument("--shapes", action="store_true", help="Send optional Line/Rectangle primitives after device shape support is verified.")
    parser.add_argument("--env-file", default=None, help="Load provider settings such as OPENAI_API_KEY from this .env file.")
    parser.add_argument("--data-dir", default=None, help="Directory for oracle_prompt.txt, teleprompter.txt, stream_cards.json, and babel_text.txt.")
    parser.add_argument("--capture-dir", default=None, help="Directory where Vision JPEG captures are saved.")
    parser.add_argument("--oracle-prompt", default=None, help="One-shot Oracle prompt override for this host run.")
    parser.add_argument("--dry-run", action="store_true", help="Render all active Host apps once without connecting to Monocle.")
    args = parser.parse_args()
    if args.env_file:
        os.environ["PRISM_ENV_FILE"] = args.env_file
    if args.data_dir:
        os.environ["PRISM_DATA_DIR"] = args.data_dir
    if args.capture_dir:
        os.environ["PRISM_CAPTURE_DIR"] = args.capture_dir
    if args.oracle_prompt:
        os.environ["PRISM_ORACLE_PROMPT"] = args.oracle_prompt
    if args.dry_run:
        dry_run_host(shapes=args.shapes)
        raise SystemExit(0)
    asyncio.run(PrismHost(shapes=args.shapes, scan_timeout=args.scan_timeout, allow_scan=args.allow_scan).run(duration=args.duration, address=args.address))
