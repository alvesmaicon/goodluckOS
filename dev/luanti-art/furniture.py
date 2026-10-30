#!/usr/bin/env python3
# goodluck_models' own textures in Minecraft's layouts: the bed's faces (each 16x16 face of its head and foot, the
# mattress from row 7 to 13 of the sides, the legs below) and the sign (32x32: the board's front and back, its edges,
# the post at the right)
#   python3 dev/luanti-art/furniture.py [out dir]
import os, random, sys
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
OUT = sys.argv[1] if len(sys.argv) > 1 else \
    ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods/goodluck_models/textures"


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) + (255,)


# dark, mid, light
WOOD = ["#5a3e1e", "#7c5a2e", "#9c7a44"]
PILLOW = ["#b8b8c0", "#e0e0e4", "#fafafa"]
BLANKETS = {"red": ["#7a1414", "#a82222", "#c83c34"], "blue": ["#1c2c78", "#2c46a8", "#4a68c8"]}
STEEL = ["#4a4c50", "#74787c", "#a0a4a8"]
OAK = ["#5e4422", "#8a683a", "#a8864e"]


def blank(w=16, h=16):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def fill(img, box, pal, seed, edge=None):
    # an area in a palette's middle shade, a little grain, its border in the dark one when asked
    rnd = random.Random(seed)
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        for x in range(x0, x1):
            c = pal[1]
            if rnd.random() < 0.18:
                c = pal[rnd.choice((0, 2))]
            if edge and (x in (x0, x1 - 1) and "v" in edge or y in (y0, y1 - 1) and "h" in edge):
                c = pal[0]
            img.putpixel((x, y), hexc(c))


def planks(img, box, pal, seed, every=4):
    # boards along x, a dark seam every few rows
    fill(img, box, pal, seed)
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        if (y - y0) % every == every - 1:
            for x in range(x0, x1):
                img.putpixel((x, y), hexc(pal[0]))


def side(blanket, pillow_cols=()):
    # a side: blanket (or pillow) on the mattress' top 3 rows, the wooden frame under it, legs at both ends
    img = blank()
    for x in range(16):
        pal = PILLOW if x in pillow_cols else blanket
        fill(img, (x, 7, x + 1, 10), pal, x)
    planks(img, (0, 10, 16, 13), WOOD, 3, every=3)
    for x0 in (0, 13):
        fill(img, (x0, 13, x0 + 3, 16), WOOD, x0, edge="v")
    return img


def top(blanket, pillow):
    img = blank()
    fill(img, (0, 0, 16, 16), blanket, 1)
    for x in range(16):
        img.putpixel((x, 0 if not pillow else 7), hexc(blanket[2]))
    if pillow:
        fill(img, (1, 1, 15, 7), PILLOW, 2, edge="hv")
    for y in range(16):
        img.putpixel((0, y), hexc(blanket[0]))
        img.putpixel((15, y), hexc(blanket[0]))
    return img


os.makedirs(OUT, exist_ok=True)
for colour, blanket in BLANKETS.items():
    b = f"{OUT}/goodluck_models_bed_{colour}_"
    top(blanket, True).save(b + "head_up.png")
    top(blanket, False).save(b + "foot_up.png")
    # seen from the east the head's north end is on the right, from the west on the left
    side(blanket, range(9, 16)).save(b + "head_east.png")
    side(blanket, range(0, 7)).save(b + "head_west.png")
    for face in ("foot_east", "foot_west", "foot_south"):
        side(blanket).save(b + face + ".png")
side(PILLOW, range(16)).save(f"{OUT}/goodluck_models_bed_head_north.png")
under = blank()
planks(under, (0, 0, 16, 16), WOOD, 9)
under.save(f"{OUT}/goodluck_models_bed_down.png")

# the sign: the board's front (0,2)-(24,14) and back (0,16)-(24,28), its edges beside and around, the post's faces
# from x 28
for material, pal in (("wood", OAK), ("steel", STEEL)):
    img = blank(32, 32)
    for box in ((0, 2, 24, 14), (0, 16, 24, 28)):
        planks(img, box, pal, box[1])
        x0, y0, x1, y1 = box
        for x in range(x0, x1):
            img.putpixel((x, y0), hexc(pal[0]))
            img.putpixel((x, y1 - 1), hexc(pal[0]))
        for y in range(y0, y1):
            img.putpixel((x0, y), hexc(pal[0]))
            img.putpixel((x1 - 1, y), hexc(pal[0]))
        if material == "steel":
            for x, y in ((x0 + 2, y0 + 2), (x1 - 3, y0 + 2), (x0 + 2, y1 - 3), (x1 - 3, y1 - 3)):
                img.putpixel((x, y), hexc(pal[2]))
    for box in ((0, 0, 24, 2), (0, 28, 24, 30), (24, 2, 26, 14), (24, 16, 26, 28)):
        fill(img, box, pal, box[0] + box[1])
    for box in ((28, 0, 32, 14), (28, 16, 32, 30), (28, 30, 30, 32)):
        fill(img, box, OAK if material == "wood" else STEEL, box[1], edge="v")
    img.save(f"{OUT}/goodluck_models_sign_{material}.png")
print("textures in", os.path.relpath(OUT, ROOT))
