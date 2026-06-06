
# App Specification: VISION
**Internal ID:** `vision`
**Role:** The Visual Analysis Interface
**Metaphor:** "The Terminator HUD" / "The Digital Eye"

---

## 1. Core Concept & Philosophy
VISION transforms the Monocle from a passive display into an active sensor. It gives the AI "eyes."

Unlike a standard camera app, the goal is not to save memories (photos) but to **extract data**. The user points the device at the physical world, captures a moment, and receives a digital overlay of information.

Because Bluetooth Low Energy (BLE) has limited bandwidth, we cannot stream live video to the AI. Therefore, the interaction model is **Snapshot-Based**: Target -> Capture -> Analyze -> Result. The UX is heavily engineered to mask the latency of image transfer (approx. 1-3 seconds) with engaging "Scanning" visuals.

---

## 2. User Experience (The Flow)

### Phase A: The Viewfinder (Targeting)
*   **Entry:** User selects VISION from the Orbit Carousel or via an OS shortcut.
*   **State:** The Camera sensor (OV5640) powers up. The FPGA configures the pipeline.
*   **Visual:** The user sees a **Static Reticle** (four corner brackets) in the center of the display.
    *   *Note:* This is not a live video feed (which would drain battery/bandwidth). It is a transparent "Targeting Box" overlaid on the real world. The user aligns the physical object within these brackets.
*   **Mode Indicator:** A small icon in the top-left indicates the current analysis mode:
    *   `[👁] IDENTIFY` (Default)
    *   `[T] READ TEXT` (OCR)

### Phase B: The Capture (Shutter)
*   **Action:** User taps **Right** to capture.
*   **Visual Feedback:**
    1.  **Flash:** The screen flashes inverted (White) for 50ms to simulate a shutter.
    2.  **Freeze:** A low-res grayscale preview of the captured image is briefly flashed (200ms) and then fades out. This confirms to the user exactly what was captured.
*   **Hardware Action:** The FPGA captures the frame, compresses it to JPEG, and begins streaming chunks to the Host via BLE.

### Phase C: The Uplink (Scanning)
*   **The Wait:** Transferring a 720p image takes ~1-2 seconds. Analyzing takes ~1-2 seconds. Total wait: ~3-4 seconds.
*   **The Animation:** To prevent user frustration, we use a **"Laser Scan"** effect.
    *   A horizontal white line moves up and down within the Reticle brackets.
    *   Text below the reticle cycles rapidly: `UPLOADING...` -> `PARSING...` -> `ANALYZING...`.
*   **Why:** This gamifies the wait time. It makes the device feel like it is "processing" the object locally, even though it is offloading to the phone.

### Phase D: The Overlay (Result)
*   **Transition:** The Scan line vanishes. The Reticle brackets lock into a solid, bold outline.
*   **Result Display:**
    *   **Identify Mode:** A label line extends from the center of the reticle to a text box.
        *   *Example:* `[ ESP32-WROOM Microcontroller ]`
    *   **Read Mode:** The extracted text is rendered in a high-contrast block, replacing the real-world text in the user's vision.
*   **Interaction:**
    *   **Tap Left:** Dismiss and return to Viewfinder.
    *   **Tap Right:** "More Info" (Triggers ORACLE with the image context).

---

## 3. User Interface (Visual Design)

The UI mimics a sci-fi tactical visor. It relies on wireframes to define the "Active Area."

### The Layout Grid
*   **Zone A (HUD):** Standard System Status.
*   **Zone B (Viewfinder):** The central 400x300px area.
*   **Zone C (Controls):** Bottom edge hints.

### Visual Elements

#### 1. The Targeting Brackets
*   **Style:** Four `L` shaped corners.
*   **Behavior:** They "breathe" (pulse opacity 80% <-> 100%) slowly while idle to indicate the camera is ready.
*   **Color:** White.

#### 2. The Mode Toggle
*   **Location:** Top-Left of Zone B.
*   **Style:** Small text label with an icon.
    *   `[o] IDENTIFY` (Active) / ` T  READ` (Dimmed).

#### 3. The Result Label (Identify Mode)
*   **Design:** A "Callout" style.
    ```text
          +---------------------------+
          |  FICUS ELASTICA (PLANT)   |
          +---------------------------+
                   |
             [  (Object)  ]
    ```
