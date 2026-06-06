# PrismOS Data Schema (v1.0)
**Format:** Host-side semantic models; runtime Host → Monocle DRAW is binary
**Transport:** BLE Raw Data Service (`e570...` RX / TX Characteristics)
**Encoding:** Monocle → Host events use minified JSON; Host → Monocle screen updates use binary DRAW

## BLE Service UUIDs (Raw Data Service)

| Name | UUID | Properties | Direction |
| :--- | :--- | :--- | :--- |
| **Raw Data Service** | `e5700001-7bac-429a-b4ce-57ff900f479d` | Service | N/A |
| **RX Characteristic** | `e5700002-7bac-429a-b4ce-57ff900f479d` | Write / Write w/o Resp | **Phone → Monocle** |
| **TX Characteristic** | `e5700003-7bac-429a-b4ce-57ff900f479d` | Notify | **Monocle → Phone** |

## Framing (Byte Transport)
This document defines PrismOS semantic structures only.

The byte-level framing used to transport these JSON payloads over BLE is defined in:
- `Documentation/PROTOCOL.md`

Runtime screen updates are packed as KIND `DRAW` frames. Monocle → Host button events are transported as KIND `CTRL_JSON` frames.

**Direction rule:** The Host writes PrismOS payload bytes to the **RX characteristic** and receives Monocle payload bytes via **TX notifications**.

---

## Host-Rendered Device Model

Current PrismOS runtime treats Monocle as external hardware:

- The Host owns app state, app switching, ranking, summarization, layout, image analysis, navigation, timers, memory, and all expensive processing.
- The Monocle owns only hardware I/O: display rendering, touch gesture detection, camera/audio capture streams, BLE framing, boot safety, and RAM protection.
- Host app output is represented as `DRAW.items` containing bounded display primitives, then packed into binary DRAW frames. Legacy `STATE` schemas remain useful as app-domain data contracts on the Host, but the device runtime does not load per-app Python modules for normal operation.

This lets the device spend its limited RAM on one larger receive buffer and the richest current screen, rather than importing app code and keeping app-local state.

## Size budgets and truncation (device-side)

The Monocle is RAM-constrained. The device enforces hard limits and will drop or truncate to protect stability:

- **Host → device binary `DRAW` must be known-length and ≤ 1536 bytes** total (`TOTAL_LEN`, per `Documentation/PROTOCOL.md`).
- The device accepts Host → device `DRAW.items` lists with at most **12** primitives per screen.
- `DRAW` text primitives are clamped to at most **32** chars each; the Host should normally fit around **26** native-font characters per row.
- Shape primitives are optional and are used only when the Host sets `"shapes": true`; keep this off until line/rectangle rendering has been verified on the target firmware.
- The legacy app-state sanitizer clamps inbound envelopes and strings:
  - `SYS/WIDGETS` values: ≤ **24** chars
  - `GHOST.text`: ≤ **48** chars, `GHOST.icon`: ≤ **6** chars
  - `ERR.msg`: ≤ **64** chars (`ERR` is displayed as a short-lived toast, not a sticky overlay)
- Avoid large arrays/objects in a single update (e.g., don’t send huge `RECALL.lines` or long histories in one payload).
- App renderers are currently “text-first”; keep fields like `STREAM.card.title/body` short enough to fit the display without wrapping surprises.

If a message is unsupported or malformed, the device may ignore it. If a string is too long, it may be truncated.

## 1. The Envelope (Root Structure)

## Canonical Identifiers
All identifiers used in this file are canonicalized in:
- `Documentation/IDENTIFIERS.md`

In particular:
- `"type"` must be one of: `SYS`, `STATE`, `GHOST`, `ERR`
- `"app"` must be one of the APP_ID values listed in `Documentation/IDENTIFIERS.md`

Legacy Host-internal state payloads follow this structure. They are not parsed by the current device runtime.

### Host → Monocle (Downlink)
```json
{
  "type": "STATE",      // Enum: STATE, GHOST, SYS, ERR
  "app": "oracle",      // Target App ID (optional if SYS)
  "data": { ... }       // The Payload (Schema varies by App)
}
```

