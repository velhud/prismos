# Contributor Notes

PrismOS is host-first. The iPhone Host owns BLE, app state, layout, provider calls, persistence, diagnostics, and recovery. Monocle firmware should stay thin and should only render bounded display payloads and report hardware input/media events.

## Hardware Safety

- Do not run physical Monocle deploys, BLE experiments, firmware changes, renderer changes, or recovery work unless you own the hardware and understand the recovery process.
- Use an explicit Monocle identifier for hardware work. Do not auto-connect by device name when multiple devices may be nearby.
- Keep `monocle/main.py` and `monocle/boot.py` minimal and recoverable.
- Device MicroPython code must avoid bytearray slice assignment; use explicit byte-copy helpers for BLE fragments.

## Development

- Keep provider credentials outside the repository. Use Keychain, environment variables, or local `.env` files ignored by git.
- Run simulator and unit tests before submitting changes:

```bash
swift test --package-path ios/Packages/PrismCore
xcodebuild test -project ios/Apps/PrismHost/PrismHost.xcodeproj -scheme PrismHost -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project ios/Apps/PrismHost/PrismHost.xcodeproj -scheme PrismWatch -destination 'platform=watchOS Simulator,name=Apple Watch SE 3 (40mm)' CODE_SIGNING_ALLOWED=NO
```

- Hardware verification should be documented separately from source changes and should not include private device IDs, personal paths, or signing identities.
