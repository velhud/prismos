
# App Specification: BABEL
**Internal ID:** `babel`
**Role:** The Live Translation Interface
**Metaphor:** "Reality Subtitles" / "The Universal Translator"

---

## 1. Core Concept & Philosophy
BABEL removes language barriers by projecting real-time subtitles onto the physical world.

Unlike a handheld translation app, BABEL allows the user to maintain **Eye Contact**. The user looks at the person speaking, not at a phone screen. The translation floats in the lower visual field, similar to movie subtitles.

**Key Constraint:** The Monocle has no speaker. Therefore, BABEL is primarily an **Input Tool** (Understanding others). For **Output** (Speaking to others), it relies on the Host Phone to act as the "Voice," or simply allows the user to speak naturally if the other party understands the user's language.

---

## 2. User Experience (The Flow)

### Phase A: The Setup (Pre-Flight)
*   **Configuration:** Language pairs (e.g., English <-> Japanese) are configured on the **Host App** (iOS). The Monocle simply loads the active pair.
*   **Entry:** User selects BABEL from the Orbit Carousel.
*   **State:** The Microphone (FPGA pipeline) activates. The BLE Audio Stream begins.

### Phase B: The Listening (Ingest)
*   **Visual Feedback:** To confirm the device is hearing the other person, a subtle **Audio Meter** (vertical bar) bounces on the right edge of the screen.
*   **Voice Activity Detection (VAD):** The Host filters out background noise. Translation only triggers when distinct speech is detected.

### Phase C: The Stream (Translation)
*   **Latency Management:** Translation is not instantaneous. There is a "lag" of 1-3 seconds.
*   **The "Ghost Text" Effect:**
    *   As the person speaks, the *raw transcription* (in the original language) appears briefly in gray text.
    *   As the translation engine confirms the meaning, the text **morphs** into the target language and turns **White**.
    *   *Why:* This fills the silence gap. Even if the user doesn't know the language, seeing the system recognize the sounds provides psychological reassurance that it is working.

### Phase D: The Scroll (Reading)
*   **Layout:** Text appears at the bottom and pushes upward.
*   **Capacity:** The screen holds ~4 lines of history. Old text fades out at the top.
*   **Pause:** If the user misses something, they can **Tap Left** to "Freeze" the stream. The buffer continues recording in the background, but the screen stops scrolling so the user can read.

---

## 3. User Interface (Visual Design)

The UI is designed to be unobtrusive. It must not block the user's view of the speaker's face.

### The Layout Grid
*   **Zone A (HUD):** Standard System Status (Dimmed).
*   **Zone B (Face Space):** The top 60% of the screen is kept mostly clear.
*   **Zone C (Subtitle Deck):** The bottom 40% (approx 160px height) is the active text area.

### Visual Elements

#### 1. The Subtitle Container
*   **Background:** A **Gradient Mesh** (Black to Transparent) rising from the bottom edge.
*   **Why:** Ensures white text is readable even if the user is looking at a white shirt or a bright window.

#### 2. The Text Stream
*   **Font:** `IBM Plex Sans` (Clean, readable).
*   **Size:** Medium (20px).
*   **Color Coding:**
    *   **White:** Finalized Translation.
    *   **Gray (Italic):** Tentative/Incoming Audio.
    *   **Yellow:** System Messages (e.g., `[ PAUSED ]`).
*   **Alignment:** Center-aligned (Cinematic style).

#### 3. The Language Indicator
*   **Location:** Top-Center (just below the HUD).
*   **Style:** Small, boxed text indicating flow.
    *   `[ JA ] >> [ EN ]` (Japanese to English).

#### 4. The Audio Meter
*   **Location:** Far Right Edge (Vertical).
*   **Style:** A thin 2px bar that grows/shrinks with volume.
*   **Color:** Green (Good Level) / Red (Clipping).

---

## 4. Interaction Logic & Controls

**System Exit: Hold Left (OS reserved, not listed below).**

| Input | State: Listening/Streaming | State: Frozen |
| :--- | :--- | :--- |
| **Tap Left** | Freeze stream | Resume (jump to now) |
| **Tap Right** | Clear history | (No action) |
| **Hold Right** | Swap language direction | (No action) |
| **Double Left** | Save transcript to Notes | Save transcript |

