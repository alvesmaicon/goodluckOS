#!/usr/bin/env python3
"""The factory U-Boot's battery screens, for BOOT's root: battery_0..3.bmp (the level, animated upwards while
charging), battery_fail.bmp (too low to boot, charging) and low_battery.bmp (too low to boot, no charger: it
powers off). 640x480, 24 bits, as logo.bmp. The charge screens have no text, so no language, and their lower
half stays black: U-Boot prints the voltage and the current there. On low_battery.bmp U-Boot prints the voltage,
black on white, at text row 18 (y 288-303, 8 px a character, centered), then "power off...": a white chip
there holds both."""
import os
from PIL import Image, ImageDraw, ImageFont

W, H = 640, 480
BX, BY, BW, BH = 210, 80, 200, 110          # battery body
NUB = (BX + BW, BY + 34, BX + BW + 16, BY + BH - 34)
GREEN, RED, AMBER, OUTLINE = (76, 200, 110), (225, 70, 60), (245, 190, 60), (225, 225, 225)
FONTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../rootfs/board/my-device/rootfs-overlay/usr/share/fonts")

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

def low_battery():
    im = battery(0.08, RED, outline=RED)
    d = ImageDraw.Draw(im)
    bold = ImageFont.truetype(os.path.join(FONTS, "AtkinsonHyperlegible-Bold.ttf"), 46)
    regular = ImageFont.truetype(os.path.join(FONTS, "AtkinsonHyperlegible-Regular.ttf"), 26)
    d.text((W // 2, 214), "Low battery", font=bold, fill=(255, 255, 255), anchor="mt")
    d.rounded_rectangle((256, 280, 383, 311), radius=16, fill=(255, 255, 255))   # "3.864 V", "power off..."
    d.text((W // 2, 338), "Plug in the charger to turn it on", font=regular, fill=(170, 170, 170), anchor="mt")
    return im

shots = {
    "battery_0.bmp": battery(0.10, RED),
    "battery_1.bmp": battery(0.50, GREEN),
    "battery_2.bmp": battery(0.75, GREEN),
    "battery_3.bmp": battery(1.00, GREEN),
    "battery_fail.bmp": battery(0.0, RED, outline=RED, bolt=True),
    "low_battery.bmp": low_battery(),
}
for name, im in shots.items():
    im.save(name, "BMP")
    im.resize((320, 240)).save(name.replace(".bmp", "-preview.png"))
print("ok", ", ".join(shots))
