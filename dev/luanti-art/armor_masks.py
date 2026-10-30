#!/usr/bin/env python3
# The masks goodluck_mcassets/textures.txt cuts the armor layers with: 64x32 as the skin, white where 3d_armor's
# character model draws the piece (binary AND in [mask), transparent elsewhere.
#   python3 dev/luanti-art/armor_masks.py
import os
from PIL import Image

OUT = os.path.dirname(os.path.abspath(__file__)) + \
    "/../../rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods/goodluck_mcassets/textures"
# the helmet in the hat's place, the chestplate the body and the arm, the leggings the leg and the body's lower 8 rows
# (Minecraft's belt), the boots a 4x8x4 box at (16, 0): its sides, and its top and sole above them
MASKS = {
    "helmet": [(32, 0, 64, 16)],
    "chestplate": [(16, 16, 56, 32)],
    "leggings": [(0, 16, 16, 32), (16, 24, 40, 32)],
    "boots": [(16, 4, 32, 12)],
    "boots_top": [(20, 0, 28, 4)],
}
os.makedirs(OUT, exist_ok=True)
for name, boxes in MASKS.items():
    im = Image.new("RGBA", (64, 32), (0, 0, 0, 0))
    for x0, y0, x1, y1 in boxes:
        im.paste((255, 255, 255, 255), (x0, y0, x1, y1))
    im.save(f"{OUT}/goodluck_mcassets_mask_{name}.png", optimize=True)
print(len(MASKS), "masks in", os.path.relpath(OUT))
