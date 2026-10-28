import importlib.util
import ast
import json
import os
import struct
import sys
import time
import types
import tempfile
import unittest


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
KERNEL_FILE = os.path.join(ROOT, "monocle", "kernel.py")
BOOT_FILE = os.path.join(ROOT, "monocle", "boot.py")
MAIN_FILE = os.path.join(ROOT, "monocle", "main.py")


class MockBluetooth:
    def __init__(self, max_len=20):
        self.max_len = max_len
        self.sent = []
        self.callback = None
        self.connected_state = False
        self.connected_states = None

    def max_length(self):
        return self.max_len

    def send(self, data):
        if len(data) > self.max_len:
            raise AssertionError("frame exceeds negotiated max_length")
        self.sent.append(bytes(data))

    def receive_callback(self, fn):
        self.callback = fn

    def connected(self):
        if self.connected_states:
            if len(self.connected_states) > 1:
                return self.connected_states.pop(0)
            return self.connected_states[0]
        return self.connected_state


class MockDisplay:
    WIDTH = 640
    HEIGHT = 400
    FONT_WIDTH = 24
    FONT_HEIGHT = 48
    WHITE = 0xFFFFFF
    GRAY6 = 0xAAAAAA
    YELLOW = 0xFFEE33
    GREEN = 0x1D6914
    MIDDLE_CENTER = "MIDDLE_CENTER"

    class Text:
        def __init__(self, text, x, y, color, justify):
            self.text = text
            self.x = x
            self.y = y
            self.color = color
            self.justify = justify

    class Line:
        def __init__(self, x1, y1, x2, y2, color, thickness=1):
            self.x1 = x1
            self.y1 = y1
            self.x2 = x2
            self.y2 = y2
            self.color = color
            self.thickness = thickness

    class Rectangle:
        def __init__(self, x1, y1, x2, y2, color):
            self.x1 = x1
            self.y1 = y1
            self.x2 = x2
            self.y2 = y2
            self.color = color

    class Fill:
        def __init__(self, color):
            self.color = color

    def clear(self):
        pass

    def show(self, *objs):
        self.last_show = objs


class MockTouch:
    A = "A"
    B = "B"

    def state(self, _pad):
        return False


class MockDevice:
    def __init__(self):
        self.prevent_sleep_calls = []
        self.force_sleep_calls = 0
        self.charging = False

    def prevent_sleep(self, enable=None):
        self.prevent_sleep_calls.append(enable)
        return enable

    def force_sleep(self):
        self.force_sleep_calls += 1

    def is_charging(self):
        return self.charging


