
# App Specification: ORACLE
**Internal ID:** `oracle`
**Role:** The Primary Intelligence Interface
**Metaphor:** "The Voice in Your Head" (Visualized)

---

## 1. Core Concept & Philosophy
Oracle is the default interaction layer for PrismOS. It is not a search engine; it is a **Fact Synthesizer**.

Standard voice assistants (Siri, Alexa) are designed for audio-first interaction, often resulting in verbose, slow speech. Oracle is designed for **Visual-First** interaction. It assumes the user can read faster than an AI can speak. Therefore, its primary goal is **Density**: conveying the maximum amount of useful information in the minimum amount of screen space and time.

It does not provide web links. It does not say "Here is what I found." It extracts the core truth of a query and projects it directly onto the user's retina.

---

## 2. User Experience (The Flow)

The interaction is designed to be a seamless loop of **Query -> Synthesis -> Consumption**.

### Phase A: The Trigger (Activation)
*   **Action:** User performs a **Double Tap Right** (OS-reserved quick-launch) on the device (or uses a Wake Word if hardware/battery permits in future iterations).
*   **Immediate Feedback:** The OS "Orbit" fades out instantly. The Oracle UI snaps into focus. A haptic pulse (from the phone) confirms the listening state.
*   **Latency Goal:** < 200ms from Tap to UI ready.

### Phase B: The Query (Listening)
*   **User Action:** The user speaks naturally. "What is the melting point of Tungsten?"
*   **Visual Feedback:** The user sees a **Live Audio Waveform** on the display. This is critical for psychological reassurance—it confirms the microphone is capturing audio in noisy environments.
*   **Silence Detection:** The system waits for a 600ms pause in speech to automatically determine the end of the query.

### Phase C: The Synthesis (Thinking)
*   **State Change:** The Waveform collapses into a **Processing Glyph** (a rotating geometric shape).
*   **Host Logic:** The iPhone captures the audio, transcribes it (Whisper), sends it to the LLM (GPT-4), and enforces a strict "Brevity Protocol" (max 2 sentences).
*   **Streaming:** The text does not pop in all at once. It streams in **token-by-token** as it is generated. This reduces perceived latency; the user starts reading the first word before the AI has finished thinking of the last word.

### Phase D: The Consumption (Reading)
*   **Result:** The answer appears in high-contrast text.
    *   *Query:* "Melting point of Tungsten."
    *   *Result:* "3,422°C (6,192°F). It has the highest melting point of all known elements."
*   **Interaction:** The user reads the text.
*   **Dismissal:**
    *   **Passive:** If the user does nothing, the screen dims after 10 seconds and returns to Orbit Mode after 20 seconds.
    *   **Active:** A **Single Tap Left** dismisses the screen immediately.

### Phase E: The Thread (Follow-Up)
*   **Context:** The Oracle remains "hot" for 10 seconds after the answer is displayed.
*   **Action:** If the user **Holds Right** while the previous answer is visible, the system enters **Follow-Up Mode**.
*   **Logic:** The previous context is preserved.
    *   *User:* "What about Titanium?"
    *   *System (Internal):* "What is the melting point of Titanium?"
    *   *Result:* "1,668°C (3,034°F)."

---

## 3. User Interface (Visual Design)

The UI is designed to look like a tactical terminal. It uses the "Reticle" concept but adapts it for text density.

### The Layout Grid
*   **Zone A:** Top 48px (one font row: `display.FONT_HEIGHT`). The Global HUD (Time, Battery) remains visible but dimmed (50% brightness) to focus attention on the answer.
*   **Zone B (Center 300px):** The Content Area.
*   **Zone C (Bottom 68px):** The Status & Input Area.

### Visual Elements

#### 1. The Listening State
*   **Center Screen:** A horizontal **Amplitude Line**.
*   **Behavior:** It is a single white pixel line that expands vertically into a jagged waveform based on input volume.
*   **Why:** It is minimal, low-CPU, and instantly recognizable.

#### 2. The Thinking State
*   **Center Screen:** The waveform collapses into a small, spinning **Hexagon**.
*   **Animation:** The hexagon rotates 90 degrees every 200ms.
*   **Text:** Below the hexagon, a small, blinking label: `SYNTHESIZING...`

#### 3. The Answer State (The "Card")
*   **The Frame:** The Reticle brackets `[` `]` expand to the full width of the screen.
*   **The Text:**
    *   **Font:** `IBM Plex Mono` or similar technical sans-serif.
    *   **Size:** Large (24px height).
    *   **Alignment:** Left-aligned, ragged right.
    *   **Formatting:** Keywords (e.g., numbers, names) are **Bolded** (rendered with double-stroke thickness) for scanability.
*   **The Overflow:** If the answer exceeds the screen height (rare, due to brevity protocols), a blinking arrow `▼` appears at the bottom center.

#### 4. The Context Hints (Bottom Corners)
*   **Bottom Left:** `L: CLEAR`
*   **Bottom Right:** `R: KEEP` (This pins the answer to the screen, preventing auto-dim).

---

## 4. Interaction Logic & Controls

**System Exit: Hold Left (OS reserved, not listed below).**

