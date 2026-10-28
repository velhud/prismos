# PrismOS native host

Open `PrismHost.xcodeproj` or `../../PrismOS.xcworkspace`. The normal entry point is `PrismHostApp` → `ShellHostModel` → `PrismShellView`, with Home, Lens, Library and Settings. `AssistantOrchestrator` owns canonical state, complete persistence and action receipts. CoreBluetooth, EventKit, Keychain, audio and WatchConnectivity are iPhone-owned adapters.

Pair by explicit peripheral identity in Settings. Cloud processing and proactive sources start disabled. API credentials are stored in Keychain. Bounded Monocle audio uses file transcription and native synthesized speech. This is independent of ChatGPT/Codex subscription voice and other companion repositories.

The prior `RootConsoleView`, mock media, generic app runtime and per-app controls are instantiated only through Developer Mode. Its old Watch bridge is not activated by the production app. The Watch target now receives the same shell scene/session/receipt state and sends versioned commands; it has no BLE owner.

See [implementation status](../../../Documentation/ADAPTIVE_SHELL_IMPLEMENTATION.md) and [verification](../../../Documentation/ADAPTIVE_SHELL_VERIFICATION.md). Linux package tests and syntax parsing do not establish Apple SDK compilation. Run the repository's Xcode host tests and Watch build, then perform separately authorized physical acceptance with the hardware owner. No automatic firmware deployment or recovery is part of this app.
