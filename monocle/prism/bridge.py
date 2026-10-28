# prism/bridge.py
# Framed transport utilities using the Monocle `bluetooth` module (Raw Data Service).

import bluetooth
import ujson
import gc

from prism import protocol

def _copy_into(dst, off, src):
    for i in range(len(src)):
        dst[off + i] = src[i]


# Outbound message id generator
_msg_id = 1

# TX buffer reused to avoid per-frame allocations
_tx_buf = None
_tx_buf_len = 0

# Inbound reassembly state (single in-flight message to reduce RAM complexity)
_rx_kind = None
_rx_msg_id = None
_rx_total_len = 0
_rx_expected_seq = 0
_rx_written = 0
_rx_buf = None
_rx_active = False

# Callback invoked when a full message is reassembled:
# fn(kind:int, msg_id:int, payload:bytearray)
_on_message = None


def set_on_message(fn):
    global _on_message
    _on_message = fn


def _next_msg_id():
    global _msg_id
    mid = _msg_id
    _msg_id = (_msg_id + 1) & 0xFFFF
    if _msg_id == 0:
        _msg_id = 1
    return mid


def next_msg_id():
    """Public: allocate a new message id for custom send flows."""
    return _next_msg_id()


def _ensure_tx_buf():
    global _tx_buf, _tx_buf_len
    max_len = bluetooth.max_length()
    if _tx_buf is None or _tx_buf_len != max_len:
        _tx_buf_len = max_len
        _tx_buf = bytearray(max_len)


def max_fragment_len():
    """Maximum payload fragment size in a single BLE frame (excluding 13-byte header)."""
    try:
        _ensure_tx_buf()
        frag = int(_tx_buf_len) - int(protocol.HEADER_LEN)
        return frag if frag > 0 else 0
    except Exception:
        return 0


# -------------------------
# Outbound (known length)
# -------------------------

def send_bytes(kind, payload_bytes, msg_id=None):
    """
    Sends payload_bytes as one or more framed packets of the given KIND.
    TOTAL_LEN is known and set to len(payload_bytes).
    Frames are flagged START/MIDDLE/END.
    Returns msg_id used.
    """
    if payload_bytes is None:
        payload_bytes = b""

    _ensure_tx_buf()

    max_len = _tx_buf_len
    header_len = protocol.HEADER_LEN
    frag_max = max_len - header_len
    if frag_max <= 0:
        return 0

    total_len = len(payload_bytes)
    mid = _next_msg_id() if msg_id is None else (int(msg_id) & 0xFFFF)

    mv = memoryview(payload_bytes)
    seq = 0
    offset = 0

    # Special case: empty payload still emits one frame (START|END)
    if total_len == 0:
        flags = protocol.FLAG_START | protocol.FLAG_END
        protocol.pack_header(_tx_buf, kind, flags, mid, 0, 0)
        bluetooth.send(_tx_buf[:header_len])
        return mid

    while offset < total_len:
        frag = mv[offset: offset + frag_max]
        frag_len = len(frag)

        flags = 0
        if offset == 0:
            flags |= protocol.FLAG_START
        if (offset + frag_len) >= total_len:
            flags |= protocol.FLAG_END

        protocol.pack_header(_tx_buf, kind, flags, mid, seq, total_len)

        _copy_into(_tx_buf, header_len, frag)
        send_len = header_len + frag_len
        bluetooth.send(_tx_buf[:send_len])

        offset += frag_len
        seq += 1

    return mid


def send_json(obj, msg_id=None):
    """
    Serializes a dict to UTF-8 JSON bytes and sends as KIND_CTRL_JSON.
    """
    s = ujson.dumps(obj)
    b = s.encode("utf-8")
    return send_bytes(protocol.KIND_CTRL_JSON, b, msg_id=msg_id)


# -------------------------
# Outbound (unknown length streaming)
# -------------------------

