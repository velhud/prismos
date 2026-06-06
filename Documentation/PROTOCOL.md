# PrismOS Wire Protocol (v1)

This document defines how PrismOS payloads are framed into bytes for transport over BLE.
It does NOT define the semantic JSON schemas for apps; those live in `Documentation/data_scheme.md`.

For physical recovery commands and hardware-tested transport pitfalls, see `Documentation/MONOCLE_RECOVERY_RUNBOOK.md`.

---

## Transport

PrismOS uses the **Raw Data Service** UUIDs:

- Service: `e5700001-7bac-429a-b4ce-57ff900f479d`
- RX (Write): `e5700002-7bac-429a-b4ce-57ff900f479d`  Host → Monocle
- TX (Notify): `e5700003-7bac-429a-b4ce-57ff900f479d`  Monocle → Host

All PrismOS traffic is sent as a sequence of **frames**. Each BLE write/notify contains exactly **one frame**.

---

## Frame Header (fixed 13 bytes)

Each frame begins with a 13-byte header:

| Offset | Size | Field | Type | Notes |
|---:|---:|---|---|---|
| 0 | 2 | MAGIC | bytes | ASCII `PM` (0x50 0x4D) |
| 2 | 1 | VERSION | u8 | v1 = `1` |
| 3 | 1 | KIND | u8 | message kind (see below) |
| 4 | 1 | FLAGS | u8 | chunk flags (START/END) |
| 5 | 2 | MSG_ID | u16 LE | increments per message |
| 7 | 2 | SEQ | u16 LE | chunk index starting at 0 |
| 9 | 4 | TOTAL_LEN | u32 LE | total payload bytes if known, else UNKNOWN sentinel |

After the header comes `PAYLOAD_FRAGMENT` (0..N bytes).

The maximum payload fragment size is:
`MAX_FRAGMENT = BLE_MAX_LENGTH - 13`

`BLE_MAX_LENGTH` is the negotiated maximum raw payload size; on-device it is available via `bluetooth.max_length()`.

## Flags (FLAGS)

FLAGS is a bitmask:

- `START` = 0x01
- `END`   = 0x02

Meanings:

- START|END: single-frame message
- START only: first frame of a multi-frame message
- END only: last frame of a multi-frame message
- 0: middle frame

---

## Kinds (KIND values)

KIND identifies what the payload bytes represent.

| KIND | Name | Payload |
|---:|---|---|
| 0x01 | CTRL_JSON | UTF-8 JSON bytes (minified). Used for Monocle → Host `BTN`/`MEDIA` events and small Host → Monocle hardware commands. |
| 0x02 | STREAM_AUDIO | raw audio bytes (format defined by higher-level design) |
| 0x03 | STREAM_IMAGE | raw image bytes (e.g., JPEG) |
| 0x04 | LOG_TEXT | UTF-8 plain text (optional; debugging/telemetry) |
| 0x05 | DRAW | Host → Monocle binary display payload |

`DRAW` is the preferred Host → Monocle rendering path. It avoids JSON parsing and large text buffers on the device.

UNKNOWN TOTAL_LEN sentinel: use `0xFFFFFFFF` when the sender does not know the full payload length up-front.

---

## Message Reassembly Rules (receiver)

Receiver groups frames by `(KIND, MSG_ID)`.

## Device inbound constraints (Monocle)

The device-side implementation is intentionally conservative to protect RAM and avoid boot loops:

- Host → device `DRAW` must use a concrete `TOTAL_LEN` (not `0xFFFFFFFF`).
- `DRAW TOTAL_LEN` must be ≤ **1536 bytes**.
- Host → device `CTRL_JSON` must be small and concrete length; current firmware accepts ≤ **384 bytes**.
- Device reassembly supports **one in-flight message** at a time; host must not interleave frames from different `(KIND, MSG_ID)` messages.
- If constraints are violated (unknown length, oversized, unexpected sequence), the device drops/resets reassembly for that message.

### DRAW (known length)
- TOTAL_LEN must be a concrete length.
- Receiver allocates a buffer sized TOTAL_LEN on START (or on START|END).
- Receiver copies fragments in SEQ order.
- Receiver completes message when END is received and the written size equals TOTAL_LEN.

Hardware implementation note:

