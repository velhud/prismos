# apps/babel.py
# Babel application - Live Translation Subtitles
#
# Rules:
# - Strictly use ui.text_lines / ui.text_line which guarantees justification=display.MIDDLE_CENTER.
# - Fully implement all BaseApp lifecycle events.
# - Clean up and prevent memory leaks.

from prism.app import BaseApp
from prism import ids, ui, sys as psys, schema, bridge, protocol, hal
import time

APP_ID = ids.APP_BABEL
APP_LABEL = ids.LABEL_BABEL

_MAX_LINES_RENDER = 4
_MAX_LINE_CHARS = 48

# Optional: start an audio stream from Monocle mic while Babel is focused.
# Host can ignore if it uses phone mic.
_ENABLE_MIC_STREAM = False
_MIC_RECORD_S = 2.0
_MIC_SAMPLE_RATE = 8000
_MIC_BIT_DEPTH = 8
_MIC_READ_SAMPLES = 127


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


def _meter(level, max_blocks=8):
    """
    Returns a premium, high-contrast block-character visualizer for the audio level.
    """
    n = int(_clamp_f01(level) * float(max_blocks))
    filled = "█" * n
    empty = "░" * (max_blocks - n)
    return f"[{filled}{empty}]"


class BabelApp(BaseApp):
    def __init__(self):
        self.src = "JA"
        self.dst = "EN"
        self.paused = False
        self.audio_level = 0.0
        self.lines = []   # list of {"text":..., "kind":...}
        self.msg = ""

        # Optional device-side mic stream sender
        self._mic_sender = None
        self._mic_streaming = False
        self._mic_ready_at = 0

        self._dirty = True

    def on_start(self):
        self.src = "JA"
        self.dst = "EN"
        self.paused = False
        self.audio_level = 0.0
        self.lines = []
        self.msg = ""
        self._dirty = True
        try:
            psys.toast("BABEL", ttl_ms=600)
        except Exception:
            pass

        if _ENABLE_MIC_STREAM:
            self._start_mic_stream()

        return True

    def _start_mic_stream(self):
        ok = hal.mic_record(seconds=_MIC_RECORD_S, sample_rate=_MIC_SAMPLE_RATE, bit_depth=_MIC_BIT_DEPTH)
        if not ok:
            return
        try:
            bridge.send_json({
                "event": "MEDIA",
                "kind": "AUDIO",
                "app": APP_ID,
                "sr": _MIC_SAMPLE_RATE,
                "bd": _MIC_BIT_DEPTH,
                "ts": int(time.ticks_ms()),
            })
        except Exception:
            pass

        self._mic_sender = bridge.StreamSender(protocol.KIND_STREAM_AUDIO)
        self._mic_streaming = True
        self._mic_ready_at = time.ticks_add(time.ticks_ms(), 200)

    def on_update(self, now_ms):
        if not _ENABLE_MIC_STREAM:
            return False

        if not self._mic_streaming or self._mic_sender is None:
            return False

        # Wait a short time for FPGA buffer to be ready.
        if time.ticks_diff(now_ms, self._mic_ready_at) < 0:
            return False

        data = hal.mic_read(samples=_MIC_READ_SAMPLES)
        if data is None:
            # End of this recording window; close and restart for continuity.
            try:
                self._mic_sender.finish()
            except Exception:
                pass
            self._mic_sender = None
            self._mic_streaming = False
            self._start_mic_stream()
            return False

        try:
            self._mic_sender.send_chunk(data)
        except Exception:
            # Stop streaming on any failure
            self._mic_sender = None
            self._mic_streaming = False

        return False

    def on_input(self, event_name):
        # Return False to propagate inputs back to the Host for full synchronization.
        
        if event_name == "TAP_L":
            self.paused = not self.paused
            try:
                psys.toast("PAUSED" if self.paused else "LIVE", ttl_ms=600)
            except Exception:
                pass
            self._dirty = True
            return False

        if event_name == "TAP_R":
            # Clear history locally
            self.lines = []
            try:
                psys.toast("CLEAR", ttl_ms=500)
            except Exception:
                pass
            self._dirty = True
            return False

        if event_name == "LONG_R":
            # Swap languages locally for instant visual feedback
            self.src, self.dst = self.dst, self.src
            try:
                psys.toast(f"{self.src} -> {self.dst}", ttl_ms=700)
            except Exception:
                pass
            self._dirty = True
            return False

        if event_name == "DOUBLE_L":
            try:
                psys.toast("EXITING BABEL", ttl_ms=600)
            except Exception:
                pass
            return False

        return False

    def on_data(self, payload):
        if not isinstance(payload, dict):
            return False

        self.src = schema.clamp_str(payload.get("src", self.src), 6)
        self.dst = schema.clamp_str(payload.get("dst", self.dst), 6)
        self.paused = bool(payload.get("paused", self.paused))
        self.audio_level = _clamp_f01(payload.get("audio_level", self.audio_level))
        self.msg = schema.clamp_str(payload.get("msg", ""), 32)

        ls = payload.get("lines")
        out = []
        if isinstance(ls, list):
            for item in ls:
                if not isinstance(item, dict):
                    continue
                txt = schema.clamp_str(item.get("text", ""), _MAX_LINE_CHARS)
                kind = item.get("kind", "FINAL")
                kind = str(kind) if kind is not None else "FINAL"
                out.append({"text": txt, "kind": kind})
        # Keep only last N to avoid growth
        if len(out) > 12:
            out = out[-12:]
        self.lines = out

        self._dirty = True
        return True

    def render(self):
        objs = []

        # Premium Language Header indicator
        lang = f"{self.src} ➔ {self.dst}"
        objs.extend(ui.text_lines(lang, 320, 48, color=ui.YELLOW, anchor="TC"))

        # Audio VU Level bar
        meter = _meter(self.audio_level, 8)
        objs.extend(ui.text_lines(f"AUDIO {meter}", 320, 96, color=ui.GRAY, anchor="MC"))

        if self.msg:
            objs.extend(ui.text_lines(self.msg, 320, 136, color=ui.YELLOW, anchor="MC"))

        if self.paused:
            objs.extend(ui.text_lines("⏸ PAUSED", 320, 200, color=ui.YELLOW, anchor="MC"))
            objs.extend(ui.text_lines("TAP L: RESUME", 320, 250, color=ui.GRAY, anchor="MC"))
            return objs

        # Subtitle deck: render last up to 4 lines, bottom-up
        n = len(self.lines)
        start = n - _MAX_LINES_RENDER
        if start < 0:
            start = 0

        y = ui.HEIGHT - 70  # bottom line baseline
        for i in range(n - 1, start - 1, -1):
            item = self.lines[i]
            txt = item.get("text", "")
            kind = item.get("kind", "FINAL")

            if kind == "RAW":
                col = ui.GRAY
                display_txt = f"… {txt}"
            elif kind == "SYS":
                col = ui.YELLOW
                display_txt = f"⚙ {txt}"
            else:
                col = ui.WHITE
                display_txt = f"➔ {txt}"

            objs.extend(ui.text_lines(display_txt, 320, y, color=col, anchor="BC", max_width_px=600))
            y -= ui.FONT_H

        # Action hints footer
        objs.extend(ui.text_lines("L: PLAY/PAUSE • R: CLEAR • HOLD R: SWAP", 320, 360, color=ui.GRAY, anchor="MC"))

        return objs

    def on_exit(self):
        # Stop mic stream if enabled
        if self._mic_sender is not None:
            try:
                self._mic_sender.finish()
            except Exception:
                pass
        self._mic_sender = None
        self._mic_streaming = False


def create():
    return BabelApp()
