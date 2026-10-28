# PrismOS Monocle thin runtime.

import bluetooth
import display
import gc
import time
import touch
import ustruct as struct
import ujson as json

try:
    import microphone
except Exception:
    microphone = None
try:
    import urandom
    BOOT_ID = str(urandom.getrandbits(30))
except Exception:
    BOOT_ID = str(time.ticks_ms())

try:
    import device
except Exception:
    device = None


BOOT_COUNT_FILE = "pm_boot_count.txt"
BOOT_OK_AFTER_MS = 5000
MAGIC = b"PM"
VER = 1
K_JSON = 1
K_DRAW = 5
F_START = 1
F_END = 2
HDR = "<2sBBBHHI"
HLEN = 13
MAX_RX = 1536
MAX_JSON = 384
MAX_ITEMS = 12
MAX_TEXT = 32
MAX_APP = 16

WIDTH = getattr(display, "WIDTH", 640)
HEIGHT = getattr(display, "HEIGHT", 400)
FONT_W = getattr(display, "FONT_WIDTH", 24)
FONT_H = getattr(display, "FONT_HEIGHT", 48)
WHITE = getattr(display, "WHITE", 0xFFFFFF)
GRAY = getattr(display, "GRAY6", 0xAAAAAA)

mid = 1
tx = None
tx_len = 0
app = None
rx = None
rx_mid = 0
rx_total = 0
rx_seq = 0
rx_written = 0
rx_active = False
rx_kind = 0
inbound = []
blank_barrier = None
down = [False, False]
since = [0, 0]
longed = [False, False]
pending = [False, False]
pending_dur = [0, 0]
deadline = [0, 0]
boot_ok_marked = False
boot_ok_deadline = 0
host_session = None
host_lease = 0
local_blank = False
audio = None
rx_started_at = 0
tx_controls = []


def copy_into(dst, off, src):
    for i in range(len(src)):
        dst[off + i] = src[i]


def clear_boot_count():
    try:
        with open(BOOT_COUNT_FILE, "w") as f:
            f.write("0")
    except Exception:
        pass


def mark_boot_ok(now):
    global boot_ok_marked
    if (not boot_ok_marked) and time.ticks_diff(now, boot_ok_deadline) >= 0:
        clear_boot_count()
        boot_ok_marked = True


mark_boot_ok_if_due = mark_boot_ok


def enable_case_sleep():
    if device is not None:
        try:
            device.prevent_sleep(False)
        except Exception:
            pass


def force_sleep():
    try:
        bluetooth.receive_callback(None)
    except Exception:
        pass
    enable_case_sleep()
    if device is not None:
        try:
            device.force_sleep()
        except Exception:
            pass


def charging():
    if device is None:
        return False
    try:
        if not device.is_charging():
            return False
    except Exception:
        return False
    force_sleep()
    return True


def to_text(buf):
    try:
        return bytes(buf).decode("utf-8")
    except Exception:
        return ""


def clamp(v, lo, hi):
    try:
        n = int(v)
    except Exception:
        n = lo
    if n < lo:
        return lo
    if n > hi:
        return hi
    return n


def text_obj(value, x, y, color=WHITE, anchor=0):
    s = ("" if value is None else str(value))[:MAX_TEXT]
    x = clamp(x, 0, WIDTH)
    y = clamp(y, 0, HEIGHT)
    w = len(s) * FONT_W
    if anchor in (1, 4, 6):
        x += w // 2
    elif anchor in (3, 5, 8):
        x -= w // 2
    if anchor in (1, 2, 3):
        y += FONT_H // 2
    elif anchor in (6, 7, 8):
        y -= FONT_H // 2
    return display.Text(s, x, y, int(color), justify=display.MIDDLE_CENTER)


def show_screen(title, a="", b="", c="", h=""):
    objs = [text_obj(title, 320, 44)]
    if a:
        objs.append(text_obj(a, 320, 140))
    if b:
        objs.append(text_obj(b, 320, 210))
    if c:
        objs.append(text_obj(c, 320, 275))
    if h:
        objs.append(text_obj(h, 320, 340, GRAY))
    try:
        display.show(*objs)
    except Exception:
        pass


