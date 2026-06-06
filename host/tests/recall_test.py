# host/tests/recall_test.py
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

# Always ensure a display mock exists with the necessary properties
if 'display' not in sys.modules:
    class MockDisplayBase:
        WHITE = 0xFFFFFF
        GRAY6 = 0xAAAAAA
        GRAY3 = 0x555555
        YELLOW = 0xFFEE33
        GREEN = 0x1D6914
        MIDDLE_CENTER = "MIDDLE_CENTER"
        def clear(self): pass
        def show(self, *args, **kwargs): pass
        def brightness(self, val): pass
    sys.modules['display'] = MockDisplayBase()

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
from apps import recall
from prism import ui

class TestRecallApp(unittest.TestCase):
    def test_lifecycle_and_rendering(self):
        # Clean up any stale persistence file from previous runs
        try:
            if os.path.exists("pm_recall_checked.json"):
                os.remove("pm_recall_checked.json")
        except Exception:
            pass

        app = recall.create()
        self.assertTrue(app.on_start())
        self.assertEqual(app.view, "DECKS")

        # Initial DECKS state update
        payload = {
            "view": "DECKS",
            "deck_title": "GROCERIES",
            "deck_index": 0,
            "deck_count": 3
        }
        self.assertTrue(app.on_data(payload))
        self.assertEqual(app.deck_title, "GROCERIES")
        self.assertEqual(app.deck_count, 3)

        # Let's render and assert all display objects use MIDDLE_CENTER
        objs = app.render()
        self.assertTrue(len(objs) > 0)
        for obj in objs:
            self.assertEqual(obj.justify, "MIDDLE_CENTER")

        # Checklist view state update
        payload_checklist = {
            "view": "CARD",
            "deck_title": "GROCERIES",
            "deck_index": 0,
            "deck_count": 3,
            "card_index": 0,
            "card_count": 1,
            "mode": "CHECKLIST",
            "cursor": 0,
            "lines": [
                "[ ] Milk",
                "[x] Bread"
            ]
        }
        self.assertTrue(app.on_data(payload_checklist))
        self.assertEqual(app.view, "CARD")
        self.assertEqual(app.mode, "CHECKLIST")
        self.assertEqual(app.cursor, 0)
        self.assertEqual(len(app.lines), 2)

        # Verify cursor scrolling and local toggles
        app.on_input("TAP_R") # Down
        self.assertEqual(app.cursor, 1)

        app.on_input("TAP_L") # Up
        self.assertEqual(app.cursor, 0)

        # Toggle item 0 from "[ ] Milk" to "[x] Milk"
        app.on_input("LONG_R")
        self.assertEqual(app.lines[0], "[x] Milk")

        # Test local checklist persistence: recreate app, load same checklist structure and check if state is restored
        app2 = recall.create()
        self.assertTrue(app2.on_start())
        payload_restore = {
            "view": "CARD",
            "deck_title": "GROCERIES",
            "deck_index": 0,
            "deck_count": 3,
            "card_index": 0,
            "card_count": 1,
            "mode": "CHECKLIST",
            "cursor": 0,
            "lines": [
                "[ ] Milk",
                "[x] Bread"
            ]
        }
        # When calling on_data, it should auto-load the previously saved state where item 0 "[ ] Milk" was toggled to "[x] Milk"
        self.assertTrue(app2.on_data(payload_restore))
        self.assertEqual(app2.lines[0], "[x] Milk")

        # Clean up the test-created JSON file to keep workspace clean
        try:
            if os.path.exists("pm_recall_checked.json"):
                os.remove("pm_recall_checked.json")
        except Exception:
            pass

        # Re-render check and verify middle-center
        objs = app2.render()
        self.assertTrue(len(objs) > 0)
        for obj in objs:
            self.assertEqual(obj.justify, "MIDDLE_CENTER")

if __name__ == '__main__':
    unittest.main()
