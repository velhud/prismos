# host/tests/babel_test.py
import sys
import os
import unittest
from unittest.mock import MagicMock

# Set up path so we can import monocle/ modules
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../monocle')))

# Setup mocks if not already mocked
if 'bluetooth' not in sys.modules:
    class MockBluetooth:
        def max_length(self): return 180
        def send(self, data): pass
        def receive_callback(self, fn): pass
    sys.modules['bluetooth'] = MockBluetooth()

if 'touch' not in sys.modules:
    class MockTouch:
        def state(self, pad): return False
    sys.modules['touch'] = MockTouch()

if 'display' not in sys.modules:
    class MockText:
        def __init__(self, text, cx, cy, color, justify):
            self.text = text
            self.cx = cx
            self.cy = cy
            self.color = color
            self.justify = justify
        def __repr__(self):
            return f"Text({self.text}, cx={self.cx}, cy={self.cy}, justify={self.justify})"

    class MockDisplay:
        WHITE = 0xFFFFFF
        GRAY6 = 0xAAAAAA
        GRAY3 = 0x555555
        YELLOW = 0xFFEE33
        GREEN = 0x1D6914
        MIDDLE_CENTER = "MIDDLE_CENTER"
        Text = MockText
        def clear(self): pass
        def show(self, *args, **kwargs): pass
        def brightness(self, val): pass

    sys.modules['display'] = MockDisplay()

# Ensure all colors and Text mock class are attached to the mock display
class MockText:
    def __init__(self, text, cx, cy, color, justify):
        self.text = text
        self.cx = cx
        self.cy = cy
        self.color = color
        self.justify = justify
    def __repr__(self):
        return f"Text({self.text}, cx={self.cx}, cy={self.cy}, justify={self.justify})"

display_mod = sys.modules['display']
display_mod.Text = MockText
if not hasattr(display_mod, 'WHITE'): display_mod.WHITE = 0xFFFFFF
if not hasattr(display_mod, 'GRAY6'): display_mod.GRAY6 = 0xAAAAAA
if not hasattr(display_mod, 'GRAY3'): display_mod.GRAY3 = 0x555555
if not hasattr(display_mod, 'YELLOW'): display_mod.YELLOW = 0xFFEE33
if not hasattr(display_mod, 'GREEN'): display_mod.GREEN = 0x1D6914
if not hasattr(display_mod, 'MIDDLE_CENTER'): display_mod.MIDDLE_CENTER = "MIDDLE_CENTER"

import json
sys.modules['ujson'] = json
import struct
sys.modules['ustruct'] = struct

# Now import the app under test
from apps import babel
from prism import ui

class TestBabelApp(unittest.TestCase):
    def test_lifecycle_and_rendering(self):
        app = babel.create()
        self.assertTrue(app.on_start())
        self.assertEqual(app.src, "JA")
        self.assertEqual(app.dst, "EN")

        # Initial STATE update
        payload = {
            "src": "JA",
            "dst": "EN",
            "paused": False,
            "audio_level": 0.5,
            "lines": [
                {"text": "Konnichiwa", "kind": "RAW"},
                {"text": "Hello.", "kind": "FINAL"}
            ]
        }
        self.assertTrue(app.on_data(payload))
        self.assertEqual(app.src, "JA")
        self.assertEqual(app.dst, "EN")
        self.assertFalse(app.paused)
        self.assertEqual(app.audio_level, 0.5)
        self.assertEqual(len(app.lines), 2)

        # Let's render and assert all display objects use MIDDLE_CENTER
        objs = app.render()
        self.assertTrue(len(objs) > 0)
        for obj in objs:
            self.assertEqual(obj.justify, "MIDDLE_CENTER")

        # PAUSED toggle test via input
        app.on_input("TAP_L")
        self.assertTrue(app.paused)

        # Clear history test via input
        app.on_input("TAP_R")
        self.assertEqual(len(app.lines), 0)

        # Swap languages test via input
        app.on_input("LONG_R")
        self.assertEqual(app.src, "EN")
        self.assertEqual(app.dst, "JA")

        # Re-render check and verify middle-center
        objs = app.render()
        self.assertTrue(len(objs) > 0)
        for obj in objs:
            self.assertEqual(obj.justify, "MIDDLE_CENTER")

if __name__ == '__main__':
    unittest.main()
