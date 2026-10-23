#!/usr/bin/env python3
# Dev only: the files goodluck_mcassets/textures.txt names, taken from your own client jar into
# dev/out/luanti-mc/devpack (gitignored). Never commit or share the result.
#   python3 dev/luanti-mc/devpack.py ~/Library/Application\ Support/minecraft/versions/26.3/26.3.jar
import os, re, sys, zipfile

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
TABLE = ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods/goodluck_mcassets/textures.txt"
OUT = ROOT + "/dev/out/luanti-mc/devpack"

os.makedirs(OUT, exist_ok=True)
paths = {p for l in open(TABLE) if not l.startswith("#") for p in re.findall(r"\{([^}]+)\}", l)}
with zipfile.ZipFile(sys.argv[1]) as jar:
    for p in sorted(paths):
        with open(f"{OUT}/mc_{p.replace('/', '_')}.png", "wb") as f:
            f.write(jar.read(f"assets/minecraft/textures/{p}.png"))
print(len(paths), "files in", os.path.relpath(OUT, ROOT))
