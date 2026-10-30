#!/usr/bin/env python3
# The witch and her swamp when the player has no Minecraft of their own: Pixel Perfection Legacy by Nova Wostra (CC BY-SA
# 4.0, https://modrinth.com/resourcepack/pixel-perfection-legacy, 26.3-97.2 unzipped), which draws the witch in
# Minecraft's layout, copied under goodluck_monsters' names
#   python3 dev/luanti-art/witch.py <pixel perfection legacy dir> [mods dir]
import os, shutil, sys

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
SRC = sys.argv[1] + "/assets/minecraft/textures/"
MODS = sys.argv[2] if len(sys.argv) > 2 else \
    ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods"
FILES = {
    "entity/witch/witch": "goodluck_monsters/textures/goodluck_monsters_witch",
    "item/witch_spawn_egg": "goodluck_monsters/textures/goodluck_monsters_witch_egg",
}

for path, name in FILES.items():
    os.makedirs(os.path.dirname(f"{MODS}/{name}"), exist_ok=True)
    shutil.copyfile(SRC + path + ".png", f"{MODS}/{name}.png")
print(len(FILES), "textures in", os.path.relpath(MODS, ROOT))
