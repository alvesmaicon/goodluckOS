#!/usr/bin/env bash
# Ocarina of Time (Ship of Harkinian) and Majora's Mask (2 Ship 2 Harkinian) for HOME/ports, without the games.
#   dev/zelda/build.sh [oot|mm] assets    the port's o2r, and the game's from the rom in dev/out/zelda/roms/<oot|mm>
#   dev/zelda/build.sh [oot|mm] game      the armhf binary, with the GLES2 renderer (patches/lus)
#   dev/zelda/build.sh [oot|mm] libs      the libraries it needs that the console's rootfs lacks, into libs/
#   dev/zelda/build.sh [oot|mm] pack      launcher, assets/ and icon (dev/zelda/cover.py) into the folder, and <port>.tar for HOME/ports
#   dev/zelda/build.sh [oot|mm] native    the same game for this machine (64-bit), in dev/out/zelda/native/<port>
#   dev/zelda/build.sh [oot|mm] shot [s]  the binary under qemu-arm on Xvfb (llvmpipe, GLES2), screenshots in dev/out/zelda/shots/<port>
#   dev/zelda/build.sh [oot|mm]           assets, game, libs and pack
# oot is the default; its port is soh, mm's is 2ship. Output in dev/out/zelda/<port>.
# Runs in the goodluck-zelda image (dev/zelda/Dockerfile, on top of goodluck-dev).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$(dirname "$HERE")")
IMAGE=goodluck-zelda

if [ ! -f /.dockerenv ]; then
    docker image inspect $IMAGE >/dev/null 2>&1 || docker build -t $IMAGE "$HERE"
    exec docker run --rm -i -v "$REPO:/repo" -v goodluck-work:/work -e GL_JOBS -e ZELDA_ELF -e SHOTS -e ZELDA_GLES2 -e LUS_TEXLOG $IMAGE /repo/dev/zelda/build.sh "$@"
fi

GAME=oot
case "${1:-}" in oot | mm) GAME=$1; shift ;; esac

W=/work/zelda
case $GAME in
    oot) PORT=soh URL=https://github.com/HarbourMasters/Shipwright.git TAG=9.3.0 REV=ecd889c2
        SRC=$W/src/Shipwright BLD=$W/build TARGET=soh ELF=soh/soh.elf DEPS= ;;
    mm) PORT=2ship URL=https://github.com/HarbourMasters/2ship2harkinian.git TAG=5.0.1 REV=8a24047f
        SRC=$W/src/2ship2harkinian BLD=$W/build-mm TARGET=2ship ELF=mm/2s2h.elf
        DEPS=-DCMAKE_PROJECT_2s2h_INCLUDE=$HERE/2ship-deps.cmake ;;
esac
OUT=/repo/dev/out/zelda/$PORT
ROMS=/repo/dev/out/zelda/roms/$GAME
TARGET_LIBS=/work/br/out/target
ARMFLAGS="-march=armv7-a -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard"
JOBS=${GL_JOBS:-$(nproc)}
COMMON=$W/build # toolchain file and libzip, shared by both games
PREFIX=$COMMON/armhf-prefix
LIBZIP=1.12.1
LIBZIP_SHA=3b66fe92cbc768d8d4d16e1427bfb7399e15d9c2795c2fc482e7b30a6332a422

