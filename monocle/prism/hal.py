# prism/hal.py
# Hardware abstraction wrappers for Monocle's MicroPython modules.

try:
    import device as _device
except Exception:
    _device = None

try:
    import led as _led
except Exception:
    _led = None

try:
    import camera as _camera
except Exception:
    _camera = None

try:
    import microphone as _microphone
except Exception:
    _microphone = None

try:
    import bluetooth as _bluetooth
except Exception:
    _bluetooth = None

try:
    import time as _time
except Exception:
    _time = None


# -------------------------
# Device power / status
# -------------------------

def battery_level():
    if _device is None:
        return None
    try:
        return int(_device.battery_level())
    except Exception:
        return None


def is_charging():
    if _device is None:
        return None
    try:
        return bool(_device.is_charging())
    except Exception:
        return None


def prevent_sleep(enable=None):
    if _device is None:
        return None
    try:
        if enable is None:
            return _device.prevent_sleep()
        return _device.prevent_sleep(bool(enable))
    except Exception:
        return None


def force_sleep():
    if _device is None:
        return False
    try:
        _device.force_sleep()
        return True
    except Exception:
        return False


def reset():
    if _device is None:
        return False
    try:
        _device.reset()
        return True
    except Exception:
        return False


# -------------------------
# LED
# -------------------------

def led_red(on):
    if _led is None:
        return False
    try:
        if on:
            _led.on(_led.RED)
        else:
            _led.off(_led.RED)
        return True
    except Exception:
        return False


def led_green(on):
    if _led is None:
        return False
    try:
        if on:
            _led.on(_led.GREEN)
        else:
            _led.off(_led.GREEN)
        return True
    except Exception:
        return False


# -------------------------
# Bluetooth
# -------------------------

def bt_max_length():
    if _bluetooth is None:
        return None
    try:
        return int(_bluetooth.max_length())
    except Exception:
        return None


def bt_connected():
    if _bluetooth is None:
        return None
    try:
        return bool(_bluetooth.connected())
    except Exception:
        return None


# -------------------------
# Camera
# -------------------------

def camera_capture():
    if _camera is None:
        return False
    try:
        _camera.capture()
        return True
    except Exception:
        return False


def camera_read(chunk_bytes=254):
    """
    Reads a single chunk from camera buffer.
    Returns bytes-like or None when no bytes remain.
    """
    if _camera is None:
        return None
    try:
        n = int(chunk_bytes)
    except Exception:
        n = 254
    if n <= 0:
        n = 254
    if n > 254:
        n = 254
    try:
        return _camera.read(n)
    except Exception:
        return None


def iter_camera_bytes(chunk_bytes=254):
    """
    Yields camera bytes until camera.read(...) returns None.
    """
    while True:
        data = camera_read(chunk_bytes=chunk_bytes)
        if data is None:
            return
        yield data


# -------------------------
# Microphone
# -------------------------

def mic_record(seconds=4.0, sample_rate=8000, bit_depth=8):
    if _microphone is None:
        return False
    try:
        _microphone.record(seconds=float(seconds), sample_rate=int(sample_rate), bit_depth=int(bit_depth))
        return True
    except Exception:
        return False


def mic_read(samples=127):
    """
    Reads a single chunk from microphone buffer.
    Returns bytearray/bytes-like, or None when no samples remain.
    """
    if _microphone is None:
        return None
    try:
        n = int(samples)
    except Exception:
        n = 127
    if n <= 0:
        n = 127
    if n > 127:
        n = 127
    try:
        return _microphone.read(n)
    except Exception:
        return None


def iter_mic_bytes(samples=127):
    """
    Yields microphone bytes until microphone.read(...) returns None.
    """
    while True:
        data = mic_read(samples=samples)
        if data is None:
            return
        yield data


# -------------------------
# Timing helpers
# -------------------------

def ticks_ms():
    if _time is None:
        return 0
    try:
        return int(_time.ticks_ms())
    except Exception:
        return 0


def sleep_ms(ms):
    if _time is None:
        return
    try:
        _time.sleep_ms(int(ms))
    except Exception:
        return
