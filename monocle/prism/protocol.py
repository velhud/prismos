# prism/protocol.py
# PrismOS Wire Protocol v1 helpers (frame header packing/unpacking).

import ustruct as struct

MAGIC = b"PM"
VERSION = 1

# Kinds
KIND_CTRL_JSON    = 0x01
KIND_STREAM_AUDIO = 0x02
KIND_STREAM_IMAGE = 0x03
KIND_LOG_TEXT     = 0x04

# Flags
FLAG_START = 0x01
FLAG_END   = 0x02

# TOTAL_LEN sentinel for unknown-length streams
TOTAL_LEN_UNKNOWN = 0xFFFFFFFF

# Header layout:
# <2sBBBHHI  => 2 + 1 + 1 + 1 + 2 + 2 + 4 = 13 bytes
# MAGIC, VERSION, KIND, FLAGS, MSG_ID, SEQ, TOTAL_LEN
HEADER_FMT = "<2sBBBHHI"
HEADER_LEN = 13

# Device inbound protection for CTRL_JSON reassembly
MAX_RX_TOTAL_LEN = 4096  # bytes

def pack_header(buf, kind, flags, msg_id, seq, total_len):
    """
    Packs a v1 header into `buf` (bytearray/memoryview) at offset 0.
    buf must be at least HEADER_LEN bytes.
    """
    struct.pack_into(
        HEADER_FMT,
        buf,
        0,
        MAGIC,
        VERSION,
        int(kind) & 0xFF,
        int(flags) & 0xFF,
        int(msg_id) & 0xFFFF,
        int(seq) & 0xFFFF,
        int(total_len) & 0xFFFFFFFF
    )

def unpack_header(data):
    """
    Returns (kind, flags, msg_id, seq, total_len) if header is valid, else None.
    """
    if data is None or len(data) < HEADER_LEN:
        return None
    magic, ver, kind, flags, msg_id, seq, total_len = struct.unpack_from(HEADER_FMT, data, 0)
    if magic != MAGIC or ver != VERSION:
        return None
    return kind, flags, msg_id, seq, total_len

