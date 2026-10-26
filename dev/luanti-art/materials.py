#!/usr/bin/env python3
# goodluck_redstone's and goodluck_metals' textures, goodluckOS's own pixel art in Minetest Game's style (16x16, a
# dark outline, lit from the top left): redstone, copper and golden tools, copper armor and the copper nugget.
# Shapes are silhouettes, one letter a material; the shades and the outline come from the shape
#   python3 dev/luanti-art/materials.py [out dir]
import os, random, sys
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
MODS = ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods"


def out(mod):
    d = sys.argv[1] if len(sys.argv) > 1 else f"{MODS}/{mod}/textures"
    os.makedirs(d, exist_ok=True)
    return d


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


# outline, dark, mid, light, highlight
COPPER = ["#4a1e0a", "#934526", "#c96a3a", "#e88e52", "#ffc390"]
GOLD = ["#5a3c04", "#b07a0a", "#e0aa1c", "#f8dc50", "#fffbd0"]
STICK = ["#2e1c0a", "#5e3c1c", "#8a5a2c", "#a87440", "#c8945a"]
RED = ["#3a0404", "#7a0c08", "#b81810", "#f03020", "#ff8a6a"]


def shaded(text, palettes, outline=True, size=(16, 16)):
    # each letter a material: its top and left edges light, bottom and right dark; a lowercase letter is the
    # material's highlight; around the shape the outline of the first material it touches
    fill = {}
    for y, row in enumerate(text.strip("\n").split("\n")):
        for x, c in enumerate(row):
            if c != ".":
                fill[(x, y)] = c
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    for (x, y), c in fill.items():
        m = c.upper()
        same = lambda p: (fill.get(p) or "").upper() == m
        if c != m:
            s = 4
        elif not same((x, y - 1)) and not same((x - 1, y)):
            s = 3
        elif not same((x + 1, y)) and not same((x, y + 1)):
            s = 1
        else:
            s = 2
        img.putpixel((x, y), hexc(palettes[m][s]) + (255,))
    if outline:
        for y in range(size[1]):
            for x in range(size[0]):
                if (x, y) not in fill:
                    near = [fill.get(p) for p in ((x, y - 1), (x - 1, y), (x + 1, y), (x, y + 1))]
                    near = sorted(c.upper() for c in near if c)
                    if near:
                        img.putpixel((x, y), hexc(palettes[near[0]][0]) + (255,))
    return img


def cells(*runs):
    # (y, x0, x1) runs to a 16x16 silhouette of M
    rows = [["."] * 16 for _ in range(16)]
    for y, x0, x1, *c in runs:
        for x in range(x0, x1 + 1):
            rows[y][x] = c[0] if c else "M"
    return "\n".join("".join(r) for r in rows)


def stick(rows, top, length, wide=2):
    # a handle from the bottom left up to the right, two wide, its top cell at (top, y)
    for t in range(length):
        x, y = top - t, 15 - top + t - (2 if wide == 2 else 1) + 1
        for k in range(wide):
            if 0 <= y < 16 and 0 <= x + k - 1 < 16:
                rows[y][x + k - 1] = "H" if rows[y][x + k - 1] == "." else rows[y][x + k - 1]


def tool(head, handle_top, handle_length):
    rows = [list(r) for r in cells(*head).split("\n")]
    stick(rows, handle_top, handle_length)
    return "\n".join("".join(r) for r in rows)


def mirrored(runs):
    # the runs and their mirror across the diagonal from the bottom left to the top right
    pts = {(x, y) for y, x0, x1 in runs for x in range(x0, x1 + 1)}
    pts |= {(15 - y, 15 - x) for x, y in pts}
    return [(y, x, x) for x, y in pts]