def send_chunks(kind, chunks_iter, msg_id=None, total_len_unknown=True):
    """
    Sends an iterator/generator of bytes chunks as a single message (multi-frame).
    Does NOT require buffering the full payload.
    Uses TOTAL_LEN_UNKNOWN by default.

    Chunk rules:
    - each yielded chunk must be a bytes-like object (bytes/bytearray/memoryview)
    - empty chunks are ignored
    - None is treated as end-of-stream if yielded (optional)
    """
    _ensure_tx_buf()

    max_len = _tx_buf_len
    header_len = protocol.HEADER_LEN
    frag_max = max_len - header_len
    if frag_max <= 0:
        return 0

    mid = _next_msg_id() if msg_id is None else (int(msg_id) & 0xFFFF)
    total_len = protocol.TOTAL_LEN_UNKNOWN if total_len_unknown else 0

    # One-chunk lookahead to set END on the final chunk
    prev = None
    seq = 0
    started = False

    for ch in chunks_iter:
        if ch is None:
            break
        mv = memoryview(ch)
        if len(mv) == 0:
            continue

        if prev is None:
            prev = mv
            continue

        # Send prev as non-final (may still be split to frag_max)
        seq = _send_stream_fragmented(
            kind, mid, prev, seq, total_len, start=(not started), end=False
        )
        started = True
        prev = mv

    # Finalize
    if prev is None:
        flags = protocol.FLAG_START | protocol.FLAG_END
        protocol.pack_header(_tx_buf, kind, flags, mid, 0, total_len)
        bluetooth.send(_tx_buf[:header_len])
        return mid

    seq = _send_stream_fragmented(
        kind, mid, prev, seq, total_len, start=(not started), end=True
    )
    return mid


def _send_stream_fragmented(kind, mid, mv, seq_start, total_len, start, end):
    """
    Sends a bytes-like memoryview mv as one or more frames, applying START only to the first frame
    of the first chunk, and END only to the last frame of the last chunk.
    """
    header_len = protocol.HEADER_LEN
    frag_max = _tx_buf_len - header_len

    offset = 0
    seq = seq_start
    length = len(mv)

    while offset < length:
        frag = mv[offset: offset + frag_max]
        frag_len = len(frag)

        flags = 0
        if start and offset == 0:
            flags |= protocol.FLAG_START
        if end and (offset + frag_len) >= length:
            flags |= protocol.FLAG_END

        protocol.pack_header(_tx_buf, kind, flags, mid, seq, total_len)

        _copy_into(_tx_buf, header_len, frag)
        bluetooth.send(_tx_buf[:header_len + frag_len])

        offset += frag_len
        seq += 1

    return seq


# -------------------------
# NEW: incremental stream sender (non-blocking, step per on_update)
# -------------------------

class StreamSender:
    """
    Incremental sender for stream kinds (STREAM_IMAGE / STREAM_AUDIO).
    Designed to let apps send 1 read-chunk per update without blocking the kernel.

    Semantics:
    - send_chunk(data): sends data bytes (may split if > frag_max)
        - START is automatically set on the first frame
        - END is NOT set here
    - finish(): sends an empty END frame (and START too if nothing was ever sent)
    """
    def __init__(self, kind, msg_id=None, total_len=None):
        self.kind = int(kind) & 0xFF
        self.msg_id = _next_msg_id() if msg_id is None else (int(msg_id) & 0xFFFF)

        if total_len is None:
            total_len = protocol.TOTAL_LEN_UNKNOWN
        self.total_len = int(total_len) & 0xFFFFFFFF

        self.seq = 0
        self.started = False
        self.closed = False

    def send_chunk(self, data):
        if self.closed:
            return False
        if data is None:
            return True

        mv = memoryview(data)
        if len(mv) == 0:
            return True

        _ensure_tx_buf()
        header_len = protocol.HEADER_LEN
        frag_max = _tx_buf_len - header_len
        if frag_max <= 0:
            return False

        off = 0
        while off < len(mv):
            frag = mv[off: off + frag_max]
            frag_len = len(frag)

            flags = 0
            if not self.started:
                flags |= protocol.FLAG_START

            protocol.pack_header(_tx_buf, self.kind, flags, self.msg_id, self.seq, self.total_len)
            _copy_into(_tx_buf, header_len, frag)
            bluetooth.send(_tx_buf[:header_len + frag_len])

            self.seq += 1
            self.started = True
            off += frag_len

        return True

    def finish(self):
        if self.closed:
            return

        _ensure_tx_buf()

        flags = protocol.FLAG_END
        if not self.started:
            flags |= protocol.FLAG_START

        protocol.pack_header(_tx_buf, self.kind, flags, self.msg_id, self.seq, self.total_len)
        bluetooth.send(_tx_buf[:protocol.HEADER_LEN])

        self.seq += 1
        self.started = True
        self.closed = True


