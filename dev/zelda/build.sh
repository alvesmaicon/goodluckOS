#!/usr/bin/env bash
# Ship of Harkinian (Ocarina of Time) for HOME/ports/soh, without the game.
#   dev/zelda/build.sh assets   soh.o2r, and oot.o2r from the roms in dev/out/zelda/roms (native asset tools)
#   dev/zelda/build.sh soh      soh.elf for armhf, with the GLES2 renderer (patches/lus)
#   dev/zelda/build.sh libs     the libraries soh.elf needs that the console's rootfs lacks, into libs/
#   dev/zelda/build.sh pack     launcher + assets/ into the folder, and dev/out/zelda/soh.tar for HOME/ports
#   dev/zelda/build.sh shot [s] soh.elf under qemu-arm on Xvfb (llvmpipe, GLES2), screenshots in dev/out/zelda/shots
#   dev/zelda/build.sh          assets, soh, libs and pack
# Output in dev/out/zelda/soh. Runs in the goodluck-zelda image (dev/zelda/Dockerfile, on top of goodluck-dev).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$(dirname "$HERE")")
IMAGE=goodluck-zelda

if [ ! -f /.dockerenv ]; then
    docker image inspect $IMAGE >/dev/null 2>&1 || docker build -t $IMAGE "$HERE"
    exec docker run --rm -i -v "$REPO:/repo" -v goodluck-work:/work -e GL_JOBS -e SOH_ELF -e SHOTS -e SOH_GLES2 $IMAGE /repo/dev/zelda/build.sh "$@"
fi

W=/work/zelda
SRC=$W/src/Shipwright
BLD=$W/build
OUT=/repo/dev/out/zelda/soh
ROMS=/repo/dev/out/zelda/roms
TARGET_LIBS=/work/br/out/target
SOH_TAG=9.3.0
SOH_REV=ecd889c2
ARMFLAGS="-march=armv7-a -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard"
JOBS=${GL_JOBS:-$(nproc)}
PREFIX=$BLD/armhf-prefix
LIBZIP=1.12.1
LIBZIP_SHA=3b66fe92cbc768d8d4d16e1427bfb7399e15d9c2795c2fc482e7b30a6332a422

