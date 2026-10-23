#!/bin/bash
# Inventory of what the Luanti game registers (nodes, items, entities, crafts, media) in dev/out/luanti-mc/dump.json.
# Runs the native Luanti of dev/out/luanti-native (volume luanti-native) as a server, no window:
#   docker run --rm -v goodluck-work:/work:ro -v luanti-native:/build:ro -v "$PWD":/repo luanti-native \
#       bash /repo/dev/luanti-mc/dump.sh
set -euo pipefail
G=/tmp/games/mcdump_game; W=/tmp/world; OUT=/repo/dev/out/luanti-mc
mkdir -p "$G" "$W" "$OUT"
cp -a /work/br/out/target/usr/share/luanti/games/minetest_game/. "$G"
cp -a /repo/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/. "$G"
cp -a /repo/dev/luanti-mc/dump "$G/mods/goodluck_dump"
printf 'gameid = mcdump\nbackend = sqlite3\n' > "$W/world.mt"
cd /tmp && MINETEST_GAME_PATH=/tmp/games LUANTI_GAME_PATH=/tmp/games timeout 120 \
    /build/src/bin/luanti --server --world "$W" --gameid mcdump --port 30099 --logfile "$OUT/dump.log" >/dev/null 2>&1 || true
cp "$W/dump.json" "$OUT/dump.json"
grep -E "ERROR|WARNING|goodluck_dump" "$OUT/dump.log" | head -20
ls -la "$OUT/dump.json"
