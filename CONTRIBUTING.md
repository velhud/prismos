# Contributing

Contributions are welcome.

Before opening a pull request:

1. Keep the host-first architecture intact.
2. Keep Monocle runtime changes small, recoverable, and bounded by memory limits.
3. Keep provider calls credential-gated and mockable.
4. Run the relevant Swift or Python tests for the area you changed.
5. Do not commit generated build output, local hardware evidence, `.env` files, or signing identities.

For hardware work, document the test method and result without publishing private device identifiers.
