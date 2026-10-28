# Adaptive shell implementation and qualification

Updated 28 October 2026. This document describes source integration, not a physical-device or release acceptance receipt. The public design is a compact implementation summary; private source conversations and hardware identifiers are excluded.

## Current owners and full inventory

| Surface | Production owner / disposition |
|---|---|
| App entry, one canonical host | `PrismHostApp` → `ShellHostModel` → `AssistantOrchestrator`. No mock transport, generic app runtime or old Watch bridge is instantiated on this path. |
| Home / Ask–Act | `PrismShellView`: typed input, microphone invocation, local activity, current session/project, complete answer, exact action previews, receipts, undo and reconciliation. |
| Lens | `PrismSceneRenderer` and `PrismDrawPacker`: 12 scene kinds, complete semantic paging, UTF-8 byte limits, whole text-box bounds, no overlapping rows, clear/pin/expiry. Phone preview is the exact current packed viewport. |
| Library | `ShellArchive` / `FileShellRepository`: complete conversations, transcripts, derived artifacts, confirmed notes, receipts and provenance. Search, note editing, full-content sharing, deletion and retention. |
| Settings | Pairing, cloud consent, API credentials, native context permissions, optional gateway, voice, privacy, retention and gestures. Developer Mode is separate. |
| Watch | `ShellPhoneWatchBridge` → `ShellWatchClient`: canonical version/session snapshots, scene-specific wrist projection, exact bounded action previews, expiry/stale indicators, immediate commands, no offline action queue. Refresh is allowed even after a snapshot becomes stale. |
| BLE | `CoreBluetoothMonocleAdapter`: remembered UUID, filtered scan, explicit selection, retrieve/connect/discover/subscribe, version handshake, bounded write queue, readiness callbacks, acknowledgements, stale timeout, reconnect and restoration. NUS is not used for runtime or automatic recovery. |
| Device | `monocle/kernel.py`: shell handshake, input/media events, incremental microphone streaming, bounded control retry queue, text DRAW, clear, display ACK and host lease. `main.py` and `boot.py` are unchanged. Legacy `prism/bridge.py` now uses explicit byte copies. |
| Model/context | `ResponsesExperienceModel`, `ExperienceSchema`, `ContextBundle`: strict structured semantic output; read-only function tools; AI interpretation, ranking, project association and modality. No project dictionaries or keyword routing. |
| Tools/effects | `AssistantOrchestrator` owns action identity, confirmation, persistence and receipts. `EventKitShellTools` owns OS permissions/effects. Native speech uses `NativeShellVoice`; actual recorded bytes use `OpenAIAudioTranscriptionClient`. |
| Compatibility owners | `ProviderApps.swift` now retains complete Oracle answers, Vision summary/OCR and Babel transcripts. Paging no longer truncates before wrapping; long Teleprompter words are preserved and scripts retain `sourceText`. Old console controls and generic runtime remain development/reference paths. |
| Tests | All seven existing package test targets plus `PrismShellTests`; all Python host/reference test files; new `ShellNativeServicesTests` in the Xcode host test target. Twenty full semantic references cover content, tools, modality and context. |

The inventory covers all normal phone tabs, the Watch entry point, all 12 scene variants, all eight tool contracts, audio input/output, protocol reassembly/splitting/queueing, native services, every existing canonical-truncation caller identified in the current source, app/project membership and active documentation entrypoints. Existing specialized application engines remain reference capabilities; completing their broader roadmaps is not part of the near-term shell.

## Implemented vertical paths

1. Typed input → persisted request → current context → structured Responses generation (with bounded read function rounds) → schema/domain validation → complete persisted assistant turn → native phone card + deterministic text-only lens pages → CoreBluetooth queue → device DRAW/ACK.
2. Global Ask → immediate local feedback → correlated four-second Monocle microphone request → signed 8-bit 8 kHz stream → bounded reassembly → PCM16 reconstruction/WAV transcription → complete transcript artifact → the same assistant path → independently authored native speech and lens response. Clear, a newer request, disconnect or expired background time invalidates late results.
3. Model-proposed note/reminder/timer/session → exact preview → explicit confirmation → host-owned idempotent execution → durable receipt → native/Library result → undo. Read functions use the same Library/context owner. They do not bypass the action policy.
4. Real EventKit calendar snapshot → mechanically eligible upcoming-event candidates → AI contextual decision across all eligible candidates → one temporary surface or quiet phone-only/suppressed result → durable source/reason history → dismiss/snooze/expiry/source-disappearance handling. No model polling occurs for an unchanged candidate revision.

## Data, permissions and effect policy

`canonicalAnswer`, original user text, complete transcripts and normalized artifacts are independent of HUD projections. Context admits complete recent records within a byte budget, reports omitted turns, and supplies retrieval for older/full records. Literal full-text filtering is mechanical; the model chooses search terms and interprets/ranks results. No embedding index or autonomous memory promotion is claimed.