source_tree() {
    mkdir -p "$W/src" "$BLD" "$OUT"
    [ -d "$SRC" ] || git clone -q --depth 1 --branch $SOH_TAG https://github.com/HarbourMasters/Shipwright.git "$SRC"
    [ "$(git -C "$SRC" rev-parse --short=8 HEAD)" = $SOH_REV ] || { echo "SoH is not at $SOH_REV" >&2; exit 1; }
    git -C "$SRC" submodule update --init --depth 1 -q
    apply_patches "$SRC" "$HERE"/patches/soh/*.patch
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
    cat > "$BLD/armhf.cmake" <<'EOF'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_C_COMPILER arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER arm-linux-gnueabihf-g++)
set(CMAKE_LIBRARY_ARCHITECTURE arm-linux-gnueabihf)
set(ENV{PKG_CONFIG_LIBDIR} /usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/share/pkgconfig)
EOF
}

assets() {
    cmake -S "$SRC" -B "$BLD/tools" -G Ninja -DCMAKE_BUILD_TYPE=Release -DSOH_TOOLS_ONLY=ON -DSOH_ROM_PATH="$ROMS"
    cmake --build "$BLD/tools" -j "$JOBS" --target GenerateSohOtr
    cp "$BLD/tools/soh/soh.o2r" "$OUT/"
    if ls "$ROMS"/*.z64 >/dev/null 2>&1; then
        cmake --build "$BLD/tools" -j "$JOBS" --target ExtractAssets
        cp "$BLD/tools/soh/"oot*.o2r "$OUT/"
    else
        echo "no rom in dev/out/zelda/roms: only soh.o2r" >&2
    fi
}

# libultraship wants a system libzip; the console has none, and Debian's pulls in GnuTLS. Static, zlib only.
build_libzip() {
    local t=$W/src/libzip-$LIBZIP.tar.gz
    [ -f "$PREFIX/lib/libzip.a" ] && return
    echo "$LIBZIP_SHA  $t" | sha256sum -c --status 2>/dev/null ||
        curl -fsSL -o "$t" https://github.com/nih-at/libzip/releases/download/v$LIBZIP/libzip-$LIBZIP.tar.gz
    echo "$LIBZIP_SHA  $t" | sha256sum -c --quiet
    rm -rf "$BLD/libzip-src"; mkdir -p "$BLD/libzip-src"
    tar -xzf "$t" -C "$BLD/libzip-src" --strip-components=1
    cmake -S "$BLD/libzip-src" -B "$BLD/libzip" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$BLD/armhf.cmake" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$ARMFLAGS" -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DBUILD_SHARED_LIBS=OFF -DENABLE_COMMONCRYPTO=OFF -DENABLE_GNUTLS=OFF -DENABLE_MBEDTLS=OFF \
        -DENABLE_OPENSSL=OFF -DENABLE_WINDOWS_CRYPTO=OFF -DENABLE_BZIP2=OFF -DENABLE_LZMA=OFF -DENABLE_ZSTD=OFF \
        -DBUILD_TOOLS=OFF -DBUILD_REGRESS=OFF -DBUILD_OSSFUZZ=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF
    cmake --build "$BLD/libzip" -j "$JOBS" --target install
}

soh() {
    toolchain
    build_libzip
    cmake -S "$SRC" -B "$BLD/armhf" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$BLD/armhf.cmake" -DCMAKE_PREFIX_PATH="$PREFIX" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$ARMFLAGS" -DCMAKE_CXX_FLAGS="$ARMFLAGS" -DUSE_OPENGLES=ON -DUSE_GLES2=${SOH_GLES2:-ON}
    cmake --build "$BLD/armhf" -j "$JOBS" --target soh -- -k 0
    cp "$BLD/armhf/soh/soh.elf" "$OUT/"
    arm-linux-gnueabihf-strip "$OUT/soh.elf"
}

# Copy each NEEDED library (and its own NEEDED, recursively) that the rootfs doesn't ship
libs() {
    local queue=("$OUT/soh.elf") seen=" " f lib path
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

# The port folder as one tar for HOME/ports. SoH refuses to start without an assets/ folder beside it,
# even with oot.o2r ready; the full one (the extractor's 120 MB of yml) only matters for extracting on the console.
pack() {
    cp "$HERE/soh.sh" "$OUT/"
    mkdir -p "$OUT/assets"
    cp "$SRC/soh/assets/yml/config.yml" "$OUT/assets/"
    tar -cf /repo/dev/out/zelda/soh.tar -C "$(dirname "$OUT")" soh
    ls -l /repo/dev/out/zelda/soh.tar
}

# soh.elf under qemu-arm on Xvfb, GLES2 on Mesa's llvmpipe: a screenshot every 30 s for $1 seconds
# (SOH_ELF picks another binary, SHOTS another folder)
shot() {
    local secs=${1:-300} run=/tmp/soh-run shots=${SHOTS:-/repo/dev/out/zelda/shots} elf=${SOH_ELF:-$OUT/soh.elf} t xvfb game
    rm -rf "$run" "$shots"; mkdir -p "$run" "$shots"
    cp "$OUT"/*.o2r "$run/"
    Xvfb :9 -screen 0 1280x960x24 -nolisten tcp & xvfb=$!
    sleep 1
    (cd "$run" && SHIP_HOME=$run DISPLAY=:9 SDL_AUDIODRIVER=dummy QEMU_LD_PREFIX=/ \
        exec qemu-arm "$elf" > "$shots/soh.log" 2>&1) & game=$!
    for ((t = 30; t <= secs; t += 30)); do
        sleep 30
        kill -0 $game 2>/dev/null || { echo "soh.elf exited before ${t}s"; break; }
        DISPLAY=:9 import -window root "$shots/t$t.png"
    done
    kill -9 $game 2>/dev/null || true
    kill $xvfb
    ls "$shots"
}

source_tree
case "${1:-all}" in
    assets) assets ;;
    soh) soh ;;
    libs) libs ;;
    pack) pack ;;
    shot) shot "${2:-}" ;;
    all) assets; soh; libs; pack ;;
    *) echo "usage: $0 [assets|soh|libs|pack|shot [seconds]]" >&2; exit 1 ;;
esac
