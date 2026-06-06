# PrismOS System Manifest
**Date:** 2025-12-07
**Status:** Bootable / Safe Mode Active

## Repo ↔ Device mapping (important)

In this repository, **`monocle/` is the on-device filesystem root** (`/`).

Examples:
- `monocle/main.py` becomes `/main.py` on device
- `monocle/kernel.py` becomes `/kernel.py`
- `monocle/apps/` becomes `/apps/`
- `monocle/prism/` becomes `/prism/`

## Repository File Structure (mirrors device `/`)
1. **`monocle/main.py`** - The reliable Monocle user entrypoint (grace period, boot-loop counter, kernel load, crash catch, Safe Mode return-to-REPL).
2. **`monocle/boot.py`** - Best-effort compatibility hook only; official Monocle firmware source guarantees `main.py`, not `boot.py`.
3. **`monocle/pm_boot_count.txt`** - Persistent boot-loop counter used by `main.py` and cleared by `kernel.py` after a stable delay.
4. **`monocle/pm_config.json`** - system config (JSON), managed by `monocle/prism/config.py`
5. **`monocle/kernel.py`** - Thin hardware client (binary DRAW renderer, input scan, framed Raw Data routing, small host hardware commands such as Vision image capture).
6. **`monocle/apps/__init__.py`** - Package marker for MicroPython.
7. **`monocle/apps/stub.py`** - Legacy repository-standard placeholder app implementation.
8. **`monocle/apps/oracle.py`** - Legacy device-side ORACLE module; not used by the live host-first runtime.
9. **`monocle/apps/vision.py`** - Legacy device-side VISION module; not used by the live host-first runtime.
10. **`monocle/apps/navigate.py`** - Archived NAVIGATE prototype; not active.
11. **`monocle/apps/stream.py`** - Legacy device-side STREAM module; not used by the live host-first runtime.
12. **`monocle/apps/chronos.py`** - Legacy device-side CHRONOS module; not used by the live host-first runtime.
13. **`monocle/apps/teleprompter.py`** - Legacy device-side TELEPROMPTER module; not used by the live host-first runtime.
14. **`monocle/apps/recall.py`** - Archived RECALL prototype; not active.
15. **`monocle/apps/babel.py`** - Legacy device-side BABEL module; not used by the live host-first runtime.
16. **`monocle/prism/__init__.py`** - Prism package root (minimal).
17. **`monocle/prism/ids.py`** - Canonical ID constants used by kernel and apps.
18. **`monocle/prism/app.py`** - Base application interface (`BaseApp`).
19. **`monocle/prism/ui.py`** - text-first UI (anchor-based), uses only `display.MIDDLE_CENTER` justify
20. **`monocle/prism/input.py`** - Canonical input event names + `event_parts(...)` helper.
21. **`monocle/prism/inputscan.py`** - Polling `InputScanner` (tap/long/double).
22. **`monocle/prism/protocol.py`** - Wire protocol constants + header helpers.
23. **`monocle/prism/bridge.py`** - Framing send/receive utilities for Raw Data Service.
24. **`monocle/prism/schema.py`** - CTRL_JSON schema validation + sanitization (bounds strings and commands).
25. **`monocle/prism/sys.py`** - device-local signaling (exit/toast/ghost)
26. **`monocle/prism/hal.py`** - hardware wrappers (device/led/camera/mic)
27. **`monocle/prism/media.py`** - convenience streaming helpers (bridge + kinds)
28. **`monocle/prism/store.py`** - bounded persistence helpers (text/JSON IO)
29. **`monocle/prism/config.py`** - system config (`pm_config.json`)

## Host runtime files
- **`host/prism_host.py`** - desktop BLE host runtime, explicit-address connection, app action scheduler, binary DRAW sender, `CAPTURE_IMAGE`/`CAPTURE_AUDIO` command sender, stream receiver.
- **`host/prism_apps.py`** - active Host-owned app state machines and renderers. Active carousel: `oracle`, `vision`, `stream`/`SIGNAL`, `chronos`, `teleprompter`, `babel`. `navigate` and `recall` are archived prototypes only.
- **`host/prism_services.py`** - desktop provider/data layer for prompt/script/card/text sources, capture persistence, clipboard, OpenAI Responses, OpenAI vision, translation, signed PCM conversion, and audio transcription.
- **`host/prism_display.py`** - bounded native-font layout helpers for Monocle DRAW items.
- **`host/data/`** - editable desktop data templates consumed by Oracle, Teleprompter, Signal, and Babel.

## Removed / Deleted Files
- `prism/prism_font.py` (deleted; native font used)

Wire protocol header is 13 bytes and includes FLAGS (START/END); stream kinds may use TOTAL_LEN = 0xFFFFFFFF.

## Documentation
- `Documentation/IDENTIFIERS.md` — canonical IDs for docs and protocol usage
- `Documentation/MONOCLE_RECOVERY_RUNBOOK.md` — mandatory physical Monocle recovery, BLE, and hardware-pitfall runbook

## Critical Parameters
*   **Boot Grace Period:** 1.5 Seconds (Hardcoded in `main.py` to handle Touch-to-Wake).
*   **Safe Mode Trigger:** automatic boot-loop counter; optional `pm_safe_request.txt` from compatibility `boot.py`.
*   **Safe Mode BLE Rule:** Preserve the vendor Monocle REPL/NUS advertiser; do not call unverified `bluetooth.BLE().gap_advertise(...)` from PrismOS recovery code.
*   **macOS BLE Rule:** Physical BLE commands must run through `tools/macos_ble_launch.py`, not direct `python3`, to avoid CoreBluetooth aborts.
*   **Device Identity Rule:** Use an explicit address/UUID for recovery and runtime; do not auto-connect by name around multiple Monocles.
*   **Bytearray Rule:** Device-side MicroPython must not use bytearray slice assignment; copy BLE fragments with explicit loops.
* **Text Justification Rule:** Repository code must use `justify=display.MIDDLE_CENTER` for all `display.Text(...)`. Manual anchoring is required; other justify modes must not be used in repository code.
*   **Display Alignment:** MUST use `justify=display.MIDDLE_CENTER` (or manual coords). `TOP_LEFT` causes crash.
