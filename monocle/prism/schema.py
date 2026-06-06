# prism/schema.py
# Minimal CTRL_JSON schema validation + sanitization.
#
# Goals:
# - bound allocations and string sizes (host payloads are untrusted)
# - reject unsupported envelope types/commands early
# - keep this module tiny and dependency-light

from prism import ids

# ---- Size budgets (define explicit constants) ----
# Must match prism.protocol.MAX_RX_TOTAL_LEN (device inbound cap enforced by prism/bridge.py).
MAX_CTRL_JSON_BYTES = 4096

MAX_WIDGET_TEXT = 24                # orbit widget short label
MAX_GHOST_TEXT = 48                 # ghost line (icon + text)
MAX_TOAST_TEXT = 64                 # toast line
MAX_ERR_TEXT = 64                   # error line
MAX_TITLE_TEXT = 24                 # generic title-ish fields
MAX_BODY_TEXT = 32                  # generic body-ish fields

_MAX_GHOST_ICON = 6
_MAX_ERR_CODE = 12
_MAX_TZ_TEXT = 8


def clamp_str(v, max_len):
    if v is None:
        return ""
    if isinstance(v, str):
        s = v
    elif isinstance(v, (bytes, bytearray)):
        try:
            s = v.decode("utf-8", "ignore")
        except Exception:
            try:
                s = str(v)
            except Exception:
                return ""
    else:
        try:
            s = str(v)
        except Exception:
            return ""

    try:
        n = int(max_len)
    except Exception:
        n = 0
    if n <= 0:
        return ""
    if len(s) > n:
        return s[:n]
    return s


def clamp_bool(v, default=False):
    if isinstance(v, bool):
        return v
    if isinstance(v, int):
        return bool(v)
    return bool(default)


def clamp_int(v, default=0, lo=None, hi=None):
    if isinstance(v, bool):
        i = int(default)
    else:
        try:
            i = int(v)
        except Exception:
            i = int(default)

    if lo is not None and i < lo:
        i = lo
    if hi is not None and i > hi:
        i = hi
    return i


def sanitize_ctrl(obj):
    """
    Input: decoded JSON dict (already ujson.loads'd).
    Output: sanitized dict or None if invalid/unsupported.

    Must handle:
      - type=SYS
      - type=STATE
      - type=GHOST
      - type=ERR
    """
    if not isinstance(obj, dict):
        return None

    mtype = obj.get("type")
    if mtype not in (ids.MSG_SYS, ids.MSG_STATE, ids.MSG_GHOST, ids.MSG_ERR):
        return None

    # ---- SYS ----
    if mtype == ids.MSG_SYS:
        cmd = obj.get("cmd")
        if not isinstance(cmd, str):
            return None
        if cmd not in (ids.SYS_FOCUS, ids.SYS_WIDGETS, ids.SYS_TIME):
            return None

        if cmd == ids.SYS_FOCUS:
            app = obj.get("app")
            if not ids.is_app_id(app):
                return None
            return {"type": ids.MSG_SYS, "cmd": ids.SYS_FOCUS, "app": str(app)}

        if cmd == ids.SYS_WIDGETS:
            data = obj.get("data")
            if not isinstance(data, dict):
                return None
            out = {}
            for k, v in data.items():
                if ids.is_app_id(k):
                    out[str(k)] = clamp_str(v, MAX_WIDGET_TEXT)
            return {"type": ids.MSG_SYS, "cmd": ids.SYS_WIDGETS, "data": out}

        # ids.SYS_TIME
        data = obj.get("data")
        if not isinstance(data, dict):
            return None

        if "epoch" not in data:
            return None
        try:
            epoch = int(data.get("epoch"))
        except Exception:
            return None

        tz = ""
        if "tz" in data and data.get("tz") is not None:
            tz = clamp_str(data.get("tz"), _MAX_TZ_TEXT)

        out_data = {"epoch": epoch}
        if tz:
            out_data["tz"] = tz
        return {"type": ids.MSG_SYS, "cmd": ids.SYS_TIME, "data": out_data}

    # ---- STATE ----
    if mtype == ids.MSG_STATE:
        app = obj.get("app")
        if not ids.is_app_id(app):
            return None
        data = obj.get("data")
        if not isinstance(data, dict):
            data = {}
        # Do not deep-copy app state (per-app sanitizers can be added later).
        return {"type": ids.MSG_STATE, "app": str(app), "data": data}

    # ---- GHOST ----
    if mtype == ids.MSG_GHOST:
        active = clamp_bool(obj.get("active"), default=False)
        text = clamp_str(obj.get("text"), MAX_GHOST_TEXT)
        icon = clamp_str(obj.get("icon"), _MAX_GHOST_ICON)
        flash = clamp_bool(obj.get("flash"), default=False)
        return {
            "type": ids.MSG_GHOST,
            "active": active,
            "text": text,
            "icon": icon,
            "flash": flash,
        }

    # ---- ERR ----
    msg = clamp_str(obj.get("msg"), MAX_ERR_TEXT)
    code = ""
    if "code" in obj and obj.get("code") is not None:
        code = clamp_str(obj.get("code"), _MAX_ERR_CODE)

    out = {"type": ids.MSG_ERR, "msg": msg}
    if code:
        out["code"] = code
    return out

