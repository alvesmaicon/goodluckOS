#!/usr/bin/env python3
# What goodluck_mcassets/textures.txt leaves out: textures the game's nodes, items and entities use (dump.sh's
# dev/out/luanti-mc/dump.json) with no line in the table, per mod, most used first
import collections, json, os, re

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
TABLE = ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods/goodluck_mcassets/textures.txt"
d = json.load(open(ROOT + "/dev/out/luanti-mc/dump.json"))
mapped = {l.split()[0] for l in open(TABLE) if l.strip() and not l.startswith("#")}
owner = {f[9:]: m for m, fs in d["media"].items() for f in fs or [] if f.startswith("textures/")}
png = re.compile(r"[A-Za-z0-9_\-]+\.png")
uses = collections.Counter()
for e in list(d["nodes"].values()) + list(d["items"].values()):
    for s in (e.get("tiles") or []) + (e.get("overlay") or []) + (e.get("special") or []) + [e.get("inv") or "", e.get("wield") or ""]:
        uses.update(set(png.findall(s)))
for e in d["entities"].values():
    for s in (e.get("textures") or []) + (e.get("mob_textures") or []):
        uses.update(set(png.findall(s)))
total = sum(uses.values())
done = sum(n for t, n in uses.items() if t in mapped)
print(f"{len([t for t in uses if t in mapped])}/{len(uses)} textures mapped, {100 * done // total}% of uses")
left = collections.defaultdict(list)
for t, n in uses.most_common():
    if t not in mapped:
        left[owner.get(t, "?")].append(f"{t[:-4]}({n})" if n > 1 else t[:-4])
for m, ts in sorted(left.items(), key=lambda x: -len(x[1])):
    print(f"{m} {len(ts)}: " + " ".join(ts))