def draw_binary(buf):
    global app
    if buf is None or len(buf) < 4 or buf[0] != 1:
        return False
    app_len = buf[2]
    count = buf[3]
    if app_len > MAX_APP or count > MAX_ITEMS:
        return False
    pos = 4
    if pos + app_len > len(buf):
        return False
    app = to_text(buf[pos:pos + app_len]) if app_len else None
    pos += app_len
    objs = []
    try:
        for _ in range(count):
            if pos >= len(buf):
                return False
            kind = buf[pos]
            pos += 1
            if kind == 1:
                if pos + 10 > len(buf):
                    return False
                x, y, color, anchor, size = struct.unpack_from("<HHIBB", buf, pos)
                pos += 10
                if size > MAX_TEXT or pos + size > len(buf):
                    return False
                objs.append(text_obj(to_text(buf[pos:pos + size]), x, y, color, anchor))
                pos += size
            elif kind == 2:
                pos += 13
            elif kind == 3:
                pos += 12
            elif kind == 4:
                pos += 4
            else:
                return False
            if pos > len(buf):
                return False
        if pos != len(buf):
            return False
        display.show(*objs)
        return True
    except Exception:
        return False


def ensure_tx():
    global tx, tx_len
    try:
        n = int(bluetooth.max_length())
    except Exception:
        n = 20
    if n < HLEN + 1:
        n = HLEN + 1
    if tx is None or tx_len != n:
        tx = bytearray(n)
        tx_len = n


def next_mid():
    global mid
    msg_id = mid
    mid = (mid + 1) & 0xFFFF
    if mid == 0:
        mid = 1
    return msg_id


def send_frame(kind, msg_id, seq, flags, total, frag):
    try:
        ensure_tx()
        end = HLEN + len(frag)
        if end > tx_len:
            return
        struct.pack_into(HDR, tx, 0, MAGIC, VER, kind, flags, msg_id, seq, total)
        if frag:
            copy_into(tx, HLEN, frag)
        bluetooth.send(tx[:end])
        return True
    except Exception:
        return False


def tx_step():
    # At most eight bounded control messages; retry the exact unsent fragment.
    for _ in range(64):
        if not tx_controls:
            return
        item = tx_controls[0]
        ensure_tx()
        frag = item["payload"][item["off"]:item["off"] + tx_len - HLEN]
        flags = F_START if item["off"] == 0 else 0
        if item["off"] + len(frag) >= len(item["payload"]):
            flags |= F_END
        if not send_frame(K_JSON, item["mid"], item["seq"], flags, len(item["payload"]), frag):
            return
        item["off"] += len(frag)
        item["seq"] += 1
        if flags & F_END:
            tx_controls.pop(0)


def send_json(js):
    try:
        payload = js.encode("utf-8")
        if len(payload) > MAX_JSON or len(tx_controls) >= 8:
            return False
        tx_controls.append({"payload": payload, "mid": next_mid(), "off": 0, "seq": 0})
        tx_step()
        return True
    except Exception:
        return False


def send_media(kind, detail):
    detail = ("" if detail is None else str(detail))[:80]
    send_json('{"event":"MEDIA","kind":"%s","status":"ERROR","detail":"%s","ts":%d}' % (
        kind, detail.replace('"', "'"), time.ticks_ms()
    ))


def capture_image_to_host():
    send_media("IMAGE", "camera deferred")


def cancel_audio():
    global audio
    # Monocle has no documented microphone.stop API. Stop transport immediately;
    # FPGA recording is bounded to four seconds and is not extended or restarted.
    audio = None


def capture_audio_to_host(request_id=None):
    global audio, local_blank
    if not host_session or local_blank or not request_id or microphone is None:
        send_json(json.dumps({"event": "MEDIA", "status": "ERROR", "request_id": request_id,
                              "detail": "Microphone or shell link unavailable"}))
        return
    cancel_audio()
    try:
        microphone.record(seconds=4.0, sample_rate=8000, bit_depth=8)
        now = time.ticks_ms()
        audio = {"request": request_id, "mid": next_mid(), "seq": 0, "bytes": 0,
                 "ready": time.ticks_add(now, 500), "deadline": time.ticks_add(now, 12000),
                 "pending": None, "offset": 0}
        local_blank = False
        show_screen("LISTENING", "Speak")
        send_json(json.dumps({"event": "MEDIA", "status": "START", "request_id": request_id,
                              "stream_id": audio["mid"]}))
    except Exception:
        cancel_audio()
        send_json(json.dumps({"event": "MEDIA", "status": "ERROR", "request_id": request_id,
                              "detail": "Microphone capture failed"}))


