# Adaptive shell VM verification receipt

Date: 28 October 2026. Environment: Ubuntu 24.04, x86_64. Source base: `e2f9ac47dd5c0a661154ce87de5d99ea68ad526b`. Integration branch: `implement/adaptive-shell-20261028`. This is source/offline verification, not an Apple build or hardware release label.

| Check | Result / evidence class |
|---|---|
| Untouched base, `swift test --package-path ios/Packages/PrismCore --jobs 4` in a separate extracted source tree | **85 tests passed**, no failures; executable Linux baseline |
| Integrated package, same command | **114 tests passed**, no failures; executable Linux package tests, final run at 04:18 UTC |
| `python3 -m unittest discover -s host/tests -p '*_test.py'` | **72 tests passed**, no failures; executable Python/reference/device-owner tests, final run at 04:23 UTC |
| Swift frontend parse of all `ios/Apps/**/*.swift` | Passed; syntax only, no Apple SDK type checking |
| `swift package --package-path ios/Packages/PrismCore dump-package` | Passed; includes `PrismShell` standalone and in the aggregate product |
| Xcode object IDs/new source membership, `Info.plist`, fixture JSON | Checked; static project/config evidence only |
| `git diff --check` | Passed |
| Required PrismHost `xcodebuild test` | **Unavailable**, exit 127: `xcodebuild: command not found` |
| Required PrismWatch `xcodebuild build` | **Unavailable**, exit 127: `xcodebuild: command not found` |
| Live provider/model semantics | **Not run**; no provider spending authorized |
| Native account effects | **Not run**; no actual Calendar/Reminders/account changes |
| Physical Monocle/iPhone/Watch, audio routing, locked screen, BLE restoration, soak | **Not run**; devices/Apple platform unavailable |

The installed Linux compiler used for these checks was official Swift 6.2.3 for Ubuntu 24.04, running the package's Swift 5 language/tools contract. The toolchain lives outside the repository. It does not provide Apple SDKs or simulators.

## Executable coverage

- Production semantic Responses adapter with safe HTTP-boundary replay, strict schema/domain validation, refusals, incomplete output and rejected mutation function calls.
- Five-turn continuity and complete long-answer preservation through context, persistence, native projection and real framing/reassembly owners.
- Audio byte conversion, transcript storage, independent speech/lens output, cancellation and late result rejection.
- All 12 scene kinds, complete semantic paging, long words/Unicode, UTF-8 byte bounds, full text-box bounds, packing and overlap constraints.
- Note preview/confirmation, project association, receipt, duplicate/stale acceptance rejection and undo; every pending action in a composed session/timer request survives earlier receipts.
- Reminder journal, uncertain external effect, reconciliation and undo; a failed durable journal prevents native execution.
- Focus timer, action review, expiry/completion and undo; expired actions cannot be revived by an error surface.
- Calendar candidate mechanics plus AI-boundary interpretation replay, quiet output, snooze, expiry, source disappearance and restart duplicate suppression.
- Privacy, retention of full content, raw-media policy, minimal external receipt ledger, corrupt-store preservation and interrupted-action recovery.
- Watch version/session freshness and bounded canonical projection; no offline mutation queue.
- Queue backpressure, coalescing, priority blank preserving a new Ask, connection epochs, protocol versions/size/sequence/total-length/time limits, audio request correlation, stale/duplicate gesture gate.
- Actual Python kernel handshake, incremental microphone sender, signed byte integrity, MTU fragmentation, retry of an unsent control fragment, cancel, local blank, empty DRAW clearing, FIFO control/draw ordering, bounded inbound queue, late activation rejection after physical blank and offline lease. Only physical module boundaries are doubled.
- Regressions for retained Oracle copy/history/paging/follow-up truth, full Vision OCR/summary, Babel transcripts beyond 24 lines and complete Teleprompter source/long words.

Twenty full-content semantic reference scenarios are replayed inside one contract test, including actual read function rounds and supplied source/prior-turn context. They are **reference replay**, not twenty independent live model judgments. No semantic quality pass rate is claimed. New Apple-native service tests are included in the Host test target and remain unrun here.

## Scope boundaries

Normal Home/Lens/Library/Settings, Developer Mode, Watch entry point, all 12 scene variants, all eight tools, protocol/media/persistence/provider owners and their consequential legacy truncation callers were inventoried. Apple compilation/UI behavior and all physical/live-account/model-quality acceptance remain unverified. Camera recovery, arbitrary generated UI/code, passive perception, unrestricted control, full legacy-app roadmaps and unrelated companion repositories are excluded by the assignment.

Run the exact Apple and physical acceptance sequence in [implementation status](ADAPTIVE_SHELL_IMPLEMENTATION.md#qualification-and-remaining-gates). Source, executable fixture, simulator, physical-device and live semantic evidence must remain separate.
