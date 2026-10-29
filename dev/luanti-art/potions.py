#!/usr/bin/env python3
# The potions' and their ingredients' textures when the player has no Minecraft of their own: Pixel Perfection Legacy
# by Nova Wostra (CC BY-SA 4.0, 26.3-97.2 unzipped) for the items, and for the brewing stand, which it lacks, Pixel
# Perfection's as Mineclonia 0.124.0 carries them (mcl_brewing; its LEGAL.md), put together in Minecraft's own layout
# (its block model takes the arms from the halves of one texture, the rod from its middle); the brewing window's arrow
# and fuel bar are goodluckOS's own
#   python3 dev/luanti-art/potions.py <pixel perfection legacy dir> <mineclonia checkout> [mods dir]
import os, shutil, sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
PP = sys.argv[1] + "/assets/minecraft/textures/"
MCL = sys.argv[2] + "/mods/ITEMS/"
MODS = sys.argv[3] if len(sys.argv) > 3 else \
    ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods"
COPY = {
    "goodluck_potions/textures/goodluck_potions_potion": PP + "item/potion",
    "goodluck_potions/textures/goodluck_potions_overlay": PP + "item/potion_overlay",
    "goodluck_potions/textures/goodluck_potions_splash": PP + "item/splash_potion",
    "goodluck_potions/textures/goodluck_potions_fermented_spider_eye": PP + "item/fermented_spider_eye",
    "goodluck_potions/textures/goodluck_potions_glistering_melon_slice": PP + "item/glistering_melon_slice",
    "goodluck_potions/textures/goodluck_potions_rabbit_foot": PP + "item/rabbit_foot",
    "goodluck_monsters/textures/goodluck_monsters_spider_eye": PP + "item/spider_eye",
    "goodluck_food/textures/goodluck_food_pufferfish": PP + "item/pufferfish",
    "goodluck_potions/textures/goodluck_potions_brewing_stand_item": MCL + "mcl_brewing/textures/mcl_brewing_stand_inv",
    "goodluck_potions/textures/goodluck_potions_bubbles": MCL + "mcl_brewing/textures/mcl_brewing_bubbles_active",
    "goodluck_potions/textures/goodluck_potions_slot_bottle": MCL + "mcl_brewing/textures/mcl_brewing_bottle_bg",
    "goodluck_potions/textures/goodluck_potions_slot_fuel": MCL + "mcl_brewing/textures/mcl_brewing_fuel_bg",
}
for out, src in COPY.items():
    os.makedirs(os.path.dirname(f"{MODS}/{out}"), exist_ok=True)
    shutil.copyfile(src + ".png", f"{MODS}/{out}.png")


def load(name):
    return Image.open(MCL + "mcl_brewing/textures/" + name + ".png").convert("RGBA")


TEX = MODS + "/goodluck_potions/textures/goodluck_potions_"
# the arms: with a bottle on the left half, empty (mirrored) on the right; the rod in columns 7 and 8 from row 2
# (Mineclonia's in its columns 5 and 6, its base's stone in 7 to 12 below the burner's glow)
stand, rack, bottle = load("mcl_brewing_stand"), load("mcl_brewing_rack"), load("mcl_brewing_rack_bottle")
out = Image.new("RGBA", (16, 16))
for y in range(16):
    for x in range(8):
        out.putpixel((x, y), bottle.getpixel((x, y)))
        out.putpixel((15 - x, y), rack.getpixel((x, y)))
for y in range(14):
    for x in range(2):
        out.putpixel((7 + x, 2 + y), stand.getpixel((5 + x, y)))
out.save(TEX + "brewing_stand.png")
# the base: its stone over the whole of it (the plates and their edges take their own parts)
base = Image.new("RGBA", (16, 16))
for y in range(16):
    for x in range(16):
        base.putpixel((x, y), stand.getpixel((7 + x % 6, 4 + y % 8)))
base.save(TEX + "brewing_stand_base.png")

# the brew's arrow, filled from the top as it goes, and the fuel bar
arrow = Image.new("RGBA", (9, 28))
d = ImageDraw.Draw(arrow)
d.rectangle((3, 0, 5, 21), fill=(255, 255, 255, 255))
d.polygon([(0, 21), (8, 21), (4, 27)], fill=(255, 255, 255, 255))
arrow.save(TEX + "progress.png")
fuel = Image.new("RGBA", (18, 4))
for x in range(18):
    for y in range(4):
        fuel.putpixel((x, y), (255, 160 - y * 18, 0, 255) if 0 < y < 3 else (166, 84, 0, 255))
fuel.save(TEX + "fuel.png")
print(len(COPY) + 4, "textures in", os.path.relpath(MODS, ROOT))
