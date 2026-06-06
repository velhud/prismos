# App Specification: TELEPROMPTER
**Internal ID:** `teleprompter`
**Role:** The Presentation Interface
**Metaphor:** "The Invisible Cue Card" / "The Anchor's Desk"

---

## 1. Core Concept & Philosophy
TELEPROMPTER solves the "Eye Contact Problem." Whether giving a speech, recording a video, or interviewing a candidate, looking down at notes destroys connection.

This app projects the script directly onto the user's lens. The text is focused at infinity, allowing the user to read while appearing to look directly at their audience or camera. It transforms the user into a "Cyborg Orator"—perfectly articulate, with perfect recall, and zero distraction.

**Key Constraint:** Reading text on a transparent display requires careful contrast management. The UI must guide the eye to the specific line being spoken, rather than flooding the vision with a wall of text.

---

## 2. User Experience (The Flow)

### Phase A: The Setup (Sync)
*   **Authoring:** The user writes or pastes the script into the **Prism iOS App**.
*   **Formatting:** The Host App automatically breaks the text into "Visual Chunks" (short lines of 3-5 words) to prevent eye scanning fatigue.
*   **Sync:** When the user opens TELEPROMPTER on Monocle, the Host pushes the active script to the device's RAM.

### Phase B: The Performance (Reading)
*   **The Stance:** The user stands naturally.
*   **The Scroll:**
    *   **Manual Mode:** The user taps their thigh (where their hand rests near the phone) or the device to advance.
    *   **Auto Mode:** The text flows automatically at a set WPM (Words Per Minute).
    *   **Voice Mode (Pro):** The text advances automatically as the user speaks it (Karaoke style).
*   **The Focus:** The user reads only the **Active Line** (Bright White). The surrounding lines are dimmed to provide context without distraction.

### Phase C: The Adjustment (On-the-Fly)
*   **Speed Correction:** If the user stumbles, they can pause or rewind instantly using the touch pads.
*   **Reset:** A specific gesture jumps back to the top of the script.

---

## 3. User Interface (Visual Design)

The UI mimics a professional broadcast teleprompter but adapted for a monocular display.

### The Layout Grid
*   **Zone A (HUD):** Hidden by default (Immersive Mode) to reduce clutter. Can be toggled.
*   **Zone B (The Scroll Deck):** The entire 400px height is used for text.
*   **Zone C (The Pacer):** A thin progress bar at the very bottom.

### Visual Elements

#### 1. The Focus Bar (The "Highlighter")
*   **Location:** Vertically centered (Pixel 200).
*   **Style:** A subtle, transparent white box (10% opacity) spanning the width.
*   **Text:** The text inside this box is **Pure White (100%)** and **Bold**.
*   **Function:** This tells the user: "Say this now."

#### 2. The Context Lines
*   **Above:** 2 lines of text. **Dimmed (40% opacity)**. This shows what was just said.
*   **Below:** 2 lines of text. **Dimmed (40% opacity)**. This shows what is coming next.
*   **Why:** Peripheral vision needs context to prevent the user from sounding robotic.

#### 3. The Pacer Widget
*   **Location:** Bottom Right Corner.
*   **Content:**
    *   **Manual:** Shows `MANUAL`.
    *   **Auto:** Shows Speed (e.g., `140 WPM`).
    *   **Voice:** Shows a Microphone Icon.
*   **Progress Bar:** A 1px line at the bottom of the screen showing how much of the speech remains.

---

## 4. Interaction Logic & Controls

**System Exit: Hold Left (OS reserved, not listed below).**

| Input | State: Manual Mode | State: Auto Mode |
| :--- | :--- | :--- |
| **Tap Left** | Scroll Up (rewind 1 line) | Decrease Speed (-10 WPM) |
| **Tap Right** | Scroll Down (next line) | Increase Speed (+10 WPM) |
| **Hold Right** | Toggle Auto Scroll | Pause → Manual |
| **Double Left** | Reset to Top | Reset to Top |

---

## 5. Host-Side Intelligence (The "Brain")

The iOS App provides the **Script Engine**.

### The "Voice Tracking" Engine (Killer Feature)
This is the advanced mode that makes the app feel magical.
1.  **Listening:** The Phone (Host) listens to the user's voice via its own mic (or Monocle's mic stream).
2.  **Matching:** It uses a lightweight ASR (Speech Recognition) to match the spoken words against the script text.
3.  **Syncing:**
    *   If the user says the word at the end of the current line, the Host sends a `SCROLL_DOWN` command.
    *   If the user stops speaking (ad-libbing), the scrolling stops.
    *   If the user skips a paragraph, the system detects the jump and "Fast Forwards" the display to match.

### The Formatter
The Host pre-processes the text before sending:
*   **Chunking:** Splits long sentences into readable phrases.
    *   *Input:* "We are gathered here today to celebrate a great achievement."
    *   *Output:*
        *   "We are gathered here today"
        *   "to celebrate"
        *   "a great achievement."
*   **Encoding:** Converts special characters to ASCII equivalents if the Monocle font is limited.

### Current Desktop Host Implementation

- Script source: `PRISM_TELEPROMPTER_FILE` or `host/data/teleprompter.txt`.
- Long script lines are wrapped into Monocle-width chunks before rendering, so real paragraphs do not get silently clipped.
- `Tap L/R` moves line-by-line in manual mode.
- `Hold R` toggles automatic pacing.
- `Double L` bookmarks the current position; pressing it again at the bookmark reloads the script and returns to the start.

### Current iOS PrismOS Implementation

- The Sessions tab provides a script title field and script body editor, so the user can paste or type the actual text they want prompted.
- `Load Script` imports that body into Monocle-width chunks and preserves the selected WPM.
- The WPM stepper controls auto-scroll speed.
- `Previous` and `Next` move line-by-line in manual mode.
- `Toggle Auto Scroll` switches between manual and timed pacing.
- `Bookmark` marks the current line, and `Start Over` returns to the first chunk.
- Voice-follow alignment remains deferred until a reliable ASR/script alignment design is implemented.

---

## 6. Use Case Examples

**The YouTuber / Content Creator:**
*   *Scenario:* Recording a video review of a product.
*   *Action:* User looks at the camera lens. Monocle displays the talking points.
*   *Result:* User delivers a flawless take without looking down at notes or memorizing the script.

**The Job Interview:**
*   *Scenario:* User is in a Zoom interview.
*   *Action:* User loads their "STAR Method" answers and questions for the interviewer into Recall/Teleprompter.
*   *Result:* User references specific project metrics ("I increased ROI by 14% in Q3") confidently while maintaining eye contact with the webcam.

**The Best Man Speech:**
*   *Scenario:* User is giving a toast at a wedding.
*   *Action:* User sets mode to **Manual**.
*   *Result:* User holds a drink in one hand, taps the device (or thigh if phone is in pocket) to advance lines, and delivers a heartfelt speech without fumbling with index cards.
