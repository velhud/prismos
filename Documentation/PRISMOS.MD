> Current production implementation (28 October 2026): [Adaptive Shell](ADAPTIVE_SHELL_IMPLEMENTATION.md) and its [verification receipt](ADAPTIVE_SHELL_VERIFICATION.md) supersede the app-launcher/developer-console paths below. Retained designs describe reference capabilities and historical architecture, not current qualification.


# PrismOS: System Definition

## 1. Core Philosophy: "Orbit & Focus"
PrismOS is not a multitasking OS (like iOS/Windows) where apps run in the background. It is a **Unikernel State Machine**.
*   **Orbit Mode (The Shell):** The user is "orbiting" their apps. The OS controls the inputs. The screen shows the App Carousel.
*   **Focus Mode (The App):** The user has "landed" inside an app. The App controls the inputs. The OS retreats to a passive background service (handling BLE/Battery only).

---

## 2. Visual Architecture (The Screen Layout)

The 640x400 display is divided into two strict zones. This prevents apps from overlapping critical system info.

### Zone A: The HUD (Heads-Up Dashboard)
*   **Height:** Top 48 pixels (one font row: `display.FONT_HEIGHT`).
*   **Persistence:** Always visible (unless an app explicitly requests "Immersive Mode").
*   **Content:**
    *   **Left:** Current Time (e.g., `14:05`).
    *   **Center:** Current Context Label (e.g., `HOME`, `NAV`, `AI`).
    *   **Right:** System Status Icons (BLE Connected/Disconnected, Battery %).
*   **Rendering:** Handled exclusively by the Kernel. Apps cannot draw here.

### Zone B: The Viewport
*   **Height:** Remaining 352 pixels (`400 - 48 = 352px`).
*   **Content:** The active "Lens" (App).
*   **Rendering:** The active app has full drawing authority here via FPGA primitives.

**ASCII Mockup:**
```text
[ 14:05 |   NAVIGATION   | (B) [|||] ]  <-- HUD (Zone A)
--------------------------------------  <-- Separator Line
                                     
          [  ^  ]                    
          [  |  ]                    
          [ 50m ]                    
                                     
       Turn Right on                 
       Broadway Ave                  
                                     
--------------------------------------  <-- Viewport (Zone B)
```

---

## 3. The Input Model (The "Hold-to-Confirm" System)

Due to hardware limitations preventing simultaneous button presses, PrismOS uses time-based gestures to distinguish between Navigation and Selection. The canonical mappings live in `Documentation/INPUT_MODEL.md` and use **Left/Right (L/R)** naming consistently: `TAP_L`, `TAP_R`, `LONG_R`, `DOUBLE_L` are delivered to apps; **`LONG_L` (Exit) and `DOUBLE_R` (Oracle quick-launch)** are OS-reserved and never bound by apps. App input handlers will never receive `LONG_L`.

Physical mapping:
* Left pad = physical left pad = `touch.B` = side `L`
* Right pad = physical right pad = `touch.A` = side `R`

Event names (canonical set):
* `TAP_L`, `TAP_R`
* `LONG_L`, `LONG_R`
* `DOUBLE_L`, `DOUBLE_R`

### Gesture Vocabulary & OS Reservations
* Delivered to apps: `TAP_L`, `TAP_R`, `LONG_R`, `DOUBLE_L`
* Reserved globally: `LONG_L` (Exit), `DOUBLE_R` (Oracle quick-launch overlay)

### State 1: Orbit Mode (The Carousel)
*   **Tap Left:** Rotate Carousel Left (Previous App).
*   **Tap Right:** Rotate Carousel Right (Next App).
*   **Hold Right (LONG_R):** **ENTER APP** (Switch to Focus Mode).
    *   *Visual:* The Label changes to `[ ENTERING... ]`.
*   **Hold Left (LONG_L):** Trigger System Settings / Sleep.