- On the target Monocle MicroPython build, `bytearray[start:end] = fragment` raises `TypeError`.
- Device-side frame assembly must copy bytes element-by element, as in `monocle/kernel.py::copy_into(...)`.
- Host-side Python can use normal bytes operations; this restriction is for on-device MicroPython code.

Binary DRAW payload v1:

| Offset | Size | Field | Notes |
|---:|---:|---|---|
| 0 | 1 | DRAW_VERSION | `1` |
| 1 | 1 | FLAGS | bit 0 = optional shapes present |
| 2 | 1 | APP_LEN | app id byte length, max 16 |
| 3 | 1 | ITEM_COUNT | max 12 |
| 4 | APP_LEN | APP | ASCII app id |
| ... | variable | ITEMS | repeated item records |

Text item record:

| Size | Field | Notes |
|---:|---|---|
| 1 | KIND | `1` = text |
| 2 | X | u16 LE |
| 2 | Y | u16 LE |
| 4 | COLOR | u32 LE RGB |
| 1 | ANCHOR | 0 MC, 1 TL, 2 TC, 3 TR, 4 ML, 5 MR, 6 BL, 7 BC, 8 BR |
| 1 | TEXT_LEN | max 32 |
| TEXT_LEN | TEXT | ASCII/UTF-8 text |

### Stream kinds (unknown length allowed)
For `STREAM_AUDIO` and `STREAM_IMAGE`, TOTAL_LEN may be unknown.
- When TOTAL_LEN is unknown, receiver must not require a pre-sized buffer.
- Receiver may append fragments until END is received.
- The Host receiver enforces stream byte ceilings and incomplete-stream timeouts before dispatching payloads to app logic.

---

## JSON Encoding Rules (CTRL_JSON)

- UTF-8
- Minified JSON (no whitespace required)
- Current live use:
  - Monocle → Host `BTN` button events.
  - Monocle → Host `MEDIA` status events (`IMAGE START/END/ERROR`, `AUDIO START/END/ERROR`).
  - Host → Monocle hardware commands that do not belong in `DRAW`.
- Keys and enums in the repository docs are canonical; abbreviations are allowed only if explicitly documented later.

### Host → Monocle hardware command: `CAPTURE_IMAGE`

The Host sends a small `CTRL_JSON` payload:

```json
{"type":"MEDIA","cmd":"CAPTURE_IMAGE","app":"vision"}
```

Product target: the thin Monocle kernel captures one JPEG frame through the camera module and streams it back as `STREAM_IMAGE` (`KIND 0x03`) with `TOTAL_LEN = 0xFFFFFFFF`. The device does not analyze, crop, OCR, or classify the image. It only uses the camera hardware and BLE transport; all interpretation happens on the Host.

Current physical boundary after the 2026-05-31 Safe Mode repair: the recovery-safe kernel returns a `CTRL_JSON` `MEDIA` error with detail `camera deferred` instead of importing `camera`. Re-enable image streaming only after a dedicated physical memory/boot verification pass.

### Host → Monocle hardware command: `CAPTURE_AUDIO`

The Host sends a small `CTRL_JSON` payload:

```json
{"type":"MEDIA","cmd":"CAPTURE_AUDIO","app":"oracle","seconds":4.0,"sample_rate":8000,"bit_depth":8}
```

Product target: the thin Monocle kernel records a short microphone buffer using the official `microphone.record(seconds=4.0, sample_rate=8000, bit_depth=8)` API, waits briefly for the FPGA buffer, then streams bytes back as `STREAM_AUDIO` (`KIND 0x02`) with `TOTAL_LEN = 0xFFFFFFFF`. Monocle microphone 8-bit samples are signed PCM. The Host converts them to transcription-ready WAV and owns ASR, LLM answering, translation, persistence, and display composition.

Current physical boundary after the 2026-05-31 Safe Mode repair: the recovery-safe kernel returns a `CTRL_JSON` `MEDIA` error with detail `audio deferred` instead of importing `microphone`. Re-enable audio streaming only after a dedicated physical memory/boot verification pass.

---

## Example (CTRL_JSON)

A button message becomes:
- payload bytes: `b'{"event":"BTN","id":"R","gesture":"TAP","app":"oracle","ts":123,"dur":80}'`
- framed into one or more v1 frames depending on maximum fragment size.
