# App Specification: NAVIGATE
**Internal ID:** `navigate`
**Current status:** Archived prototype; removed from active desktop carousel.
**Role:** The Spatial Guidance Interface
**Metaphor:** "The Floating Arrow" / "The Compass of Destiny"

---

## Archive Note

Navigate is not part of the current active suite. The concept depends on reliable maps, location, route recalculation, safety policy, and glanceable turn semantics. In the present Monocle constraints, it is too complex to present honestly before a real mobile location/maps integration exists.

The source class remains in `host/prism_apps.py` only as an archived prototype reference. The active carousel excludes `navigate`.

## 1. Core Concept & Philosophy
NAVIGATE strips the concept of "Maps" down to its atomic unit: **The Next Step**.

Traditional map apps require cognitive load; the user must mentally translate a 2D top-down view into a 3D first-person reality. NAVIGATE removes this step. It projects the instruction directly into the user's field of view.

It is designed primarily for **Pedestrian** and **Cyclist** use cases, where hands-free operation is a safety requirement, not just a convenience. It relies heavily on the **Ghost Pinning** architecture, assuming the user will want to minimize the navigation while walking to look at other things.

---

## 2. User Experience (The Flow)

### Phase A: The Setup (Hand-Off)
*   **Input Method 1 (Phone):** User opens the Host App, types a destination, and hits "Start AR Nav."
*   **Input Method 2 (Oracle):** User activates ORACLE on Monocle and says, "Navigate to the nearest Starbucks." Oracle processes the intent and hands the payload to NAVIGATE.
*   **Initialization:** The NAVIGATE app launches. The Host calculates the route and pushes the first instruction.

### Phase B: The Journey (Guidance)
*   **The "Quiet" Protocol:** The app does not update constantly (like a GPS frame rate). It updates **discretely**.
    *   *State 1:* "Continue Straight for 200m." (Static display).
    *   *State 2:* User walks. Distance counter ticks down: `190m`... `180m`.
    *   *State 3:* Geofence Trigger (< 20m). The UI wakes up/pulses. The Arrow changes to "Turn Right."
*   **Off-Route Handling:** If the user misses a turn, the screen flashes `REROUTING...` and the Host calculates a new path.

### Phase C: The Arrival (Success)
*   **Trigger:** User is within 10m of the destination.
*   **Visual:** The Arrow turns into a **Target Icon** (Concentric circles) or a **Flag**.
*   **Text:** `ARRIVED: 123 BROADWAY`.
*   **Exit:** After 30 seconds of arrival, the app automatically closes to Orbit Mode.

---

## 3. User Interface (Visual Design)

The UI is bold and geometric. It must be readable instantly against moving pavement or busy street traffic.

### The Layout Grid
*   **Zone A (HUD):** Standard System Status.
*   **Zone B (The Signpost):** The central 300px area.
*   **Zone C (The Footer):** Street names and ETA.

### Visual Elements

#### 1. The Directional Glyph (The Arrow)
*   **Size:** Massive (150x150px). Centered.
*   **Style:** Thick, blocky lines. No curves unless necessary.
    *   `^` (Straight)
    *   `|>` (Turn Right)
    *   `<|` (Turn Left)
    *   `U` (U-Turn)
*   **Animation:**
    *   **Far (>50m):** Static.
    *   **Near (<20m):** The arrow blinks slowly (1Hz).
    *   **Immediate (<5m):** The arrow blinks fast (4Hz).

#### 2. The Distance Meter
*   **Location:** Directly below the Arrow.
*   **Typography:** Huge Font (48px).
*   **Format:** `250m` or `0.2km`.
*   **Dynamic:** Updates in real-time based on GPS delta.

#### 3. The Street Label
*   **Location:** Bottom of the screen (Zone C).
*   **Style:** Inverted Box (White background, Black text).
*   **Text:** The name of the *next* street (e.g., `ON: 5TH AVENUE`).

#### 4. The Ghost Widget (Minimized View)
When the user pins this app (see Interaction Logic), it shrinks to the Global HUD.
*   **Size:** 64x32px (Top Right Corner).
*   **Content:** A tiny arrow icon + distance. `[ -> 50m ]`.

---

## 4. Interaction Logic & Controls

**System Exit: Hold Left (OS reserved, not listed below).**

| Input | State: Active Navigation | State: Arrival |
| :--- | :--- | :--- |
| **Tap Left** | Toggle View (Simple ↔ Details) | Dismiss |
| **Tap Right** | Peek Next Step | Dismiss |
| **Hold Right** | Pin/Unpin Ghost Nav | Dismiss |
| **Double Left** | End Navigation (Cancel) | (No action) |

---

## 5. Host-Side Intelligence (The "Brain")

The iOS App manages the GPS and Routing via the **Navigation Module**.

### The Geofence Logic
To save battery and BLE bandwidth, the Monocle does not receive a stream of GPS coordinates. It receives **Triggers**.
1.  **Route Calculation:** The Phone calculates the path nodes.
2.  **Delta Tracking:** The Phone tracks the user's GPS position at 1Hz.
3.  **Push Logic:**
    *   Is the user > 50m from the next node? -> Do nothing (or update distance every 10s).
    *   Is the user < 20m from the next node? -> Send `BLE_NAV_UPDATE` (Change Arrow).
    *   Did the user deviate > 30m from path? -> Trigger Reroute.

### The "Compass" Fallback
If the user is standing still, GPS heading is unreliable.
*   **Logic:** The Host App uses the **Phone's Compass** (Magnetometer) to determine heading.
*   **Assumption:** The user is holding the phone or has it in a pocket aligned with their body.
*   **Correction:** If the user starts walking, the system switches to **GPS Bearing** (Vector based) which is more accurate.

### Audio Integration
*   **Voice Cues:** The Phone can optionally speak the directions ("Turn left") while the Monocle shows them.
*   **Sync:** The visual update on Monocle happens 500ms *before* the audio cue, giving the user time to process the visual before hearing the command.

---

## 6. Use Case Examples

**The Urban Commuter:**
*   *Scenario:* User exits a subway station in Tokyo.
*   *Action:* "Navigate to Ramen Jiro."
*   *Experience:* User puts phone in pocket. A large arrow points "Left." User walks. The distance counts down. User navigates complex intersections without looking like a tourist staring at a phone.

**The Cyclist:**
*   *Scenario:* User is biking. Hands are on handlebars.
*   *Action:* Navigation is active.
*   *Experience:* User keeps eyes on the road. The Monocle provides a peripheral cue for the next turn. Safety is maintained because the display is transparent and the UI is high-contrast (readable in sunlight).

**The Multitasker:**
*   *Scenario:* User is walking to a meeting while reading the agenda.
*   *Action:* User starts Navigation, then **Pins** it (Hold Right). User opens **Teleprompter** to read notes.
*   *Experience:* The main screen shows the meeting notes. The top-right corner shows `[ ^ 200m ]`. The user knows they are on the right path without stopping their reading.
