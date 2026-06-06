# PrismOS UI Layer (Repository Baseline)

This document defines how UI is rendered in this repository.

---

## 1) Critical Rendering Rule (Single Justify)

All `display.Text(...)` objects must use:

- `justify = display.MIDDLE_CENTER`

Other justify modes must not be used in repository UI code.

Positioning for "top-left", "top-center", etc. is done by manual anchor math.

---

## 2) Font / Metrics

The display module exposes:

- `display.WIDTH`  (expected 640)
- `display.HEIGHT` (expected 400)
- `display.FONT_WIDTH`  (expected 24)
- `display.FONT_HEIGHT` (expected 48)

Text size approximation used by PrismOS:
- text width (px)  = `len(text) * FONT_WIDTH`
- text height (px) = `FONT_HEIGHT`

## 2.1 Text Style (Current Device)

The current hardware style is sparse native text, not phone-style prose.

- Host/system labels use short uppercase HUD copy.
- Dynamic user, transcript, translation, OCR, and script content may preserve original case when that preserves meaning.
- Runtime rows should target **26 visible characters** (`640 / 24`) even though the protocol allows 32 UTF-8 bytes per text primitive.
- Text must be pre-wrapped or clipped by the Host before `DRAW`; the Monocle must not infer wrapping or app meaning.
- Prefer ASCII status tokens for system copy (`READY`, `WAIT`, `MIC`, `NO SCRIPT`, `OPEN PHONE`) because the device path is byte-budgeted.

## 2.5 HUD Height (Canonical)

The HUD ("Zone A") must be sized to one native font row.

Canonical:
- HUD height = `display.FONT_HEIGHT` (48px on current Monocle firmware)

All documentation that references "Zone A" height must use this value (not 32px).

---

## 3) Anchors

Anchors are specified using 2-letter codes:

Vertical:
- `T` = top
- `M` = middle
- `B` = bottom

Horizontal:
- `L` = left
- `C` = center
- `R` = right

Examples:
- `TL` = top-left
- `TC` = top-center
- `TR` = top-right
- `MC` = middle-center
- `BR` = bottom-right

Anchor meaning:
- `(x, y)` is the anchor point (e.g., top-left corner for `TL`)
- PrismOS computes the text center `(cx, cy)` for `display.MIDDLE_CENTER`

---

## 4) `prism.ui` API (baseline)

`prism/ui.py` provides:

- `text_line(text, x, y, color, anchor="MC") -> display.Text`
- `text_lines(text, x, y, color, anchor="TL", line_gap=0, max_width_px=None, max_chars=None) -> list[display.Text]`
- `chars_for_width(width_px) -> int`
- `draw_hud(time_text, title_text, battery_text=None) -> list[display objects]`
- `draw_carousel_item(label, position) -> list[display.Text]`
- `draw_hint(text, color) -> list[display.Text]`
- `rect(x1, y1, x2, y2, color=WHITE) -> list[display objects]` (feature-gated, default-off)
- `line(x1, y1, x2, y2, color=WHITE, thickness=1) -> list[display objects]` (feature-gated, default-off)
- `fill(color=BLACK) -> list[display objects]` (feature-gated, default-off)

Notes:
- `draw_hud(...)` returns text-only objects (no lines/rectangles).
- `max_width_px` is converted to `max_chars` using `FONT_WIDTH`.
