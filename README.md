# PrismOS

PrismOS is a host-first operating surface for Brilliant Labs Monocle hardware. The iPhone Host owns BLE, app state, layout, providers, media processing, persistence, diagnostics, recovery, and bounded `DRAW` output. Monocle stays a thin display, touch, camera, microphone, and boot/recovery endpoint.

The repository also contains a Series 3-first Apple Watch companion. The Watch is a control surface for PrismOS, not a second Monocle host: it renders compact state snapshots, sends semantic commands to the iPhone, and leaves BLE, providers, persistence, recovery, diagnostics, and display layout on the phone.

This public repository is a clean export of the project source and selected documentation. It intentionally excludes private history, local environment files, generated artifacts, personal signing metadata, and hardware-specific evidence logs.

## Current Product Surface

- Native iPhone/iPad Host app: `ios/Apps/PrismHost`.
- Apple Watch companion app: `ios/Apps/PrismWatch`.
- Shared pure Swift package: `ios/Packages/PrismCore`.
- Thin Monocle firmware/runtime: `monocle/`.
- Desktop/reference Host harness: `host/`.
- Product and architecture docs: `Documentation/`.

Active production apps are Oracle, Vision, Signal, Chronos, Teleprompter, Babel, and the documented Gallery OS camera surface. Navigate and Recall remain archived prototypes unless future product work revives them with real runtime support.

## Architecture

PrismOS keeps authority on the host:

- The iPhone selects the Monocle by explicit identity, connects over Raw Data BLE, and sends binary `DRAW` frames.
- Monocle reports button, audio, image, and status events; it does not run provider logic or own app state.
- `PrismCore` contains platform-neutral protocol, draw, runtime, diagnostics, persistence, AI contracts, and watch model code.
- `PrismHost` contains platform services such as CoreBluetooth, Keychain, OpenAI transports, SwiftUI screens, and WatchConnectivity.
- `PrismWatch` uses WatchConnectivity snapshots and commands. It does not talk directly to Monocle in the current product shape.

## App State

- Oracle: text and voice questions, bounded HUD answers, answer paging, copy/keep/follow-up controls, and provider-backed responses when credentials are configured.
- Vision: Monocle image capture request path, OCR/scene analysis state, note save, retake/cancel, and Oracle follow-up.
- Signal: local card stack, priority order, privacy masking, selection, dismissal, reload, and handoff URL support.
- Chronos: timer/stopwatch state, alarm boundary, pinning, duration presets, add-time, reset, and host-owned truth.
- Teleprompter: host-imported script chunks, manual/auto movement, bookmark, reset, WPM adjustment, and privacy masking.
- Babel: text/audio translation state, freeze, language swap, presets, transcript save/clear, and repeat-last.
- Gallery OS: product-facing camera surface; real Monocle image capture is currently blocked by the device camera path recorded in `Documentation/MONOCLE_CAMERA_CAPTURE_FAILURE_2026_05_30.md`.

## Apple Watch State

The Watch app source is present and builds. It includes:

- a `PrismWatch` watchOS target;
- a compact Lens Deck and per-app Watch decks for Oracle, Vision, Signal, Chronos, Teleprompter, and Babel;
- `PrismWatchModels` snapshots, commands, acknowledgements, validators, reducers, and wire codecs;
- iPhone-side WatchConnectivity bridge code;
- Watch-side command queuing, acknowledgement display, degraded/offline states, haptics, and simulator debug launch state.

The implementation is simulator-verified for build and model/bridge tests, but real Apple Watch, paired iPhone, and Monocle behavior remains hardware-gated. Current follow-up is product polish and real-device validation: Lens Deck copy/typography, selected-app-vs-active-surface clarity, and per-deck functionality review.

## Repository Layout

```text
host/                         Desktop/reference Host harness and tests
monocle/                      Thin device runtime and Monocle helpers
ios/Apps/PrismHost/           iPhone/iPad SwiftUI Host app
ios/Apps/PrismWatch/          Apple Watch companion app
ios/Packages/PrismCore/       Shared Swift packages and tests
Documentation/                Product, architecture, app, protocol, and hardware docs
docs/                         Operator-facing repository map and action notes
tools/                        Local hardware/debug utilities
```

## Setup

Python tools:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

Open the iOS workspace or project in Xcode:

```bash
open ios/PrismOS.xcworkspace
```

The checked-in Xcode project uses public-safe bundle identifiers and no personal Apple Team ID. For real-device builds, set your own team and bundle identifiers locally in Xcode or via build settings.

Provider calls are optional. The iOS Host stores secrets in Keychain. The desktop host can read provider settings from environment variables or a local `.env` file.

## Verification Entry Points

Use these from the repository root:

```bash
swift test --package-path ios/Packages/PrismCore
xcodebuild test -project ios/Apps/PrismHost/PrismHost.xcodeproj -scheme PrismHost -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project ios/Apps/PrismHost/PrismHost.xcodeproj -scheme PrismWatch -destination 'platform=watchOS Simulator,name=Apple Watch SE 3 (40mm)' CODE_SIGNING_ALLOWED=NO
```

Current local Xcode installations may not provide an Apple Watch Series 3 simulator. Series 3 compatibility remains a source and hardware requirement, while simulator checks use the smallest available watchOS simulator unless a Series 3 runtime is installed.

Physical Monocle, iPhone, and Apple Watch behavior remains hardware-gated unless exact device evidence is recorded. Before any physical Monocle deploy, BLE test, boot change, renderer change, or live media check, read `Documentation/MONOCLE_RECOVERY_RUNBOOK.md`.

Hardware evidence should stay private unless device identifiers and personal signing details have been removed.
