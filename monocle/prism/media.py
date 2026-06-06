# prism/media.py
# Convenience helpers combining hal + bridge + protocol kinds.
#
# These functions define a repo-standard way to send streams without buffering:
# - image bytes -> KIND_STREAM_IMAGE via bridge.send_chunks(...)
# - audio bytes -> KIND_STREAM_AUDIO via bridge.send_chunks(...)

from prism import hal
from prism import bridge
from prism import protocol


def send_camera_capture_stream(msg_id=None, chunk_bytes=254):
    """
    Captures an image and streams all bytes as a single STREAM_IMAGE message.
    TOTAL_LEN may be unknown (protocol.TOTAL_LEN_UNKNOWN).
    """
    ok = hal.camera_capture()
    if not ok:
        return 0

    def gen():
        for b in hal.iter_camera_bytes(chunk_bytes=chunk_bytes):
            yield b

    return bridge.send_chunks(protocol.KIND_STREAM_IMAGE, gen(), msg_id=msg_id, total_len_unknown=True)


def send_mic_record_stream(seconds=4.0, sample_rate=8000, bit_depth=8, msg_id=None, samples=127):
    """
    Starts a mic recording and streams all bytes as a single STREAM_AUDIO message.
    """
    ok = hal.mic_record(seconds=seconds, sample_rate=sample_rate, bit_depth=bit_depth)
    if not ok:
        return 0

    # Some firmwares require a short delay before reads return data; do not hardcode delays here.
    def gen():
        for b in hal.iter_mic_bytes(samples=samples):
            yield b

    return bridge.send_chunks(protocol.KIND_STREAM_AUDIO, gen(), msg_id=msg_id, total_len_unknown=True)


def send_log_text(text, msg_id=None):
    """
    Sends a small LOG_TEXT message (known-length).
    """
    if text is None:
        text = ""
    b = str(text).encode("utf-8")
    return bridge.send_bytes(protocol.KIND_LOG_TEXT, b, msg_id=msg_id)

