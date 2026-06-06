# App Specification: CHRONOS
**Internal ID:** `chronos`
**Role:** The Temporal Interface
**Metaphor:** "The Doomsday Clock" / "The Visual Pacer"

---

## 1. Core Concept & Philosophy
CHRONOS visualizes the passage of time.

Checking a wristwatch requires a physical action (raising the wrist). Checking a phone requires disengagement. CHRONOS places time directly into the user's peripheral vision.

It is designed for **Flow State** maintenance. Whether a user is holding a plank position, timing a steak on the grill, or managing a strict 5-minute presentation, CHRONOS provides constant, passive awareness of time remaining without requiring the user to break focus.

**Key Feature:** It heavily utilizes **Ghost Pinning**. A timer is rarely the *only* thing a user wants to see; it is usually a secondary data point supporting a primary task.

---

## 2. User Experience (The Flow)

### Phase A: The Setup (Input)
*   **Method 1 (Manual):** User opens CHRONOS. Taps buttons to increment minutes/seconds.
*   **Method 2 (Voice - Recommended):** User activates ORACLE and says "Set a timer for 5 minutes." Oracle hands the intent to CHRONOS, which auto-launches in a running state.
*   **Method 3 (Context):** User selects a preset from the Host App (e.g., "Pomodoro", "Steak Medium-Rare").

### Phase B: The Countdown (Active)
*   **The Visual:** A large digital counter dominates the screen.
*   **The Graphic:** A **Progress Ring** or **Bar** shrinks visually. This allows the user to judge "halfway there" without reading the numbers.
*   **The Pin:** User holds **Right** to **Pin** the timer. The app minimizes to the Global HUD. The user returns to Orbit or opens another app (e.g., Teleprompter).

### Phase C: The Alarm (Completion)
*   **Trigger:** Timer hits `00:00`.
*   **Visual:**
    *   **If Active:** The screen flashes Inverted (White/Black) at 2Hz.
    *   **If Pinned:** The Ghost Widget expands and pulses.
*   **Haptic:** The Host Phone vibrates (since Monocle has no vibration motor).
*   **Action:** User Taps any button to dismiss.

---

## 3. User Interface (Visual Design)

The UI is bold and urgent. It prioritizes readability over style.

### The Layout Grid
*   **Zone A (HUD):** Standard System Status.
*   **Zone B (The Clock Face):** Center screen.
*   **Zone C (Controls):** Bottom hints.

### Visual Elements

#### 1. The Digital Counter
*   **Font:** `IBM Plex Mono` (Tabular figures to prevent jitter).
*   **Size:** Massive (80px height).
*   **Format:** `MM:SS` (e.g., `04:59`).
*   **Behavior:** If < 1 minute, switches to `SS.ms` (e.g., `59.9`) for precision.

#### 2. The Progress Arc
*   **Style:** A thick white circle surrounding the numbers.
*   **Behavior:** It un-draws itself counter-clockwise as time passes.
*   **Why:** Peripheral vision detects shape change better than reading text.

#### 3. The Stopwatch Mode
*   **Style:** Counts UP.
*   **Visual:** The Progress Arc fills up (looping every 60s).

#### 4. The Ghost Widget (Pinned View)
*   **Location:** Top Right (Zone A).
*   **Content:** `[ T-04:59 ]` (Timer) or `[ SW 01:22 ]` (Stopwatch).
*   **Priority:** Overrides the Battery icon if space is tight.

---

## 4. Interaction Logic & Controls

**System Exit: Hold Left (OS reserved, not listed below).**

| Input | State: Setup (Paused) | State: Running | State: Alarm (Ringing) |
| :--- | :--- | :--- | :--- |
| **Tap Left** | -1 minute | Toggle Ghost Pin | Dismiss |
| **Tap Right** | +1 minute | Toggle Ghost Pin | Dismiss |
| **Hold Right** | Start | Pause/Resume | Dismiss |
| **Double Left** | Reset to 0 | Stop & Reset | (No action) |

---

## 5. Host-Side Intelligence (The "Brain")

The iOS App manages the **Timekeeper Module**.

### The State Sovereignty
*   **The Problem:** If the Monocle battery dies or the app crashes, the timer must not be lost.
*   **The Solution:** The Timer runs on the **Phone**.
    *   The Phone sends a `SYNC_TIME` packet to Monocle every second (or Monocle calculates locally and syncs every 10s to correct drift).
    *   If Monocle disconnects, the Phone will ring its own alarm when the timer finishes.

Current desktop Host implementation:
- Default timer length comes from `PRISM_CHRONOS_SECONDS`, falling back to 300 seconds.
- Timer state is owned by the Host app engine.
- Countdown clamps at zero and stops running, so the display stays in a stable `ALARM` state instead of drifting into negative time.
- Stopwatch remains count-up and loops its progress bar every minute.

### The "Smart Extend"
*   **Logic:** If the timer ends (`00:00`) and the user does not dismiss it within 10 seconds, the system automatically switches to **Overtime Mode**.
*   **Visual:** The counter starts counting *UP* in negative numbers (`-00:01`, `-00:02`) and turns Red (if color supported) or blinks.
*   **Use Case:** Cooking. Knowing *how long* you burned the steak is valuable info.

---

## 6. Use Case Examples

**The Public Speaker:**
*   *Scenario:* User has a strict 10-minute slot.
*   *Action:* User sets 10m Timer. Pins it. Opens **Teleprompter**.
*   *Experience:* User reads speech. In the top corner, they see `T-02:00`. They know to wrap up. At `T-00:00`, the corner pulses silently. User finishes exactly on time.

**The Athlete (HIIT):**
*   *Scenario:* User is doing interval sprints.
*   *Action:* User sets Stopwatch.
*   *Experience:* User runs. Glances up to see `00:45`. Sprints harder. Hits `01:00`. Stops. No fumbling with a wrist-watch while running.

**The Chemist / Barista:**
*   *Scenario:* User is brewing pour-over coffee or developing film. Hands are wet/busy.
*   *Action:* "Oracle, set timer for 3 minutes."
*   *Experience:* Timer starts. User focuses on the pour. The visual countdown ensures precision without touching a device.

---

## 7. PrismOS Watch Control Surface

The PrismOS Watch deck mirrors CHRONOS through WatchConnectivity and keeps the iPhone Host authoritative for timer truth.

*   **Timer ownership:** The Watch does not own the timer engine. It renders the latest host snapshot and a local estimate when host data is stale or unreachable.
*   **Controls:** The Watch deck exposes start, pause/resume, reset, dismiss alarm, timer/stopwatch mode, pin/unpin, preset selection, and add-time actions as thin commands to the Host.
*   **Alarm feedback:** When Chronos reaches alarm state, the host publishes a stable alarm acknowledgement so repeated refreshes do not retrigger the same haptic event.