TOOLS = {
    "pick": tool(mirrored([(2, 5, 9), (3, 3, 11), (4, 2, 3), (4, 9, 11), (5, 2, 2)]), 11, 10),
    "axe": tool([(1, 8, 10), (2, 7, 11), (3, 6, 11), (4, 5, 11), (5, 4, 10), (6, 4, 8), (7, 5, 6), (3, 13, 13),
                 (4, 13, 13)], 12, 11),
    "shovel": tool([(y, x, x) for y in range(16) for x in range(16) if (x - 11.6) ** 2 + (y - 3.4) ** 2 <= 6.6],
                   10, 9),
    "sword": tool([(9 - t, 5 + t, 7 + t) for t in range(8)] + [(1, 13, 14)] +
                  [(10 + i, 5 + i, 6 + i, "H") for i in range(-2, 3)], 4, 3),
    "hoe": tool([(2, 6, 12), (3, 6, 13), (4, 6, 7), (5, 6, 6)], 12, 11),
}

ARMOR = {
    "helmet": cells((3, 4, 11), (4, 3, 12), (5, 3, 12), (6, 3, 12), (7, 3, 5), (7, 10, 12), (8, 3, 5), (8, 10, 12),
                    (9, 3, 4), (9, 11, 12), (4, 5, 6, "m")),
    "chestplate": cells((2, 3, 5), (2, 10, 12), (3, 2, 6), (3, 9, 13), (4, 2, 13), (5, 2, 13), (6, 3, 12),
                        *[(y, 4, 11) for y in range(7, 14)], (4, 4, 5, "m")),
    "leggings": cells((2, 4, 11), (3, 4, 11), *[(y, 4, 6) for y in range(4, 13)], *[(y, 9, 11) for y in range(4, 13)],
                      (2, 5, 6, "m")),
    "boots": cells(*[(y, 3, 5) for y in range(6, 10)], *[(y, 10, 12) for y in range(6, 10)], (10, 1, 5), (11, 1, 5),
                   (10, 10, 14), (11, 10, 14), (6, 3, 3, "m"), (6, 10, 10, "m")),
}

NUGGET = cells((5, 5, 7), (6, 4, 8), (7, 4, 8), (8, 5, 7), (8, 10, 11), (9, 9, 12), (10, 9, 12), (11, 10, 11),
               (6, 5, 5, "m"), (9, 10, 10, "m"))

# 3d_armor's model: where each piece is drawn on its 64x32 texture, and on the 32x64 front view of the inventory
WORN = {
    "helmet": [(40, 0, 8, 8), (32, 8, 32, 3), (32, 11, 9, 3), (43, 11, 2, 2), (47, 11, 17, 3), (57, 14, 6, 1)],
    "chestplate": [(20, 16, 8, 2), (44, 16, 4, 4), (20, 18, 2, 2), (26, 18, 2, 2), (16, 20, 6, 1), (26, 20, 30, 1),
                   (16, 21, 7, 1), (25, 21, 31, 1), (16, 22, 40, 2), (16, 24, 24, 7), (21, 31, 6, 1),
                   (33, 31, 6, 1)],
    "leggings": [(4, 16, 4, 4), (28, 16, 8, 4), (0, 20, 16, 8), (16, 31, 24, 1)],
    "boots": [(20, 0, 8, 4), (16, 4, 16, 7)],
}
PREVIEW = {
    "helmet": [(8, 0, 16, 6), (8, 6, 2, 6), (14, 6, 4, 4), (22, 6, 2, 6)],
    "chestplate": [(1, 16, 11, 2), (20, 16, 11, 2), (1, 18, 13, 2), (18, 18, 13, 2), (1, 20, 30, 4), (8, 24, 16, 14),
                   (10, 38, 12, 2)],
    "leggings": [(8, 38, 16, 18)],
    "boots": [(8, 50, 16, 14)],
}


def plates(rects, size, palette):
    # each region a plate: light along its top and left, dark along its bottom and right, a little grain
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    rnd = random.Random(len(rects))
    for x0, y0, w, h in rects:
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                s = 3 if (y == y0 or x == x0) else 1 if (y == y0 + h - 1 or x == x0 + w - 1) else 2
                if s == 2 and rnd.random() < 0.12:
                    s = rnd.choice((1, 3))
                img.putpixel((x, y), hexc(palette[s]) + (255,))
    return img


