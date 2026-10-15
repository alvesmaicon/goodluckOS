#!/usr/bin/env bash
# Ship of Harkinian (Ocarina of Time) for HOME/ports/soh, without the game.
#   dev/zelda/build.sh assets   soh.o2r, and oot.o2r from the roms in dev/out/zelda/roms (native asset tools)
#   dev/zelda/build.sh soh      soh.elf for armhf
#   dev/zelda/build.sh libs     the libraries soh.elf needs that the console's rootfs lacks, into libs/
#   dev/zelda/build.sh          all three
# Output in dev/out/zelda/soh. Runs in the goodluck-zelda image (dev/zelda/Dockerfile, on top of goodluck-dev).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$(dirname "$HERE")")
IMAGE=goodluck-zelda

if [ ! -f /.dockerenv ]; then
    docker image inspect $IMAGE >/dev/null 2>&1 || docker build -t $IMAGE "$HERE"
    exec docker run --rm -i -v "$REPO:/repo" -v goodluck-work:/work -e GL_JOBS $IMAGE /repo/dev/zelda/build.sh "$@"
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
    local p
    for p in "$HERE"/patches/soh/*.patch; do
        git -C "$SRC" apply --reverse --check "$p" 2>/dev/null || git -C "$SRC" apply "$p"
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
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$ARMFLAGS" -DCMAKE_CXX_FLAGS="$ARMFLAGS" -DUSE_OPENGLES=ON
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

source_tree
case "${1:-all}" in
    assets) assets ;;
    soh) soh ;;
    libs) libs ;;
    all) assets; soh; libs ;;
    *) echo "usage: $0 [assets|soh|libs]" >&2; exit 1 ;;
esac
