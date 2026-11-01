#!/usr/bin/env python3
# goodluck_craft's panel, inventory tabs and slot background, drawn pixel by pixel in the game's greys: the panel's outline at the
# image's edge, and tabs of 26x32 sliced at 4 px, whose rows match Minecraft's own sprites (goodluck_mcassets puts
# those in their place), so one layout serves both: a closed tab 2 px short of the open one on top and 4 px below,
# an open tab's last (first, below) 4 rows lying over the panel's border, with left and right variants that carry
# the panel's side on
#   python3 dev/luanti-art/tabs.py [out dir]
import os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
OUT = sys.argv[1] if len(sys.argv) > 1 else \
    ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods/goodluck_craft/textures"
OUTLINE, PANEL, BEHIND, LIGHT = (2, 2, 2, 255), (52, 52, 52, 255), (30, 30, 30, 255), (78, 78, 78, 255)
W, H = 26, 32


# a shape's rows, top down: (first, last) columns of the outline's ends, or None for an empty row
def draw(rows, fill, bevel=None, sides_from=0, sides_to=H):
    im = Image.new("RGBA", (W, H))
    for y, row in enumerate(rows):
        if row is None:
            continue
        a, b = row
        for x in range(a, b + 1):
            im.putpixel((x, y), fill)
        if sides_from <= y < sides_to:
            im.putpixel((a, y), OUTLINE)
            im.putpixel((b, y), OUTLINE)
            if bevel and a + 1 < b:
                im.putpixel((a + 1, y), bevel)
    return im


def cap(im, y, a, b):
    for x in range(a, b + 1):
        im.putpixel((x, y), OUTLINE)


# a tab standing on the panel's top line: rows 0-1 empty, a cut corner, sides down to the bottom
def top_closed():
    rows = [None, None, (2, 23), (1, 24)] + [(0, 25)] * 28
    im = draw(rows, BEHIND)
    cap(im, 2, 2, 23)
    return im


# the open one is 2 px taller and its last 4 rows are the panel's top border: the sides end on its line (row 28),
# then panel; at the panel's left (right) corner its side goes on as the panel's
def top_open(side=None):
    rows = [(2, 23), (1, 24)] + [(0, 25)] * 30
    im = draw(rows, PANEL, LIGHT, 0, 28)
    cap(im, 0, 2, 23)
    for x in range(2, 24):
        im.putpixel((x, 1), LIGHT)
    im.putpixel((0, 28), OUTLINE)
    im.putpixel((25, 28), OUTLINE)
    for y in range(28, H):
        if side == "left":
            im.putpixel((0, y), OUTLINE)
        if side == "right":
            im.putpixel((25, y), OUTLINE)
    return im


# below the panel: the closed one starts under its line and ends 4 px short of the open one
def bottom_closed():
    rows = [(0, 25)] * 26 + [(1, 24), (2, 23), None, None, None, None]
    im = draw(rows, BEHIND)
    cap(im, 27, 2, 23)
    return im


# the open one's first 4 rows are the panel's bottom border, the sides start on its line (row 3)
def bottom_open(side=None):
    rows = [(0, 25)] * 30 + [(1, 24), (2, 23)]
    im = draw(rows, PANEL, LIGHT, 3, H)
    cap(im, 31, 2, 23)
    for y in range(3):
        if side == "left":
            im.putpixel((0, y), OUTLINE)
        if side == "right":
            im.putpixel((25, y), OUTLINE)
    return im


# 32x32, sliced at 10: the outline on the edge with cut corners, as the tabs'
def panel():
    rows = [(2, 29), (1, 30)] + [(0, 31)] * 28 + [(1, 30), (2, 29)]
    im = Image.new("RGBA", (32, 32))
    for y, (a, b) in enumerate(rows):
        for x in range(a, b + 1):
            im.putpixel((x, y), OUTLINE if y in (0, 31) or x in (a, b) else PANEL)
    return im


os.makedirs(OUT, exist_ok=True)
for name, im in {
    "goodluck_craft_panel": panel(),
    # the lists' colour as an image, under the marks of the empty armor slots (listimages[])
    "goodluck_craft_slot": Image.new("RGBA", (32, 32), (0, 0, 0, 0x69)),
    "goodluck_craft_tab": top_closed(),
    "goodluck_craft_tab_selected": top_open(),
    "goodluck_craft_tab_selected_left": top_open("left"),
    "goodluck_craft_tab_selected_right": top_open("right"),
    "goodluck_craft_tab_bottom": bottom_closed(),
    "goodluck_craft_tab_bottom_selected": bottom_open(),
    "goodluck_craft_tab_bottom_selected_left": bottom_open("left"),
    "goodluck_craft_tab_bottom_selected_right": bottom_open("right"),
}.items():
    im.save(f"{OUT}/{name}.png", optimize=True)
