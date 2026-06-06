# PrismOS SDK Reference (Repository Baseline)

This file documents the legacy SDK surface that exists in this repository under `prism/`.
The live Monocle runtime is host-first: `monocle/kernel.py` does not import these app modules during normal operation.

---

## 0) Canonical Identifiers

Canonical identifiers (APP_ID values, message type strings, SYS command strings) live in:
- `Documentation/IDENTIFIERS.md` (documentation)
- `prism/ids.py` (on-device constants)

---

## 1) Apps (`prism.app` + `apps/*`)

`prism/app.py` defines `BaseApp` (kernel-facing interface).

### App Modules (`apps/<name>.py`)
Each app is a module under `apps/` and must expose:

- `APP_ID` (string)
- `def create():` returning an instance of `prism.app.BaseApp`

### BaseApp (`prism.app.BaseApp`)
Apps implement:

- `__init__(self)` — allocation-only
- `on_start(self) -> bool` — called once when activated
- `on_update(self, now_ms) -> bool` — called frequently
- `on_input(self, event: str) -> bool` — receives input events
- `on_data(self, payload: dict) -> bool` — receives decoded `"data"` field from host `STATE` messages
- `render(self) -> list` — returns display objects; apps must not call `display.show()` directly
- `on_exit(self)` — called once before unload

---

## 2) Input (`prism.input` + `prism.inputscan`)

### Canonical Inputs (`prism.input`)
Physical mapping:
- Left pad = `touch.B`  → side `"L"`
- Right pad = `touch.A` → side `"R"`

Event names (strings):
- `TAP_L`, `TAP_R`
- `LONG_L`, `LONG_R`
- `DOUBLE_L`, `DOUBLE_R`

Repository rule:
- `LONG_L` is reserved by the kernel for exit-to-orbit.
- `DOUBLE_R` is reserved by the kernel for Oracle quick-focus.

Helper:
- `event_parts(event_name) -> (side, gesture)` where:
  - side is `"L"` or `"R"`
  - gesture is `"TAP" | "LONG" | "DOUBLE"`

### Input Scanner (`prism.inputscan.InputScanner`)
`InputScanner` polls `touch.state(...)` and emits canonical events via a callback.

### InputScanner (`prism.inputscan`)
`InputScanner` polls `touch.state(touch.A)` / `touch.state(touch.B)` and emits canonical event names:

- `TAP_L`, `TAP_R`
- `LONG_L`, `LONG_R`
- `DOUBLE_L`, `DOUBLE_R`

Timing constants (repository defaults):
- long press: 800ms
- double window: 300ms
- debounce: 30ms

Gesture emission notes:
- A single `TAP_*` is emitted only after the double-tap window expires without a second tap.
- `DOUBLE_*` is emitted immediately on the second release (within the window).
- `LONG_*` is emitted while still held at the long threshold and cancels any pending TAP/DOUBLE sequence.

---

## 3) UI (`prism.ui`)

### Anchors
All UI text uses `display.MIDDLE_CENTER` justify. To place text in corners/edges, `prism.ui` uses anchor codes:

- `TL`, `TC`, `TR`
- `ML`, `MC`, `MR`
- `BL`, `BC`, `BR`

`text_line(...)` and `text_lines(...)` accept `anchor="<code>"`.
`text_lines(...)` supports wrapping via `max_chars` or `max_width_px`.

Repository baseline UI is a safe, text-first module with a strict rule:
- all `display.Text(...)` must use `justify=display.MIDDLE_CENTER`
- positioning is done by manual anchoring (pixel math)

Key functions:
- `ui.text_lines(text, x, y, color, anchor, line_gap=0) -> list[Text]`
- `ui.text_line(text, x, y, color, anchor) -> Text`
- `ui.draw_hud(time_text, title_text, battery_text=None) -> list[display objects]`
- `ui.draw_carousel_item(label, position) -> list[Text]`
- `ui.draw_hint(text, color) -> list[Text]`

Shape primitives:
- `ui.rect(...)`, `ui.line(...)`, `ui.fill(...)` exist as helper wrappers in `prism/ui.py`.
- They are disabled by default via `ENABLE_SHAPES = False`.
- When disabled, these wrappers return `[]` (safe no-op).

---

## 4) Wire Protocol (`prism.protocol` + `prism.bridge`)

Legacy note: `prism.bridge` still documents JSON helpers for device-side app experiments. The live Host → Monocle screen path uses binary `KIND_DRAW` in `host/prism_host.py` and `monocle/kernel.py`.
The live Host → Monocle sensor path uses small `CTRL_JSON` hardware commands (`CAPTURE_IMAGE`, `CAPTURE_AUDIO`) handled directly by `monocle/kernel.py`; app logic remains on the Host.