Cloud processing starts OFF. Source permissions and proactive surfaces start OFF. Calendar permission is requested through Settings. Reminder permission is requested only at an explicitly confirmed reminder. Multiple pending actions survive each receipt so a composed request can be confirmed fully. On the lens, left cycles available choices and right opens a full review before confirmation; phone and Watch expose exact previews. All state-changing tools require confirmation, including local notes/timers; read-only tools execute within the approved context boundary. No messages, calls, deployments, unrestricted shells or agent approvals are offered.

Reminder actions are journaled before EventKit writes. A process interruption restores an executing action as **uncertain**, never as safe to retry. EventKit reminders carry a stable action marker; reconciliation searches for that marker. Undo checks ownership before removing a reminder. Local note/timer/session changes commit atomically with their receipts. Undo refuses to erase an edited note or overwrite a newer timer.

The Library is stored atomically in the app's Application Support directory, with device file protection and owner-only permissions. Corrupt or unknown-version data is preserved and prevents startup rather than being replaced by empty data. Raw audio is discarded by default. Retention is applied on load, setting changes and at most hourly while running. Old content and local receipt payloads expire; minimal external reminder identifiers remain for duplicate prevention/reconciliation/undo. Delete Library content scrubs retained reminder argument payloads. Individual artifact deletion does not automatically delete conversation copies; Settings explains the full deletion control. Keychain stores provider and gateway secrets.

## Protocol and lifecycle

Wire framing remains `PM` version 1 with the existing 13-byte header and bounded DRAW version 1. Shell feature negotiation adds `HELLO` with `protocol_version=1`, `shell_version=1`, a host session nonce and a device boot nonce/clock. Incompatible runtime source is reported; no firmware write is attempted.

Control commands: `HELLO`, `PING`, `BEGIN_INTERACTION`, `CLEAR`, `CAPTURE_AUDIO`, `CANCEL_CAPTURE`. Device events: `HELLO`, `PONG`, `BTN`, `MEDIA START/ERROR`, `DRAW_ACK`. `MEDIA START` binds the host request UUID to the audio stream message ID. Old/cancelled/unbound streams are discarded. Gestures carry the negotiated host session and a device timestamp; duplicates and implausible clock ages are rejected. A physical blank establishes a timestamp barrier: old queued activation/capture cannot resume the lens before the host acknowledges that input. Device control and DRAW messages are consumed in one bounded FIFO, preserving BEGIN/clear/capture/render ordering.

Host writes are serialized, bounded to eight messages, respect `canSendWriteWithoutResponse`, and preserve fragmented-message ordering. Only unsent complete draws may be superseded; their ACK expectations are removed. With-response fallback is bounded to the negotiated ATT write size. Reassembly limits simultaneous streams, size, total-length consistency, sequence and elapsed time. Connection loss resets transport/media owners and pending effects; assistant effects already committing retain their receipt/uncertainty semantics.

A 5-second host heartbeat renews a 20-second device lease. If the host disappears or iOS suspends it, the device marks stale/offline independently. Hold-left blanks locally, cancels transport and discards pending device projection even without the host. An intentional new interaction can resume projection. The default lens is blank.

Monocle's documented microphone API has bounded `record`/`read`, but no `stop` operation. Cancellation stops transport and acceptance immediately; the bounded four-second FPGA recording may finish locally. This is not continuous/passive listening. No unsupported microphone-stop call is invented. BLE throughput, FPGA buffering, case sleep and actual display/font behavior require hardware acceptance.

The phone uses CoreBluetooth background restoration plus a finite UIKit background task for an explicitly initiated interaction. Audio playback uses the audio background mode and current route. Route changes/interruption stop speech rather than replaying private content on a new speaker. These mechanisms do not promise unlimited background execution or recovery after user force-quit.

## Tools and composability

| Contract | Actual owner | Result/undo |
|---|---|---|
| `save_note` | Canonical Library transaction | Full note, receipt, delete undo |
| `retrieve_notes` | Canonical Library search | Complete admitted records, explicit omitted count |
| `create_reminder` | EventKit | Real identifier, receipt, ownership-checked delete undo, uncertain reconciliation |
| `read_upcoming_calendar` | EventKit | Permitted upcoming snapshot; unavailable status when denied |
| `get_agent_status` | Optional authenticated HTTPS JSON gateway | Fresh normalized exceptions; unavailable when unconfigured |
| `start_timer` / `stop_timer` | Host archive | Durable end time/completion, receipt and prior-state undo |
| `set_session` | Canonical session/project | Conversation/focus/walk/meeting/build/presentation context, prior-state undo |

