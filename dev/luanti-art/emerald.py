#!/usr/bin/env python3
# goodluck_emerald's textures, goodluckOS's own pixel art: a step-cut ("emerald cut") gem, an octagon with stepped
# facets around a flat table, in Minetest Game's style (16x16, dark outline, four shades)
#   python3 dev/luanti-art/emerald.py [out dir]
import os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
OUT = sys.argv[1] if len(sys.argv) > 1 else \
    ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods/goodluck_emerald/textures"
C = {"o": (10, 42, 22), "d": (20, 101, 47), "m": (33, 145, 74), "l": (63, 191, 107), "h": (126, 232, 162),
     "w": (230, 255, 240)}

CRYSTAL = [".oo.", "ohlo", "olmo", "omdo", ".oo."]
SPOTS = [(1, 2, "l"), (9, 1, "l"), (5, 7, "w"), (11, 9, "l"), (2, 11, "l")]


def gem():
    # an octagon (columns 3-12, rows 1-14, corners cut by 2): outline, a bright and a dark step, then the table
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    for y in range(16):
        for x in range(16):
            l, r, t, b = x - 3, 12 - x, y - 1, 14 - y
            sides = {"l": l, "t": t, "r": r, "b": b, "tl": l + t - 2, "tr": r + t - 2, "bl": l + b - 2, "br": r + b - 2}
            side = min(sides, key=sides.get)
            d = sides[side]
            if d < 0:
                continue
            lit = side in ("l", "t", "tl")
            c = ("o", "h" if lit else "d", "l" if lit else "m")[d] if d < 3 else "m"
            if d >= 3 and (x - 6) + (y - 4) < 2:
                c = "l"
            img.putpixel((x, y), C[c] + (255,))
    img.putpixel((6, 4), C["w"] + (255,))
    return img


def mineral():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    for sx, sy, shine in SPOTS:
        for y, row in enumerate(CRYSTAL):
            for x, c in enumerate(row):
                if c in C:
                    img.putpixel((sx + x, sy + y), C[shine if c == "l" else c] + (255,))
    return img


def block():
    # concentric steps lit from the top left: each ring light on its top and left, dark on its bottom and right
    rings = [("h", "o"), ("l", "d"), ("m", "d"), ("h", "m"), ("l", "m"), ("m", "d"), ("l", "d"), ("w", "m")]
    img = Image.new("RGBA", (16, 16))
    for y in range(16):
        for x in range(16):
            r = min(x, y, 15 - x, 15 - y)
            lit, dark = rings[r]
            img.putpixel((x, y), C[lit if (x == r or y == r) and x + y < 15 else dark] + (255,))
    return img


os.makedirs(OUT, exist_ok=True)
gem().save(OUT + "/goodluck_emerald.png")
mineral().save(OUT + "/goodluck_emerald_mineral.png")
block().save(OUT + "/goodluck_emerald_block.png")
print("3 textures in", os.path.relpath(OUT, ROOT))
