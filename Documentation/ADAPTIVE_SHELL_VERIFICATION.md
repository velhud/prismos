# Adaptive shell verification receipt

Date: 28 October 2026. Integration branch: `implement/adaptive-shell-20261028`. Source base: `e2f9ac47dd5c0a661154ce87de5d99ea68ad526b`. Source, executable fixture, Apple simulator, live provider and physical-device evidence are distinct. This is not a release or physical acceptance label.

## Executed checks

| Check | Result / evidence class |
|---|---|
| Untouched base package in a separate extracted tree | **85 tests passed**, Linux baseline |
| `swift test --package-path ios/Packages/PrismCore --jobs 4` | **122 tests passed**, Linux executable package owners |
| `python3 -m unittest discover -s host/tests -p '*_test.py'` | **72 tests passed**, Python host/reference/device owners |
| Offline `PrismShellEvaluate` capture | **20 complete reference cases structurally accepted**, semantic scores deliberately unassigned |
| PrismHost unit tests on iPhone 17 Pro simulator, iOS 26.5 / Xcode 26.5 (17F42) | **62 tests passed**, including native transcription/permission boundaries and timer notification race/restart tests |
| Full native Home/Lens/Library/Settings XCUITest run | **5 UI journeys passed together with all 62 native tests**, one complete green Xcode run; all 12 scenes, five turns/relaunch, note receipts/undo, Library edit/share/delete, consent/blank and Developer Mode separation |
| PrismHost Release build, generic iOS Simulator | **Build succeeded**, Apple SDK compilation; Debug acceptance ingress excluded |
| PrismWatch direct target build, `-sdk watchsimulator` | **Build succeeded**, Apple Watch SDK compilation for applicable architectures |
| PrismWatch scheme / generic Watch simulator destination | Blocked: Watch 26.5 platform components/runtime unavailable. Direct SDK build above is separate successful evidence; no Watch simulator execution claimed |
| `git diff --check` | Passed |
| Live provider/model semantics, actual Calendar/Reminders effects | **Not run**; no provider spending or personal account effects authorized |
| Physical Monocle/iPhone/Watch, real audio routing, locked-screen, BLE restoration, notification delivery and soak | **Not run** |

Linux uses official Swift 6.2.3 for Ubuntu 24.04 in the package's Swift 5 language/tools contract. Apple checks use an isolated scratch extraction on the reachable Mac. Existing public/private Mac checkouts are untouched. No firmware install, hardware connect/scan, physical app install, reboot, account mutation or provider request was performed.

The earlier source receipt at `1831aba` had 114 Swift / 72 Python passes and no Apple execution. Continuation then reached the Mac. Its first native unit run found one legacy reserved-gesture diagnostic test failure (59/60); the reserved helper/diagnostic order were repaired, and the current native unit run passes. Intermediate UI runs exposed consent hit-target, accessibility selector, keyboard-dismissal and invalid-fixture issues; they are retained as historical failures in the private evidence packet. They are not retroactively called green. Xcode also emitted a nonfatal simctl diagnostics-collector PATH error after successful test execution; test result bundles and screenshot attachments were exported successfully.

A separate all-scene screen-capture run also passed. Visual export has an instrumentation limit: some app-window and screen captures intermittently omit otherwise stable chrome, while other frames (including timer/comparison) are complete. Raw captures are preserved privately. Automated journey/bounds passes are not a pixel-perfect visual signoff; reliable on-screen and physical visual acceptance remains open.

## Reproducible Apple commands

Use an available iPhone simulator name (`xcrun simctl list devices available`). The project instruction's iPhone 16 was not installed; the actual destination used here was iPhone 17 Pro.

```bash
xcodebuild test -project ios/Apps/PrismHost/PrismHost.xcodeproj -scheme PrismHost \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO -jobs 2 CODE_SIGNING_ALLOWED=NO
xcodebuild build -project ios/Apps/PrismHost/PrismHost.xcodeproj -scheme PrismHost \
  -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project ios/Apps/PrismHost/PrismHost.xcodeproj -target PrismWatch \
  -configuration Debug -sdk watchsimulator CODE_SIGNING_ALLOWED=NO
```

After installing the appropriate Watch simulator components, the requested Watch scheme destination can be exercised separately:

```bash
xcodebuild build -project ios/Apps/PrismHost/PrismHost.xcodeproj -scheme PrismWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch SE 3 (40mm)' CODE_SIGNING_ALLOWED=NO
```

## Coverage and limits

- Real Responses adapter and read-tool loop: malformed/unknown payloads, refusal/incomplete output, mutation-function rejection, host-receipt forgery rejection and complete context/tool results.
- Five-turn continuity, long-answer persistence/relaunch, full transcripts, separate complete speech and glanceable projection, byte conversion, cancel/late results.
- All 12 scene kinds, paging, Unicode/long words, UTF-8 byte and whole text-box bounds, pack/reassembly, queue backpressure/coalescing/priority blank, reconnect epochs, stale/duplicate gestures and audio correlation.
- Notes, reminders, timer/session and conversational choices: exact preview, explicit confirmation, idempotent receipts, compound requests, undo ownership, durable external-effect/undo uncertainty, reconciliation and blank during native completion.
- Proactive source identity/time/freshness, AI-boundary interpretation, quiet suppression, failed-evaluation cooldown, snooze/expiry/source disappearance and restart/reconnect deduplication.
- Watch version/session/privacy/freshness and complete bounded action previews; no offline mutation queue.
- Canonical retention, raw-media policy, minimal external ledger, corrupt-store preservation and interrupted process restoration.
- Actual Python kernel handshake, bounded capture/streaming/retry, FIFO control/DRAW order, empty DRAW, cancellation, physical-blank barrier and offline lease, with only hardware module boundaries doubled.
- Consequential legacy data-loss callers: complete Oracle copy/history/paging/follow-up, Vision summary/OCR, Babel beyond 24 lines and Teleprompter source/long words.

The semantic set contains 20 fictional requests with complete source context, reference answers, speech, scenes, actions, expected reads and case-specific meaning-based rubrics. Offline replay and structural acceptance do **not** measure live model quality. The evaluation executable captures complete requests/plans and leaves semantic judgment to a separately identified reviewer; it never assigns token-presence scores or confirms effects.

The inventoried surface is every normal phone tab, the Watch entry point, all 12 scene variants, all nine tools, transport/media/persistence/context/provider owners, consequential legacy truncation callers, test/project membership and current documentation entrypoints. Exclusions remain those in the assignment: camera recovery, arbitrary generated UI/code, passive perception, unrestricted control, full legacy-app roadmaps and unrelated companion repositories. Remaining real-device/account/model acceptance is listed in the [implementation status](ADAPTIVE_SHELL_IMPLEMENTATION.md#qualification-and-remaining-gates).
