#!/usr/bin/env python3
"""The factory U-Boot's charge screens: battery_0..3.bmp (the level, animated upwards while charging) and
battery_fail.bmp (too low to boot, charging). 640x480, 24 bits, as logo.bmp. The lower half stays black:
U-Boot prints the voltage and the current there. No text, so no language."""
from PIL import Image, ImageDraw

W, H = 640, 480
BX, BY, BW, BH = 210, 80, 200, 110          # battery body
NUB = (BX + BW, BY + 34, BX + BW + 16, BY + BH - 34)
GREEN, RED, AMBER, OUTLINE = (76, 200, 110), (225, 70, 60), (245, 190, 60), (225, 225, 225)

def battery(fill, colour, outline=OUTLINE, bolt=False):
    im = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((BX, BY, BX + BW, BY + BH), radius=14, outline=outline, width=7)
    d.rounded_rectangle(NUB, radius=4, fill=outline)
    if fill > 0:
        inner = (BX + 15, BY + 15, BX + 15 + int((BW - 30) * fill), BY + BH - 15)
        d.rounded_rectangle(inner, radius=6, fill=colour)
    if bolt:     # charging: a bolt across the empty battery
        cx, cy = BX + BW // 2, BY + BH // 2
        d.polygon([(cx + 12, cy - 44), (cx - 26, cy + 6), (cx - 2, cy + 6), (cx - 14, cy + 44), (cx + 26, cy - 8), (cx + 2, cy - 8)], fill=AMBER)
    return im

shots = {
    "battery_0.bmp": battery(0.10, RED),
    "battery_1.bmp": battery(0.50, GREEN),
    "battery_2.bmp": battery(0.75, GREEN),
    "battery_3.bmp": battery(1.00, GREEN),
    "battery_fail.bmp": battery(0.0, RED, outline=RED, bolt=True),
}
for name, im in shots.items():
    im.save(name, "BMP")
    im.resize((320, 240)).save(name.replace(".bmp", "-preview.png"))
print("ok", ", ".join(shots))
