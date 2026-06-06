# App Specification: RECALL
**Internal ID:** `recall`
**Current status:** Archived prototype; removed from active desktop carousel.
**Role:** The External Memory Interface
**Metaphor:** "Digital Flashcards" / "The Infinite Clipboard"

---

## Archive Note

Recall is not part of the current active suite. A useful version needs a real memory/conversation index, ranking policy, privacy policy, and fast lookup flow. Without that substrate it becomes a tiny manual note reader, which does not justify a live Monocle app slot.

The source class remains in `host/prism_apps.py` and legacy tests remain for regression coverage, but the active carousel excludes `recall`.

## 1. Core Concept & Philosophy
RECALL is the user's "Second Brain." It offloads the burden of memorization to the device.

While **Teleprompter** is for linear performance, **Recall** is for random-access reference. It organizes information into **"Decks"** (Categories) and **"Cards"** (Pages). It is designed for high-density, static data that the user needs to glance at repeatedly—shopping lists, gate codes, technical pinouts, or talking points.

**Key Constraint:** Navigation depth. We cannot have complex folder structures on a two-button device. The hierarchy is flattened to just two levels: **Deck -> Card**.

---

## 2. User Experience (The Flow)

### Phase A: The Organization (Phone Side)
*   **Creation:** User creates Decks in the Prism iOS App (e.g., "Groceries", "Wifi Passwords", "Server Configs").
*   **Editing:** User types content using the phone keyboard. Supports two formats:
    1.  **Note:** Freeform text.
    2.  **Checklist:** Interactive items with checkboxes.
*   **Sync:** Decks are pushed to the Monocle's storage. They are cached locally so RECALL works **Offline** (without phone connection).

### Phase B: The Selection (Deck View)
*   **Entry:** User opens RECALL.
*   **View:** User sees the **Deck Carousel** (Horizontal list of categories).
*   **Action:** User holds **Right** to open a Deck.

### Phase C: The Reference (Card View)
*   **Navigation:** User taps **Left/Right** to flip through cards in the deck.
*   **Interaction (Checklist Mode):**
    *   The active item is highlighted.
    *   User holds **Right** to "Check" the box.
    *   The item dims and strikes through visually.
*   **Interaction (Note Mode):**
    *   User reads the data.
    *   If text is long, the card becomes scrollable (vertical).

---

## 3. User Interface (Visual Design)

The UI mimics a stack of physical index cards, optimized for high contrast.

### The Layout Grid
*   **Zone A (Header):** The Deck Name (e.g., `[ GROCERIES ]`) and Card Counter (`3/12`).
*   **Zone B (Content):** The body of the card.
*   **Zone C (Footer):** Context hints.

### Visual Elements

#### 1. The Card Frame
*   **Style:** A white rectangular border outlining Zone B.
*   **Why:** Visually groups the data, separating it from the real world.

#### 2. The Checklist Item
*   **Unchecked:** `[ ] Milk` (Bright White).
*   **Checked:** `[x] Milk` (Dimmed Gray, Strikethrough).
*   **Focus:** The "Active" item has a solid white block cursor `█` to the left of it.

#### 3. The Data Table (Note Mode)
*   For technical data, the font switches to a smaller monospaced type to align columns.
    ```text
    IP:   192.168.1.55
    PORT: 8080
    USER: admin
    PASS: hunter2
    ```

#### 4. The "Empty" State
*   If a deck is finished (all items checked), a large **Checkmark Icon** appears in the center with the text `COMPLETE`.

---

## 4. Interaction Logic & Controls

**System Exit: Hold Left (OS reserved, not listed below).**

**Deck View**

| Input | Action |
| :--- | :--- |
| **Tap Left** | Previous Deck |
| **Tap Right** | Next Deck |
| **Hold Right** | Open Deck |
| **Double Left** | Deck Options (future) / no-op for v1 |

**Card View (Note)**

| Input | Action |
| :--- | :--- |
| **Tap Left** | Previous Card |
| **Tap Right** | Next Card |
| **Hold Right** | Pin/Unpin Ghost |
| **Double Left** | Back to Decks |

**Card View (Checklist)**

| Input | Action |
| :--- | :--- |
| **Tap Left** | Move selection up |
| **Tap Right** | Move selection down |
| **Hold Right** | Toggle checkbox |
| **Double Left** | Back to Decks |

---

## 5. Host-Side Intelligence (The "Brain")

The iOS App manages the **Database Module**.

### The Sync Engine
*   **Bi-Directional Sync:** If the user checks off "Milk" on the Monocle, the iOS App updates the list on the phone instantly. If the user adds "Eggs" on the phone, it appears on the Monocle instantly.
*   **Conflict Resolution:** "Last Write Wins."

### The "Smart Sort" Algorithm
*   **Logic:** The Host tracks which cards are viewed most often and at what times/locations.
*   **Contextual Sorting:**
    *   If the user is at the Grocery Store (GPS), the "Groceries" deck automatically moves to the front of the Deck Carousel.
    *   If it is 9:00 AM on a Monday, the "Work Tasks" deck moves to the front.

### Integrations (Future)
*   **Apple Reminders / Google Keep:** The Host App can act as a bridge, pulling lists from these services so the user doesn't have to manually duplicate data.

---

## State Payload Contract
Host sends `type: STATE`, `app: "recall"` messages as defined in `Documentation/data_scheme.md` (RECALL section).

## 6. Use Case Examples

**The Shopper:**
*   *Scenario:* User is at the supermarket.
*   *Action:* Opens `GROCERIES`.
*   *Experience:* User pushes the cart with both hands. Glances at list. Sees "Milk." Grabs milk. Taps device to check it off. Sees "Bread." Moves to aisle 4. Phone stays in pocket the entire time.

**The Network Engineer:**
*   *Scenario:* User is atop a ladder fixing a server.
*   *Action:* Opens `CONFIGS`.
*   *Experience:* User needs the static IP and Gateway for the switch. Instead of climbing down the ladder to check a laptop, user glances at the Monocle. The IP address is pinned there. User types it into the console.

**The Public Speaker (Q&A):**
*   *Scenario:* User finishes a speech and takes questions.
*   *Action:* Opens `TALKING POINTS`.
*   *Experience:* A hostile audience member asks about "Q3 Losses." User flips to the "Financials" card. User reads the exact prepared rebuttal statistics without stuttering or saying "Let me get back to you."
