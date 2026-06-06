# PrismOS Host-First Architecture (iOS Companion)
**Scope:** Host app modules that receive Monocle streams, run AI/app logic, compose display frames, and return results.

For physical BLE commands, recovery procedure, and 2026-05-26 hardware evidence, see `Documentation/MONOCLE_RECOVERY_RUNBOOK.md`.

## Architecture Rule: Monocle Is External Hardware

PrismOS is now host-first:

- Monocle is a BLE-connected peripheral with display, touch pads, camera, microphone, boot safety, and bounded rendering.
- The Host owns app execution, app switching, memory, retrieval, AI calls, navigation, timers, translation, summarization, image analysis, and display layout.
- The runtime display contract is binary `DRAW`: compact Host-composed primitives sent as protocol kind `0x05`.
- Legacy per-app `STATE` payloads remain Host-internal app data shapes and test fixtures, but normal Monocle runtime must not depend on importing `monocle/apps/*.py`.

This preserves Monocle RAM for the current receive buffer and screen presentation rather than spending it on app modules and app state.

**Implementation plan:** See `Documentation/IOS_APP_ARCHITECTURE_PLAN.md` for the native iOS Host architecture and `Documentation/APPLE_WATCH_APP_ARCHITECTURE_PLAN.md` for the active Series 3-first Apple Watch architecture. `Documentation/IOS_WATCHOS_ARCHITECTURE_PLAN.md` remains broader reference where it does not conflict with those current plans.

## BLE Services & Characteristic Directions (Canonical)

Monocle exposes two BLE services relevant to PrismOS:

### 1) Raw Data Service (binary + PrismOS control channel)
Use this for PrismOS control messages and for raw streams (audio/images).

- Service UUID: `e5700001-7bac-429a-b4ce-57ff900f479d`
- RX Characteristic UUID: `e5700002-7bac-429a-b4ce-57ff900f479d`  (Write / Write Without Response)  **Host → Monocle**
- TX Characteristic UUID: `e5700003-7bac-429a-b4ce-57ff900f479d`  (Notify)  **Monocle → Host**

**Host rule:** write outbound bytes to **RX**, subscribe to notifications on **TX**.

### 2) Serial Service (REPL only)
Use this only for REPL/console-style text transport, not for PrismOS runtime messaging.

- Service UUID: `6e400001-b5a3-f393-e0a9-e50e24dcca9e`
- RX Characteristic UUID: `6e400002-b5a3-f393-e0a9-e50e24dcca9e` (Write) **Host → Monocle**
- TX Characteristic UUID: `6e400003-b5a3-f393-e0a9-e50e24dcca9e` (Notify) **Monocle → Host**

## Core Modules Breakdown

### BLEManager (Bluetooth Communication Service)
*   **Role:** Centralizes BLE connectivity and data exchange with Monocle.
*   **Connection & Scanning:** Runtime connections should use a stored/explicit device identity after an intentional scan/selection step. Development tools refuse to auto-select by name unless `--allow-scan` is passed, because a broken or spare Monocle may still advertise nearby.
*   **macOS Development Path:** Physical BLE tests from this repo must be launched through `tools/macos_ble_launch.py` so CoreBluetooth runs inside `Python.app`. Direct `python3` Bleak calls can abort before exceptions are printed.
*   **Service Setup:** Discovers the Raw Data service, enables notifications on the **TX** characteristic, and holds a reference to **RX** for writes.
*   **Outbound:** Host writes to **Raw Data RX** (`e5700002-7bac-429a-b4ce-57ff900f479d`).
*   **Inbound:** Host subscribes/receives on **Raw Data TX** (`e5700003-7bac-429a-b4ce-57ff900f479d`).
*   **Data Reception:** Buffers chunked payloads received over the Raw Data TX notifications and reassembles message boundaries according to PrismOS protocol documents. Flags missing/out-of-order chunks.
*   Implements frame parsing using the 13-byte header with FLAGS (START/END) as defined in `Documentation/PROTOCOL.md`.
*   For binary `DRAW`, uses TOTAL_LEN to allocate and reassemble a single bounded payload buffer.
*   For stream kinds (`STREAM_AUDIO`, `STREAM_IMAGE`), supports TOTAL_LEN = `0xFFFFFFFF`, reassembles by appending fragments until END, enforces per-kind byte ceilings, and drops incomplete streams after timeout.
*   **Data Transmission:** Formats outgoing messages, splits long payloads to MTU, and uses Write w/ or w/o Response appropriately while pacing writes to avoid flooding.
*   **Monitoring & Recovery:** Tracks connection state, leverages CoreBluetooth State Preservation/Restoration, and retries connections transparently. Handles low-level error signaling to higher layers.
*   **Throughput Tuning:** Requests 2M PHY, Data Length Extension (251-byte MTU), and short connection intervals (≈15–30ms) to maximize data rate within iOS limits; can apply simple flow control when needed.

