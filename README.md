# PrismOS

PrismOS is a native, host-first personal assistant for Brilliant Labs Monocle. One iPhone-owned conversation generates temporary interfaces across the lens, speech, phone and Watch. The lens is blank by default. The normal phone app has **Home, Lens, Library and Settings**.

The iPhone owns Bluetooth, context, model requests, actions, persistence and rendering. Monocle renders bounded text payloads and reports gestures and deliberately captured audio. Watch projects the phone's state; it never owns BLE or provider calls.

## Adaptive shell

- Typed or deliberately captured voice → context → structured `ExperiencePlan` → native scene → bounded binary DRAW.
- Complete answers and transcripts in an atomic, protected local Library; separate spoken and glanceable lens responses.
- Twelve trusted scene types: blank, activity, fact, list, comparison, choice, confirmation, progress, caption, timer, alert and route. Models cannot supply coordinates or executable UI.
- Notes, search, EventKit reminders, calendar reads, optional authenticated agent exceptions, timers and session/project state. Mutations require an exact preview and confirmation, then produce receipts and undo where supported.
- Optional upcoming-calendar candidates interpreted by AI, with source, time, reason, expiry, dismiss, snooze and durable duplicate suppression.
- Explicit remembered Monocle identity, CoreBluetooth restoration, fragmented writes, backpressure, media reconstruction, cancellation and an offline display lease.

**Qualification:** the shared Swift runtime and Python device/reference tests execute on Linux. Apple adapter sources and platform tests are present, but this change has not been compiled with Xcode or exercised on an iPhone, Watch or Monocle. Reference scenario replay is not a live model quality score. See [implementation status](Documentation/ADAPTIVE_SHELL_IMPLEMENTATION.md) for the exact inventory, evidence classes and remaining acceptance gates.

## Setup

Open `ios/PrismOS.xcworkspace` in Xcode. Public-safe bundle identifiers are checked in; supply your own signing team locally for physical devices.

In Settings, select your Monocle explicitly and configure your assistant API key in Keychain. Cloud processing, calendar context and proactive surfaces start disabled. The production text model retains the repository's `gpt-5.5` default; bounded voice capture uses file transcription with `gpt-transcribe` and native iPhone speech output. API billing is separate from ChatGPT/Codex subscriptions. No provider calls are needed to run offline tests.

An existing Monocle runtime without shell version 1 reports incompatibility. This app does not flash, reset or recover hardware automatically. Keep `monocle/main.py` and `monocle/boot.py` recoverable and follow the hardware owner's separate deployment/recovery process.

The old Oracle, Chronos, Babel, Signal, Vision and Teleprompter console remains available only after entering Developer Mode. Camera repair, continuous passive capture, arbitrary generated code/UI, universal app control and remote approvals are outside this build. Python is a protocol/device laboratory, not a second production assistant.

## Verification

```bash
swift test --package-path ios/Packages/PrismCore
python3 -m unittest discover -s host/tests -p '*_test.py'
xcodebuild test -project ios/Apps/PrismHost/PrismHost.xcodeproj -scheme PrismHost -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project ios/Apps/PrismHost/PrismHost.xcodeproj -scheme PrismWatch -destination 'platform=watchOS Simulator,name=Apple Watch SE 3 (40mm)' CODE_SIGNING_ALLOWED=NO
```

Hardware verification and private identifiers must stay outside the public repository. Provider keys belong in Keychain or ignored environment files. The recovered private discussion is not part of this repository.
