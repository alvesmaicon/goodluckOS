#!/usr/bin/env python3
# The End's creatures, blocks and items when the player has no Minecraft of their own: Pixel Perfection Legacy by Nova
# Wostra (CC BY-SA 4.0, https://modrinth.com/resourcepack/pixel-perfection-legacy, 26.3-97.2 unzipped), in 26.x's
# layouts, copied under goodluck_end's names; the end portal's surface is its star field cut to 16x16 frames
#   python3 dev/luanti-art/end.py <pixel perfection legacy dir> [out dir]
import os, shutil, sys
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
print(len(FILES) + 1, "textures in", os.path.relpath(OUT, ROOT))
