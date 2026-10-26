#!/usr/bin/env python3
# goodluck_models' default textures for Minecraft's layouts, from Pixel Perfection by XSSheep (CC BY-SA 4.0) as
# Mineclonia carries it (https://codeberg.org/mineclonia/mineclonia, 7410cf1): its chest drawn for Minecraft's
# model before 1.15, which stood upside down, is turned to the layout since, and its double chest split into the two
# halves; the minecart and its item as they are; the farm animals moved to 26.x's layouts (below)
#   python3 dev/luanti-art/pixelperfection.py <mineclonia checkout> [out dir]
import os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
SRC = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else \
    ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods/goodluck_models/textures"


def faces(u, v, w, h, d):
    # a box's areas on the texture: top, bottom, -x, -z, +x, +z
    return [(u + d, v, w, d), (u + d + w, v, w, d), (u, v + d, d, h), (u + d, v + d, w, h), (u + d + w, v + d, d, h),
            (u + d + w + d, v + d, w, h)]


def turned(img, u, v, w, h, d):
    # a box's faces moved and turned from the old layout to the new, in faces() order: top and bottom mirrored and
    # swapped, the sides a half turn, front and back swapped
    crop = [img.crop((x, y, x + cw, y + ch)) for x, y, cw, ch in faces(u, v, w, h, d)]
    top, bottom = (c.transpose(Image.FLIP_LEFT_RIGHT) for c in crop[:2])
    west, north, east, south = (c.rotate(180) for c in crop[2:])
    return [bottom, top, west, south, east, north]


def put(out, parts, u, v, w, h, d):
    for img, (x, y, _, _) in zip(parts, faces(u, v, w, h, d)):
        out.paste(img, (x, y))


def cols(img, a, b):
    return img.crop((a, 0, b, img.height))


os.makedirs(OUT, exist_ok=True)
chests = SRC + "/mods/ITEMS/mcl_chests/textures/"
single = Image.open(chests + "mcl_chests_normal.png").convert("RGBA")
out = Image.new("RGBA", single.size)
for box in ((0, 0, 14, 5, 14), (0, 19, 14, 10, 14), (0, 0, 2, 4, 1)):
    put(out, turned(single, *box), *box)
out.save(OUT + "/goodluck_models_chest.png")

# the double chest, 30 wide, turned as one box, then each half takes its 15 (a box's top, back and bottom run with
# x, its front against it) and its end; halves named as seen from the front
double = Image.open(chests + "mcl_chests_normal_double.png").convert("RGBA")
halves = {"left": Image.new("RGBA", (64, 64)), "right": Image.new("RGBA", (64, 64))}
for u, v, w, h, d in ((0, 0, 30, 5, 14), (0, 19, 30, 10, 14), (0, 0, 2, 4, 1)):
    top, bottom, west, back, east, front = turned(double, u, v, w, h, d)
    half = w // 2
    for name, (lo, hi), end in (("left", (0, half), west), ("right", (half, w), east)):
        flo, fhi = w - hi, w - lo
        put(halves[name], [cols(top, lo, hi), cols(bottom, lo, hi), end, cols(back, lo, hi), end,
                           cols(front, flo, fhi)], u, v, half, h, d)
for name, img in halves.items():
    img.save(OUT + f"/goodluck_models_chest_{name}.png")

carts = SRC + "/mods/ENTITIES/mcl_minecarts/textures/"
Image.open(carts + "mcl_minecarts_minecart.png").convert("RGBA").save(OUT + "/goodluck_models_minecart.png")
Image.open(carts + "mcl_minecarts_minecart_normal.png").convert("RGBA").save(OUT + "/goodluck_models_minecart_item.png")
print("textures in", os.path.relpath(OUT, ROOT))

# the farm animals, under mobs_animal's names (animals in a world keep theirs) in the layouts of goodluck_models'
# meshes: 26.x's cow and pig on 64x64, the cow's muzzle (a 6x3x1 box at 1,33) taken from the nose Pixel Perfection
# draws on the head's front (8x8 at 6,6); the sheep's body over its wool on one texture, and no horns; chickens all
# white, as Minecraft's in the plains (the chicken is kingoscargames' addition to Pixel Perfection, CC BY-SA 4.0 too)
ANIMALS = OUT.replace("/goodluck_models/textures", "/mobs_animal/textures")
mobs = SRC + "/mods/ENTITIES/mobs_mc/textures/mobs_mc_"


def canvas(top=None, bottom=None):
    img = Image.new("RGBA", (64, 64))
    for part, y in ((top, 0), (bottom, 32)):
        if part:
            img.paste(Image.open(mobs + part + ".png").convert("RGBA"), (0, y))
    return img


cow = canvas("cow")
for (sx, sy, w, h), (dx, dy) in (((7, 11, 6, 1), (2, 33)), ((7, 13, 6, 1), (8, 33)), ((7, 11, 1, 3), (1, 34)),
                                 ((7, 11, 6, 3), (2, 34)), ((12, 11, 1, 3), (8, 34)), ((7, 11, 6, 3), (9, 34))):
    cow.paste(cow.crop((sx, sy, sx + w, sy + h)), (dx, dy))
for name in ("mobs_cow", "mobs_cow2"):
    cow.save(f"{ANIMALS}/{name}.png")
canvas("pig").save(ANIMALS + "/mobs_pumba.png")
for name in ("mobs_chicken", "mobs_chicken_brown", "mobs_chicken_black", "mobs_chick"):
    Image.open(mobs + "chicken.png").convert("RGBA").save(f"{ANIMALS}/{name}.png")
canvas("sheep").save(ANIMALS + "/mobs_sheep_base.png")
# the wool is tinted as the sheep is: Pixel Perfection's beige made grey, its shading kept, as light as Minecraft's
wool = canvas(bottom="sheep_fur")
px = wool.load()
lit = [(0.299 * r + 0.587 * g + 0.114 * b) for y in range(64) for x in range(64) for r, g, b, a in [px[x, y]] if a]
gain = 238 / (sum(lit) / len(lit))
for y in range(64):
    for x in range(64):
        r, g, b, a = px[x, y]
        if a:
            v = min(255, round((0.299 * r + 0.587 * g + 0.114 * b) * gain))
            px[x, y] = (v, v, v, a)
wool.save(ANIMALS + "/mobs_sheep_wool.png")
canvas("sheep_sheared").save(ANIMALS + "/mobs_sheep_shaved.png")
canvas().save(ANIMALS + "/mobs_sheep_horns.png")
print("textures in", os.path.relpath(ANIMALS, ROOT))