### AudioStreamHandler (Voice Capture & Processing)
*   **Role:** Owns the audio pipeline from BLE packets to transcription-ready buffers.
*   **Buffering:** Collects framed audio payloads (KIND `STREAM_AUDIO`) into an audio buffer (8 kHz, signed 8-bit PCM mono from Monocle) and reformats it for the transcription engine.
*   **Noise Mitigation (Optional):** Can apply light filtering/voice isolation via AVAudioEngine or DSP helpers.
*   **Transcription Trigger:** When a complete audio payload is received (or incrementally), invokes STT (Whisper API or on-device). Supports batch mode (MVP default) with room for streaming mode later.
*   **Output:** Emits recognized text (and metadata/raw audio if needed) to downstream modules.

### AIClient (AI Engine and Assistant Logic)
*   **Role:** Routes user queries to AI and returns concise answers.
*   **Query Handling:** Accepts text (from voice or image flows) and chooses the right path (chat, vision, other APIs).
*   **OpenAI Call:** Builds a brief system prompt, calls the configured OpenAI API via HTTPS, and awaits the response.
*   **Response Processing:** Cleans/truncates output to meet length/clarity goals; can hand off to a Summarizer module if too verbose.
*   **Vision/Alternates:** Optionally invokes image captioning or other services (VisionProcessor) for image queries.
*   **Resilience:** Detects network/API failures, retries when appropriate, or returns a fallback (“No internet”, etc.) using a shared ErrorHandler; keeps logic off the main thread.

### StateCoordinator (App State Coordinator & Workflow Manager)
*   **Role:** Orchestrates the end-to-end pipeline and global state machine (Idle → Listening → Processing → Responding).
*   **State Machine:** Ensures only one query runs at a time; prevents overlap if new audio payloads arrive mid-cycle.
*   **Event Orchestration:** Reacts to module signals (e.g., BLEManager start/end, AudioStreamHandler transcription done, AIClient reply ready) and advances the workflow; routes responses to DisplayController/BLEManager.
*   **Timeouts/Watchdog:** Defines time limits for stages (e.g., missing expected payload completion or slow AI responses) and resets gracefully to Idle with user-friendly feedback when needed.
*   **User Feedback:** Can inject interim cues (e.g., “...thinking...”) or LED/UI indicators during long operations.
*   **Global Error Handling:** Works with ErrorHandler to map internal faults to recoveries or user messages, keeping the app stable after failures.

