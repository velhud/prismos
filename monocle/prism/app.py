# prism/app.py
# Base application interface for PrismOS.
#
# Kernel expectations:
# - App instance exposes lifecycle + render methods.
# - App must NOT call display.show() directly; render() returns objects for kernel to show.

class BaseApp:
    def __init__(self):
        # Allocation only; keep side effects minimal.
        pass

    def on_start(self):
        # Called once after app instance is created and focus is granted.
        # Return True if this changes what should be rendered.
        return True

    def on_update(self, now_ms):
        # Called frequently by the kernel with time.ticks_ms().
        # Return True if this changes what should be rendered.
        return False

    def on_input(self, event_name):
        # Receives canonical event names from prism/input.py.
        # Return True if this changes what should be rendered.
        return False

    def on_data(self, payload):
        # Receives dict payload from host "STATE" message.
        # Return True if this changes what should be rendered.
        return False

    def render(self):
        # Return list of display objects (Text, etc). Kernel calls display.show(...).
        return []

    def on_exit(self):
        # Called once right before the kernel unloads this app module.
        pass