---

## 5. Host-Side Intelligence (The "Brain")

The iOS App manages the heavy audio processing via the **Babel Module**.

### The Pipeline
1.  **Ingest:** Receives 8kHz/16kHz audio chunks from Monocle.
2.  **Transcription (ASR):** Uses **OpenAI Whisper** (High Accuracy) or **Apple Speech** (Low Latency).
    *   *Optimization:* Uses "Streaming ASR" to send partial results immediately.
3.  **Translation:** Sends text to **DeepL API** or **Google Translate API**.
    *   *Context:* Sends the previous sentence as context to ensure gender/grammar continuity.
4.  **Formatting:** Breaks the result into "Subtitle Chunks" (max 40 chars per line) to fit the Monocle screen.

### The "Swap" Logic (Conversation Mode)
When the user holds Right to **Swap Languages** (e.g., switch from JA->EN to EN->JA):
1.  The Monocle UI updates the indicator: `[ EN ] >> [ JA ]`.
2.  The Host App switches the ASR target language.
3.  **The Output Problem:** Since Monocle has no speaker, how does the user "speak" Japanese?
    *   *Solution:* The Host App (Phone) automatically **Speaks** the translated text out loud using TTS (Text-to-Speech).
    *   *User Flow:* User speaks English -> Monocle shows English text -> Phone speaks Japanese.

### Error Handling
*   **Network Lag:** If translation takes > 3 seconds, the "Ghost Text" (Raw Transcription) stays on screen with a `...` animation.
*   **Unknown Language:** If confidence is low, the system displays `[ ??? ]`.

---

## State Payload Contract
Host sends `type: STATE`, `app: "babel"` messages as defined in `Documentation/data_scheme.md` (BABEL section).

## Current Desktop Host Implementation

The live desktop harness implements Babel as a host translation app with offline-safe provider behavior:

- `Tap R` starts Monocle microphone capture via the Host `CAPTURE_AUDIO` command. The Monocle streams signed 8-bit PCM; the Host transcribes it, translates it, and renders subtitle lines back as bounded `DRAW`.
- `Double R` translates host text from `PRISM_BABEL_TEXT`, `PRISM_BABEL_TEXT_FILE` / `host/data/babel_text.txt`, macOS clipboard, then a safe default phrase.
- If `OPENAI_API_KEY` is configured, the Host calls the OpenAI Responses API for translation.
- If a `STREAM_AUDIO` payload arrives, the Host converts Monocle 8 kHz signed 8-bit PCM to signed 16-bit WAV, transcribes it with OpenAI Audio Transcriptions when configured, then translates the transcript.
- If no provider is configured, Babel shows an explicit offline translation marker rather than fake live subtitles.
- Translation/transcription requests are request-id protected: clearing the buffer prevents late provider results from reappearing.
- While a translation is pending, additional complete audio payloads are dropped with a `BUSY DROP` status instead of queueing unbounded work.
- `Tap L` freezes/resumes display updates.
- `Hold R` swaps the language direction.
- `Double L` saves the visible subtitle buffer to `host/data/babel_transcripts.jsonl`, then clears it.

Continuous live conversation quality still depends on a reliable audio stream and voice activity policy. The current real path is provider-backed text/audio processing on the Host; the Monocle remains only a microphone stream source and subtitle display.

## 6. Use Case Examples

**The Business Meeting:**
*   *Scenario:* User is negotiating with a German client.
*   *Action:* User activates BABEL (DE -> EN).
*   *Experience:* Client speaks German. User maintains eye contact. English subtitles appear at the bottom of the user's vision. User nods and responds in English (assuming client speaks English, or using Swap mode).

**The Tourist:**
*   *Scenario:* User is at a train station in Paris, listening to an announcement.
*   *Action:* User activates BABEL (FR -> EN).
*   *Experience:* The announcement "Le train à destination de..." is visualized as "The train bound for Lyon is delayed 10 minutes."

**The Accessibility Tool:**
*   *Scenario:* User is Hard of Hearing.
*   *Action:* User activates BABEL (EN -> EN).
*   *Experience:* The app functions as a live captioning system for the real world, transcribing speech to text without translation.
