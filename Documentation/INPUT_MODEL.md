> Current production implementation (28 October 2026): [Adaptive Shell](ADAPTIVE_SHELL_IMPLEMENTATION.md) and its [verification receipt](ADAPTIVE_SHELL_VERIFICATION.md) supersede the app-launcher/developer-console paths below. Retained designs describe reference capabilities and historical architecture, not current qualification.

# PrismOS Input Model (Canonical)

## A. Physical Mapping
* **L (Left)** = physical left pad = `touch.B`
* **R (Right)** = physical right pad = `touch.A`
* Simultaneous press of both pads is unreliable and **not supported** for app UX.

## B. Gesture Definitions (canonical timings)

Canonical timing constants:
- Debounce: 30ms
- Long press threshold: 800ms
- Double-tap window: 300ms

Gesture semantics (as implemented by `prism/inputscan.InputScanner`):
- TAP:
  - recognized on press+release that does NOT reach LONG threshold
  - emitted only after the DOUBLE window expires without a second tap (to disambiguate single vs double)
- DOUBLE:
  - two TAPs on the same side within the DOUBLE window
  - emitted immediately on the second release
- LONG:
  - emitted while the pad is still held once it reaches LONG threshold
  - cancels any pending TAP/DOUBLE sequence

## C. OS Behavior by State
**Orbit Mode**
* `TAP_L`: Previous app
* `TAP_R`: Next app
* `LONG_R`: Enter selected app
* `LONG_L`: System menu / sleep (future settings)
* `DOUBLE_R`: Oracle quick-launch (reserved)

**Focus Mode**
* `LONG_L`: Exit to Orbit (**OS intercepts**)
* `DOUBLE_R`: Oracle quick-launch overlay (**OS intercepts**)
* All other gestures are delivered to the active app.

## D. App Allowance Table
* **Allowed to apps:** `TAP_L`, `TAP_R`, `LONG_R`, `DOUBLE_L`
* **Reserved by OS:** `LONG_L` (Exit), `DOUBLE_R` (Oracle quick-launch)

## E. Gesture Matrix (OS vs Apps)

| Gesture | Orbit Mode | Focus Mode | Delivered to Apps |
| :--- | :--- | :--- | :--- |
| `TAP_L` | Previous app | Passed through | Yes |
| `TAP_R` | Next app | Passed through | Yes |
| `LONG_R` | Enter selected app | Passed through | Yes |
| `LONG_L` | System menu / sleep | Exit to Orbit (intercepted) | No |
| `DOUBLE_L` | (No OS action) | Passed through | Yes |
| `DOUBLE_R` | Oracle quick-launch (reserved) | Oracle quick-launch overlay (reserved) | No |
