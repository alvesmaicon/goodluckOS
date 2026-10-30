#!/usr/bin/env python3
# The witch and her swamp when the player has no Minecraft of their own: Pixel Perfection Legacy by Nova Wostra (CC BY-SA
# 4.0, https://modrinth.com/resourcepack/pixel-perfection-legacy, 26.3-97.2 unzipped), which draws the witch in
# Minecraft's layout, copied under the mods' names: the witch, the cauldron (its content the still water's first
# frame, which the game tints), the flower pot, and the vine in Minecraft's swamp foliage colour
#   python3 dev/luanti-art/witch.py <pixel perfection legacy dir> [mods dir]
import os, shutil, sys
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
SRC = sys.argv[1] + "/assets/minecraft/textures/"
MODS = sys.argv[2] if len(sys.argv) > 2 else \
    ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods"
FILES = {
    "entity/witch/witch": "goodluck_monsters/textures/goodluck_monsters_witch",
    "item/witch_spawn_egg": "goodluck_monsters/textures/goodluck_monsters_witch_egg",
    "block/cauldron_side": "goodluck_potions/textures/goodluck_potions_cauldron_side",
    "block/cauldron_top": "goodluck_potions/textures/goodluck_potions_cauldron_top",
    "block/cauldron_bottom": "goodluck_potions/textures/goodluck_potions_cauldron_bottom",
    "block/cauldron_inner": "goodluck_potions/textures/goodluck_potions_cauldron_inner",
    "item/cauldron": "goodluck_potions/textures/goodluck_potions_cauldron_item",
    "block/flower_pot": "goodluck_swamp/textures/goodluck_swamp_flower_pot",
}

for path, name in FILES.items():
    os.makedirs(os.path.dirname(f"{MODS}/{name}"), exist_ok=True)
    shutil.copyfile(SRC + path + ".png", f"{MODS}/{name}.png")
water = Image.open(SRC + "block/water_still.png").convert("RGBA")
water.crop((0, 0, 16, 16)).save(f"{MODS}/goodluck_potions/textures/goodluck_potions_cauldron_content.png")
vine = Image.open(SRC + "block/vine.png").convert("RGBA")
vine.putdata([(r * 0x6a // 255, g * 0x70 // 255, b * 0x39 // 255, a) for r, g, b, a in vine.getdata()])
vine.save(f"{MODS}/goodluck_swamp/textures/goodluck_swamp_vine.png")
print(len(FILES) + 2, "textures in", os.path.relpath(MODS, ROOT))
