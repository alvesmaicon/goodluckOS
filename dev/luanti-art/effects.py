#!/usr/bin/env python3
# goodluck_effects' textures when the player has no Minecraft of their own: Pixel Perfection's, by XSSheep and Nova
# Wostra's Legacy (CC BY-SA 4.0), as Mineclonia 0.124.0 carries them (mcl_potions' effect icons, heart and swirl,
# mcl_hunger's poisoned heart, mcl_mobitems' feather for Slow Falling; its LEGAL.md), copied under goodluck_effects'
# names; those icons have their own frame, so the background is left empty
#   python3 dev/luanti-art/effects.py <mineclonia checkout> [out dir]
import os, shutil, sys
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
SRC = sys.argv[1] + "/mods"
OUT = sys.argv[2] if len(sys.argv) > 2 else \
    ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods/goodluck_effects/textures"
FILES = {
    "speed": "ITEMS/mcl_potions/textures/mcl_potions_effect_swift",
    "slowness": "ITEMS/mcl_potions/textures/mcl_potions_effect_slow",
    "jump_boost": "ITEMS/mcl_potions/textures/mcl_potions_effect_leaping",
    "slow_falling": "ITEMS/mcl_mobitems/textures/mcl_mobitems_feather",
    "poison": "ITEMS/mcl_potions/textures/mcl_potions_effect_poisoned",
    "wither": "ITEMS/mcl_potions/textures/mcl_potions_effect_withering",
    "regeneration": "ITEMS/mcl_potions/textures/mcl_potions_effect_regenerating",
    "strength": "ITEMS/mcl_potions/textures/mcl_potions_effect_strong",
    "weakness": "ITEMS/mcl_potions/textures/mcl_potions_effect_weak",
    "fire_resistance": "ITEMS/mcl_potions/textures/mcl_potions_effect_fire_proof",
    "water_breathing": "ITEMS/mcl_potions/textures/mcl_potions_effect_water_breathing",
    "invisibility": "ITEMS/mcl_potions/textures/mcl_potions_effect_invisible",
    "hunger": "ITEMS/mcl_potions/textures/mcl_potions_effect_food_poisoning",
    "heart_poisoned": "PLAYER/mcl_hunger/textures/hbhunger_icon_health_poison",
    "heart_withered": "ITEMS/mcl_potions/textures/mcl_potions_icon_wither",
    "particle": "ITEMS/mcl_potions/textures/mcl_particles_effect",
}

os.makedirs(OUT, exist_ok=True)
for name, path in FILES.items():
    shutil.copyfile(f"{SRC}/{path}.png", f"{OUT}/goodluck_effects_{name}.png")
Image.new("RGBA", (24, 24)).save(OUT + "/goodluck_effects_background.png", optimize=True)