### DisplayComposer (Host-Owned Monocle Layout)
*   **Role:** Converts Host app state into bounded binary `DRAW` packets.
*   **Text Packing:** Wraps and ranks content for the 640×400 native-font display, targeting about 26 characters per row and five non-overlapping content rows plus header/footer.
*   **Pagination:** Keeps long answers, recall cards, transcripts, and translations on the Host; sends only the current viewport to Monocle.
*   **Optional Shapes:** Shape primitives remain host-gated and hardware-risky. The current memory-safe Monocle kernel parses line/rectangle/fill records to preserve frame alignment but does not render them; text-only rendering is the live hardware default until shape rendering is validated one primitive type at a time.
*   **Image Results:** Image capture, analysis, scaling, and raster/vector simplification run on the Host. If a visual result needs display, the Host sends a compact text summary or a capped rectangle/line primitive representation, not raw image processing logic.
*   **Input Feedback:** Consumes `BTN` events including `ts` and `dur` to implement app-specific controls, repeat behavior, and gesture confidence without changing Monocle firmware.

### HostAppSuite (Host-Owned Apps)
The desktop harness now models the intended iOS architecture with `host/prism_apps.py`:

- `OracleApp`: visual-first assistant states backed by `host/prism_services.py`, Monocle mic capture (`CAPTURE_AUDIO`), host transcription, host prompt sources (`PRISM_ORACLE_PROMPT`, prompt file, clipboard), OpenAI Responses API when configured, answer paging, follow-up, and clipboard copy.
- `VisionApp`: identify/OCR mode, Host -> Monocle `CAPTURE_IMAGE` command, Monocle JPEG byte stream, host capture persistence, OpenAI vision analysis when configured, result paging, and Oracle follow-up.
- `StreamApp` / `SIGNAL`: host-curated cards loaded from `PRISM_STREAM_FILE` or defaults, privacy mode, dismiss, and host clipboard handoff.
- `ChronosApp`: host-sovereign timer, setup/running/alarm states, configurable default seconds, pinning, tick updates, and zero-clamped alarm stop.
- `TeleprompterApp`: manual and auto-scroll script engine with WPM control, bookmark/reset, and host script loading from `PRISM_TELEPROMPTER_FILE`.
- `BabelApp`: host translation action, Monocle mic capture (`CAPTURE_AUDIO`), text-source fallback (`PRISM_BABEL_TEXT`, text file, clipboard), OpenAI transcription/translation when configured, freeze/resume, clear, and language swap.

`NavigateApp` and `RecallApp` remain in source as archived prototypes, but they are removed from the active carousel. Navigate is too interaction-heavy for the current display/input constraints. Recall needs a real memory/conversation substrate before it belongs in the live suite.

Each app exposes `on_enter`, `on_button`, `on_tick`, `widget`, and `render`. `render` returns only bounded `DRAW.items`, which the Host packs to binary before BLE transmission; app state never moves to Monocle.

Current iOS boundary note from `AIUX-004` on 2026-05-28:

- `RuntimeEffect.sendOrbitDrawNow` represents orbit display updates explicitly, so returning to Orbit no longer masquerades as an Oracle app draw request.
- `MonocleControlNotificationDecoder` accepts the canonical thin-kernel uplink shape (`event: "BTN"` / `event: "MEDIA"`) and legacy `type` packets.
- `host/tests/thin_kernel_test.py` now asserts `monocle/kernel.py` does not import `apps.*` or `prism.app`, preserving the thin host-first runtime entrypoint.

Current physical Monocle boundary after the 2026-05-31 Safe Mode repair:

- The live recovery-safe `kernel.py` keeps DRAW, button events, charging-case sleep, host-disconnect `WAIT HOST`, and five-minute wait-host sleep.
- Camera/audio capture is deferred in the physical kernel to stay within the Monocle memory budget; `CAPTURE_IMAGE` and `CAPTURE_AUDIO` return explicit `MEDIA ERROR` events instead of importing `camera` or `microphone`.
- Re-enable media capture only one path at a time after physical boot verification and recovery-runbook review.

Current active app UX pass:

