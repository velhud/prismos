# host/tests/bridge_test.py
import sys
import os
import unittest
from unittest.mock import MagicMock

# 1) Set up path so we can import monocle/ modules
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../monocle')))

# 2) Dynamically mock MicroPython-specific modules
class MockBluetooth:
    def __init__(self):
        self.sent_frames = []
        self.rx_callback = None

    def max_length(self):
        return 180

    def send(self, data):
        self.sent_frames.append(bytes(data))

    def receive_callback(self, fn):
        self.rx_callback = fn

mock_ble = MockBluetooth()
sys.modules['bluetooth'] = mock_ble

class MockTouch:
    def __init__(self):
        self.A = "touch_A"
        self.B = "touch_B"
    def state(self, pad):
        return False

sys.modules['touch'] = MockTouch()

class MockDisplay:
    WHITE = 1
    RED = 2
    YELLOW = 3
    GRAY = 4
    MIDDLE_CENTER = "MIDDLE_CENTER"
    def clear(self): pass
    def show(self, *args, **kwargs): pass
    def brightness(self, val): pass

sys.modules['display'] = MockDisplay()

import json
sys.modules['ujson'] = json
import struct
sys.modules['ustruct'] = struct

# Now import the modules under test
from prism import protocol
from prism import bridge
from prism import schema
from prism import ids

class TestBridgeAndSchema(unittest.TestCase):
    def setUp(self):
        mock_ble.sent_frames.clear()
        bridge._reset_rx()

    def test_successful_reassembly(self):
        # Build a JSON payload
        payload_obj = {"type": "GHOST", "active": True, "text": "Hello World"}
        payload_bytes = json.dumps(payload_obj).encode('utf-8')
        total_len = len(payload_bytes)

        # Sequence of frames
        # We will split payload into two fragments
        frag1 = payload_bytes[:10]
        frag2 = payload_bytes[10:]

        # Frame 1: START, msg_id=42, seq=0
        header1 = bytearray(protocol.HEADER_LEN)
        protocol.pack_header(header1, protocol.KIND_CTRL_JSON, protocol.FLAG_START, 42, 0, total_len)
        frame1 = bytes(header1) + frag1

        # Frame 2: END, msg_id=42, seq=1
        header2 = bytearray(protocol.HEADER_LEN)
        protocol.pack_header(header2, protocol.KIND_CTRL_JSON, protocol.FLAG_END, 42, 1, total_len)
        frame2 = bytes(header2) + frag2

        # Set callback
        received = []
        def on_msg(kind, msg_id, payload):
            received.append((kind, msg_id, bytes(payload)))
        bridge.set_on_message(on_msg)

        # Feed Frame 1
        bridge.on_rx_frame(frame1)
        self.assertEqual(len(received), 0)

        # Feed Frame 2
        bridge.on_rx_frame(frame2)
        self.assertEqual(len(received), 1)
        self.assertEqual(received[0][0], protocol.KIND_CTRL_JSON)
        self.assertEqual(received[0][1], 42)
        self.assertEqual(json.loads(received[0][2].decode('utf-8')), payload_obj)

    def test_oversized_payload_rejected(self):
        # An oversized start frame (total_len > 4096)
        header = bytearray(protocol.HEADER_LEN)
        protocol.pack_header(header, protocol.KIND_CTRL_JSON, protocol.FLAG_START, 43, 0, 5000)
        frame = bytes(header) + b"A" * 100

        # Should be rejected
        self.assertFalse(bridge._start_rx(protocol.KIND_CTRL_JSON, 43, 5000))

    def test_non_ctrl_json_start_frame_rejected(self):
        # A non-CTRL_JSON start frame (e.g. KIND_STREAM_IMAGE)
        header = bytearray(protocol.HEADER_LEN)
        protocol.pack_header(header, protocol.KIND_STREAM_IMAGE, protocol.FLAG_START, 44, 0, 1000)
        frame = bytes(header) + b"IMAGE_DATA"

        # Should return False and not allocate _rx_buf
        self.assertFalse(bridge._start_rx(protocol.KIND_STREAM_IMAGE, 44, 1000))
        self.assertIsNone(bridge._rx_buf)

    def test_schema_string_clamping(self):
        # Test widget text clamping (max 24)
        oversized_widget = "A" * 50
        sanitized_widget = schema.clamp_str(oversized_widget, schema.MAX_WIDGET_TEXT)
        self.assertEqual(len(sanitized_widget), 24)

        # Test ghost text clamping (max 48)
        oversized_ghost = "B" * 100
        sanitized_ghost = schema.clamp_str(oversized_ghost, schema.MAX_GHOST_TEXT)
        self.assertEqual(len(sanitized_ghost), 48)

        # Test toast text clamping (max 64)
        oversized_toast = "C" * 120
        sanitized_toast = schema.clamp_str(oversized_toast, schema.MAX_TOAST_TEXT)
        self.assertEqual(len(sanitized_toast), 64)

        # Test full schema sanitization of a GHOST command
        ghost_obj = {
            "type": "GHOST",
            "active": True,
            "text": "X" * 100,
            "icon": "FLASHY",
            "flash": True
        }
        res = schema.sanitize_ctrl(ghost_obj)
        self.assertIsNotNone(res)
        self.assertTrue(res["active"])
        self.assertEqual(len(res["text"]), 48)
        self.assertEqual(res["icon"], "FLASHY")
        self.assertTrue(res["flash"])

if __name__ == '__main__':
    unittest.main()