*   **Typography:** Bold, Uppercase for the main object name. Smaller, sentence case for subtitle (e.g., "Rubber Fig, native to Asia").

#### 4. The Text Block (Read Mode)
*   **Design:** A solid black rectangle (opacity 80%) with white text overlaid on top.
*   **Why:** Real-world text is often on noisy backgrounds. We create our own clean background to ensure readability.
*   **Formatting:** The text wraps automatically to fit the box.

## Current Desktop Host Implementation

The live desktop harness implements Vision as a true sensor-to-host flow:

- `Tap R` in Vision emits a Host action.
- The Host sends `CTRL_JSON {"cmd":"CAPTURE_IMAGE"}` to the thin Monocle kernel.
- The Monocle uses the camera module only to capture and stream JPEG bytes back as `STREAM_IMAGE`.
- The Host saves the capture under `host/captures/`.
- If `OPENAI_API_KEY` is configured, the Host sends the JPEG to the OpenAI Responses API as an image input and asks for a short result.
- If no provider is configured, Vision shows an explicit offline capture result with the byte count.
- Capture and analysis are request-id protected: aborted captures ignore late image/result payloads.
- If no image arrives, the Host times out the capture and returns Vision to ready state with `NO IMAGE`.
- OCR mode changes the Host prompt toward text extraction; the device still only captures bytes.
- `Tap R` on a result bridges the visual result into Oracle for a host-side follow-up.
- `Hold R` on a result saves a durable host note in `host/data/vision_notes.jsonl` with the capture path.

This keeps the Monocle in its correct role: camera, buttons, BLE, and display. It does not classify images or run OCR locally.

---

## 4. Interaction Logic & Controls

**System Exit: Hold Left (OS reserved, not listed below).**

| Input | State: Viewfinder | State: Scanning | State: Result |
| :--- | :--- | :--- | :--- |
| **Tap Left** | Toggle Mode (Identify/Text) | Cancel (Abort) | Dismiss → Viewfinder |
| **Tap Right** | Capture | (No action) | Ask Oracle (“More Info”) |
| **Hold Right** | Toggle Flashlight (if available) | (No action) | Save to Recall / Notes |
| **Double Left** | (No action) | (No action) | Copy extracted text to phone (OCR mode only) |

---

## 5. Host-Side Intelligence (The "Brain")

The iOS App handles the heavy lifting via the **Vision Module**.

### The Pipeline
1.  **Reassembly:** The Host receives BLE chunks and reassembles the JPEG.
2.  **Routing:**
    *   If **Mode == IDENTIFY**: Send to GPT-4 Vision API.
        *   *Prompt:* "Identify the main object in this image. Return ONLY the name and a 5-word description. Format: `NAME|DESCRIPTION`."
    *   If **Mode == READ**: Send to Apple Vision Framework (On-Device OCR) or GPT-4 Vision.
        *   *Prompt:* "Extract the text. Fix typos. Return raw text."
3.  **Formatting:** The Host formats the JSON response and pushes it back to Monocle.

### The "Smart Crop" Feature
To save bandwidth, the Monocle FPGA does not send the full 5MP image.
*   **Logic:** The FPGA crops the center 720x720 square (the area inside the Reticle).
*   **Benefit:** Reduces file size by 60%, doubling the transfer speed.

### Error Handling
*   **Blurry Image:** If the Host detects blur, it returns `ERR: FOCUS`. Monocle shows a "Shake" animation on the brackets.
*   **Nothing Found:** Returns `NO OBJECT DETECTED`.
*   **Too Dark:** Returns `LOW LIGHT`. Monocle suggests `LONG PRESS B` (Flashlight).

---

## 6. Use Case Examples

**The Tourist (Read Mode):**
*   *Scenario:* User looks at a Japanese menu.
*   *Action:* Toggles to `READ`. Captures.
*   *Result:* The Japanese characters are obscured by a black box containing the English text: "Grilled Eel over Rice - $15."

**The Technician (Identify Mode):**
*   *Scenario:* User looks at a specific port on a server rack.
*   *Action:* Captures.
*   *Result:* "SFP+ 10GbE Port."
*   *Follow-up:* User Taps B ("Ask Oracle"). "What cable do I need for this?" -> Oracle answers.

**The Shopper (Identify Mode):**
*   *Scenario:* User sees a cool sneaker.
*   *Action:* Captures.
*   *Result:* "Nike Air Max 90."