### Monocle → Host (Uplink)
```json
{
  "event": "BTN",       // Repository baseline emits BTN and FOCUS (others reserved)
  "id": "L",            // L or R (physical side)
  "gesture": "TAP",     // TAP | LONG | DOUBLE
  "app": "oracle",      // Active app id
  "ts": 123456,         // monotonic ms (ticks_ms) for debugging
  "dur": 92             // press duration in ms when available
}
```
Repository baseline:
- Uplink emits `event: "BTN"` and `event: "FOCUS"` packets.
- `ts` is always included (monotonic milliseconds from `time.ticks_ms()`).
- `dur` is included by the thin hardware client for richer Host-side input interpretation.
* `id` is always the physical side: `L` (touch.B) or `R` (touch.A). No `BOTH`.
* `gesture` is `TAP`, `LONG`, or `DOUBLE`; Monocle does not emit unsupported combos.
* `LONG_L` is interpreted as Exit (OS), `DOUBLE_R` is reserved for Oracle quick-launch.
* On-device event names are defined in `prism/input.py`; the uplink envelope uses `event_parts(...)` mapping.

### Monocle → Host: Focus change (`event: "FOCUS"`)

```json
{
  "event": "FOCUS",
  "mode": "FOCUS",      // "FOCUS" when entering an app, "ORBIT" when leaving to Orbit
  "app": "vision",      // current focused app id, or null in ORBIT
  "prev": "oracle",     // previous focused app id, or null
  "ts": 123456          // monotonic ms (time.ticks_ms)
}
```

---

## 2. System Messages (`type: SYS`)

These handle the "Orbit" logic, app switching, and hardware status.

### A. App Switch (Historical Host -> Monocle)
This JSON shape is retained for legacy state documentation. The live host-first runtime does not ask the Monocle to load app modules; it sends binary `DRAW` frames with the selected app id.
```json
{
  "type": "SYS",
  "cmd": "FOCUS",
  "app": "oracle"
}
```
*Historical action:* Older kernels purged RAM, loaded `apps/<id>.py`, and initialized a device renderer. Current action: Host updates its focused app and sends bounded `DRAW` items.

### B. Live Orbit Update (Host -> Monocle)
Sent periodically to update the widgets in the Carousel menu.
```json
{
  "type": "SYS",
  "cmd": "WIDGETS",
  "data": {
    "chronos": "04:59",
    "oracle": "AI READY",
    "stream": "3 New"
  }
}
```
*Action:* Kernel updates the text labels in the Orbit menu without loading the full apps.

### C. Time Sync (Host -> Monocle)
Sets the device wall-clock time used by the HUD.

```json
{
  "type": "SYS",
  "cmd": "TIME",
  "data": {
    "epoch": 1734300000,
    "tz": "+03:00"
  }
}
```

Notes:

* `epoch` is Unix epoch seconds.
* `tz` is optional. If present, it is passed to the device `time.zone(...)` API (string like `"+03:00"` or `"-06:30"`).

## 2.5. Host-Rendered Screen (`type: DRAW`)

`DRAW` is the preferred Host → Monocle display contract. The Host app model still represents screens as the JSON-like `items` structure below, but runtime transport packs it into protocol kind `0x05` binary DRAW so Monocle does not parse JSON.

```json
{
  "type": "DRAW",
  "app": "oracle",
  "shapes": false,
  "items": [
    { "k": "t", "v": "ORACLE", "x": 320, "y": 4, "c": 16777215, "a": "TC", "n": 26 },
    { "k": "t", "v": "Host owns context", "x": 320, "y": 140, "c": 16777215, "a": "MC", "n": 26 }
  ]
}
```

Primitive keys:

