"""Prints "1" when a talk key is pressed and "0" when released, read straight from every keyboard device.

Any key counts (except F1, the debug toggle), so a USB foot pedal, presentation clicker,
one-key macro pad or big USB button works as a hold-to-talk button, as long as it acts as a keyboard.

Used by the game on the Pi, where the desktop does not deliver key presses to the game window.
Needs read access to /dev/input (the user is in the "input" group).
"""

import os
import re
import select
import struct

EVENT = struct.Struct("llHHi")  # struct input_event: time (2 longs), type, code, value
EV_KEY, KEY_F1 = 1, 59

devices = open("/proc/bus/input/devices").read().split("\n\n")
# Keyboard-like devices (with or without LEDs), plus the arcade button on GPIO17 (dtoverlay=gpio-key,
# shows up as "button@11" with only key events, EV=3). Skips HDMI-CEC and media/power-button nodes.
paths = ["/dev/input/" + m.group(0) for d in devices
         if "kbd" in d and ("EV=120013" in d or "EV=100013" in d or "button@" in d) and (m := re.search(r"event\d+", d))]
fds = [os.open(p, os.O_RDONLY) for p in paths]
print("keyboards", " ".join(paths), flush=True)

while True:
    for fd in select.select(fds, [], [])[0]:
        data = os.read(fd, EVENT.size * 64)
        for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
            _, _, typ, code, value = EVENT.unpack_from(data, i)
            if typ == EV_KEY and code != KEY_F1 and value in (0, 1):
                print(value, flush=True)
