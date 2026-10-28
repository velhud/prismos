# Using the adaptive shell

The iPhone owns PrismOS. Open **Home** to ask a question, capture a thought, or continue the current conversation. The lens starts blank. **Lens** previews the exact current Monocle page; **Library** holds complete content; **Settings** controls consent, pairing and privacy. Specialized capabilities are selected in the conversation rather than through an app launcher.

## First use

1. In Settings, enable cloud processing only after reviewing the disclosure, and save your API credential. API billing is separate from a ChatGPT/Codex subscription. Keys are stored in Keychain.
2. For lens/microphone use, select **Pair a Monocle**, then select your intended device explicitly. Only that remembered identity reconnects automatically. A compatible shell handshake is required. PrismOS never installs firmware or invokes recovery automatically.
3. Calendar is optional. **Allow Calendar access** requests iOS permission; **Use Calendar** controls whether permitted events enter assistant context. Upcoming event surfaces additionally require **Useful upcoming event surfaces**. All start off.
4. Optional agent status requires your own HTTPS gateway and bearer token. An unconfigured, denied or stale integration is reported as unavailable.
5. **Spoken responses** uses the iPhone's native voice and current audio route. **Allow timer notifications** separately asks iOS to deliver focus alerts in the background. Timers still persist if alerts are declined.

A disconnected Monocle does not prevent typed phone conversations. Voice input in this build uses the Monocle microphone; it requires an actual compatible connection and cloud consent. This is bounded capture, not passive listening or subscription voice.

## Ask, inspect and act

Type a question on Home and press Ask. The assistant can explain, compare supplied options, interpret permitted context, retrieve notes, translate a bounded utterance, and propose useful actions. Full answers and transcripts are saved independently of the small lens complement. The phone and Watch project the same host-owned state.

For an ambiguous reminder, answer the clarification rather than accepting an invented time. A prepared action shows its complete arguments before **Confirm**. Notes, reminders, timers, session changes and conversational choices all require your acceptance. Multiple proposed actions remain available after the first receipt.

A successful receipt explains the actual result. **Undo** reverses eligible notes, reminders, timers and session changes. It cannot erase an edited note or overwrite a newer timer/session. A conversational selection becomes an ordinary follow-up turn, with a selection receipt; it has no destructive undo.

If a reminder's creation or deletion was interrupted, use **Check action outcome**. The app looks up its stable action marker before permitting any further operation. It does not blindly repeat uncertain effects. Receipts remain accessible in Library after their temporary lens surface disappears.

A timer stores its absolute end time, survives app relaunch, and displays completion locally. When explicitly allowed, iOS schedules one background alert for the current timer. Replacing, stopping or undoing the timer updates that same notification slot. Notification delivery on a locked physical phone remains a device acceptance gate.

## Lens and gestures

- Double right: Ask. Hold right: follow up in the current conversation.
- Right tap: review an action, advance its full review pages, then confirm; otherwise advance the current scene page.
- Left tap: cancel an active action review; otherwise cycle choices, dismiss a proactive surface, or undo an eligible receipt.
- Double left: pin an ordinary scene. Pending actions and proactive surfaces still expire.
- Hold left: blank immediately. The device also handles local blank while the host is unavailable.

Home's Blank button also cancels capture/generation and stops speech. Late results from an older interaction cannot revive the surface. A new Ask resumes normal use. Stale/disconnected state is visible; reconnect starts with a blank lens rather than replaying old content.

Scenes include facts, lists, comparisons, choices, confirmations, activity/progress, captions, timers, alerts and supplied route content. Native layout handles paging and bounds. A route card does not imply a navigation integration; a caption does not imply continuous listening. Speech can explain the full answer while the lens shows a useful complementary fact, or stays blank.

## Complete Library and continuity

Search Library text and optional project association, open complete artifacts, select/copy text or use Share, and edit saved notes. Original source/provenance remains visible. New session begins a fresh conversation with an optional project; earlier sessions remain stored. Recent complete turns enter the next request within a declared byte budget; the assistant can retrieve older notes using read tools.

Deleting an artifact removes that artifact; it does not silently erase copies in conversation history. **Delete Library content** removes conversation and artifact content, while preserving the minimum external reminder ledger needed to reconcile/undo existing effects and prevent duplicates. It does not delete external reminders automatically.

Retention defaults to 30 days and can be set to 1–365 days. Raw audio retention starts off. **Hide lens and Watch content** blanks those projections; it is not a promise that an explicitly submitted cloud request stays local. Disable cloud processing to prevent assistant/transcription requests. A corrupt or inaccessible Library is preserved and blocks startup instead of being replaced by an empty store.

## Quiet proactive surfaces

With calendar permission and proactive consent, a fresh real upcoming event can become a candidate. The assistant interprets its relevance in current context. The host enforces event existence, timestamps, deduplication, cooldowns and expiry. A time window alone never selects a semantic winner.

A useful candidate may briefly appear on the lens/phone, remain phone-only, or be suppressed. Proactive cards do not speak automatically. Dismiss keeps that event revision quiet; Snooze allows reconsideration after the requested interval, before expiry. Source disappearance, stale data, privacy mode or event expiry removes the active surface. Failed evaluations can retry after a bounded cooldown; successful unchanged decisions are not repeatedly polled.

## Watch and recovery

Watch displays the canonical host scene, pending exact action previews and recent receipt. Commands require a fresh version/session and reachable iPhone; effects are never queued for later offline replay. Refresh retrieves a new snapshot. Watch owns neither BLE nor providers.

If Bluetooth or a source becomes unavailable, inspect Settings and reconnect the explicitly remembered device. An incompatible runtime is reported without updating it. Physical firmware recovery requires the hardware owner's separate procedure. Background execution and CoreBluetooth restoration are bounded by iOS; force-quit is not a promise of continuous service.

Developer Mode reveals the separate legacy simulation console. Its mock/protocol/provider controls are development tools and are not part of ordinary Ask–Act use. Camera recovery, arbitrary generated code/UI, passive perception and general remote control are outside this build.

See [implementation and qualification](ADAPTIVE_SHELL_IMPLEMENTATION.md) and [verification evidence](ADAPTIVE_SHELL_VERIFICATION.md) before treating any hardware behavior as accepted.
