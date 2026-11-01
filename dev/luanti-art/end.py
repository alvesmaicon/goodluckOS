#!/usr/bin/env python3
# The End's creatures, blocks and items when the player has no Minecraft of their own: Pixel Perfection Legacy by Nova
# Wostra (CC BY-SA 4.0, https://modrinth.com/resourcepack/pixel-perfection-legacy, 26.3-97.2 unzipped), in 26.x's
# layouts, copied under goodluck_end's names; the end portal's surface is its star field cut to 16x16 frames, and
# the crystal's beam (which Pixel Perfection lacks) white specks of our own
#   python3 dev/luanti-art/end.py <pixel perfection legacy dir> [out dir]
import os, random, shutil, sys
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
SRC = sys.argv[1] + "/assets/minecraft/textures/"
OUT = sys.argv[2] if len(sys.argv) > 2 else \
    ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods/goodluck_end/textures"
FILES = {
    "entity/enderman/enderman": "enderman", "entity/enderman/enderman_eyes": "enderman_eyes",
    "entity/silverfish/silverfish": "silverfish", "entity/enderdragon/dragon": "dragon",
    "entity/enderdragon/dragon_eyes": "dragon_eyes", "entity/enderdragon/dragon_fireball": "dragon_fireball",
    "entity/end_crystal/end_crystal": "end_crystal", "entity/end_portal/end_portal": "end_portal_stars",
    "environment/end_sky": "sky",
    "item/ender_pearl": "ender_pearl", "item/ender_eye": "ender_eye", "item/end_crystal": "end_crystal_item",
    "item/enderman_spawn_egg": "enderman_egg", "item/silverfish_spawn_egg": "silverfish_egg",
    "item/ender_dragon_spawn_egg": "dragon_egg_item",
    "block/end_stone": "end_stone", "block/end_stone_bricks": "end_stone_bricks", "block/dragon_egg": "dragon_egg",
    "block/end_portal_frame_top": "frame_top", "block/end_portal_frame_side": "frame_side",
    "block/end_portal_frame_bottom": "frame_bottom", "block/end_portal_frame_eye": "frame_eye",
    "block/mossy_stone_bricks": "stonebrick_mossy", "block/cracked_stone_bricks": "stonebrick_cracked",
    "block/chiseled_stone_bricks": "stonebrick_chiseled", "block/iron_bars": "iron_bars",
    "block/purpur_block": "purpur_block", "block/purpur_pillar_side": "purpur_pillar_side",
    "block/purpur_pillar_top": "purpur_pillar_top", "block/end_rod": "end_rod", "block/chorus_plant": "chorus_plant",
    "block/chorus_flower": "chorus_flower", "block/chorus_flower_dead": "chorus_flower_dead",
    "item/chorus_fruit": "chorus_fruit", "item/popped_chorus_fruit": "chorus_fruit_popped",
    "entity/endermite/endermite": "endermite",
    "item/endermite_spawn_egg": "endermite_egg",
}

os.makedirs(OUT, exist_ok=True)
for path, name in FILES.items():
    shutil.copyfile(SRC + path + ".png", f"{OUT}/goodluck_end_{name}.png")