### Protocol constants (`prism.protocol`)
- header constants (MAGIC, VERSION)
- kind constants:
  - `KIND_CTRL_JSON`
  - `KIND_STREAM_AUDIO`
  - `KIND_STREAM_IMAGE`
  - `KIND_LOG_TEXT`
- flag constants:
  - `FLAG_START`, `FLAG_END`
- unknown-length sentinel:
  - `TOTAL_LEN_UNKNOWN`

Header parsing/packing helpers are also defined there.

### Bridge (`prism.bridge`)
Implements framing/reassembly for the Raw Data Service.

Functions:
- `bridge.send_json(obj, msg_id=None)` — send dict as CTRL_JSON
- `bridge.send_bytes(kind, payload_bytes, msg_id=None)` — send known-length payload
- `bridge.send_chunks(kind, chunks_iter, msg_id=None, total_len_unknown=True)` — send unknown-length stream
- `bridge.set_on_message(fn)` — callback receives `(kind, msg_id, payload_bytearray)`
- `bridge.decode_json_payload(payload_bytes) -> dict|None`
- `bridge.on_rx_frame(data)` — suitable as callback for `bluetooth.receive_callback(...)`

### CTRL_JSON schema hardening (`prism.schema`)

The kernel sanitizes inbound `CTRL_JSON` envelopes before applying them:

- `schema.sanitize_ctrl(obj) -> dict|None` validates `type` (`SYS|STATE|GHOST|ERR`) and clamps fields to safe sizes.
- `SYS` commands are restricted to `FOCUS|WIDGETS|TIME`; unknown commands are dropped.
- Legacy Host → device `CTRL_JSON` must be known-length and ≤ **4096 bytes** total (`prism.protocol.MAX_RX_TOTAL_LEN`); current binary `DRAW` downlink is capped at **1536 bytes**.

---

## 5) System Signaling (`prism.sys`)

This module is device-local signaling between apps and the kernel.

- `sys.request_exit()` / `sys.consume_exit_request()`
- `sys.toast(msg, ttl_ms=1500)` / `sys.get_toast(now_ms=None)` / `sys.clear_toast()`
- `sys.set_ghost(active, text="", flash=False, icon="")` / `sys.get_ghost() -> (active, text, flash, icon)` / `sys.clear_ghost()`
- `sys.consume_dirty()` — kernel polls this to redraw after sys state changes

---

## 6) Hardware wrappers (`prism.hal`)

This module wraps Monocle hardware modules defensively:

- `hal.battery_level() -> int|None`
- `hal.is_charging() -> bool|None`
- `hal.prevent_sleep(enable=None) -> value|None`
- `hal.force_sleep() -> bool`
- `hal.reset() -> bool`

LED:
- `hal.led_red(on: bool) -> bool`
- `hal.led_green(on: bool) -> bool`

Bluetooth:
- `hal.bt_max_length() -> int|None`

Camera:
- `hal.camera_capture() -> bool`
- `hal.iter_camera_bytes(chunk_bytes=254)` yields bytes until None

Microphone:
- `hal.mic_record(seconds=..., sample_rate=..., bit_depth=...) -> bool`
- `hal.iter_mic_bytes(samples=127)` yields bytes until None
- Manufacturer firmware returns signed PCM samples. The host converts 8 kHz / signed 8-bit mic bytes to signed 16-bit WAV before transcription.

Timing:
- `hal.ticks_ms()`
- `hal.sleep_ms(ms)`

---

## 7) Media helpers (`prism.media`)

Convenience functions combining `hal` + `bridge`:

- `media.send_camera_capture_stream(...) -> msg_id`
- `media.send_mic_record_stream(...) -> msg_id`
- `media.send_log_text(text, ...) -> msg_id`

---

## 8) Semantic JSON Schemas

Semantic envelopes and app state structures are specified in:
- `Documentation/data_scheme.md`

---

## Persistence (`prism.store`, `prism.config`)

### `prism.store`
Small helpers for bounded file IO:
- `store.read_text(path, max_bytes=4096) -> str|None`
- `store.write_text(path, text) -> bool`
- `store.load_json(path, default=None, max_bytes=4096) -> any`
- `store.save_json(path, obj) -> bool` (tmp + rename when possible)

### `prism.config`
System config file:
- file: `pm_config.json`
- `config.load() -> dict` (sanitized)
- `config.save(cfg) -> bool`

Known keys:
- `orbit_sel` (int)
- `brightness` (int 0..4)
