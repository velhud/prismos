# prism/store.py
# Small persistence helpers for MicroPython.
#
# Design constraints:
# - keep allocations bounded (size limits)
# - avoid partial-write corruption where possible (tmp + rename)
# - never raise exceptions to callers (return defaults / False)

import ujson

try:
    import os
except Exception:
    os = None


def exists(path):
    if os is None:
        # best-effort: try open
        try:
            with open(path, "r"):
                return True
        except Exception:
            return False
    try:
        os.stat(path)
        return True
    except Exception:
        return False


def _safe_size(path):
    if os is None:
        return None
    try:
        st = os.stat(path)
        # MicroPython stat tuple size is typically at index 6
        return int(st[6])
    except Exception:
        return None


def read_text(path, max_bytes=4096):
    """
    Returns string on success, or None.
    If max_bytes is set and file is larger, returns None.
    """
    try:
        mb = None if max_bytes is None else int(max_bytes)
    except Exception:
        mb = 4096

    if mb is not None:
        sz = _safe_size(path)
        if sz is not None and sz > mb:
            return None

    try:
        with open(path, "r") as f:
            s = f.read()
        if mb is not None and len(s) > mb:
            return None
        return s
    except Exception:
        return None


def write_text(path, text):
    """
    Writes text to path (overwrites).
    Returns True on success, False otherwise.
    """
    try:
        s = "" if text is None else str(text)
        with open(path, "w") as f:
            f.write(s)
        return True
    except Exception:
        return False


def load_json(path, default=None, max_bytes=4096):
    """
    Loads JSON from file.
    Returns parsed value, or default.
    """
    s = read_text(path, max_bytes=max_bytes)
    if s is None:
        return default
    try:
        return ujson.loads(s)
    except Exception:
        return default


def save_json(path, obj):
    """
    Saves obj to path as JSON using a tmp file + rename when possible.
    Returns True on success, False otherwise.
    """
    try:
        payload = ujson.dumps(obj)
    except Exception:
        return False

    tmp = str(path) + ".tmp"

    # If no os module, fall back to direct write.
    if os is None:
        return write_text(path, payload)

    try:
        # Write temp file
        with open(tmp, "w") as f:
            f.write(payload)

        # Remove destination if it exists (some FS do not overwrite on rename)
        try:
            os.remove(path)
        except Exception:
            pass

        # Move temp into place
        os.rename(tmp, path)
        return True

    except Exception:
        # Fallback direct write
        ok = write_text(path, payload)
        return ok

    finally:
        # Best-effort cleanup of tmp
        try:
            os.remove(tmp)
        except Exception:
            pass

