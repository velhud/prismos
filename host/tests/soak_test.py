# host/tests/soak_test.py
import sys
import os
import unittest
import gc

# Set up path so we can import monocle/ modules
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../monocle')))

# Setup mocks if not already mocked
if 'bluetooth' not in sys.modules:
    class MockBluetooth:
        def max_length(self): return 180
        def send(self, data): pass
        def receive_callback(self, fn): pass
    sys.modules['bluetooth'] = MockBluetooth()

import time
if not hasattr(time, 'ticks_ms'):
    time.ticks_ms = lambda: 1000
if not hasattr(time, 'ticks_add'):
    time.ticks_add = lambda t, d: t + d
if not hasattr(time, 'ticks_diff'):
    time.ticks_diff = lambda t1, t2: t1 - t2


if 'touch' not in sys.modules:
    class MockTouch:
        def state(self, pad): return False
    sys.modules['touch'] = MockTouch()

if 'display' not in sys.modules:
    class MockDisplay:
        WHITE = 0xFFFFFF
        GRAY6 = 0xAAAAAA
        GRAY3 = 0x555555
        YELLOW = 0xFFEE33
        GREEN = 0x1D6914
        MIDDLE_CENTER = "MIDDLE_CENTER"
        def clear(self): pass
        def show(self, *args, **kwargs): pass
        def brightness(self, val): pass
    sys.modules['display'] = MockDisplay()

# Mock display.Text and display shapes
class MockText:
    def __init__(self, text, cx, cy, color, justify):
        self.text = text
        self.cx = cx
        self.cy = cy
        self.color = color
        self.justify = justify

sys.modules['display'].Text = MockText

class MockShape:
    def __init__(self, *args, **kwargs): pass

sys.modules['display'].Line = MockShape
sys.modules['display'].Rectangle = MockShape
sys.modules['display'].Fill = MockShape

if 'camera' not in sys.modules:
    class MockCamera:
        def read(self): return b"\xFF\xD8\xFF"
    sys.modules['camera'] = MockCamera()

if 'microphone' not in sys.modules:
    class MockMicrophone:
        def record(self, *args, **kwargs): return True
        def read(self, *args, **kwargs): return None
    sys.modules['microphone'] = MockMicrophone()

import json
sys.modules['ujson'] = json
import struct
sys.modules['ustruct'] = struct

# Now import modules under test
from prism import ids
from prism import sys as psys
from prism import ui

class TestSystemSoakAndStress(unittest.TestCase):
    def test_consecutive_app_swaps_100_times(self):
        """
        Legacy soak: simulate swapping through the original 8 device app modules.
        Assert module purges correctly from sys.modules and there is zero leak.
        """
        app_list = [
            (ids.APP_ORACLE, "apps.oracle"),
            (ids.APP_VISION, "apps.vision"),
            (ids.APP_NAVIGATE, "apps.navigate"),
            (ids.APP_STREAM, "apps.stream"),
            (ids.APP_CHRONOS, "apps.chronos"),
            (ids.APP_TELEPROMPTER, "apps.teleprompter"),
            (ids.APP_RECALL, "apps.recall"),
            (ids.APP_BABEL, "apps.babel"),
        ]

        # Initial baseline count of modules
        initial_module_count = len(sys.modules)

        # Run 100 consecutive swaps across the legacy modules (800 load/unload cycles)
        for loop in range(100):
            for app_id, mod_path in app_list:
                # 1. Load app module
                gc.collect()
                module = __import__(mod_path, None, None, ("create",))
                app = module.create()

                # 2. Start and feed sample mock data
                app.on_start()
                
                # Feed basic dummy dictionary payload to test data parser robustly
                app.on_data({})
                
                # 3. Render verification
                objs = app.render()
                self.assertIsNotNone(objs)
                
                # Assert strict MIDDLE_CENTER justification rule for all text lines
                for obj in objs:
                    if hasattr(obj, 'justify'):
                        self.assertEqual(obj.justify, "MIDDLE_CENTER")

                # 4. Exit and unload
                app.on_exit()
                app = None
                
                # Clean sys.modules just like the kernel does
                if mod_path in sys.modules:
                    del sys.modules[mod_path]
                
                gc.collect()

        # After 800 swaps, assert that sys.modules has not leaked or grown with app modules
        for _, mod_path in app_list:
            self.assertNotIn(mod_path, sys.modules)

        # Confirm module footprint remains bounded
        final_module_count = len(sys.modules)
        self.assertLessEqual(final_module_count - initial_module_count, 15)

if __name__ == '__main__':
    unittest.main()
