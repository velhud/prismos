# Gallery OS

Gallery OS is the PrismOS camera app. It is host-first: Monocle owns camera capture and JPEG streaming, while the iPhone Host owns app state, Photos permission, persistence, and user feedback.

## Product Contract

- Active app ID: `gallery`.
- Display label: `Gallery OS`.
- `TAP_R` while Gallery OS is focused starts photo capture.
- The iPhone app capture control sends the same command.
- Host command to Monocle: `CTRL_JSON` media command with `cmd=CAPTURE_IMAGE`, `app=gallery`, `request_id`, and `timeout`.
- Expected Monocle response: `STREAM_IMAGE` (`PM` kind `0x03`) containing JPEG bytes.
- iPhone save target: iOS Photos through `PHPhotoLibrary`.
- iOS permissions: Photos add/read permission for saving and reviewing captured output.

## Runtime States

- `READY`: Gallery OS is focused and ready for capture.
- `CAPTURE`: capture command was sent and the Host is waiting for `STREAM_IMAGE`.
- `SAVED`: iPhone Photos save completed and the lens shows saved state.
- `ERROR`: iPhone save failed, the image stream reports an error, or the Host times out waiting for `STREAM_IMAGE`.

## Failure Handling

- Gallery OS must ignore duplicate capture taps while one image request is pending.
- The Host owns the capture timeout because it owns the BLE request and pending media target.
- If no `STREAM_IMAGE` arrives before timeout, the Host clears the pending capture and routes a bounded image error back to Gallery OS.
- A successful `STREAM_IMAGE` cancels the timeout, saves the JPEG through Photos, and updates Gallery OS to `SAVED`.
- Gallery OS must save only actual JPEG image bytes, never metadata-only `IMAGE END` or status events.
- If Gallery OS is not focused when a late image or timeout arrives, app state may update; the Monocle lens should redraw immediately only when Gallery OS is focused.

## Non-Goals

- Gallery OS does not analyze images. That remains Vision or a future agent/tool workflow.
- Gallery OS does not stream live video. It captures single JPEG frames.
- Gallery OS does not replace Monocle capture with the iPhone camera as the product answer. Any phone-camera fallback is only a continuity or diagnostic path.
- Gallery OS does not store private app-local photo copies by default; Photos is the durable user-facing destination.

## Current Hardware Gate

As of 2026-05-30, Gallery OS is blocked by the Monocle camera capture path, not by the iPhone UI or Photos save path.

Physical and Mac-side evidence is recorded in `Documentation/MONOCLE_CAMERA_CAPTURE_FAILURE_2026_05_30.md`.

Current proven facts:

- The Host can send `CAPTURE_IMAGE`.
- The Monocle can receive and dispatch the command.
- The Monocle emits media-start events.
- The camera/FPGA status remains `b'2'`.
- The image byte count remains `0`.
- No `STREAM_IMAGE` JPEG bytes arrive.
- The same failure remains after verified official FPGA app refresh.

Required before claiming Gallery OS works end to end:

1. Prove a vendor-minimal Monocle camera capture can produce JPEG bytes.
2. Prove PrismOS `kernel.py` can stream those JPEG bytes as `STREAM_IMAGE`.
3. Prove the iPhone Host saves the received JPEG into Photos.
4. Prove focused Gallery OS updates from `CAPTURE` to `SAVED` on the physical iPhone.

## Verification Status

Host-side tests and simulator checks can prove state handling, timeout recovery, and Photos-save adapters, but they cannot prove Monocle image capture.

The current missing proof is physical:

- a real Monocle JPEG stream from `CAPTURE_IMAGE`;
- saved output visible in iPhone Photos;
- repeated capture without leaving Gallery OS stuck in `CAPTURE`.