def audio_step(now):
    global audio
    if tx_controls or audio is None or time.ticks_diff(now, audio["ready"]) < 0:
        return
    if time.ticks_diff(now, audio["deadline"]) >= 0:
        request = audio["request"]
        cancel_audio()
        send_json(json.dumps({"event": "MEDIA", "status": "ERROR", "request_id": request,
                              "detail": "Audio transfer deadline exceeded"}))
        return
    # Bound work per tick and retain each fragment until bluetooth.send succeeds.
    # No entire recording is buffered on the device; host owns reconstruction.
    try:
        ensure_tx()
        for _ in range(8):
            if audio["pending"] is None:
                chunk = microphone.read(127)
                if chunk is None:
                    flags = F_END | (F_START if audio["seq"] == 0 else 0)
                    if send_frame(2, audio["mid"], audio["seq"], flags, 0xFFFFFFFF, b""):
                        cancel_audio()
                    return
                if not len(chunk):
                    return
                audio["pending"] = chunk
                audio["offset"] = 0
            off = audio["offset"]
            frag = audio["pending"][off:off + tx_len - HLEN]
            flags = F_START if audio["seq"] == 0 else 0
            if not send_frame(2, audio["mid"], audio["seq"], flags, 0xFFFFFFFF, frag):
                return
            audio["seq"] += 1
            audio["bytes"] += len(frag)
            audio["offset"] += len(frag)
            if audio["bytes"] > 32000:
                raise ValueError("audio bound")
            if audio["offset"] >= len(audio["pending"]):
                audio["pending"] = None
    except Exception:
        request = audio["request"] if audio else None
        cancel_audio()
        send_json(json.dumps({"event": "MEDIA", "status": "ERROR", "request_id": request,
                              "detail": "Audio stream failed"}))


def handle_cmd(buf):
    global host_session, host_lease, local_blank, blank_barrier
    try:
        obj = json.loads(to_text(buf))
        if not isinstance(obj, dict):
            return
    except Exception:
        return
    cmd = obj.get("cmd")
    if cmd == "HELLO":
        if obj.get("protocol_version") != 1 or obj.get("shell_version") != 1:
            return
        cancel_audio()
        host_session = obj.get("request_id")
        host_lease = time.ticks_add(time.ticks_ms(), 20000)
        local_blank = False
        blank_barrier = None
        display.show()
        send_json(json.dumps({"event": "HELLO", "protocol_version": 1, "shell_version": 1,
                              "request_id": host_session, "boot_id": BOOT_ID, "ts": time.ticks_ms()}))
    elif cmd == "PING" and obj.get("request_id") == host_session and host_session:
        host_lease = time.ticks_add(time.ticks_ms(), 20000)
        send_json(json.dumps({"event": "PONG", "request_id": host_session, "ts": time.ticks_ms()}))
    elif cmd == "CLEAR":
        local_blank = True
        cancel_audio()
        display.show()
    elif cmd == "BEGIN_INTERACTION" and host_session:
        timestamp = obj.get("input_ts")
        if blank_barrier is None or (isinstance(timestamp, int) and time.ticks_diff(timestamp, blank_barrier) >= 0):
            local_blank = False
        else:
            send_json(json.dumps({"event": "INTERACTION", "status": "ERROR", "detail": "Blank gesture must be acknowledged before a new interaction"}))
    elif cmd == "CANCEL_CAPTURE":
        cancel_audio()
    elif cmd == "CAPTURE_IMAGE":
        capture_image_to_host()
    elif cmd == "CAPTURE_AUDIO":
        capture_audio_to_host(obj.get("request_id"))


def lease_step(now):
    global host_session
    if host_session and time.ticks_diff(now, host_lease) >= 0:
        host_session = None
        cancel_audio()
        if not local_blank:
            show_screen("HOST OFFLINE", "Information is stale")


def send_btn(kind, side, dur=0):
    if not host_session:
        return
    send_json(json.dumps({"event": "BTN", "id": side, "gesture": kind, "app": app,
                          "ts": time.ticks_ms(), "dur": int(dur), "session_id": host_session}))


def rx_reset():
    global rx, rx_mid, rx_total, rx_seq, rx_written, rx_active, rx_kind
    rx = None
    rx_mid = 0
    rx_total = 0
    rx_seq = 0
    rx_written = 0
    rx_active = False
    rx_kind = 0
    gc.collect()


