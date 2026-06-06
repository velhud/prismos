# apps/vision.py
# Vision application - The Visual Analysis Interface
#
# Rules:
# - Strictly use ui.text_lines / ui.text_line which guarantees justification=display.MIDDLE_CENTER.
# - Fully implement all BaseApp lifecycle events.
# - Clean up and prevent memory leaks.

from prism.app import BaseApp
from prism import ids, ui, sys as psys, schema, bridge, protocol, hal

import time

APP_ID = ids.APP_VISION
APP_LABEL = ids.LABEL_VISION

_STATUS_READY = "READY"
_STATUS_CAPTURING = "CAPTURING"
_STATUS_SCANNING = "SCANNING"
_STATUS_RESULT = "RESULT"

_MODE_IDENTIFY = "IDENTIFY"
_MODE_READ = "READ"

_SCAN_PHASES = ("UPLOADING...", "PARSING...", "ANALYZING...")


def _clamp_i(v, default=0, lo=0, hi=100):
    try:
        i = int(v)
    except Exception:
        i = int(default)
    if i < lo:
        return lo
    if i > hi:
        return hi
    return i


def _fmt_bytes(n):
    try:
        n = int(n)
    except Exception:
        n = 0
    if n < 1024:
        return str(n) + " B"
    if n < 1024 * 1024:
        return str(n // 1024) + " KB"
    return str(n // (1024 * 1024)) + " MB"


def _bar(pct, width_chars):
    pct = _clamp_i(pct, 0, 0, 100)
    filled = (pct * width_chars) // 100
    if filled < 0:
        filled = 0
    if filled > width_chars:
        filled = width_chars
    return "[" + ("#" * filled) + ("." * (width_chars - filled)) + "]"


class VisionApp(BaseApp):
    def __init__(self):
        self.mode = _MODE_IDENTIFY

        # Host-driven fields
        self.host_status = _STATUS_READY
        self.progress = 0
        self.result_header = ""
        self.result_body = ""

        # Local capture/upload pipeline
        self._sending = False
        self._sender = None
        self._bytes_sent = 0
        self._chunk_bytes = 200

        # Animation timing
        self._phase_i = 0
        self._next_anim = time.ticks_ms()
        
        # Local shutter flash simulation
        self._shutter_flash_until = 0

        self._dirty = True

    def on_start(self):
        self.mode = _MODE_IDENTIFY
        self.host_status = _STATUS_READY
        self.progress = 0
        self.result_header = ""
        self.result_body = ""
        self._sending = False
        self._sender = None
        self._bytes_sent = 0
        self._shutter_flash_until = 0
        self._dirty = True
        
        try:
            psys.toast("VISION", ttl_ms=600)
        except Exception:
            pass
        return True

    def _start_capture(self):
        # 1) Trigger 50ms local shutter flash
        self._shutter_flash_until = time.ticks_add(time.ticks_ms(), 50)
        
        # 2) Call hardware capture
        ok = hal.camera_capture()
        if not ok:
            try:
                psys.toast("CAM FAIL", ttl_ms=900)
            except Exception:
                pass
            return False

        # 3) Inform host of capture start
        try:
            bridge.send_json({
                "event": "MEDIA",
                "kind": "IMAGE",
                "app": APP_ID,
                "mode": self.mode,
                "ts": int(time.ticks_ms()),
            })
        except Exception:
            pass

        self._sender = bridge.StreamSender(protocol.KIND_STREAM_IMAGE)
        self._sending = True
        self._bytes_sent = 0

        frag_max = bridge.max_fragment_len()
        if frag_max <= 0:
            frag_max = 200
        if frag_max > 254:
            frag_max = 254
        if frag_max < 64:
            frag_max = 64
        self._chunk_bytes = int(frag_max)

        self._phase_i = 0
        self._next_anim = time.ticks_ms()
        self._dirty = True
        return True

    def _cancel_capture(self):
        if self._sender is not None:
            try:
                self._sender.finish()
            except Exception:
                pass
        self._sender = None
        self._sending = False
        
        try:
            bridge.send_json({
                "event": "MEDIA",
                "kind": "IMAGE",
                "app": APP_ID,
                "mode": self.mode,
                "abort": True,
                "ts": int(time.ticks_ms()),
            })
        except Exception:
            pass

        try:
            psys.toast("ABORTED", ttl_ms=600)
        except Exception:
            pass

        self._dirty = True

    def on_update(self, now_ms):
        changed = False

        # Upload loop: stream 1 chunk per tick to ensure smooth HUD rendering
        if self._sending and self._sender is not None:
            data = hal.camera_read(self._chunk_bytes)
            if data is None:
                # Finished sending full image
                try:
                    self._sender.finish()
                except Exception:
                    pass
                self._sender = None
                self._sending = False
                try:
                    psys.toast("IMAGE SENT", ttl_ms=500)
                except Exception:
                    pass
                self._dirty = True
                changed = True
            else:
                try:
                    self._sender.send_chunk(data)
                    self._bytes_sent += len(data)
                except Exception:
                    self._cancel_capture()
                    return True
                self._dirty = True
                changed = True

        # Scan text / reticle animation timing
        scanning = self._sending or (self.host_status == _STATUS_SCANNING)
        if scanning:
            if time.ticks_diff(now_ms, self._next_anim) >= 0:
                self._next_anim = time.ticks_add(now_ms, 250)
                self._phase_i = (self._phase_i + 1) % len(_SCAN_PHASES)
                self._dirty = True
                changed = True
        else:
            # Breathe the brackets slowly while ready/idle
            if time.ticks_diff(now_ms, self._next_anim) >= 0:
                self._next_anim = time.ticks_add(now_ms, 1000)
                self._dirty = True
                changed = True

        return changed

    def on_input(self, event_name):
        if event_name == "TAP_L":
            if self._sending:
                self._cancel_capture()
                return True

            if self.host_status == _STATUS_RESULT:
                self.host_status = _STATUS_READY
                self._dirty = True
                return True

            # Toggle analysis mode
            self.mode = _MODE_READ if self.mode == _MODE_IDENTIFY else _MODE_IDENTIFY
            try:
                psys.toast(self.mode, ttl_ms=600)
            except Exception:
                pass
            self._dirty = True
            return True

        if event_name == "TAP_R":
            if self._sending:
                return False
            if self.host_status == _STATUS_RESULT:
                # Trigger Oracle bridging with image context
                return False  # Let host receive tap to bridge to Oracle

            return self._start_capture()

        if event_name == "LONG_R":
            try:
                psys.toast("SAVING NOTE", ttl_ms=600)
            except Exception:
                pass
            return False

        if event_name == "DOUBLE_L":
            try:
                psys.toast("COPIED TEXT", ttl_ms=600)
            except Exception:
                pass
            return False

        return False

    def on_data(self, payload):
        if not isinstance(payload, dict):
            return False

        st = payload.get("status")
        if isinstance(st, str) and st in (_STATUS_READY, _STATUS_CAPTURING, _STATUS_SCANNING, _STATUS_RESULT):
            self.host_status = st

        self.progress = _clamp_i(payload.get("progress", self.progress), default=self.progress, lo=0, hi=100)
        self.result_header = schema.clamp_str(payload.get("result_header", ""), 64)
        self.result_body = schema.clamp_str(payload.get("result_body", ""), 128)

        self._dirty = True
        return True

    def _render_viewfinder(self, objs):
        # 1) Draw mode toggle indicator on the top-left
        if self.mode == _MODE_IDENTIFY:
            objs.extend(ui.text_lines("[o] IDENTIFY", 8, 60, color=ui.WHITE, anchor="TL"))
            objs.extend(ui.text_lines(" T  READ", 8, 110, color=ui.GRAY, anchor="TL"))
        else:
            objs.extend(ui.text_lines(" o  IDENTIFY", 8, 60, color=ui.GRAY, anchor="TL"))
            objs.extend(ui.text_lines("[T] READ", 8, 110, color=ui.WHITE, anchor="TL"))

        # 2) Static targeting box (corners) breathing animation
        pulse = (time.ticks_ms() // 1000) % 2 == 0
        b_col = ui.WHITE if pulse else ui.GRAY

        objs.extend(ui.text_lines("┌", 120, 100, color=b_col, anchor="TL"))
        objs.extend(ui.text_lines("┐", 520, 100, color=b_col, anchor="TR"))
        objs.extend(ui.text_lines("└", 120, 300, color=b_col, anchor="BL"))
        objs.extend(ui.text_lines("┘", 520, 300, color=b_col, anchor="BR"))

    def render(self):
        objs = []

        # 1) Solid shutter flash simulation overlay (50ms)
        if time.ticks_diff(time.ticks_ms(), self._shutter_flash_until) < 0:
            for y in range(48, ui.HEIGHT, 48):
                objs.extend(ui.text_lines("██████████████████████████████", 320, y, color=ui.WHITE, anchor="MC"))
            return objs

        # Determine effective status
        status = _STATUS_SCANNING if self._sending else self.host_status

        if status == _STATUS_READY:
            self._render_viewfinder(objs)
            objs.extend(ui.text_lines("READY", 320, 200, color=ui.WHITE, anchor="MC"))
            objs.extend(ui.text_lines("TAP R: CAPTURE", 320, 250, color=ui.GRAY, anchor="MC"))
            objs.extend(ui.text_lines("TAP L: TOGGLE MODE", 8, ui.HEIGHT, color=ui.GRAY, anchor="BL"))
            return objs

        if status == _STATUS_CAPTURING:
            self._render_viewfinder(objs)
            objs.extend(ui.text_lines("CAPTURING...", 320, 200, color=ui.WHITE, anchor="MC"))
            return objs

        if status == _STATUS_SCANNING:
            self._render_viewfinder(objs)

            # 2) Dynamic horizontal sweeping laser-scan line centering
            period_ms = 2000
            cycle = (time.ticks_ms() % period_ms) / period_ms
            if cycle < 0.5:
                scan_y = int(100 + (cycle * 2.0) * 200)
            else:
                scan_y = int(300 - ((cycle - 0.5) * 2.0) * 200)
            if ui.ENABLE_SHAPES:
                objs.extend(ui.line(120, scan_y, 520, scan_y, color=ui.CYAN, thickness=2))
            else:
                objs.extend(ui.text_lines("======================", 320, scan_y, color=ui.CYAN, anchor="MC"))

            # Processing phase
            phase = _SCAN_PHASES[self._phase_i]
            objs.extend(ui.text_lines(phase, 320, 200, color=ui.WHITE, anchor="MC"))

            # Stream / parse progress
            if self.host_status == _STATUS_SCANNING:
                objs.extend(ui.text_lines(_bar(self.progress, 16), 320, 240, color=ui.WHITE, anchor="MC"))
                objs.extend(ui.text_lines(str(self.progress) + "%", 320, 280, color=ui.GRAY, anchor="MC"))
            else:
                objs.extend(ui.text_lines("SENT: " + _fmt_bytes(self._bytes_sent), 320, 240, color=ui.GRAY, anchor="MC"))

            objs.extend(ui.text_lines("L: CANCEL", 8, ui.HEIGHT, color=ui.GRAY, anchor="BL"))
            return objs

        # RESULT State
        if self.mode == _MODE_IDENTIFY:
            # 3) Sci-Fi Tactile Callout Box
            if self.result_header:
                objs.extend(ui.text_lines("+------------------------------+", 320, 72, color=ui.WHITE, anchor="TC"))
                objs.extend(ui.text_lines("| " + self.result_header.upper() + " |", 320, 120, color=ui.WHITE, anchor="TC"))
                objs.extend(ui.text_lines("+------------------------------+", 320, 168, color=ui.WHITE, anchor="TC"))
                objs.extend(ui.text_lines("|", 320, 216, color=ui.GRAY, anchor="TC"))
            else:
                objs.extend(ui.text_lines("[ ANALYSIS COMPLETE ]", 320, 120, color=ui.CYAN, anchor="TC"))

            if self.result_body:
                objs.extend(ui.text_lines(self.result_body, 320, 260, color=ui.GRAY, anchor="MC", max_width_px=560))

        else:
            # READ / OCR Mode Centered text block
            objs.extend(ui.text_lines("[ EXTRACTED TEXT ]", 320, 80, color=ui.CYAN, anchor="TC"))
            if self.result_body:
                objs.extend(ui.text_lines(self.result_body, 320, 160, color=ui.WHITE, anchor="TC", max_width_px=560))
            else:
                objs.extend(ui.text_lines("[NO TEXT DETECTED]", 320, 160, color=ui.GRAY, anchor="TC"))

        objs.extend(ui.text_lines("L: VIEWINDER", 8, ui.HEIGHT, color=ui.GRAY, anchor="BL"))
        objs.extend(ui.text_lines("R: ASK ORACLE", ui.WIDTH - 8, ui.HEIGHT, color=ui.GRAY, anchor="BR"))
        return objs

    def on_exit(self):
        if self._sending:
            self._cancel_capture()
        self._dirty = True


def create():
    return VisionApp()