- Oracle prioritizes voice ask on `Tap R`, silent host prompt fallback on `Hold R`, host-backed answers, explicit follow-up context, pinning, copying, and page-aware reading.
- Vision separates target, camera command, upload, analysis, result, abort, OCR copy, and Oracle follow-up flows.
- Signal ranks cards by priority, supports privacy masking, dismissal, and handoff acknowledgement.
- Chronos supports both timer and stopwatch modes, host-owned ticking, alarm dismissal, adjustment, pinning, and safe stop at zero.
- Teleprompter supports manual and automatic pacing, WPM adjustment, progress, and bookmark/reset behavior.
- Babel supports mic-triggered audio transcription/translation on `Tap R`, host text translation fallback on `Double R`, freeze/resume, rolling transcript, clear, and language swap.

### PrismServices (Desktop Host Provider Layer)

`host/prism_services.py` is the current desktop provider layer. It uses only the Python standard library and keeps tests offline-safe:

- Loads optional `.env` from `PRISM_ENV_FILE`.
- Uses `OPENAI_API_KEY` plus optional `PRISM_OPENAI_MODEL`, `PRISM_OPENAI_VISION_MODEL`, `PRISM_OPENAI_TRANSLATE_MODEL`, and `PRISM_OPENAI_TRANSCRIBE_MODEL`.
- Defaults text, vision, and translation to `gpt-5.5` with low reasoning effort / low verbosity for a latency-sensitive HUD; all model choices are environment-overridable.
- Calls OpenAI Responses for Oracle, Vision, and translation when configured.
- Calls OpenAI Audio Transcriptions for Monocle 8 kHz signed 8-bit PCM audio after converting it to signed 16-bit WAV.
- Falls back to explicit offline text instead of blocking app rendering when no provider is configured.
- Reads host prompt/script/card/text sources from env, host data files, or macOS clipboard.
- Protects app state with per-request IDs so stale provider results cannot reappear after a user cancels, clears, or starts a newer request.
- Vision applies a Host-side capture timeout and handles Monocle `MEDIA IMAGE ERROR/START/END` status events.
- Oracle and Babel apply Host-side audio capture timeouts and handle Monocle `MEDIA AUDIO ERROR/START/END` status events.
- Persists practical app artifacts as JSONL in `host/data/`: `oracle_history.jsonl`, `vision_notes.jsonl`, and `babel_transcripts.jsonl`.

The desktop host accepts runtime options:

```bash
python3 tools/macos_ble_launch.py --timeout 330 host/prism_host.py \
  --address <MONOCLE_UUID> \
  --env-file /path/to/.env \
  --data-dir host/data \
  --capture-dir host/captures
```

For a no-hardware app/render smoke test:

```bash
python3 host/prism_host.py --dry-run
```

This is not the final iOS implementation. It is a real desktop host bridge that proves the app contracts and provider calls while preserving the same Host-owned architecture the iOS companion should implement.

## StreamEngine (v1)

Purpose:
Provide the data needed for the STREAM app without assuming access to global iOS notifications.

This module is a logical grouping (implementation may be split across files), consisting of:

### EventIngest
Responsibilities:
- Collect events ONLY from sources the Host is permitted to access:
  - Prism-owned notifications (push/local notifications from the Prism app)
  - Explicit user-authorized sources (calendar/reminder-like)
  - Explicit integrations (future)

Non-responsibilities:
- Must not assume it can read system notifications from other apps.

### StreamFilter
Responsibilities:
- Apply user preferences:
  - source allow/deny
  - priority allow/deny
  - quiet hours
  - privacy mode defaults

### StreamNormalizer
Responsibilities:
- Convert raw events into compact STREAM cards:
  - source code
  - title/body (2 lines)
  - priority
  - optional handoff target

### HandoffDispatcher
Responsibilities:
- On `BTN` gesture `LONG_R` while STREAM is active:
  - If current card has a handoff target, open it on the Host
  - Otherwise no-op

See `Documentation/STREAM_FEASIBILITY_AND_SCOPE.md` for constraints and future ANCS notes.