Oracle-style explanation and bounded Babel-style translation/captions are generated by the assistant; Chronos-style timing is a registered tool; Signal-style ingestion/relevance is a source/AI decision. Existing Teleprompter and Vision engines remain below the normal navigation layer as reference/development capabilities. This build does not claim continuous captions, a full presentation workflow, navigation guidance, camera recovery or completion of every legacy app. Route/caption scenes can represent supplied semantic content without implying those integrations exist.

Optional agent gateway response contract:

```json
{"generatedAt":"2027-01-15T08:00:00Z","exceptions":[{"id":"example","project":"Example","summary":"Decision requested","observedAt":"2027-01-15T08:00:00Z","expiresAt":"2027-01-15T08:05:00Z"}]}
```

Configure an HTTPS URL and bearer token in Settings. No endpoint/account is provisioned by this change. Snapshot age is limited to 120 seconds; expired exceptions are excluded. The initial proactive source is Calendar, not a second agent event feed.

## Voice ownership and verified interfaces

The existing PrismOS Responses/transcription adapters are retained. The shell uses `gpt-5.5` for structured text generation (the repository default) and current bounded file transcription with `gpt-transcribe`. Speech output is native `AVSpeechSynthesizer`, not subscription/Codex voice or generic Realtime speech-to-speech. `ExperienceModel`, `SpeechClient`, `ShellVoiceOutput` and host-owned typed tools are the future adapter seams. No CodeMind or phone companion repository is modified.

Official interfaces checked on 28 October 2026:

- [Responses structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs): `text.format` JSON schema, required properties, refusal/incomplete handling.
- [GPT-5.5](https://developers.openai.com/api/docs/models/gpt-5.5): existing text default remains available through the API.
- [File transcription](https://developers.openai.com/api/docs/guides/speech-to-text): current file transcription model/endpoint and WAV input; historical transcription model suggestions are not used as current defaults here.
- [Monocle MicroPython source documentation](https://github.com/brilliantlabsAR/docs/blob/main/monocle/micropython.md): signed PCM, bounded reads and Raw Data BLE.
- [CoreBluetooth write readiness](https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate/peripheralisready(tosendwritewithoutresponse:)): host backpressure boundary.

## Qualification and remaining gates

See the checked-in [verification receipt](ADAPTIVE_SHELL_VERIFICATION.md) for exact VM commands/results. The untouched baseline was compiled separately at `e2f9ac4`: 85 package tests passed. Current checks execute real internal owners with safe external HTTP, OS and physical-transport doubles. There was no provider spending or real account mutation.

Twenty realistic cases in `PrismShellTests/Fixtures/semantic-evaluations.json` include complete reference content, speech, scene, actions, context, read expectations and evaluation guidance. Offline replay proves schema, read-tool/context integration, persistence, effects remaining pending and projection constraints. It **does not measure whether a live model selects the reference experience**. For a separately authorized live evaluation, use these exact inputs/context with the actual configured model, retain complete outputs, and review factual grounding, interpretation, tool arguments, confirmation, language, modality, expiry and usefulness. Do not replace that review with token matching.

Remaining external acceptance:

1. Xcode compilation and all host/package tests, then Watch build with the commands below. Apple SDK type checking is not established by Linux syntax parsing.
2. On a simulator, exercise all four normal tabs, every scene variant, long-answer copy/share/edit/search, privacy/deletion, permission denials and normal/developer separation. Replay references through the production shell; no real reminder writes are needed for this simulator stage.
3. With the hardware owner's explicit device selection and recovery knowledge, separately install compatible source and prove physical gesture → host → DRAW ACK → actual display. Do not auto-select by name or use NUS recovery as runtime.
4. Capture real Monocle audio; measure sample integrity/latency at negotiated MTUs, cancellation at every stage, route changes, headphone loss, lock/unlock, background expiration, Bluetooth off/on, process restoration and force-quit behavior. Verify local blank and stale lease while disconnected.
5. With separately authorized real accounts, prove a note, calendar read, reminder creation/undo and uncertain-action reconciliation; run the semantic evaluation against the configured model. No such effects were performed on this VM.
6. Prove a real calendar candidate's contextual usefulness, dismiss/snooze/expiry and source deletion on phone/Watch/lens; then soak for duplicate/noise/reconnect behavior. Offline replay is not physical soak evidence.

```bash
swift test --package-path ios/Packages/PrismCore
xcodebuild test -project ios/Apps/PrismHost/PrismHost.xcodeproj -scheme PrismHost -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project ios/Apps/PrismHost/PrismHost.xcodeproj -scheme PrismWatch -destination 'platform=watchOS Simulator,name=Apple Watch SE 3 (40mm)' CODE_SIGNING_ALLOWED=NO
```

Camera/renderer recovery, boot changes, arbitrary executable UI, passive perception, unrestricted remote control, new cloud services and unrelated companion work remain excluded by the work order. No physical deploy, flash, reset, calendar/reminder mutation, message, call or cloud deployment was run in this assignment.