source_tree() {
    mkdir -p "$W/src" "$BLD" "$OUT"
    [ -d "$SRC" ] || git clone -q --depth 1 --branch $TAG "$URL" "$SRC"
    [ "$(git -C "$SRC" rev-parse --short=8 HEAD)" = $REV ] || { echo "$PORT is not at $REV" >&2; exit 1; }
    git -C "$SRC" submodule update --init --depth 1 -q
    apply_patches "$SRC" "$HERE"/patches/$PORT/*.patch
    apply_patches "$SRC/libultraship" "$HERE"/patches/lus/*.patch
}

# Patches $2... onto the tree $1; when one changed since it was applied, start again from a clean tree
apply_patches() {
    local tree=$1 p; shift
    for p in "$@"; do
        git -C "$tree" apply --reverse --check "$p" 2>/dev/null && continue
        git -C "$tree" apply --check "$p" 2>/dev/null || { git -C "$tree" checkout -q -- .; apply_patches "$tree" "$@"; return; }
        git -C "$tree" apply "$p"
    done
}

toolchain() {
    cat > "$COMMON/armhf.cmake" <<'EOF'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_C_COMPILER arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER arm-linux-gnueabihf-g++)
set(CMAKE_LIBRARY_ARCHITECTURE arm-linux-gnueabihf)
set(ENV{PKG_CONFIG_LIBDIR} /usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/share/pkgconfig)
EOF
}

configure_native() {
    cmake -S "$SRC" -B "$BLD/native" -G Ninja -DCMAKE_BUILD_TYPE=Release -DUSE_OPENGLES=ON -DUSE_GLES2=ON $DEPS
}

assets() {
    case $GAME in
        oot)
            cmake -S "$SRC" -B "$BLD/tools" -G Ninja -DCMAKE_BUILD_TYPE=Release -DSOH_TOOLS_ONLY=ON -DSOH_ROM_PATH="$ROMS"
            cmake --build "$BLD/tools" -j "$JOBS" --target GenerateSohOtr
            cp "$BLD/tools/soh/soh.o2r" "$OUT/"
            if ls "$ROMS"/*.z64 >/dev/null 2>&1; then
                cmake --build "$BLD/tools" -j "$JOBS" --target ExtractAssets
                cp "$BLD/tools/soh/"oot*.o2r "$OUT/"
            else
                echo "no rom in $ROMS: only soh.o2r" >&2
            fi
            ;;
        mm)
            # ZAPD from the native tree; the extractor runs in mm/ like the ExtractAssets target, with the rom given
            local rom mode=--norom
            rom=$(ls "$ROMS"/*.z64 2>/dev/null | head -1) || true
            [ -n "$rom" ] && mode="--non-interactive --xml-root ../mm/assets/xml" || echo "no rom in $ROMS: only 2ship.o2r" >&2
            configure_native
            cmake --build "$BLD/native" -j "$JOBS" --target ZAPD
            # 2Ship keeps its own copy of libultraship's shaders (SoH copies them at build time): use the patched ones
            cp -r "$SRC/libultraship/src/fast/shaders/." "$SRC/mm/assets/custom/shaders/"
            (cd "$SRC/mm" && rm -f mm.o2r 2ship.o2r &&
                python3 ../OTRExporter/extract_assets.py -z "$BLD/native/ZAPD/ZAPD.out" $mode --custom-otr-file 2ship.o2r \
                    --custom-assets-path "$SRC/mm/assets/custom" --port-ver $TAG ${rom:+"$rom"})
            cp "$SRC/mm/2ship.o2r" "$OUT/"
            [ -z "$rom" ] || cp "$SRC/mm/mm.o2r" "$OUT/"
            ;;
    esac
    ls -l "$OUT"/*.o2r
}

# libultraship wants a system libzip; the console has none, and Debian's pulls in GnuTLS. Static, zlib only.
build_libzip() {
    local t=$W/src/libzip-$LIBZIP.tar.gz
    [ -f "$PREFIX/lib/libzip.a" ] && return
    echo "$LIBZIP_SHA  $t" | sha256sum -c --status 2>/dev/null ||
        curl -fsSL -o "$t" https://github.com/nih-at/libzip/releases/download/v$LIBZIP/libzip-$LIBZIP.tar.gz
    echo "$LIBZIP_SHA  $t" | sha256sum -c --quiet
    rm -rf "$COMMON/libzip-src"; mkdir -p "$COMMON/libzip-src"
    tar -xzf "$t" -C "$COMMON/libzip-src" --strip-components=1
    cmake -S "$COMMON/libzip-src" -B "$COMMON/libzip" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$COMMON/armhf.cmake" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$ARMFLAGS" -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DBUILD_SHARED_LIBS=OFF -DENABLE_COMMONCRYPTO=OFF -DENABLE_GNUTLS=OFF -DENABLE_MBEDTLS=OFF \
        -DENABLE_OPENSSL=OFF -DENABLE_WINDOWS_CRYPTO=OFF -DENABLE_BZIP2=OFF -DENABLE_LZMA=OFF -DENABLE_ZSTD=OFF \
        -DBUILD_TOOLS=OFF -DBUILD_REGRESS=OFF -DBUILD_OSSFUZZ=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF
    cmake --build "$COMMON/libzip" -j "$JOBS" --target install
}

game() {
    mkdir -p "$COMMON"
    toolchain
    build_libzip
    cmake -S "$SRC" -B "$BLD/armhf" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$COMMON/armhf.cmake" -DCMAKE_PREFIX_PATH="$PREFIX" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$ARMFLAGS" -DCMAKE_CXX_FLAGS="$ARMFLAGS" -DUSE_OPENGLES=ON -DUSE_GLES2=${ZELDA_GLES2:-ON} $DEPS
    cmake --build "$BLD/armhf" -j "$JOBS" --target $TARGET -- -k 0
    cp "$BLD/armhf/$ELF" "$OUT/"
    arm-linux-gnueabihf-strip "$OUT/$(basename $ELF)"
}

# Both ports refuse to start without an assets/ folder beside the binary, even with their o2r ready; the full
# one (the extractor's xml) only matters for extracting on the console. SoH also reads its config.yml.
port_assets() {
    mkdir -p "$1/assets"
    [ $GAME = mm ] || cp "$SRC/soh/assets/yml/config.yml" "$1/assets/"
}

# The same game for the build machine (64-bit, its own GL), to tell 32-bit bugs from renderer ones
native() {
    local dir=/repo/dev/out/zelda/native/$PORT
    configure_native
    cmake --build "$BLD/native" -j "$JOBS" --target $TARGET -- -k 0
    mkdir -p "$dir"
    cp "$BLD/native/$ELF" "$dir/"
    port_assets "$dir"
}

# Copy each NEEDED library (and its own NEEDED, recursively) that the rootfs doesn't ship
libs() {
    local queue=("$OUT/$(basename $ELF)") seen=" " f lib path
    rm -rf "$OUT/libs"; mkdir -p "$OUT/libs"
    while [ ${#queue[@]} -gt 0 ]; do
        f=${queue[0]}; queue=("${queue[@]:1}")
        for lib in $(arm-linux-gnueabihf-readelf -d "$f" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
            case "$seen" in *" $lib "*) continue ;; esac
            seen="$seen$lib "
            [ -e "$TARGET_LIBS/usr/lib/$lib" ] || [ -e "$TARGET_LIBS/lib/$lib" ] && continue
            path=$(find /usr/lib/arm-linux-gnueabihf /lib/arm-linux-gnueabihf -name "$lib" 2>/dev/null | head -1)
            [ -n "$path" ] || { echo "missing on both sides: $lib" >&2; continue; }
            cp -L "$path" "$OUT/libs/"
            queue+=("$path")
        done
    done
    ls -l "$OUT/libs"
}

# The port folder as one tar for HOME/ports
pack() {
    cp "$HERE/$PORT.sh" "$OUT/"
    cp "$HERE/$PORT-defaults.json" "$OUT/defaults.json"
    port_assets "$OUT"
    # The launcher icon from cover.py, which runs on the host (the games' own art, so it isn't in git)
    [ ! -f /repo/dev/out/zelda/covers/$PORT.png ] || cp /repo/dev/out/zelda/covers/$PORT.png "$OUT/icon.png"
    tar -cf /repo/dev/out/zelda/$PORT.tar -C "$(dirname "$OUT")" $PORT
    ls -l /repo/dev/out/zelda/$PORT.tar
}

# The binary under qemu-arm on Xvfb, GLES2 on Mesa's llvmpipe: a screenshot every 30 s for $1 seconds
# (ZELDA_ELF picks another binary, a 64-bit one runs without qemu; SHOTS another folder)
shot() {
    local secs=${1:-300} run=/tmp/$PORT-run shots=${SHOTS:-/repo/dev/out/zelda/shots/$PORT} elf=${ZELDA_ELF:-$OUT/$(basename $ELF)} t xvfb game
    rm -rf "$run" "$shots"; mkdir -p "$run" "$shots"
    cp "$OUT"/*.o2r "$elf" "$run/"
    port_assets "$run"
    Xvfb :9 -screen 0 1280x960x24 -nolisten tcp & xvfb=$!
    sleep 1
    local qemu=qemu-arm
    [ "$(od -An -tx1 -j4 -N1 "$elf" | tr -d ' ')" = 02 ] && qemu=""
    (cd "$run" && SHIP_HOME=$run DISPLAY=:9 SDL_AUDIODRIVER=dummy QEMU_LD_PREFIX=/ \
        exec $qemu "$run/$(basename "$elf")" > "$shots/$PORT.log" 2>&1) & game=$!
    for ((t = 30; t <= secs; t += 30)); do
        sleep 30
        kill -0 $game 2>/dev/null || { echo "$PORT exited before ${t}s"; break; }
        DISPLAY=:9 import -window root "$shots/t$t.png"
    done
    kill -9 $game 2>/dev/null || true
    kill $xvfb
    ls "$shots"
}

source_tree
case "${1:-all}" in
    assets) assets ;;
    game) game ;;
    libs) libs ;;
    pack) pack ;;
    native) native ;;
    shot) shot "${2:-}" ;;
    all) assets; game; libs; pack ;;
    *) echo "usage: $0 [oot|mm] [assets|game|libs|pack|native|shot [seconds]]" >&2; exit 1 ;;
esac