def on_rx(data):
    global rx, rx_mid, rx_total, rx_seq, rx_written, rx_active, rx_kind, rx_started_at
    if data is None or len(data) < HLEN:
        return
    try:
        magic, ver, kind, flags, msg_id, seq, total = struct.unpack_from(HDR, data, 0)
    except Exception:
        return
    if magic != MAGIC or ver != VER or flags & ~(F_START | F_END):
        return
    max_total = MAX_RX if kind == K_DRAW else MAX_JSON if kind == K_JSON else 0
    if max_total == 0:
        return
    if flags & F_START:
        rx_reset()
        if total > max_total:
            return
        try:
            rx = bytearray(total)
        except MemoryError:
            rx_reset()
            return
        rx_mid = msg_id
        rx_total = total
        rx_kind = kind
        rx_started_at = time.ticks_ms()
        rx_active = True
    if not rx_active or msg_id != rx_mid or seq != rx_seq or kind != rx_kind or total != rx_total or time.ticks_diff(time.ticks_ms(), rx_started_at) > 5000:
        rx_reset()
        return
    frag = data[HLEN:]
    end = rx_written + len(frag)
    if end > rx_total:
        rx_reset()
        return
    if frag:
        copy_into(rx, rx_written, frag)
    rx_written = end
    rx_seq += 1
    if flags & F_END:
        if rx_written == rx_total and len(inbound) < 8:
            inbound.append((rx_kind, msg_id, rx))
        rx_reset()


def process_inbound():
    # Preserve control/draw order. A single command slot could overwrite BEGIN with CAPTURE
    # or render DRAW before a queued BEGIN, despite correct host fragment ordering.
    for _ in range(8):
        if not inbound:
            return
        kind, msg_id, payload = inbound.pop(0)
        if kind == K_JSON:
            handle_cmd(payload)
        elif host_session and not local_blank:
            ok = draw_binary(payload)
            send_json(json.dumps({"event": "DRAW_ACK", "stream_id": msg_id, "status": "OK" if ok else "ERROR"}))
        else:
            send_json(json.dumps({"event": "DRAW_ACK", "stream_id": msg_id, "status": "IGNORED"}))


def state(index):
    try:
        return bool(touch.state(touch.B if index == 0 else touch.A))
    except Exception:
        return False


def emit(index, kind, dur=0):
    global local_blank, blank_barrier
    if index == 0 and kind == "LONG":
        cancel_audio()
        local_blank = True
        blank_barrier = time.ticks_ms()
        del inbound[:]
        display.show()
    elif index == 1 and kind == "DOUBLE":
        local_blank = False
        if host_session:
            show_screen("LISTENING", "Waiting for host")
        else:
            show_screen("HOST OFFLINE", "Open PrismOS on phone")
    send_btn(kind, "L" if index == 0 else "R", dur)


def scan(now):
    for index in (0, 1):
        pressed = state(index)
        if pending[index] and time.ticks_diff(now, deadline[index]) >= 0:
            pending[index] = False
            emit(index, "TAP", pending_dur[index])
        if pressed and not down[index]:
            down[index] = True
            since[index] = now
            longed[index] = False
        elif pressed and down[index]:
            if (not longed[index]) and time.ticks_diff(now, since[index]) >= 800:
                longed[index] = True
                pending[index] = False
                emit(index, "LONG", time.ticks_diff(now, since[index]))
        elif (not pressed) and down[index]:
            down[index] = False
            dur = time.ticks_diff(now, since[index])
            if longed[index] or dur < 30:
                continue
            if pending[index]:
                pending[index] = False
                emit(index, "DOUBLE", dur)
            else:
                pending[index] = True
                pending_dur[index] = dur
                deadline[index] = time.ticks_add(now, 300)


def start():
    global boot_ok_deadline, boot_ok_marked, app, host_session, local_blank
    enable_case_sleep()
    bluetooth.receive_callback(on_rx)
    boot_ok_marked = False
    boot_ok_deadline = time.ticks_add(time.ticks_ms(), BOOT_OK_AFTER_MS)
    gc.collect()
    if charging():
        return
    display.show()
    hc = False
    wait_deadline = time.ticks_add(time.ticks_ms(), 300000)
    while True:
        now = time.ticks_ms()
        mark_boot_ok(now)
        if charging():
            return
        try:
            connected = bool(bluetooth.connected())
        except Exception:
            connected = False
        if not connected:
            if hc:
                hc = False
                app = None
                host_session = None
                del tx_controls[:]
                cancel_audio()
                del inbound[:]
                rx_reset()
                if not local_blank:
                    show_screen("HOST OFFLINE", "Reconnect phone")
                wait_deadline = time.ticks_add(now, 300000)
            elif time.ticks_diff(now, wait_deadline) >= 0:
                force_sleep()
                return
            scan(now)
            time.sleep_ms(25)
            continue
        hc = True
        scan(now)
        process_inbound()
        lease_step(now)
        tx_step()
        audio_step(now)
        time.sleep_ms(10 if audio else 25)
