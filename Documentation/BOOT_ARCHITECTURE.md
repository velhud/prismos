# PrismOS Boot Architecture (The Sanctuary)

For physical recovery commands and hardware-tested failure signatures, see `Documentation/MONOCLE_RECOVERY_RUNBOOK.md`.
For the current recovery risk audit and guarantee boundaries, see `Documentation/SAFE_MODE_RECOVERY_AUDIT_2026_05_31.md`.

## 1. Philosophy
To prevent "Soft-Bricking," we separate the **Bootstrap** from the **Kernel**.
*   **`main.py`:** The first reliable user entrypoint on the Brilliant Monocle firmware. It applies the 1.5s grace period, maintains the boot-loop counter, and calls `kernel.start()` under a global try/except.
*   **`boot.py`:** A best-effort compatibility hook only. The official Monocle firmware source auto-runs `main.py`; PrismOS must not rely on `boot.py` for recovery.
*   **`kernel.py`:** The OS logic (apps, input, BLE routing). It clears the boot-loop counter only after a stable delay.

## 2. The Boot Sequence (User Perspective)
Reliable execution order: **1) vendor firmware → 2) `main.py` → 3) `kernel.py`** (loaded by `main.py`).

1.  **Power On:** User removes device from case.
2.  **Wake:** User taps touch pad once. Red LED lights up.
3.  **Grace Period:** System waits 1.5s (ignoring inputs) to allow user to release the wake tap.
4.  **Decision (Manual Safe Mode):** If a compatible firmware runs `boot.py`, a continuous **Left** (`touch.B`) hold writes `pm_safe_request.txt`. `main.py` then displays Safe Mode and returns to the vendor REPL.
5.  **Normal Boot:** `main.py` bumps the boot-loop counter (`pm_boot_count.txt`) and starts `kernel.py`.

## 3. Safe Mode Behavior
If Safe Mode is triggered (Manually or via Kernel Crash):
1.  **Display:** `boot.py` is display-free; `main.py` may show "SAFE MODE" and a short reason string.
2.  **Bluetooth:** Preserves the vendor Monocle REPL/NUS advertisement. PrismOS must not replace the advertising payload with unverified low-level BLE calls.
3.  **CPU:** Returns from `main.py` so the vendor firmware can enter the built-in Bluetooth REPL. Safe Mode must not trap forever inside user Python code.

## 3.1 Guarantee Boundary
This architecture protects the normal development failure path: a bad or too-large `kernel.py`, repeated runtime crashes, and display errors inside Safe Mode. It does not protect a `main.py` that is syntactically invalid, loops before the guard runs, imports heavy modules before the guard, or exhausts memory before Safe Mode can execute.

For that reason, `main.py` and `boot.py` are sanctuary files. Normal app/runtime behavior belongs in `kernel.py` or Host code.

## 4. Recovery Protocol
If you break `kernel.py` and the device crashes loop:
1.  Reboot the Monocle.
2.  Connect via VS Code / REPL to the known-good Monocle identity after `SAFE MODE` appears. If more than one Monocle can advertise nearby, scan first and use the explicit address/UUID rather than name-based auto-selection.
3.  On macOS, run BLE recovery through `tools/macos_ble_launch.py`; direct Python CoreBluetooth can abort.
4.  Upload the minimum fixed files first, normally `kernel.py`, `main.py`, and `boot.py`.
5.  Clear `pm_boot_count.txt` and stale `pm_safe_request.txt` before reset. `tools/monocle_ble.py deploy` does this automatically.

## 5. Hardware-Tested Crash Signature
If the device reaches `PRISM OS WAIT HOST`, host connects, but the screen does not update, inspect Raw Data reassembly before blaming the host. On 2026-05-26, the verified root cause was:

```text
TypeError: 'bytearray' object doesn't support item assignment
```

The Monocle MicroPython build rejected bytearray slice assignment. Device BLE reassembly must use explicit byte-copy loops.


## Adaptive shell boundary

The 28 October 2026 adaptive shell changes runtime transport/media handling in `monocle/kernel.py`. It does not modify `main.py`, `boot.py`, vendor REPL recovery or the owner's physical recovery process. There was no physical deployment in the Linux implementation assignment. See [implementation and qualification](ADAPTIVE_SHELL_IMPLEMENTATION.md).
