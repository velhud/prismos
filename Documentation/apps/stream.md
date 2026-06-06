# STREAM / SIGNAL — Host-curated Event Stream (Attention Firewall)

Internal ID: `stream`
Active label: `SIGNAL`

Current iOS ID note: the active iOS app identifier is `signal` (`PrismAppID.signal`). `stream` remains the historical concept name and desktop class name until a later code/docs naming cleanup. Both refer to the same active Signal attention-firewall app, not two separate production apps.

Primary concept:
A scrollable stack of events curated by the Host (not a mirror of the phone's global notification center). The Host normalizes event sources into compact "cards" and sends the currently-selected card to Monocle.

See: `Documentation/STREAM_FEASIBILITY_AND_SCOPE.md` for hard constraints.

---

## 1. Goals (v1)
- Show the user a minimal, high-signal stream of events as compact 2-line cards
- Support simple stack navigation and dismiss
- Support "handoff" to the Host for sources that can be opened (optional per-card)
- Support privacy/obfuscation (host-controlled)

## 2. Non-goals (v1)
- Do not ingest arbitrary iOS system notifications from other apps (SMS/Slack/Uber/etc.)
- Do not assume access to the phone's Notification Center
- Do not assume reply-to-message for third-party apps

---

## 3. Card format (device UI contract)
A card is exactly two lines of primary text plus urgency indication.
- Line 1: `title` (e.g., "MEETING", "REMINDER", "PRISM")
- Line 2: `body` (e.g., "4PM JOHN", "BUY MILK", "BUILD DONE")
- Urgency: derived from `prio` (INFO/IMPORTANT/CRITICAL)

The Host is responsible for producing strings that fit the display.

Current desktop host sources:
- `PRISM_STREAM_FILE` or `host/data/stream_cards.json`
- built-in Prism/system cards when no file is present

The app is intentionally not a notification mirror. It is a small, curated signal stack with dismiss, privacy, and handoff behavior.

---

## 4. Inputs (gesture mapping)
The STREAM app uses the standard gesture events (`BTN`) and the Host interprets them based on current app + current card.

Gesture meanings (v1):
- `TAP_L`  : Next (older) card
- `TAP_R`  : Dismiss current card
- `TAP_R` when empty: reload session cards and clear session dismissals
- `LONG_R` : Handoff (open on Host) IF the current card includes a handoff target; otherwise no-op
- `DOUBLE_L`: Toggle privacy mode for STREAM cards (host decides obfuscation level)

Note: "Reply via Oracle" is explicitly out-of-scope for v1. It can be added later only for sources where the Host can actually send a reply.

---

## 5. Host responsibilities (v1)
### 5.1 Event ingest
Host collects events ONLY from sources it can legally access:
- Prism-owned notifications (push/local notifications posted by the Prism app)
- Explicit user-authorized sources (calendar/reminder-like)
- Explicit integrations (future)

### 5.2 Filtering
Host applies user rules:
- allow/deny by source code
- allow/deny by priority
- allow quiet hours
- allow privacy mode defaults

### 5.3 Summarization/normalization
Host converts each event into:
- `source` short code (CAL/REM/PRISM/SYS/EXT)
- 2-line compact text (`title`, `body`)
- priority (`prio`)
- optional `handoff`

### 5.4 Handoff
If a card includes a handoff target, the Host may open the relevant destination when it receives `LONG_R` while STREAM is active.
If a card has no handoff, `LONG_R` must do nothing.

Current desktop behavior keeps dismissals for the Host session. Dismissed cards do not reappear when re-entering Signal; when the stack is empty, `Tap R` reloads the source cards.

---

## 6. State contract (JSON)
STREAM state is delivered via `STATE` messages using the schema defined in `Documentation/data_scheme.md`.

---

## 7. Examples (v1-compliant)
- Calendar: "MEETING" / "10 MIN JOHN" (prio IMPORTANT)
- Reminder: "REMINDER" / "BUY MILK" (prio INFO)
- Prism internal: "PRISM" / "SYNC DONE" (prio INFO)
- System: "BATTERY" / "LOW" (prio CRITICAL)