# the portal: Minecraft draws its stars with a shader, layers of them in teal and violet drifting over the black;
# here three such layers, each a 32x32 window of the star field shrunk to 16 and sliding at its own speed, in 64
# frames that loop
stars = Image.open(SRC + "entity/end_portal/end_portal.png").convert("RGB")
W = stars.width
LAYERS = [((40, 200, 190), 4), ((60, 140, 230), 8), ((140, 90, 210), 12)]
tall = Image.new("RGB", (W, 2 * W))
tall.paste(stars, (0, 0))
tall.paste(stars, (0, W))
frames = Image.new("RGB", (16, 16 * 64))
for i in range(64):
    tile = [(4, 10, 14)] * 256
    for k, (tint, speed) in enumerate(LAYERS):
        y0 = i * speed % W
        small = tall.crop((k * 64, y0, k * 64 + 32, y0 + 32)).resize((16, 16), Image.NEAREST).getdata()
        tile = [tuple(min(255, c + s[0] * t // 255) for c, t in zip(px, tint)) for px, s in zip(tile, small)]
    img = Image.new("RGB", (16, 16))
    img.putdata(tile)
    frames.paste(img, (0, i * 16))
frames.save(f"{OUT}/goodluck_end_portal.png")
# the beam: a third of its pixels white or nearly, the rest clear, 32 rows as Minecraft's beam shows on 4 nodes
rng = random.Random(1029)
beam = Image.new("RGBA", (16, 32), (255, 255, 255, 0))
for y in range(32):
    for x in range(16):
        if rng.random() < 0.3:
            g = rng.randint(220, 255)
            beam.putpixel((x, y), (g, g, g, 255))
beam.save(f"{OUT}/goodluck_end_crystal_beam.png")


# the ender chest: Pixel Perfection draws it for Minecraft's model before 1.15, which stood upside down; turned to the
# layout since, as pixelperfection.py turns the chest
def faces(u, v, w, h, d):
    return [(u + d, v, w, d), (u + d + w, v, w, d), (u, v + d, d, h), (u + d, v + d, w, h), (u + d + w, v + d, d, h),
            (u + d + w + d, v + d, w, h)]


old = Image.open(SRC + "entity/chest/ender.png").convert("RGBA")
chest = Image.new("RGBA", old.size)
for box in ((0, 0, 14, 5, 14), (0, 19, 14, 10, 14), (0, 0, 2, 4, 1)):
    crop = [old.crop((x, y, x + cw, y + ch)) for x, y, cw, ch in faces(*box)]
    top, bottom = (c.transpose(Image.FLIP_LEFT_RIGHT) for c in crop[:2])
    west, north, east, south = (c.rotate(180) for c in crop[2:])
    for img, (x, y, _, _) in zip([bottom, top, west, south, east, north], faces(*box)):
        chest.paste(img, (x, y))
chest.save(f"{OUT}/goodluck_end_ender_chest.png")
# the End cities: the shulker in its colours (this game's 15 dyes), its spark, shell and egg, the item frame, the
# magenta glass, a firework's spark for the end rod's glitter (which Pixel Perfection lacks); the dragon head as worn
# (its upper head's faces where a 128x64 skin has its hat, the rest masked off by goodluck_end_hat_mask.png, which the
# Minecraft textures' line uses too); the Levitation icon for goodluck_effects
CITY = {"entity/shulker/shulker": "shulker", "entity/shulker/spark": "shulker_spark",
        "item/shulker_shell": "shulker_shell", "item/shulker_spawn_egg": "shulker_egg",
        "block/item_frame": "item_frame", "item/item_frame": "item_frame_item",
        "block/magenta_stained_glass": "magenta_stained_glass", "particle/spark_1": "glitter"}
for colour in ("white", "light_gray", "gray", "black", "purple", "blue", "cyan", "green", "lime", "yellow", "brown",
               "orange", "red", "magenta", "pink"):
    CITY["entity/shulker/shulker_" + colour] = "shulker_" + colour
for path, name in CITY.items():
    shutil.copyfile(SRC + path + ".png", f"{OUT}/goodluck_end_{name}.png")
mask = Image.new("L", (128, 64), 0)
mask.paste(255, (64, 0, 128, 32))
mask.save(f"{OUT}/goodluck_end_hat_mask.png")
worn = Image.new("RGBA", (128, 64))
worn.paste(Image.open(SRC + "entity/enderdragon/dragon.png").convert("RGBA").crop((48, 30, 176, 94)), (0, 0))
worn.putalpha(Image.composite(worn.getchannel("A"), mask, mask))
worn.save(f"{OUT}/goodluck_end_dragon_head_worn.png")
shutil.copyfile(SRC + "mob_effect/levitation.png",
                f"{OUT}/../../goodluck_effects/textures/goodluck_effects_levitation.png")
print(len(FILES) + len(CITY) + 6, "textures in", os.path.relpath(OUT, ROOT))
