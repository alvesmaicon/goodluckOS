#!/usr/bin/env python3
# The Nether's monsters and their items when the player has no Minecraft of their own: Pixel Perfection Legacy by Nova
# Wostra (CC BY-SA 4.0, https://modrinth.com/resourcepack/pixel-perfection-legacy, 26.3-97.2 unzipped), which draws
# them in 26.x's layouts (the ghast and the magma cube at twice their pixels), copied under goodluck_nether's names
#   python3 dev/luanti-art/nether_mobs.py <pixel perfection legacy dir> [out dir]
import os, shutil, sys

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
SRC = sys.argv[1] + "/assets/minecraft/textures/"
OUT = sys.argv[2] if len(sys.argv) > 2 else \
    ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods/goodluck_nether/textures"
FILES = {
    "entity/blaze/blaze": "blaze", "entity/ghast/ghast": "ghast", "entity/ghast/ghast_shooting": "ghast_shooting",
    "entity/slime/magmacube": "magma_cube", "entity/piglin/zombified_piglin": "zombified_piglin",
    "entity/skeleton/wither_skeleton": "wither_skeleton",
    "item/blaze_rod": "blaze_rod", "item/blaze_powder": "blaze_powder", "item/ghast_tear": "ghast_tear",
    "item/magma_cream": "magma_cream", "item/fire_charge": "fire_charge",
    "item/blaze_spawn_egg": "blaze_egg", "item/ghast_spawn_egg": "ghast_egg", "item/magma_cube_spawn_egg":
    "magma_cube_egg", "item/zombified_piglin_spawn_egg": "zombified_piglin_egg",
    "item/wither_skeleton_spawn_egg": "wither_skeleton_egg",
}

os.makedirs(OUT, exist_ok=True)
for path, name in FILES.items():
    shutil.copyfile(SRC + path + ".png", f"{OUT}/goodluck_nether_{name}.png")
print(len(FILES), "textures in", os.path.relpath(OUT, ROOT))
