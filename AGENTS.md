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

## Literal Whole-Scope Requests
- When the user asks to do something across the whole project, across every file, across every page of a website, across every UI layer, across all cards/components/routes, or uses similar whole-scope wording, treat it as a literal requirement, not emphasis or rhetoric.
- Do not narrow the task to the most recent example, the most visible offender, the current file, or a representative subset unless the user explicitly narrows the scope.
- Before claiming completion, inventory the full requested surface: all relevant files, routes, pages, components, data sources, generated views, locales, and variants that the wording covers.
- Execute and verify against that full inventory. For websites, this means checking every affected public route/page and the shared components that can render the pattern. For code changes, this means searching all relevant files and call sites, not only the initial examples.
- If a literal whole-scope request is too large, risky, or ambiguous, stop and say exactly what scope is covered, what is excluded, and why. Do not silently reduce scope.
- Final reports for whole-scope requests must state the inventory checked and any remaining exclusions or unverified areas.

