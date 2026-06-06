# prism/config.py
# Repository-standard system config (small JSON file on root FS).

from prism import store

CONFIG_FILE = "pm_config.json"
CONFIG_MAX_BYTES = 1024

DEFAULT = {
    # Last orbit selection index
    "orbit_sel": 0,
    # Display brightness (0..4), default per vendor docs is 3
    "brightness": 3,
}


def _int_clamp(v, default, lo, hi):
    try:
        i = int(v)
    except Exception:
        i = int(default)
    if i < lo:
        return int(lo)
    if i > hi:
        return int(hi)
    return int(i)


def load():
    """
    Returns a sanitized config dict.
    Unknown keys are preserved if present (pass-through), but core keys are clamped.
    """
    raw = store.load_json(CONFIG_FILE, default=None, max_bytes=CONFIG_MAX_BYTES)
    if not isinstance(raw, dict):
        raw = {}

    cfg = {}
    # Preserve unknown keys first
    for k in raw:
        cfg[k] = raw[k]

    # Apply defaults and sanitize known keys
    if "orbit_sel" not in cfg:
        cfg["orbit_sel"] = DEFAULT["orbit_sel"]
    if "brightness" not in cfg:
        cfg["brightness"] = DEFAULT["brightness"]

    cfg["orbit_sel"] = _int_clamp(cfg.get("orbit_sel"), DEFAULT["orbit_sel"], 0, 9999)
    cfg["brightness"] = _int_clamp(cfg.get("brightness"), DEFAULT["brightness"], 0, 4)

    return cfg


def save(cfg):
    """
    Saves cfg as JSON. Caller is responsible for keeping cfg small.
    Returns True/False.
    """
    if not isinstance(cfg, dict):
        return False
    return store.save_json(CONFIG_FILE, cfg)

