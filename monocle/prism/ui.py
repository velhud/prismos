# prism/ui.py
# Text-first UI utilities with anchor-based positioning.
#
# Repository rule:
# - Only use display.Text(..., justify=display.MIDDLE_CENTER)
# - Never use other justify modes (TOP_LEFT, TOP_CENTER, etc.)
#
# This module exposes a minimal UI surface used by kernel and app stubs.

import display

# Screen metrics
WIDTH = getattr(display, "WIDTH", 640)
HEIGHT = getattr(display, "HEIGHT", 400)

# Font metrics (approx per-character cell)
FONT_W = getattr(display, "FONT_WIDTH", 24)
FONT_H = getattr(display, "FONT_HEIGHT", 48)

# Colors (ints 0xRRGGBB)
BLACK = 0x000000
WHITE = 0xFFFFFF

# Prefer display-provided palette if present; fall back to reasonable defaults
GRAY = getattr(display, "GRAY6", 0xAAAAAA)
GRAY_DARK = getattr(display, "GRAY3", 0x555555)

RED = getattr(display, "RED", 0xAD2323)
GREEN = getattr(display, "GREEN", 0x1D6914)
YELLOW = getattr(display, "YELLOW", 0xFFEE33)
CYAN = getattr(display, "CYAN", 0x29D0D0)
MAGENTA = getattr(display, "MAGENTA", 0x8126C0)

# Feature gate: keep default text-only rendering safe on current firmware.
ENABLE_SHAPES = True

# -----------------------------------------
# Helpers
# -----------------------------------------

def chars_for_width(width_px):
    """
    Converts pixel width into maximum character count using FONT_W.
    """
    try:
        w = int(width_px)
    except Exception:
        return 1
    if w <= 0:
        return 1
    c = w // int(FONT_W)
    return c if c > 0 else 1


def measure_text(text):
    """
    Returns (w_px, h_px) approximate.
    """
    if text is None:
        text = ""
    s = str(text)
    return (len(s) * int(FONT_W), int(FONT_H))