### State 2: Focus Mode (In-App)
*   **Tap Left / Tap Right:** Passed directly to the Active App (Context-specific actions).
*   **Hold Right (LONG_R):** Passed to App (Context-specific secondary action, e.g., "Pin").
*   **Hold Left (LONG_L):** **EXIT APP** (Return to Orbit Mode; intercepted by OS, not delivered to app).
    *   *Priority:* The OS intercepts this gesture. Apps cannot override the Exit command.

---

## 4. The Kernel Architecture (Technical Implementation)

This is how we solve the 64KB RAM limit. We cannot keep apps in memory. We use a **Hot-Swap** architecture.

### 4.1. The `Kernel` Class
This is the `main.py` that never dies.

### App Registry (Repository Baseline)
The repository stores the app registry as canonical constants in `prism/ids.py`:

- `ids.APPS` — list of `(app_id, label, module_path)`
- `ids.APP_IDS` — allowed APP_ID values

The kernel imports these values and uses them for orbit rendering and app loading.

1.  **Loader:**
    *   When switching apps, the Kernel performs a **Garbage Collection (GC) Purge**.
    *   It unloads the current module: `del sys.modules['current_app']`.
    *   It runs `gc.collect()` to free RAM.
    *   It imports the app module (e.g., `apps/oracle.py`) and calls `create()` to construct a `BaseApp` instance.
    *   It calls `on_start()`, then renders via `render()` and presents via `display.show(...)` (kernel-owned).
2.  **Watchdog:** Wraps the app execution in a `try/except` block. If an app crashes, the Kernel catches the error, displays a "Crash Dump" for 3 seconds, and reboots into Orbit Mode.

### 4.2. The `App` Interface (API)
Every app must adhere to this strict template to work with PrismOS.

```python
class BaseApp:
    def __init__(self):
        # Allocation-only
        pass

    def on_start(self):
        # Called once when app becomes active
        return False

    def on_update(self, now_ms):
        # Called frequently; return True to request redraw
        return False

    def on_input(self, event):
        # Canonical input event string (e.g., TAP_L, LONG_R)
        return False

    def on_data(self, payload):
        # Decoded "data" from inbound CTRL_JSON envelopes
        return False

    def render(self):
        # Return display objects; apps must not call display.show() directly
        return []

    def on_exit(self):
        # Cleanup before unload
        pass
```

---

## 5. Hardware Abstraction Layer (HAL)

The OS must protect the hardware from the apps.

### 5.1. FPGA Management
The FPGA is power-hungry. The OS manages it based on the active Lens.
*   **Default:** FPGA Graphics Mode ON, Camera OFF, Mic OFF.
*   **Vision App:** Requests `FPGA_CAMERA_MODE`. OS grants it.
*   **Voice App:** Requests `FPGA_MIC_MODE`. OS grants it.
*   **Sleep:** When the OS detects inactivity (e.g., 60s), it overrides the App, shuts down the FPGA, and turns off the Display.

### 5.2. Display Burn-in Protection
OLEDs burn in.
*   **Pixel Shift:** The OS Kernel shifts the entire viewport by 1-2 pixels in random directions every minute.
*   **Auto-Dim:** Auto-dim sets `display.brightness(1)` after 15s inactivity (runtime-only) and restores configured brightness on input.

---

## 6. Summary of the "Basic OS"

You asked for the definition of the Basic OS. Here it is:

**PrismOS is a single-tasking, hot-swapping window manager.**
1.  **Visuals:** It enforces a persistent **HUD** for system status.
2.  **Navigation:** It uses an **Orbit/Focus** state machine to overload the two buttons for both system navigation and app interaction.
3.  **Memory:** It uses a **Load/Unload** cycle to allow an unlimited number of apps to exist on storage, despite only 64KB of RAM.
4.  **Safety:** It acts as a **Watchdog** that catches app crashes and manages hardware power states automatically.
