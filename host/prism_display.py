"""Host-side display composition helpers for Monocle DRAW packets."""

WHITE = 0xFFFFFF
GRAY = 0xAAAAAA
DIM = 0x555555
YELLOW = 0xFFEE33
GREEN = 0x1D6914
CYAN = 0x29D0D0
RED = 0xAD2323
WIDTH = 640
HEIGHT = 400
TEXT_COLS = 26
TEXT_ITEM_LIMIT = 12
TITLE_COLS = 14
HEADER_SIDE_COLS = 5


def clean_text(value):
    s = "" if value is None else str(value)
    return s.replace("\n", " ").replace('"', "'").replace("\\", "/")


def clip_text(value, limit=TEXT_COLS):
    s = clean_text(value)
    if len(s) <= limit:
        return s
    if limit <= 1:
        return s[:limit]
    return s[:limit - 1] + "."


def wrap_text(value, cols=TEXT_COLS, max_lines=6):
    words = clean_text(value).split()
    if not words:
        return []
    lines = []
    cur = ""
    for word in words:
        if len(word) > cols:
            if cur:
                lines.append(cur)
                cur = ""
            while len(word) > cols and len(lines) < max_lines:
                lines.append(word[:cols - 1] + ".")
                word = word[cols - 1:]
            if word:
                cur = word
        elif not cur:
            cur = word
        elif len(cur) + 1 + len(word) <= cols:
            cur += " " + word
        else:
            lines.append(cur)
            cur = word
        if len(lines) >= max_lines:
            break
    if cur and len(lines) < max_lines:
        lines.append(cur)
    return lines[:max_lines]


def t_item(text, x, y, color=WHITE, anchor="MC", limit=TEXT_COLS):
    return {
        "k": "t",
        "v": clip_text(text, limit),
        "x": int(x),
        "y": int(y),
        "c": int(color),
        "a": anchor,
        "n": int(limit),
    }


def l_item(x1, y1, x2, y2, color=WHITE, width=1):
    return {
        "k": "l",
        "x1": int(x1),
        "y1": int(y1),
        "x2": int(x2),
        "y2": int(y2),
        "c": int(color),
        "w": int(width),
    }


def r_item(x1, y1, x2, y2, color=WHITE):
    return {
        "k": "r",
        "x1": int(x1),
        "y1": int(y1),
        "x2": int(x2),
        "y2": int(y2),
        "c": int(color),
    }


def bitmap_items(pattern, x, y, cell=8, color=WHITE, max_items=16):
    items = []
    for row_idx, row in enumerate(pattern or []):
        col = 0
        row_s = str(row)
        while col < len(row_s):
            while col < len(row_s) and row_s[col] != "1":
                col += 1
            start = col
            while col < len(row_s) and row_s[col] == "1":
                col += 1
            if col > start:
                x1 = x + start * cell
                y1 = y + row_idx * cell
                items.append(r_item(x1, y1, x + col * cell - 1, y1 + cell - 1, color))
                if len(items) >= max_items:
                    return items
    return items


def screen_items(title, lines=None, footer="", left="", right="", accent=WHITE, dense=False):
    lines = list(lines or [])
    items = [
        t_item(left, 8, 4, DIM, "TL", HEADER_SIDE_COLS),
        t_item(title, WIDTH // 2, 4, accent, "TC", TITLE_COLS),
        t_item(right, WIDTH - 8, 4, DIM, "TR", HEADER_SIDE_COLS),
    ]
    if footer:
        ys = [84, 140, 196, 252, 308]
        line_limit = 5
    else:
        ys = [80, 136, 192, 248, 304, 360]
        line_limit = 6
    for y, line in zip(ys, lines[:line_limit]):
        items.append(t_item(line, WIDTH // 2, y, WHITE, "MC", TEXT_COLS))
    if footer:
        items.append(t_item(footer, WIDTH // 2, HEIGHT - 4, GRAY, "BC", TEXT_COLS))
    return items[:TEXT_ITEM_LIMIT]
