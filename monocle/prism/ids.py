# prism/ids.py
# Canonical identifiers shared across kernel, apps, and protocol routing.
# Keep this file pure-constants + tiny helpers (no side effects).

# -------------------------
# App IDs (APP_ID)
# -------------------------
APP_ORACLE = "oracle"
APP_VISION = "vision"
APP_NAVIGATE = "navigate"
APP_STREAM = "stream"
APP_CHRONOS = "chronos"
APP_TELEPROMPTER = "teleprompter"
APP_RECALL = "recall"
APP_BABEL = "babel"

APP_IDS = (
    APP_ORACLE,
    APP_VISION,
    APP_NAVIGATE,
    APP_STREAM,
    APP_CHRONOS,
    APP_TELEPROMPTER,
    APP_RECALL,
    APP_BABEL,
)

# Display labels (UI text only)
LABEL_ORACLE = "ORACLE"
LABEL_VISION = "VISION"
LABEL_NAVIGATE = "NAVIGATE"
LABEL_STREAM = "STREAM"
LABEL_CHRONOS = "CHRONOS"
LABEL_TELEPROMPTER = "TELEPROMPTER"
LABEL_RECALL = "RECALL"
LABEL_BABEL = "BABEL"

APP_LABEL = {
    APP_ORACLE: LABEL_ORACLE,
    APP_VISION: LABEL_VISION,
    APP_NAVIGATE: LABEL_NAVIGATE,
    APP_STREAM: LABEL_STREAM,
    APP_CHRONOS: LABEL_CHRONOS,
    APP_TELEPROMPTER: LABEL_TELEPROMPTER,
    APP_RECALL: LABEL_RECALL,
    APP_BABEL: LABEL_BABEL,
}

# Module paths (kernel import targets)
MOD_ORACLE = "apps.oracle"
MOD_VISION = "apps.vision"
MOD_NAVIGATE = "apps.navigate"
MOD_STREAM = "apps.stream"
MOD_CHRONOS = "apps.chronos"
MOD_TELEPROMPTER = "apps.teleprompter"
MOD_RECALL = "apps.recall"
MOD_BABEL = "apps.babel"

APP_MODULE = {
    APP_ORACLE: MOD_ORACLE,
    APP_VISION: MOD_VISION,
    APP_NAVIGATE: MOD_NAVIGATE,
    APP_STREAM: MOD_STREAM,
    APP_CHRONOS: MOD_CHRONOS,
    APP_TELEPROMPTER: MOD_TELEPROMPTER,
    APP_RECALL: MOD_RECALL,
    APP_BABEL: MOD_BABEL,
}

# Registry tuple used by kernel orbit rendering and loader
# Each entry: (app_id, label, module_path)
APPS = (
    (APP_ORACLE, LABEL_ORACLE, MOD_ORACLE),
    (APP_VISION, LABEL_VISION, MOD_VISION),
    (APP_NAVIGATE, LABEL_NAVIGATE, MOD_NAVIGATE),
    (APP_STREAM, LABEL_STREAM, MOD_STREAM),
    (APP_CHRONOS, LABEL_CHRONOS, MOD_CHRONOS),
    (APP_TELEPROMPTER, LABEL_TELEPROMPTER, MOD_TELEPROMPTER),
    (APP_RECALL, LABEL_RECALL, MOD_RECALL),
    (APP_BABEL, LABEL_BABEL, MOD_BABEL),
)

def is_app_id(value):
    if value is None:
        return False
    s = str(value)
    for a in APP_IDS:
        if s == a:
            return True
    return False


# -------------------------
# Message types (CTRL_JSON semantic payload)
# -------------------------
MSG_SYS = "SYS"
MSG_STATE = "STATE"
MSG_GHOST = "GHOST"
MSG_ERR = "ERR"

# SYS commands
SYS_FOCUS = "FOCUS"
SYS_WIDGETS = "WIDGETS"
SYS_TIME = "TIME"

# Device->Host event types
EVT_BTN = "BTN"
EVT_FOCUS = "FOCUS"

# Focus modes (device -> host)
FOCUS_ORBIT = "ORBIT"
FOCUS_APP = "FOCUS"

# Button envelope fields
BTN_ID_L = "L"
BTN_ID_R = "R"
GEST_TAP = "TAP"
GEST_LONG = "LONG"
GEST_DOUBLE = "DOUBLE"