# -------------------------
# Inbound (device-side reassembly)
# -------------------------

def _reset_rx():
    global _rx_kind, _rx_msg_id, _rx_total_len, _rx_expected_seq, _rx_written, _rx_buf, _rx_active
    _rx_kind = None
    _rx_msg_id = None
    _rx_total_len = 0
    _rx_expected_seq = 0
    _rx_written = 0
    _rx_buf = None
    _rx_active = False


def _start_rx(kind, msg_id, total_len):
    global _rx_kind, _rx_msg_id, _rx_total_len, _rx_expected_seq, _rx_written, _rx_buf, _rx_active

    # If another message is already in-flight, explicitly clear it
    if _rx_active:
        _reset_rx()
        gc.collect()

    # Device only reassembles known-length CTRL_JSON safely.
    if kind != protocol.KIND_CTRL_JSON:
        return False
    if total_len == protocol.TOTAL_LEN_UNKNOWN:
        return False
    if total_len < 0 or total_len > protocol.MAX_RX_TOTAL_LEN:
        return False

    _rx_kind = kind
    _rx_msg_id = msg_id
    _rx_total_len = total_len
    _rx_expected_seq = 0
    _rx_written = 0
    try:
        _rx_buf = bytearray(total_len) if total_len else bytearray(0)
    except MemoryError:
        _reset_rx()
        gc.collect()
        return False
    _rx_active = True
    return True


def on_rx_frame(data):
    """
    Intended for bluetooth.receive_callback(...).
    Accepts a single raw frame bytes object.
    """
    global _rx_kind, _rx_msg_id, _rx_total_len, _rx_expected_seq, _rx_written, _rx_buf, _rx_active
    if data is None or len(data) < protocol.HEADER_LEN:
        return

    header = protocol.unpack_header(data)
    if header is None:
        return

    kind, flags, msg_id, seq, total_len = header
    frag = data[protocol.HEADER_LEN:]

    is_start = (flags & protocol.FLAG_START) != 0
    is_end = (flags & protocol.FLAG_END) != 0

    # START begins a new message (reset state).
    if is_start:
        if not _start_rx(kind, msg_id, total_len):
            return

    # If not started, ignore
    if not _rx_active:
        return

    # Validate identity
    if msg_id != _rx_msg_id or kind != _rx_kind:
        _reset_rx()
        return

    # Validate ordering
    if seq != _rx_expected_seq:
        _reset_rx()
        return

    # Copy fragment
    frag_len = len(frag)
    if frag_len:
        end_i = _rx_written + frag_len
        if end_i > _rx_total_len:
            _reset_rx()
            return
        _copy_into(_rx_buf, _rx_written, frag)
        _rx_written = end_i

    _rx_expected_seq += 1

    # END completes message
    if is_end:
        if _rx_written != _rx_total_len:
            _reset_rx()
            return

        if _on_message is not None:
            try:
                _on_message(_rx_kind, _rx_msg_id, _rx_buf)
            except Exception:
                pass

        _reset_rx()
        gc.collect()


def decode_json_payload(payload_bytes):
    """
    Decodes a CTRL_JSON payload (bytearray/bytes) into a dict. Returns None on failure.
    """
    try:
        s = bytes(payload_bytes).decode("utf-8")
        return ujson.loads(s)
    except Exception:
        return None
