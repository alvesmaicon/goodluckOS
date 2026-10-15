#!/usr/bin/env bash
# F2 bench on the Mac: the console's game files, patches and bench save, run natively on arm64 in the
# goodluck-stardew container (Debian's Mono 6.12 arm64 with the port's class libraries, Mesa llvmpipe on Xvfb at
# 640x480, OpenAL Soft's null output). Update times track the console's CPU; draw times do not (llvmpipe).
#   dev/stardew/macbench.sh setup                       arm64 Mono, OpenAL and lz4 shim into the work volume
#   dev/stardew/macbench.sh run <name> [VAR=x...]       SDV_BENCH run, log in dev/out/stardew/results/mac-<name>.log
#                                                       (through SdvLoader.exe; BENCH_LOADER=StardewValley.exe skips it)
#   dev/stardew/macbench.sh aot                         copy of the runtime, port and game assemblies in the
#                                                       work volume (virtiofs page faults are slow), AOT-compiled; then
#                                                       BENCH_TREE=aot macbench.sh run|perf ... runs from it
#                                                       (AOT_PROFILE=<file>: also the generic instances
#                                                       recorded by a run with MONO_ENV_OPTIONS=--profile=aot:...)
#   dev/stardew/macbench.sh perf <name> [VAR=x...]      the same with Linux perf on the main thread during the
#                                                       measured window: results/mac-<name>.perf.txt (self, inclusive)
# Needs dev/stardew/build.sh and build.sh game first. Nothing else should run on the Mac during a bench.
# A screenshot every 20 s goes to results/mac-<name>.png; a run that hangs gets a thread dump (SIGQUIT) at
# BENCH_TIMEOUT seconds (default 420).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$(dirname "$HERE")")

if [ ! -f /.dockerenv ]; then
    others=$(docker ps -q | wc -l | tr -d ' ')
    caps=(); [ "${1:-}" = perf ] && caps=(--cap-add PERFMON --cap-add SYS_PTRACE)
    exec docker run --rm -i ${caps[@]+"${caps[@]}"} -e PERF_WINDOW="${PERF_WINDOW:-}" -e BENCH_TREE="${BENCH_TREE:-}" -e AOT_PROFILE="${AOT_PROFILE:-}" -e BENCH_REV="$(git -C "$REPO" describe --always --dirty)" -e BENCH_OTHERS="$others" \
        -v "$REPO:/repo" -v goodluck-work:/work goodluck-stardew /repo/dev/stardew/macbench.sh "$@"
fi

W=/work/stardew
M=$W/mac
P=/repo/dev/out/stardew/stardewvalley
G=/repo/dev/out/stardew/gamedata
R=/repo/dev/out/stardew/results
SLOT=ALVESFARM_451629148
SNAP=/repo/dev/out/stardew/saves/alvesfarm-day2.tgz
MONO=6.12.0.199+dfsg-6
AOT=$W/mac-aot
if [ "${BENCH_TREE:-}" = aot ]; then
    M=$AOT P=$AOT/port G=$AOT/game
fi

