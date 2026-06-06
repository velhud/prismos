# PrismOS Persistence (Repository Baseline)

This repository stores small persistent state in root-level files on the device filesystem.

---

## 1) System Config (`pm_config.json`)

File: `pm_config.json`  
Writer/Reader: `prism/config.py`

Keys (v1):
- `orbit_sel` (int) — last orbit selection index
- `brightness` (int 0..4) — display brightness level

Size constraints:
- `pm_config.json` is expected to remain small (≤ 1024 bytes).
- `prism/config.py` enforces a max read size and clamps core keys.

---

## 2) Boot-loop Counter (`pm_boot_count.txt`)

File: `pm_boot_count.txt`  
Writer: `main.py`  
Clearer: `kernel.py` after a stable delay

Purpose:
- Count rapid restarts and enter Safe Mode when the counter exceeds the threshold.

---

## 3) Storage Helpers

`prism/store.py` provides:
- `load_json(path, default, max_bytes)`
- `save_json(path, obj)` (tmp + rename when possible)
- `read_text(path, max_bytes)`
- `write_text(path, text)`

