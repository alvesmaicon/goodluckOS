#!/usr/bin/env python3
# Fake mc_*.png for every {path} in goodluck_mcassets/textures.txt: a flat colour with a stripe (grey where the
# game tints it), so the mapping can be checked without Minecraft's files. Output: dev/out/luanti-mc/fakepack
import hashlib, os, re, sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
TABLE = ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods/goodluck_mcassets/textures.txt"
OUT = ROOT + "/dev/out/luanti-mc/fakepack"
FRAMES = {"block/water_still": (16, 32), "block/water_flow": (32, 32), "block/lava_still": (16, 20),
          "block/lava_flow": (32, 16), "block/fire_0": (16, 32)}

os.makedirs(OUT, exist_ok=True)
paths = set()
for line in open(TABLE):
    if not line.startswith("#"):
        paths.update(re.findall(r"\{([^}]+)\}", line))
for p in sorted(paths):
    w, n = FRAMES.get(p, (16, 1))
    tinted = re.search(r"grass|leaves|fern|water|lily|sugar_cane", p)
    c = (170, 170, 170) if tinted else tuple(hashlib.md5(p.encode()).digest()[:3])
    img = Image.new("RGBA", (w, w * n), c + (255,))
    d = ImageDraw.Draw(img)
    for f in range(n):
        y = f * w
        d.rectangle([0, y, w - 1, y + w - 1], outline=tuple(v // 2 for v in c))
        d.line([0, y + (f % w), w - 1, y + (f % w)], fill=(255, 255, 255))
    if p.endswith("_overlay"):
        img.paste((0, 0, 0, 0), (0, 4, w, w))
    img.save(f"{OUT}/mc_{p.replace('/', '_')}.png")
print(len(paths), "fake textures in", os.path.relpath(OUT, ROOT))