| `k` | Meaning | Notes |
|---|---|---|
| `t` | Text | Uses `display.Text(..., justify=display.MIDDLE_CENTER)` only. `a` is a manual anchor (`TL`, `TC`, `TR`, `ML`, `MC`, `MR`, `BL`, `BC`, `BR`). |
| `l` | Line | Optional shape; ignored unless `shapes=true`. |
| `r` | Rectangle | Optional shape; ignored unless `shapes=true`. |
| `f` | Full-screen fill | Optional shape; ignored unless `shapes=true`. |

The Host must pre-wrap, summarize, paginate, rank, and choose what appears on screen. The Monocle does not infer app meaning from `DRAW`.

For picture-like output, the Host must downsample/simplify the visual into a capped set of `r`/`l` primitives or a text summary before sending. The Monocle must not do image scaling, object recognition, or layout analysis.

Host apps should follow the runtime contract implemented by `host/prism_apps.py`: app engines consume `BTN` events, update Host-side state, and render a fresh complete `DRAW` viewport. The Host may keep arbitrarily rich internal state, but each sent viewport must fit the 1536-byte binary transport budget and 12-primitive device renderer budget. Text rows must be spaced to avoid Brilliant firmware `TextOverlapError`.

---

## 3. App-Specific Schemas (`type: STATE`)

When an app is active (Focus Mode), the Host sends these packets to update the screen. The App Renderer simply draws what it receives.

### 1. ORACLE (AI Assistant)
```json
{
  "type": "STATE",
  "app": "oracle",
  "data": {
    "mode": "THINKING",      // LISTENING, THINKING, ANSWER
    "audio_level": 0.8,      // 0.0 - 1.0 (For waveform animation)
    "text": "The melting point of Tungsten is 3,422°C.",
    "is_final": false        // true = done generating, false = streaming
  }
}
```

### 2. VISION (Camera)
```json
{
  "type": "STATE",
  "app": "vision",
  "data": {
    "status": "SCANNING",    // READY, CAPTURING, SCANNING, RESULT
    "progress": 45,          // 0-100 (For progress bar)
    "result_header": "FICUS ELASTICA",
    "result_body": "Rubber Fig. Native to SE Asia."
  }
}
```

### 3. NAVIGATE (Maps, archived prototype)
```json
{
  "type": "STATE",
  "app": "navigate",
  "data": {
    "icon": "ARROW_RIGHT",   // ARROW_LEFT, ARROW_STRAIGHT, FLAG, U_TURN
    "distance": "50m",
    "street": "Broadway Ave",
    "alert": false           // true = blink the screen (turn imminent)
  }
}
```

### 4. TELEPROMPTER (Script)
```json
{
  "type": "STATE",
  "app": "teleprompter",
  "data": {
    "prev_line": "Welcome everyone,",
    "curr_line": "THANK YOU FOR COMING.",  // Highlighted line
    "next_line": "We have a lot to discuss.",
    "wpm": 140,
    "is_playing": true
  }
}
```

**STREAM (Event Stack)**
```json
{
  "type": "STATE",
  "app": "stream",
  "data": {
    "count": 3,
    "index": 0,
    "privacy": false,
    "card": {
      "id": "evt_1734300000_001",
      "source": "CAL",
      "title": "MEETING",
      "body": "10 MIN JOHN",
      "prio": "IMPORTANT",
      "handoff": {
        "kind": "URL",
        "value": "opaque_or_url_like_string"
      }
    }
  }
}
```

Field notes:

* `count`: number of pending cards in the stack
* `index`: which card is currently being shown (0 = newest/top)
* `privacy`: host-controlled privacy mode flag; when true, host should obfuscate `title/body`
* `card.id`: stable until dismissed
* `source`: one of `CAL | REM | PRISM | SYS | EXT`
* `prio`: one of `INFO | IMPORTANT | CRITICAL`
* `handoff` is optional:

  * if missing or `{ "kind": "NONE" }`, device gesture `LONG_R` is a no-op

### 6. CHRONOS (Timer)
```json
{
  "type": "STATE",
  "app": "chronos",
  "data": {
    "mode": "TIMER",         // TIMER, STOPWATCH
    "time": "04:59",
    "progress": 0.75,        // 0.0 - 1.0 (For drawing the arc)
    "alarm": false           // true = flash screen
  }
}
```