def speckled(text, palette, seed, light=0.25):
    # dust: a heap of grains, light and dark at random
    img = shaded(text, {"R": palette})
    rnd = random.Random(seed)
    for y in range(16):
        for x in range(16):
            p = img.getpixel((x, y))
            if p[3] and p[:3] != hexc(palette[0]) and rnd.random() < light:
                img.putpixel((x, y), hexc(palette[rnd.choice((1, 3, 4))]) + (255,))
    return img


def mineral():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    spot = [".oo.", "olro", "ordo", ".oo."]
    shades = {"o": RED[0], "l": RED[4], "r": RED[3], "d": RED[2]}
    for sx, sy in [(1, 1), (9, 0), (5, 5), (11, 6), (1, 10), (7, 11), (12, 12)]:
        for y, row in enumerate(spot):
            for x, c in enumerate(row):
                if c in shades and 0 <= sx + x < 16 and 0 <= sy + y < 16:
                    img.putpixel((sx + x, sy + y), hexc(shades[c]) + (255,))
    return img


def block():
    # red with a grain of dots, bevelled: light along the top and left, dark along the bottom and right
    img = Image.new("RGBA", (16, 16))
    rnd = random.Random(7)
    for y in range(16):
        for x in range(16):
            s = 3 if x == 0 or y == 0 else 1 if x == 15 or y == 15 else 2
            if s == 2 and (x * 5 + y * 3) % 7 == 0:
                s = 1
            if s == 2 and rnd.random() < 0.08:
                s = 4
            img.putpixel((x, y), hexc(RED[s]) + (255,))
    return img


def lamp(on):
    # four panes in a frame; lit, the panes glow from their middle
    frame = ["#2a1a0c", "#4a3018", "#6a4422"] if not on else ["#4a2a10", "#8a5a2a", "#b07a3a"]
    glass = ["#3e2a14", "#5a3c1e", "#7a5428"] if not on else ["#e8a030", "#f8d070", "#fff4c8"]
    img = Image.new("RGBA", (16, 16))
    for y in range(16):
        for x in range(16):
            if x in (0, 15) or y in (0, 15):
                c = frame[0]
            elif x in (7, 8) or y in (7, 8):
                c = frame[2] if (x == 7 or y == 7) else frame[1]
            else:
                px, py = (x - 1) % 7, (y - 1) % 7
                d = max(abs(px - 2.5), abs(py - 2.5))
                c = glass[2] if d < 1 else glass[1] if d < 2 else glass[0]
            img.putpixel((x, y), hexc(c) + (255,))
    return img


DUST = cells((7, 7, 8, "R"), (8, 6, 9, "R"), (9, 4, 11, "R"), (10, 3, 12, "R"), (11, 3, 12, "R"), (12, 4, 11, "R"),
             (5, 2, 2, "R"), (6, 12, 12, "R"), (4, 9, 9, "R"))

red = out("goodluck_redstone")
speckled(DUST, RED, 3).save(f"{red}/goodluck_redstone_dust.png")
mineral().save(f"{red}/goodluck_redstone_mineral.png")
block().save(f"{red}/goodluck_redstone_block.png")
lamp(False).save(f"{red}/goodluck_redstone_lamp.png")
lamp(True).save(f"{red}/goodluck_redstone_lamp_on.png")

metals = out("goodluck_metals")
for metal, palette in (("copper", COPPER), ("gold", GOLD)):
    for kind, shape in TOOLS.items():
        shaded(shape, {"M": palette, "H": STICK}).save(f"{metals}/goodluck_metals_{kind}_{metal}.png")
for piece, shape in ARMOR.items():
    shaded(shape, {"M": COPPER}).save(f"{metals}/3d_armor_inv_{piece}_copper.png")
    plates(WORN[piece], (64, 32), COPPER).save(f"{metals}/3d_armor_{piece}_copper.png")
    plates(PREVIEW[piece], (32, 64), COPPER).save(f"{metals}/3d_armor_{piece}_copper_preview.png")
shaded(NUGGET, {"M": COPPER}).save(f"{metals}/goodluck_metals_copper_nugget.png")
print("textures in", os.path.relpath(red, ROOT), "and", os.path.relpath(metals, ROOT))
