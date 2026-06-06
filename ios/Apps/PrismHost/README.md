# PrismOS iOS App Surface

PrismOS is the SwiftUI iPhone/iPad host application for Monocle. The underlying Xcode target is still named `PrismHost`.

Phase 0 intentionally creates the app ownership folders before real UI implementation starts:

- `App`: SwiftUI app entry, root coordinator wiring, and lifecycle.
- `Bluetooth`: CoreBluetooth transport, device identity, scan, connect, reconnect, restoration, Raw Data, and NUS recognition adapters.
- `Media`: microphone, camera, audio/image stream conversion, Speech, Vision, and Translation adapters.
- `Services`: Keychain, provider, notification, clipboard, haptics, file storage, and repository adapters.
- `UI`: Device, Apps, Sessions, Diagnostics, Settings, and per-app screens.
- `Diagnostics`: runtime diagnostics, redaction, export preview, and developer surfaces.
- `Resources`: Info.plist, assets, local fixtures, and app resources.
- `PrismHostTests`: app/adapter unit tests.
- `PrismHostUITests`: simulator UI tests.

`PrismCore` remains a separate pure Swift package under `ios/Packages/PrismCore` and must not import SwiftUI, UIKit, CoreBluetooth, AVFoundation, Speech, Vision, Translation, provider SDKs, or storage frameworks.

## Watch Companion

The repository now includes a Series 3-first `PrismWatch` companion target beside `PrismHost`. The Watch app is a control deck, not a second host:

- `ios/Packages/PrismCore/Sources/PrismWatchModels` contains watch-safe snapshots, commands, acknowledgements, validators, reducers, and wire codecs.
- `WatchBridge/PhoneWatchBridge.swift` owns host-side snapshot publication, command validation, acknowledgements, queued commands, and per-app state projection.
- `WatchBridge/WatchConnectivityBridge.swift` connects the iOS runtime, local app model, and provider model to WatchConnectivity.
- `../PrismWatch/Connectivity/WatchConnectivityClient.swift` receives snapshots, sends commands, tracks pending acknowledgements, and exposes debug launch state for simulator review.
- `../PrismWatch/UI/WatchRootView.swift` renders the Lens Deck and Oracle, Vision, Signal, Chronos, Teleprompter, and Babel decks.

The iPhone Host remains authoritative for Monocle BLE, provider calls, media conversion, persistence, recovery, diagnostics, and `DRAW` layout. Watch commands synchronize runtime focus and app state through the bridge callbacks added to `RuntimeConsoleModel`, `LocalConsoleModel`, and `ProviderConsoleModel`.

The Watch source is present and builds, but real Watch/iPhone/Monocle behavior remains hardware-gated until it is validated on paired devices.

## Provider Layer

The iOS host keeps provider routing in the app target, behind `PrismCore` protocols:

- `OpenAIResponsesClient` uses `/v1/responses` for Oracle-style text requests.
- `OpenAIVisionProcessor` uses Responses image input with a JPEG data URL for Vision analysis/OCR summary.
- `OpenAITranslationClient` uses Responses with a translation prompt for Babel text translation.
- `OpenAIRealtimeWhisperTranscriptionClient` uses Realtime WebSocket input transcription for Oracle/Babel voice capture when the transcription model is `gpt-realtime-whisper`.
- `OpenAIAudioTranscriptionClient` wraps Monocle PCM16 mono audio in WAV and posts it to `/v1/audio/transcriptions` when a non-realtime transcription model is selected.

Default OpenAI model IDs are configurable in Settings. As of the 2026-05-31 Oracle/Babel audio pass, text, vision, and translation default to `gpt-5.5`, Realtime session model defaults to `gpt-realtime-2`, transcription defaults to `gpt-realtime-whisper`, and realtime transcription delay defaults to `low`. Response model choices are ordered newest practical first: `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.4-nano`, `gpt-5.2`, `gpt-5.1`, `gpt-5`, and `gpt-4.1`. Transcription choices are ordered as realtime first, then `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`, `gpt-4o-transcribe-diarize`, and `whisper-1`. Realtime session choices are `gpt-realtime-2`, `gpt-realtime-1.5`, `gpt-realtime-mini`, and `gpt-realtime`. Responses requests set `store=false`, and the HUD-oriented defaults use low reasoning effort and low text verbosity. Provider API keys remain Keychain-only, and tests use fake transports rather than live credentials by default.

Live verification on 2026-05-28 showed that the WebSocket URL must use a realtime session model such as `gpt-realtime-2`; `gpt-realtime-whisper` is passed inside `audio.input.transcription.model`. Official OpenAI realtime transcription docs consulted on 2026-05-31 also require transcription-only sessions to send `session.type = "transcription"` and 24 kHz mono PCM. Using `gpt-realtime-whisper` as the WebSocket session model is rejected by the OpenAI API.

## App Icon Assets

The current PrismOS icon follows the warm dark/gold visual direction. Source app icon assets live in `Resources/Assets.xcassets/AppIcon.appiconset/`, including `AppIcon-1024.png`. Runtime iOS icon PNGs live in `Resources/AppIcons/` and are declared in `Resources/Info.plist` through `CFBundleIcons` and `CFBundleIcons~ipad`.

The explicit PNG fallback is intentional for this local environment because `actool --app-icon` failed through `AssetCatalogSimulatorAgent` during local simulator integration.