setup() {
    local d=$W/debs-arm64 r=$W/build/mono-arm64 p
    mkdir -p "$d"
    if ! ls "$d"/mono-runtime-sgen_*.deb >/dev/null 2>&1; then
        apt-get update -qq
        (cd "$d" && apt-get download -qq mono-runtime-sgen:arm64=$MONO mono-runtime-common:arm64=$MONO \
            libmono-profiler:arm64=$MONO 2>&1 | grep -v unsandboxed || true)
    fi
    rm -rf "$r" "$M"
    mkdir -p "$r" "$M/lib"
    for p in "$d"/*.deb; do dpkg-deb -x "$p" "$r"; done
    cp -r "$P/mono" "$M/mono"
    rm "$M"/mono/lib/*.so*
    cp "$r/usr/bin/mono-sgen" "$M/mono/bin/mono"
    cp -a "$r"/usr/lib/libmono-native.so* "$r/usr/lib/libMonoPosixHelper.so" "$r"/usr/lib/libmono-profiler-aot.so* \
        "$M/mono/lib/"
    gcc -O2 -shared -fPIC -Wl,-soname,libgssapi_krb5.so.2 \
        -Wl,--version-script=<(echo 'gssapi_krb5_2_MIT { global: *; };') "$HERE/gssstub.c" -o "$M/mono/lib/libgssapi_krb5.so.2"
    cmake -S "$W/src/openal-soft" -B "$W/build/openal-arm64" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF -DALSOFT_BACKEND_ALSA=OFF \
        -DALSOFT_BACKEND_PIPEWIRE=OFF -DALSOFT_BACKEND_PULSEAUDIO=OFF -DALSOFT_BACKEND_JACK=OFF \
        -DALSOFT_BACKEND_OSS=OFF -DALSOFT_BACKEND_SNDIO=OFF -DALSOFT_BACKEND_PORTAUDIO=OFF \
        -DALSOFT_BACKEND_SDL2=OFF -DALSOFT_BACKEND_SDL3=OFF > "$W/build/openal-arm64.cmake.log"
    ninja -C "$W/build/openal-arm64" > "$W/build/openal-arm64.log"
    cp -L "$W/build/openal-arm64/libopenal.so.1" "$M/lib/"
    gcc -O2 -shared -fPIC -I"$W/src/lz4/lib" "$HERE/lz4shim.c" "$W/src/lz4/lib/lz4.c" -o "$M/lib/liblwjgl_lz4.so"
    "$M/mono/bin/mono" --version | head -1
}

run() {
    local name=$1 log=$R/mac-$1.log saves=$W/machome/.config/StardewValley/Saves start
    shift
    mkdir -p "$R" "$saves"
    rm -rf "${saves:?}/$SLOT"
    tar -xzof "$SNAP" -C "$saves"
    [ -f "$saves/../startup_preferences" ] || printf '<?xml version="1.0" encoding="utf-8"?>\n<StartupPreferences xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n  <languageCode>pt</languageCode>\n</StartupPreferences>\n' > "$saves/../startup_preferences"
    export HOME=$W/machome LD_LIBRARY_PATH=$M/lib:$M/mono/lib MONO_PATH=$P/dlls:$P
    export MONOGAME_PATCH=$P/dlls/StardewPatches.dll ALSOFT_DRIVERS=null SDL_VIDEODRIVER=x11 LP_NUM_THREADS=2
    export SDV_BENCH=$SLOT DISPLAY=:9
    for v in "$@"; do export "${v?}"; done
    Xvfb :9 -screen 0 640x480x24 -nolisten tcp 2>/dev/null &
    sleep 1
    (while sleep 20; do import -window root "$R/mac-$name.png" 2>/dev/null; done) &
    cmp -s "$P/SdvLoader.exe" "$G/SdvLoader.exe" || cp "$P/SdvLoader.exe" "$G/"
    cd "$G"
    : > "$log"
    # PERF_WINDOW=load records from the title to the loaded save instead of the measured minute
    [ -z "${PERF:-}" ] || (
        sleep 5
        from='^bench .* measuring' to=; [ "${PERF_WINDOW:-}" = load ] && from='^bench .*title after' to='loaded after'
        until grep -q "$from" "$log"; do pgrep -x mono > "$PERF.pid" || exit 0; sleep 0.2; done
        if [ -n "$to" ]; then
            perf record -q -e cpu-clock -F 1000 -g -p "$(cat "$PERF.pid")" -o "$PERF.data" &
            until grep -q "$to" "$log"; do sleep 0.2; done
            kill -INT $!; wait $!
        else
            perf record -q -e cpu-clock -F 1000 -g -p "$(cat "$PERF.pid")" -o "$PERF.data" -- sleep "${BENCH_MEASURE:-60}"
        fi
    ) &
    {
        echo "mac $name $(date '+%F %T') rev $BENCH_REV, other containers $BENCH_OTHERS, $*"
        timeout -s QUIT -k 10 "${BENCH_TIMEOUT:-420}" "$M/mono/bin/mono" ${BENCH_LOADER:-SdvLoader.exe} ||
            echo "exit $?"
        echo "ended $(date +%T)"
    } >> "$log" 2>&1
    kill %1 %2
    wait
    cp /tmp/perf-*.map "$R/mac-$name.jitmap" 2>/dev/null || true
    grep -E '^(mac|bench|probe)|exit' "$log" || true
}

# Mono's own sampling profiler puts every sample in sem_post on arm64; perf reads its JIT map (--jitmap). The main
# thread's stacks are saved folded (root;...;leaf count) for dev/stardew/folded.py
perf_run() {
    local out=$R/mac-$1
    PERF=$out MONO_ENV_OPTIONS=--jitmap run "$@"
    perf script -i "$out.data" --tid="$(cat "$out.pid")" -F ip,sym 2>/dev/null | awk '
        function name(s) { sub(/^[ \t]*[0-9a-f]+ ?/, "", s); if (s == "") s = "?"; sub(/^\(wrapper [a-z-]+\) /, "", s); sub(/ \(.*$/, "", s)
            gsub(/;/, ",", s); return s }
        NF == 0 { if (n) { k = f[n]; for (i = n - 1; i > 0; i--) k = k ";" f[i]; c[k]++ } n = 0; next }
        { f[++n] = name($0) }
        END { for (k in c) print k, c[k] }' > "$out.folded"
    rm -f "$out.data" "$out.data.old" "$out.pid"
    echo "$(awk '{s += $NF} END {print s}' "$out.folded") main-thread samples in $out.folded"
}

# AOT images sit next to their assemblies (<name>.so), so the bench gets its own copy of every assembly
aot() {
    local f
    rm -rf "$AOT"
    mkdir -p "$AOT/port" "$AOT/game"
    cp -r "$M/mono" "$M/lib" "$AOT/"
    cp -r "$P/dlls" "$AOT/port/"
    cp "$G"/*.exe "$G"/*.dll "$G"/*.config "$AOT/game/"
    ln -s "$G/Content" "$AOT/game/Content"
    export MONO_PATH=$AOT/port/dlls:$AOT/port:$AOT/game
    # the class libraries load from the GAC, mscorlib from 4.5
    for f in "$AOT"/mono/lib/mono/4.5/mscorlib.dll "$AOT"/mono/lib/mono/gac/*/*/*.dll "$AOT"/port/dlls/*.dll \
            "$AOT"/game/*.dll "$AOT"/game/*.exe; do
        if "$AOT/mono/bin/mono" -O=all --aot${AOT_PROFILE:+=profile=$AOT_PROFILE} "$f" > "$f.aot.log" 2>&1; then
            printf '%-40s %6s KB\n' "$(basename "$f")" "$(( $(stat -c %s "$f.so") / 1024 ))"
        else
            echo "$(basename "$f"): $(tail -1 "$f.aot.log")"
        fi
    done
}

case ${1:-} in
    setup) setup ;;
    run) shift; run "$@" ;;
    perf) shift; perf_run "$@" ;;
    aot) aot ;;
    *) sed -n '2,10p' "$0"; exit 1 ;;
esac
