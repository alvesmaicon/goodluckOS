#!/bin/bash
# Screenshots of every node (floor, wall) and item image, with goodluck_mcassets reading the pack in dev/out/luanti-mc/<pack>:
#   docker run --rm -v goodluck-work:/work:ro -v luanti-native:/build:ro -v "$PWD":/repo luanti-native \
#       bash /repo/dev/luanti-mc/shot.sh <pack>       (no pack: the game as it ships)
# WORLD=<seed>: a normal world instead, looking around where the player spawns; FIRST=<pattern>: those first;
# EXTRA=<mod dir>: one more mod (a scene of its own); MARKS="a b": a screenshot at each "scene: a" it logs
set -euo pipefail
L=/tmp/l; G=$L/games/mcdump_game; OUT=/repo/dev/out/luanti-mc; NAME=${1:-none}
mkdir -p "$L" "$G" "$OUT" "$L/textures/server" "$L/worlds/show"
for d in bin builtin client fonts textures locale; do [ -e /build/src/$d ] && cp -a /build/src/$d "$L/"; done
cp -a /work/br/out/target/usr/share/luanti/games/minetest_game/. "$G"
cp -a /repo/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/. "$G"
[ -z "${WORLD:-}" ] && cp -a /repo/dev/luanti-mc/showcase "$G/mods/goodluck_showcase"
[ -n "${EXTRA:-}" ] && cp -a "$EXTRA" "$G/mods/"
[ "$NAME" != none ] && cp -a "$OUT/$NAME"/. "$L/textures/server/"
cp /repo/rootfs/board/my-device/rootfs-overlay/usr/share/goodluck/defaults/luanti.conf "$L/minetest.conf"
printf 'fullscreen = false\nviewing_range = 60\ngoodluck_mc_assets = %s\n' \
    "$([ "$NAME" != none ] && echo true || echo false)" >> "$L/minetest.conf"
if [ -n "${WORLD:-}" ]; then printf 'fixed_map_seed = %s\n' "$WORLD" >> "$L/minetest.conf"
else printf 'mg_name = singlenode\nenable_fog = false\nshowcase_first = %s\n' "${FIRST:-}" >> "$L/minetest.conf"; fi
printf 'gameid = mcdump\nbackend = sqlite3\n' > "$L/worlds/show/world.mt"
Xvfb :99 -screen 0 640x480x24 -nolisten tcp >/dev/null 2>&1 & X=$!
sleep 1
(cd "$L" && DISPLAY=:99 SDL_VIDEODRIVER=x11 MESA_GLES_VERSION_OVERRIDE=2.0 LIBGL_ALWAYS_SOFTWARE=1 \
    ./bin/luanti --go --world "$L/worlds/show" --name dev > "$OUT/shot-$NAME.log" 2>&1) & P=$!
if [ -n "${MARKS:-}" ]; then
    for v in $MARKS; do
        for _ in $(seq 120); do grep -q "scene: $v" "$OUT/shot-$NAME.log" && break; sleep 1; done
        DISPLAY=:99 xwd -root -silent | convert xwd:- "$OUT/shot-$NAME-$v.png"; echo "dev/out/luanti-mc/shot-$NAME-$v.png"
    done
    grep "scene:" "$OUT/shot-$NAME.log" | sed 's/.*scene:/scene:/'
elif [ -n "${WORLD:-}" ]; then
    for v in 1 2 3; do
        sleep 25
        DISPLAY=:99 xwd -root -silent | convert xwd:- "$OUT/shot-$NAME-world$v.png"; echo "dev/out/luanti-mc/shot-$NAME-world$v.png"
        DISPLAY=:99 xdotool mousemove_relative -- 200 0
    done
else
    for v in floor wall items close; do
        for _ in $(seq 120); do grep -q "showcase: $v" "$OUT/shot-$NAME.log" && break; sleep 1; done
        DISPLAY=:99 xwd -root -silent | convert xwd:- "$OUT/shot-$NAME-$v.png"; echo "dev/out/luanti-mc/shot-$NAME-$v.png"
    done
fi
kill $P $X 2>/dev/null || true
grep -E "ERROR|WARNING" "$OUT/shot-$NAME.log" | grep -v "backend" | head -20 || true