| Input | State: Listening | State: Thinking | State: Result |
| :--- | :--- | :--- | :--- |
| **Tap Left** | Cancel / Exit | Cancel / Exit | Dismiss |
| **Tap Right** | Force End Speech | (No action) | Toggle Pin (“KEEP”) |
| **Hold Right** | (No action) | (No action) | Follow-up Mode |
| **Double Left** | (No action) | (No action) | Copy text to phone clipboard |

---

## 5. Host-Side Intelligence (The "Brain")

The Monocle is just the display; the intelligence lives in the iOS App's **Oracle Module**.

### The Prompt Engineering
The System Prompt sent to the LLM is strictly engineered for AR:
> "You are ORACLE, a HUD assistant.
> 1. **Absolute Brevity:** Answers must be < 25 words.
> 2. **Front-Load Facts:** Put the most important data (numbers, names) at the very start of the string.
> 3. **No Fluff:** Never say 'I think', 'According to', or 'Here is the answer'.
> 4. **Formatting:** Use standard capitalization. Do not use Markdown."

### The "Silent Query" Feature
*   **Scenario:** The user is in a meeting and cannot speak.
*   **Action:** The user types a question into the Prism iOS App text field.
*   **Result:** The answer is pushed immediately to the Monocle display via the Oracle interface.

## Current Desktop Host Implementation

The live desktop harness implements Oracle in `host/prism_apps.py` with provider adapters in `host/prism_services.py`.

- `Tap R` starts Monocle microphone capture via the Host `CAPTURE_AUDIO` command. The Monocle streams signed 8-bit PCM; the Host transcribes it, sends the transcript to the provider, and renders the answer back as bounded `DRAW`.
- `Hold R` without a visible answer starts a silent host prompt query. Prompt source priority: `PRISM_ORACLE_PROMPT`, `PRISM_ORACLE_PROMPT_FILE` / `host/data/oracle_prompt.txt`, macOS clipboard, then a safe default prompt.
- If `OPENAI_API_KEY` is configured, the Host calls the OpenAI Responses API and asks for short HUD-appropriate output.
- If no provider is configured, Oracle shows an explicit offline fallback instead of pretending a real answer was generated.
- Provider calls are request-id protected: if the user cancels or starts a new query, a late old answer is ignored.
- Completed answers are appended to `host/data/oracle_history.jsonl`.
- Voice answers are stored with source `AUDIO`; silent prompt answers keep their prompt source label.
- Answers stay on the Host, are wrapped into pages, and only the current page is sent as bounded binary `DRAW`.
- `Hold R` uses the previous answer as context for a follow-up/tip query.
- `Double L` copies the current answer to the macOS clipboard.

The Monocle does not run the LLM, hold conversation state, or format long answers. It only reports button events and displays the current Host-composed page.
*   **UX:** The Monocle skips the "Listening" and "Thinking" animations and jumps straight to the "Answer" state.

## Current iOS Host Implementation Notes

- iOS Oracle capture is host-first: the Monocle sends signed 8-bit PCM over `STREAM_AUDIO`; the iPhone converts it to PCM16, transcribes it, sends the transcript to the configured provider, and sends the bounded answer back as `DRAW`.
- The iOS host owns request identity. Late provider completions are ignored if the user cancels or starts a new request.
- 2026-05-31 fix: stale `MEDIA AUDIO END` notifications that arrive after `STREAM_AUDIO` are ignored by `DeviceConsoleModel` and are not forwarded to Oracle, preventing a valid provider answer from being overwritten by `NO TRANSCRIPT`.
- 2026-05-31 repeat-capture fix: the host response timeout is no longer equal to the 4-second recording duration. A 4-second Oracle capture now waits up to 12 seconds for complete BLE audio delivery/reassembly before showing `NO AUDIO`.
- 2026-05-31 paging fix: iOS Oracle stores the cleaned full answer instead of only the first short HUD slice, then renders bounded pages to Monocle. `Tap L` advances to the next answer page, `Double L` returns to the previous page, and the title shows `ORACLE n/m` when multiple pages exist. `Hold R` copies the full cleaned answer to the phone clipboard.
- Regression coverage: `testOracleIgnoresStaleAudioEndAfterStreamDataWhileProviderCompletes` reproduces the physical-device ordering and asserts that Oracle reaches `Provider answer.` without `NO TRANSCRIPT`.
- Regression coverage: `testAudioResponseTimeoutCoversRecordingAndBleTransferWindow` locks the response-timeout policy for Monocle audio transfer.

### Error Handling
*   **Network Fail:** The "Thinking" Hexagon turns into a static `X`. Text: `OFFLINE`.
*   **Unclear Speech:** Text: `???`. The system automatically re-opens the mic for 3 seconds for a retry.

---

## 6. Use Case Examples

**The Engineer:**
*   *User:* "Convert 55 foot-pounds to Newton-meters."
*   *Oracle:* "74.57 Nm."

**The Traveler:**
*   *User:* "What is the currency rate, Yen to USD?"
*   *Oracle:* "1 JPY = 0.0067 USD. 1000 Yen is approx $6.70."

**The Student:**
*   *User:* "When did the Roman Empire fall?"
*   *Oracle:* "The Western Empire fell in 476 AD. The Eastern (Byzantine) Empire fell in 1453 AD."
