#!/usr/bin/env python3
# goodluck_recipes' notice: a dark box with a light edge and cut corners, 140x24 (the HUD shows it at 280x48)
#   python3 dev/luanti-art/toast.py [out dir]
import os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
OUT = sys.argv[1] if len(sys.argv) > 1 else \
    ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods/goodluck_recipes/textures"
W, H = 140, 24
FILL, EDGE, SHADE = (24, 24, 28, 230), (150, 150, 160, 255), (60, 60, 68, 255)

img = Image.new("RGBA", (W, H))
for y in range(H):
    for x in range(W):
        corner = (x in (0, W - 1)) and (y in (0, H - 1))
        if corner:
            continue
        edge = x in (0, W - 1) or y in (0, H - 1)
        inner = x in (1, W - 2) or y in (1, H - 2)
        img.putpixel((x, y), EDGE if edge else SHADE if inner else FILL)
os.makedirs(OUT, exist_ok=True)
img.save(OUT + "/goodluck_recipes_toast.png", optimize=True)