### 7. BABEL (Live Translation Subtitles)
```json
{
  "type": "STATE",
  "app": "babel",
  "data": {
    "src": "JA",
    "dst": "EN",
    "paused": false,
    "audio_level": 0.7,
    "lines": [
      { "text": "…incoming transcription…", "kind": "RAW" },
      { "text": "Final translated sentence.", "kind": "FINAL" }
    ],
    "msg": ""
  }
}
```

Field notes:

* `src` / `dst`: BCP-47-ish short codes (e.g., EN, JA, DE). Exact set is host-defined.
* `paused`: when true, UI should show a paused indicator and stop scrolling.
* `audio_level`: 0.0–1.0 for an on-device meter.
* `lines`: newest-last list of subtitle lines to render. `kind` is one of:

  * `RAW` (tentative transcription)
  * `FINAL` (final translation)
  * `SYS` (system message line)
* `msg`: optional short status string (e.g., "OFFLINE", "REROUTING", etc.)

### 8. RECALL (Deck/Card Reference, archived prototype)
```json
{
  "type": "STATE",
  "app": "recall",
  "data": {
    "view": "DECKS",
    "deck_title": "GROCERIES",
    "deck_index": 0,
    "deck_count": 4,
    "card_index": 0,
    "card_count": 12,
    "mode": "NOTE",
    "cursor": 0,
    "lines": [
      "[ ] Milk",
      "[x] Bread",
      "[ ] Eggs"
    ]
  }
}
```

Field notes:

* `view`: `DECKS` or `CARD`
* `deck_title`: current deck name (or empty string in DECKS overview)
* `deck_index/deck_count`: navigation metadata
* `card_index/card_count`: navigation metadata for the current deck (0-based index)
* `mode`: `NOTE` or `CHECKLIST`
* `cursor`: selected line index for CHECKLIST mode (ignored for NOTE mode)
* `lines`: device-renderable text lines (already formatted to fit display)

---

## 4. The Ghost Protocol (`type: GHOST`)

This is the multitasking channel. These packets are processed by the Kernel *regardless* of which app is running.

### Host -> Monocle
```json
{
  "type": "GHOST",
  "active": true,            // true = show ghost slot, false = hide
  "icon": "NAV",
  "text": "-> 50m",
  "flash": false             // true = flash the ghost line (urgent)
}
```
Field notes:
- `icon` is an optional short text token (e.g., `NAV`, `TMR`, `AI`). The repository UI is text-first; icon is rendered as a prefix to `text`.
- `flash=true` causes the ghost line to alternate visibility at a fixed cadence (repository constant).
*Action:* The Kernel draws this data in the top-right corner of the HUD (Zone A), overlaying whatever the active app is drawing.

---

## 5. Error & Status Codes (`type: ERR`)

Used for global system alerts (Toast Notifications).

```json
{
  "type": "ERR",
  "code": "NO_NET",          // NO_NET, API_FAIL, BLE_DROP
  "msg": "Phone Offline"     // Human readable text for the Toast
}
```

---

## 6. Implementation Strategy

### Why Binary DRAW?
*   **Pros:** Smaller device heap footprint, no MicroPython JSON parser on the live screen path, deterministic bounds.
*   **Cons:** Less human-readable than JSON.
*   **Mitigation:** Host apps still render JSON-like `DRAW.items` in Python/Swift; only the final BLE payload is binary-packed.

### State Synchronization Logic
1.  **Idempotency:** The Host sends the *full state* every time it changes.
2.  **No Deltas:** We do not send `{"diff": "+1"}`. We send `{"count": 5}`. This prevents the Monocle from getting "out of sync" if a packet is dropped.
3.  **Heartbeat:** If the Monocle receives no packets for 5 seconds, it assumes disconnection and enters "Offline UI" mode automatically.

---

**Do you approve of this Data Schema?** If yes, we will move to the final step: **The Boot & Pairing Sequence.**