def _center_from_anchor(x, y, text, anchor):
    """
    Converts an (x,y) anchor point into a center point (cx,cy) for MIDDLE_CENTER justify.
    anchor is a 2-letter code: TL, TC, TR, ML, MC, MR, BL, BC, BR
    """
    try:
        ax = int(x)
        ay = int(y)
    except Exception:
        ax = 0
        ay = 0

    a = "MC" if anchor is None else str(anchor).upper()
    if len(a) != 2:
        a = "MC"

    v = a[0]  # T/M/B
    h = a[1]  # L/C/R

    w_px, h_px = measure_text(text)

    # Horizontal center
    if h == "L":
        cx = ax + (w_px // 2)
    elif h == "R":
        cx = ax - (w_px // 2)
    else:
        cx = ax

    # Vertical center
    if v == "T":
        cy = ay + (h_px // 2)
    elif v == "B":
        cy = ay - (h_px // 2)
    else:
        cy = ay

    return cx, cy


def _wrap_line_words(line, max_chars):
    """
    Word-wrap a single line into a list of lines not exceeding max_chars.
    Splits long words when needed.
    """
    if max_chars is None:
        return [line]
    try:
        m = int(max_chars)
    except Exception:
        return [line]
    if m <= 0:
        return [line]

    s = "" if line is None else str(line)
    if len(s) <= m:
        return [s]

    words = s.split(" ")
    out = []
    cur = ""

    for w in words:
        if cur == "":
            if len(w) <= m:
                cur = w
            else:
                # break long word
                i = 0
                while i < len(w):
                    out.append(w[i:i+m])
                    i += m
                cur = ""
        else:
            if len(cur) + 1 + len(w) <= m:
                cur = cur + " " + w
            else:
                out.append(cur)
                if len(w) <= m:
                    cur = w
                else:
                    i = 0
                    while i < len(w):
                        out.append(w[i:i+m])
                        i += m
                    cur = ""

    if cur:
        out.append(cur)

    if not out:
        out = [""]

    return out


def _split_text_to_lines(text, max_chars):
    """
    Splits multi-line text into wrapped lines.
    """
    if text is None:
        text = ""
    s = str(text)

    raw_lines = s.split("\n")
    lines = []
    for rl in raw_lines:
        if max_chars is None:
            lines.append(rl)
        else:
            lines.extend(_wrap_line_words(rl, max_chars))

    if not lines:
        lines = [""]

    return lines


# -----------------------------------------
# Public UI primitives
# -----------------------------------------

def text_line(text, x, y, color=WHITE, anchor="MC"):
    """
    Returns one display.Text object positioned using anchor math.
    Uses justify=display.MIDDLE_CENTER always.
    """
    t = "" if text is None else str(text)
    cx, cy = _center_from_anchor(x, y, t, anchor)
    return display.Text(t, cx, cy, int(color), justify=display.MIDDLE_CENTER)


def text_lines(text, x, y, color=WHITE, anchor="TL", line_gap=0, max_width_px=None, max_chars=None):
    """
    Returns multiple display.Text objects for wrapped multi-line text.

    Wrapping precedence:
    - if max_chars is provided: wrap to max_chars
    - else if max_width_px is provided: wrap to chars_for_width(max_width_px)
    - else: no wrapping (only split on '\n')
    """
    if max_chars is None and max_width_px is not None:
        max_chars = chars_for_width(max_width_px)

    lines = _split_text_to_lines(text, max_chars)

    try:
        dy = int(FONT_H) + int(line_gap)
    except Exception:
        dy = int(FONT_H)

    # Vertical anchor behavior for multi-line blocks:
    # - T*: y is top of first line
    # - M*: y is center of whole block
    # - B*: y is bottom of last line
    a = "TL" if anchor is None else str(anchor).upper()
    if len(a) != 2:
        a = "TL"
    v = a[0]

    n = len(lines)
    if v == "B":
        y0 = int(y) - (n - 1) * dy
    elif v == "M":
        y0 = int(y) - ((n - 1) * dy) // 2
    else:
        y0 = int(y)

    objs = []
    yy = y0
    for ln in lines:
        objs.append(text_line(ln, x, yy, color=color, anchor=anchor))
        yy += dy

    return objs


# -----------------------------------------
# Kernel-facing widgets
# -----------------------------------------

def draw_hud(time_text, title_text, battery_text=None):
    """
    Returns HUD objects (text + visual divider separator line).
    """
    objs = []
    margin = 8
    y_top = 0

    if time_text is not None:
        objs.append(text_line(str(time_text), margin, y_top, color=YELLOW, anchor="TL"))

    if title_text is not None:
        objs.append(text_line(str(title_text), WIDTH // 2, y_top, color=GRAY_DARK, anchor="TC"))

    if battery_text is not None:
        objs.append(text_line(str(battery_text), WIDTH - margin, y_top, color=GREEN, anchor="TR"))

    if ENABLE_SHAPES:
        objs.extend(line(0, FONT_H, WIDTH, FONT_H, color=GRAY_DARK, thickness=1))

    return objs


def draw_carousel_item(label, position):
    """
    position: -1 (left), 0 (center), +1 (right)
    """
    t = "" if label is None else str(label)

    if position == 0:
        return [text_line(t, WIDTH // 2, HEIGHT // 2, color=WHITE, anchor="MC")]

    if position == -1:
        return [text_line(t, 40, HEIGHT // 2, color=GRAY, anchor="ML")]

    if position == 1:
        return [text_line(t, WIDTH - 40, HEIGHT // 2, color=GRAY, anchor="MR")]

    return []


def draw_hint(text, color=WHITE):
    """
    Bottom-center hint.
    """
    return [text_line("" if text is None else str(text), WIDTH // 2, HEIGHT, color=color, anchor="BC")]


def rect(x1, y1, x2, y2, color=WHITE):
    """
    Returns [display.Rectangle(...)] if ENABLE_SHAPES, else [].
    Defensive: never throws.
    """
    if not ENABLE_SHAPES:
        return []
    try:
        return [display.Rectangle(int(x1), int(y1), int(x2), int(y2), int(color))]
    except Exception:
        return []


def line(x1, y1, x2, y2, color=WHITE, thickness=1):
    """
    Returns [display.Line(...)] if ENABLE_SHAPES, else [].
    Defensive: never throws.
    """
    if not ENABLE_SHAPES:
        return []
    try:
        return [display.Line(int(x1), int(y1), int(x2), int(y2), int(color), thickness=int(thickness))]
    except Exception:
        return []


def fill(color=BLACK):
    """
    Returns [display.Fill(...)] if ENABLE_SHAPES, else [].
    Defensive: never throws.
    """
    if not ENABLE_SHAPES:
        return []
    try:
        return [display.Fill(int(color))]
    except Exception:
        return []