class TestThinKernelSafety(unittest.TestCase):
    def _load_kernel(self, ble, device=None):
        saved = {name: sys.modules.get(name) for name in ("bluetooth", "display", "touch", "ustruct", "ujson", "camera", "microphone", "device")}
        self.addCleanup(lambda: self._restore_modules(saved))
        saved_time = {name: (hasattr(time, name), getattr(time, name, None)) for name in ("ticks_ms", "ticks_add", "ticks_diff", "sleep_ms")}
        self.addCleanup(lambda: self._restore_time(saved_time))
        time.ticks_ms = lambda: 1000
        time.ticks_add = lambda value, delta: value + delta
        time.ticks_diff = lambda left, right: left - right
        time.sleep_ms = lambda _ms: None
        sys.modules["bluetooth"] = ble
        sys.modules["display"] = MockDisplay()
        sys.modules["touch"] = MockTouch()
        sys.modules["ustruct"] = struct
        sys.modules["ujson"] = json
        if device is None:
            sys.modules.pop("device", None)
        else:
            sys.modules["device"] = device
        spec = importlib.util.spec_from_file_location("thin_kernel_under_test", KERNEL_FILE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        module.BOOT_COUNT_FILE = os.path.join(folder.name, "boot_count.txt")
        return module

    @staticmethod
    def _restore_modules(saved):
        for name, module in saved.items():
            if module is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = module

    @staticmethod
    def _restore_time(saved):
        for name, (existed, value) in saved.items():
            if existed:
                setattr(time, name, value)
            else:
                delattr(time, name)

    def _json_payloads(self, kernel, ble):
        payloads = []
        by_msg = {}
        totals = {}
        for frame in ble.sent:
            magic, ver, kind, _flags, msg_id, _seq, total = struct.unpack_from(kernel.HDR, frame, 0)
            self.assertEqual(magic, kernel.MAGIC)
            self.assertEqual(ver, kernel.VER)
            if kind == kernel.K_JSON:
                by_msg.setdefault(msg_id, []).append(frame[kernel.HLEN:])
                totals[msg_id] = total
        for msg_id, parts in by_msg.items():
            payload = b"".join(parts)
            self.assertEqual(len(payload), totals[msg_id])
            payloads.append(json.loads(payload.decode("utf-8")))
        return payloads

    def test_btn_event_is_fragmented_to_negotiated_mtu(self):
        ble = MockBluetooth(max_len=20)
        kernel = self._load_kernel(ble)

        kernel.handle_cmd(json.dumps({"cmd":"HELLO","protocol_version":1,"shell_version":1,"request_id":"fixture"}).encode())
        ble.sent.clear()
        kernel.send_btn("TAP", "R", 92)

        self.assertGreater(len(ble.sent), 1)
        payload_parts = []
        msg_id = None
        total = None
        for seq, frame in enumerate(ble.sent):
            self.assertLessEqual(len(frame), ble.max_len)
            magic, ver, kind, flags, current_msg_id, current_seq, current_total = struct.unpack_from(kernel.HDR, frame, 0)
            self.assertEqual(magic, kernel.MAGIC)
            self.assertEqual(ver, kernel.VER)
            self.assertEqual(kind, kernel.K_JSON)
            self.assertEqual(current_seq, seq)
            if seq == 0:
                self.assertTrue(flags & kernel.F_START)
                msg_id = current_msg_id
                total = current_total
            else:
                self.assertFalse(flags & kernel.F_START)
                self.assertEqual(current_msg_id, msg_id)
                self.assertEqual(current_total, total)
            payload_parts.append(frame[kernel.HLEN:])

        self.assertTrue(flags & kernel.F_END)
        payload = b"".join(payload_parts)
        self.assertEqual(len(payload), total)
        obj = json.loads(payload.decode("utf-8"))
        self.assertEqual(obj["event"], "BTN")
        self.assertEqual(obj["id"], "R")
        self.assertEqual(obj["gesture"], "TAP")
        self.assertEqual(obj["dur"], 92)

    def test_boot_counter_clears_only_after_stable_delay(self):
        ble = MockBluetooth(max_len=180)
        kernel = self._load_kernel(ble)
        calls = []
        kernel.clear_boot_count = lambda: calls.append("clear")
        kernel.boot_ok_marked = False
        kernel.boot_ok_deadline = 1500

        kernel.mark_boot_ok_if_due(1499)
        self.assertEqual(calls, [])
        self.assertFalse(kernel.boot_ok_marked)

        kernel.mark_boot_ok_if_due(1500)
        self.assertEqual(calls, ["clear"])
        self.assertTrue(kernel.boot_ok_marked)

    def test_startup_disables_case_sleep_prevention(self):
        ble = MockBluetooth(max_len=180)
        dev = MockDevice()
        kernel = self._load_kernel(ble, device=dev)

        kernel.enable_case_sleep()

        self.assertIn(False, dev.prevent_sleep_calls)

    def test_charging_requests_sleep_and_unbinds_receiver(self):
        ble = MockBluetooth(max_len=180)
        dev = MockDevice()
        dev.charging = True
        kernel = self._load_kernel(ble, device=dev)
        ble.receive_callback(kernel.on_rx)

        self.assertTrue(kernel.charging())

        self.assertIsNone(ble.callback)
        self.assertIn(False, dev.prevent_sleep_calls)
        self.assertEqual(dev.force_sleep_calls, 1)

    def test_host_disconnect_marks_offline_immediately(self):
        ble = MockBluetooth(max_len=180)
        kernel = self._load_kernel(ble)
        ble.connected_states = [True, False]
        ticks = [1000]
        sleeps = []

        class StopLoop(Exception):
            pass

        def ticks_ms():
            ticks[0] += 25
            return ticks[0]

        def sleep_ms(_ms):
            sleeps.append(_ms)
            if len(sleeps) >= 2:
                raise StopLoop()

        kernel.time.ticks_ms = ticks_ms
        kernel.time.sleep_ms = sleep_ms

        with self.assertRaises(StopLoop):
            kernel.start()

        shown = kernel.display.last_show
        self.assertEqual(shown[0].text, "HOST OFFLINE")
        self.assertEqual(shown[1].text, "Reconnect phone")
        self.assertIsNone(kernel.app)

    def test_wait_host_timeout_requests_sleep(self):
        ble = MockBluetooth(max_len=180)
        dev = MockDevice()
        kernel = self._load_kernel(ble, device=dev)
        ble.connected_state = False
        ticks = [0, 0, 300000]
        kernel.time.ticks_ms = lambda: ticks.pop(0) if ticks else 300000

        kernel.start()

        self.assertEqual(dev.force_sleep_calls, 1)

    def test_binary_draw_renders_without_json_parser(self):
        ble = MockBluetooth(max_len=180)
        kernel = self._load_kernel(ble)
        text = b"HELLO HOST"
        payload = bytearray([1, 0, 6, 1])
        payload.extend(b"oracle")
        payload.extend(struct.pack("<BHHIBB", 1, 320, 200, 0xFFFFFF, 0, len(text)))
        payload.extend(text)

        self.assertTrue(kernel.draw_binary(payload))
        shown = kernel.display.last_show
        self.assertEqual(len(shown), 1)
        self.assertEqual(shown[0].text, "HELLO HOST")
        self.assertEqual(kernel.app, "oracle")

    def test_binary_draw_parses_optional_shape_primitives_without_rendering(self):
        ble = MockBluetooth(max_len=180)
        kernel = self._load_kernel(ble)
        payload = bytearray([1, 1, 6, 4])
        payload.extend(b"vision")
        payload.extend(struct.pack("<BHHIBB", 1, 320, 40, 0xFFFFFF, 0, 5))
        payload.extend(b"SHAPE")
        payload.extend(struct.pack("<BHHHHIB", 2, 10, 20, 30, 40, 0xAAAAAA, 2))
        payload.extend(struct.pack("<BHHHHI", 3, 50, 60, 70, 80, 0x555555))
        payload.extend(struct.pack("<BI", 4, 0x111111))

        self.assertTrue(kernel.draw_binary(payload))
        shown = kernel.display.last_show
        self.assertEqual(len(shown), 1)
        self.assertEqual(shown[0].text, "SHAPE")

    def test_capture_image_command_returns_deferred_error(self):
        ble = MockBluetooth(max_len=40)
        kernel = self._load_kernel(ble)

        kernel.capture_image_to_host()

        payloads = self._json_payloads(kernel, ble)
        self.assertEqual(payloads[-1]["event"], "MEDIA")
        self.assertEqual(payloads[-1]["kind"], "IMAGE")
        self.assertEqual(payloads[-1]["status"], "ERROR")
        self.assertEqual(payloads[-1]["detail"], "camera deferred")

    def test_capture_audio_without_negotiated_link_fails_honestly(self):
        ble = MockBluetooth(max_len=40)
        kernel = self._load_kernel(ble)

        kernel.capture_audio_to_host()

        payloads = self._json_payloads(kernel, ble)
        self.assertEqual(payloads[-1]["event"], "MEDIA")
        self.assertEqual(payloads[-1]["status"], "ERROR")
        self.assertEqual(payloads[-1]["detail"], "Microphone or shell link unavailable")

    def test_kernel_avoids_bytearray_slice_assignment(self):
        with open(KERNEL_FILE, "r", encoding="utf-8") as f:
            tree = ast.parse(f.read(), filename=KERNEL_FILE)

        for node in ast.walk(tree):
            if isinstance(node, ast.Assign):
                for target in node.targets:
                    self.assertFalse(
                        isinstance(target, ast.Subscript) and isinstance(target.slice, ast.Slice),
                        "Monocle MicroPython rejects bytearray slice assignment",
                    )

    def test_kernel_does_not_import_device_side_app_modules(self):
        with open(KERNEL_FILE, "r", encoding="utf-8") as f:
            tree = ast.parse(f.read(), filename=KERNEL_FILE)

        forbidden_prefixes = ("apps", "prism.app")
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    self.assertFalse(
                        alias.name.startswith(forbidden_prefixes),
                        "thin host-first kernel must not import device-side app modules",
                    )
            elif isinstance(node, ast.ImportFrom):
                module = node.module or ""
                self.assertFalse(
                    module.startswith(forbidden_prefixes),
                    "thin host-first kernel must not import device-side app modules",
                )

    def test_boot_and_main_do_not_use_unverified_custom_ble_advertising(self):
        with open(BOOT_FILE, "r", encoding="utf-8") as f:
            boot_tree = ast.parse(f.read(), filename=BOOT_FILE)
        with open(MAIN_FILE, "r", encoding="utf-8") as f:
            main_tree = ast.parse(f.read(), filename=MAIN_FILE)

        for tree in (boot_tree, main_tree):
            for node in ast.walk(tree):
                if isinstance(node, ast.Call):
                    func = node.func
                    if isinstance(func, ast.Attribute):
                        self.assertNotEqual(func.attr, "gap_advertise")
                    if isinstance(func, ast.Attribute) and func.attr == "BLE":
                        self.fail("recovery code must not call bluetooth.BLE()")

    def test_boot_py_keeps_minimal_recovery_import_surface(self):
        with open(BOOT_FILE, "r", encoding="utf-8") as f:
            boot_tree = ast.parse(f.read(), filename=BOOT_FILE)

        allowed = {"time", "touch", "led"}
        for node in ast.walk(boot_tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    root = alias.name.split(".", 1)[0]
                    self.assertIn(root, allowed, "boot.py must not import non-minimal modules")
            elif isinstance(node, ast.ImportFrom):
                self.fail("boot.py must not use from-imports in the recovery gate")

    def test_main_py_keeps_recovery_sanctuary_ordering(self):
        with open(MAIN_FILE, "r", encoding="utf-8") as f:
            main_tree = ast.parse(f.read(), filename=MAIN_FILE)

        constants = {}
        for node in main_tree.body:
            if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
                try:
                    constants[node.targets[0].id] = ast.literal_eval(node.value)
                except Exception:
                    pass
        self.assertEqual(constants.get("BOOT_COUNT_LIMIT"), 3)
        self.assertGreaterEqual(constants.get("GRACE_PERIOD_S", 0), 1.5)

        run_fn = next(
            node for node in ast.walk(main_tree)
            if isinstance(node, ast.FunctionDef) and node.name == "run"
        )

        def contains_call(node, name):
            for child in ast.walk(node):
                if isinstance(child, ast.Call):
                    func = child.func
                    if isinstance(func, ast.Name) and func.id == name:
                        return True
            return False

        def contains_kernel_import(node):
            return any(
                isinstance(child, ast.Import)
                and any(alias.name == "kernel" for alias in child.names)
                for child in ast.walk(node)
            )

        bump_index = next(i for i, stmt in enumerate(run_fn.body) if contains_call(stmt, "_bump_boot_count"))
        kernel_index = next(i for i, stmt in enumerate(run_fn.body) if contains_kernel_import(stmt))

        self.assertLess(bump_index, kernel_index)
        self.assertIsInstance(run_fn.body[kernel_index], ast.Try)
        self.assertTrue(
            any(contains_call(handler, "safe_mode") for handler in run_fn.body[kernel_index].handlers),
            "kernel import/start must be guarded by Safe Mode fallback",
        )

    def test_safe_mode_does_not_trap_before_vendor_repl(self):
        with open(MAIN_FILE, "r", encoding="utf-8") as f:
            main_tree = ast.parse(f.read(), filename=MAIN_FILE)

        safe_mode = next(
            node for node in ast.walk(main_tree)
            if isinstance(node, ast.FunctionDef) and node.name == "safe_mode"
        )
        self.assertFalse(
            any(isinstance(node, ast.While) for node in ast.walk(safe_mode)),
            "safe_mode must return so vendor firmware enters REPL",
        )


class TestAdaptiveDeviceLink(unittest.TestCase):
    _load_kernel = TestThinKernelSafety._load_kernel
    _restore_modules = staticmethod(TestThinKernelSafety._restore_modules)
    _restore_time = staticmethod(TestThinKernelSafety._restore_time)
    _json_payloads = TestThinKernelSafety._json_payloads
    # Exercise actual device owners with only the physical module boundary doubled.
    def ready(self, ble):
        kernel = self._load_kernel(ble)
        kernel.handle_cmd(json.dumps({"cmd": "HELLO", "protocol_version": 1, "shell_version": 1,
                                      "request_id": "host-session"}).encode())
        return kernel

    def test_handshake_version_lease_and_local_blank(self):
        ble = MockBluetooth(40)
        kernel = self.ready(ble)
        hello = self._json_payloads(kernel, ble)[-1]
        self.assertEqual(hello["shell_version"], 1)
        self.assertEqual(hello["request_id"], "host-session")
        self.assertIn("boot_id", hello)
        kernel.lease_step(21001)
        self.assertIsNone(kernel.host_session)
        self.assertEqual(kernel.display.last_show[0].text, "HOST OFFLINE")
        kernel.emit(0, "LONG")
        self.assertEqual(kernel.display.last_show, ())
        self.assertTrue(kernel.local_blank)
        kernel.handle_cmd(b'{"cmd":"HELLO","protocol_version":99,"shell_version":1}')
        self.assertIsNone(kernel.host_session)

    def test_audio_is_real_bounded_incremental_and_correlated(self):
        ble = MockBluetooth(40)
        kernel = self.ready(ble)
        chunks = [bytearray([0, 127, 128, 255] * 20), bytearray([4, 5]), None]
        calls = []
        kernel.microphone = types.SimpleNamespace(record=lambda **kw: calls.append(kw), read=lambda n: chunks.pop(0))
        kernel.capture_audio_to_host("request-1")
        start = self._json_payloads(kernel, ble)[-1]
        self.assertEqual(start["request_id"], "request-1")
        self.assertEqual(calls, [{"seconds":4.0,"sample_rate":8000,"bit_depth":8}])
        for _ in range(8):
            kernel.audio_step(1600)
        frames = [f for f in ble.sent if f[3] == 2]
        self.assertTrue(frames)
        self.assertEqual(b"".join(f[13:] for f in frames), bytes([0,127,128,255] * 20 + [4,5]))
        headers = [struct.unpack_from("<2sBBBHHI", f) for f in frames]
        self.assertEqual([h[5] for h in headers], list(range(len(headers))))
        self.assertTrue(headers[0][3] & kernel.F_START)
        self.assertTrue(headers[-1][3] & kernel.F_END)
        self.assertTrue(all(h[4] == start["stream_id"] for h in headers))
        self.assertIsNone(kernel.audio)

    def test_cancel_stops_transport_and_lease_does_not_restart_recording(self):
        ble = MockBluetooth(40); kernel = self.ready(ble)
        calls = []
        kernel.microphone = types.SimpleNamespace(record=lambda **kw:calls.append(kw), read=lambda n:bytearray([1,2]))
        kernel.capture_audio_to_host("request-2")
        kernel.handle_cmd(b'{"cmd":"CANCEL_CAPTURE"}')
        count = len(ble.sent); kernel.audio_step(2000)
        self.assertEqual(len(ble.sent),count)
        self.assertEqual(len(calls),1)
        kernel.emit(0,"LONG"); kernel.lease_step(21001)
        self.assertEqual(kernel.display.last_show,())

    def test_control_backpressure_retries_exact_fragment(self):
        ble = MockBluetooth(20); kernel = self._load_kernel(ble)
        original = ble.send
        failures = [True]
        def send(data):
            if failures:
                failures.pop(); raise RuntimeError("busy")
            original(data)
        ble.send = send
        kernel.send_json('{"event":"TEST","value":"complete payload"}')
        self.assertEqual(len(kernel.tx_controls),1)
        kernel.tx_step()
        self.assertEqual(len(kernel.tx_controls),0)
        self.assertEqual(self._json_payloads(kernel,ble)[-1]["value"],"complete payload")

    def test_empty_draw_actually_blanks(self):
        kernel = self.ready(MockBluetooth(40))
        kernel.show_screen("OLD")
        self.assertTrue(kernel.draw_binary(bytes([1,0,5,0]) + b"prism"))
        self.assertEqual(kernel.display.last_show,())

    def test_inbound_begin_draw_order_and_queue_bound(self):
        ble = MockBluetooth(40); kernel = self.ready(ble)
        kernel.local_blank = True
        def feed(kind, payload, mid):
            for seq, off in enumerate(range(0, len(payload), 7)):
                frag = payload[off:off + 7]
                flags = (kernel.F_START if off == 0 else 0) | (kernel.F_END if off + len(frag) == len(payload) else 0)
                kernel.on_rx(struct.pack(kernel.HDR, kernel.MAGIC, 1, kind, flags, mid, seq, len(payload)) + frag)
        feed(1, b'{"cmd":"BEGIN_INTERACTION"}', 100)
        text = b"CURRENT"
        draw = bytes([1,0,5,1]) + b"prism" + bytes([1]) + struct.pack("<HHIBB",320,100,0xFFFFFF,0,len(text)) + text
        feed(5, draw, 101)
        self.assertEqual(len(kernel.inbound), 2)
        kernel.process_inbound()
        self.assertFalse(kernel.local_blank)
        self.assertEqual(kernel.display.last_show[0].text,"CURRENT")
        for i in range(12):
            feed(1,b'{"cmd":"CANCEL_CAPTURE"}',200+i)
        self.assertEqual(len(kernel.inbound),8)
        kernel.handle_cmd(b"[]")
        kernel.handle_cmd(b"null")
        self.assertEqual(kernel.host_session,"host-session")

    def test_physical_blank_rejects_late_activation_and_capture_until_acknowledged(self):
        ble = MockBluetooth(40); kernel = self.ready(ble)
        calls = []
        kernel.microphone = types.SimpleNamespace(record=lambda **kw:calls.append(kw),read=lambda n:None)
        kernel.emit(0,"LONG")
        kernel.handle_cmd(b'{"cmd":"BEGIN_INTERACTION","input_ts":999}')
        kernel.capture_audio_to_host("late")
        self.assertTrue(kernel.local_blank)
        self.assertEqual(calls,[])
        kernel.handle_cmd(b'{"cmd":"BEGIN_INTERACTION","input_ts":1000}')
        kernel.capture_audio_to_host("new")
        self.assertFalse(kernel.local_blank)
        self.assertEqual(len(calls),1)


if __name__ == "__main__":
    unittest.main()
