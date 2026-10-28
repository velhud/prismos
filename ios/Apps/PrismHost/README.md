# PrismOS native host

Open `PrismHost.xcodeproj` or `../../PrismOS.xcworkspace`. The normal entry point is `PrismHostApp` → `ShellHostModel` → `PrismShellView`, with Home, Lens, Library and Settings. `AssistantOrchestrator` owns canonical state, complete persistence and action receipts. CoreBluetooth, EventKit, Keychain, audio and WatchConnectivity are iPhone-owned adapters.

Pair by explicit peripheral identity in Settings. Cloud processing and proactive sources start disabled. API credentials are stored in Keychain. Bounded Monocle audio uses file transcription and native synthesized speech. This is independent of ChatGPT/Codex subscription voice and other companion repositories.

The prior `RootConsoleView`, mock media, generic app runtime and per-app controls are instantiated only through Developer Mode. Its old Watch bridge is not activated by the production app. The Watch target now receives the same shell scene/session/receipt state and sends versioned commands; it has no BLE owner.

See [implementation status](../../../Documentation/ADAPTIVE_SHELL_IMPLEMENTATION.md) and [verification](../../../Documentation/ADAPTIVE_SHELL_VERIFICATION.md). Xcode 26.5 native tests, five UI journeys, Release and Watch SDK builds now pass. Physical acceptance, live model evaluation and real account effects still require separate qualification with the owner. See the user guide for normal operation and the fixture README for reproducible semantic capture. No automatic firmware deployment or recovery is part of this app.
