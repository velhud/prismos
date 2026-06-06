# Security Policy

PrismOS is a hardware-adjacent project. Please report security issues privately before public disclosure.

Do not commit:

- provider API keys or `.env` files;
- personal Apple Team IDs, signing identities, provisioning profiles, or physical device IDs;
- physical hardware logs that expose private device identifiers;
- captured images, audio, transcripts, or diagnostics from real users.

The iOS Host should store provider credentials in Keychain. The desktop host reads optional provider credentials from environment variables or a local `.env` file.
