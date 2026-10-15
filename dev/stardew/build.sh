#!/usr/bin/env bash
# The Stardew Valley port for HOME/ports/stardewvalley, without the game: Mono armhf (plain files: apps run
# as player, which cannot mount, and HOME is FAT, which has no symlinks),
# gl4es, OpenAL Soft, the lz4 shim, PortMaster's managed MonoGame and patches, the HelloMG test.
#   dev/stardew/build.sh          build into dev/out/stardew/stardewvalley
#   (dev/out/stardew/altone: a 1 s OpenAL tone, for the console's /tmp)
#   dev/stardew/build.sh game     dev/out/stardew/gamedata from your own game (SDV_GAME, default: Steam on macOS)
#   dev/stardew/build.sh smoke    run Mono armhf under qemu-arm (no display): assemblies and native libs load
#   dev/stardew/build.sh patches  rebuild only stardew.sh, StardewPatches.dll, SVLoader.exe and SdvIcon.exe
#   dev/stardew/build.sh xmlgen   StardewValley.XmlSerializers.dll (+ its AOT image) in gamedata: the save's
#                                 serializers pregenerated from your game, installed by SdvLoader before the game
#                                 starts (the console builds them at run time in ~60 s and reads saves ~3x slower)
#   dev/stardew/build.sh aot      AOT-compile (Mono armhf under qemu-arm) the class libraries, the port's DLLs and
#                                 the game's assemblies in gamedata: <assembly>.so next to each one. Not used: on
#                                 the A33 it saved no startup time and cost 13% FPS (2026-10-15). With
#                                 AOT_PROFILE=<file> (macbench.sh's --profile=aot recording, inside the container's
#                                 /repo) the generic instances the game used are compiled in too
# StardewPatches.dll is compiled against your StardewValley.exe and icon.png made from its title logo, when
# SDV_GAME exists.
# Runs in the goodluck-stardew image (dev/stardew/Dockerfile, on top of goodluck-dev).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$(dirname "$HERE")")
IMAGE=goodluck-stardew
SDV_GAME=${SDV_GAME:-$HOME/Library/Application Support/Steam/steamapps/common/Stardew Valley}

if [ ! -f /.dockerenv ]; then
    docker image inspect $IMAGE >/dev/null 2>&1 || docker build -t $IMAGE "$HERE"
    game=(); [ -d "$SDV_GAME" ] && game=(-v "$SDV_GAME:/game:ro")
    exec docker run --rm -i -e AOT_PROFILE="${AOT_PROFILE:-}" -v "$REPO:/repo" -v goodluck-work:/work "${game[@]}" $IMAGE /repo/dev/stardew/build.sh "$@"
fi

W=/work/stardew
SRC=$W/src
BLD=$W/build
P=/repo/dev/out/stardew/stardewvalley
ARMFLAGS="-O2 -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard"

PM=https://raw.githubusercontent.com/PortsMaster/PortMaster-New/49b642ae4a3699bfa3626933ed70e7b34efd14e2/ports/stardewvalley/stardewvalley
PM_FILES="SVLoader.exe LICENSE.GL4ES.txt LICENSE.Mono.txt LICENSE.MonoGame.txt LICENSE.Patch.txt LICENSE_lwjgl.txt
    LICENSE_lz4.txt dlls/0Harmony.dll dlls/ATI.TextureConverter.dll dlls/AssimpNet.dll dlls/FreeImageNET.dll
    dlls/Lidgren.Network.dll dlls/Microsoft.Xna.Framework.dll.config dlls/Microsoft.Xna.Framework.Game.dll.config
    dlls/MonoGame.Framework.dll dlls/MonoGame.Framework.dll.config dlls/MonoGame.Framework.Content.Pipeline.dll
    dlls/MonoGame.Framework.Net.dll dlls/Nvidia.TextureTools.dll dlls/PVRTexLibNET.dll dlls/SharpFont.dll
    dlls/StardewPatches.dll"
GL4ES_REV=ec16bedd8819c475326f4f1a3063772c6d986e06
OPENAL=1.25.2
OPENAL_SHA=fb27e5839aa11f0e5b9d33756965291fad5d6909ab928ea1f796f4a1a6877894
LZ4=1.10.0
LZ4_SHA=537512904744b35e232912055ccf8ec66d768639ff3abe5788d90d792ec5f48b
MONO=6.12.0.199+dfsg-6
MONO_PKGS="mono-runtime-sgen:armhf mono-runtime-common:armhf libmono-corlib4.5-cil libmono-corlib4.5-dll
    libmono-posix4.0-cil libmono-security4.0-cil libmono-system-configuration4.0-cil libmono-system-core4.0-cil
    libmono-system-data4.0-cil libmono-system-drawing4.0-cil libmono-system-enterpriseservices4.0-cil
    libmono-system-numerics4.0-cil libmono-system-runtime-serialization4.0-cil libmono-system-security4.0-cil
    libmono-system-servicemodel-internals0.0-cil libmono-system-transactions4.0-cil libmono-system-xaml4.0-cil
    libmono-system-xml-linq4.0-cil libmono-system-xml4.0-cil libmono-system4.0-cil libmono-windowsbase4.0-cil
    mono-4.0-gac mono-gac"

# A source tarball with a pinned hash, unpacked once into $SRC/<name>
tarball() {
    local t=$SRC/$1.tar.gz
    if ! echo "$3  $t" | sha256sum -c --quiet >/dev/null 2>&1; then
        curl -fsSL -o "$t" "$2"
        echo "$3  $t" | sha256sum -c --quiet
    fi
    [ -d "$SRC/$1" ] || { mkdir "$SRC/$1"; tar -xzf "$t" -C "$SRC/$1" --strip-components=1; }
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

build_gl4es() {
    [ -d "$SRC/gl4es" ] || git clone -q https://github.com/ptitSeb/gl4es "$SRC/gl4es"
    git -C "$SRC/gl4es" cat-file -e $GL4ES_REV 2>/dev/null || git -C "$SRC/gl4es" fetch -q origin
    git -C "$SRC/gl4es" checkout -q $GL4ES_REV
    cmake -S "$SRC/gl4es" -B "$BLD/gl4es" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$BLD/armhf.cmake" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$ARMFLAGS -Wno-error=return-mismatch -Wno-error=int-conversion -Wno-error=incompatible-pointer-types" \
        -DNOX11=ON -DGLX_STUBS=OFF -DEGL_WRAPPER=ON -DGBM=ON > "$BLD/gl4es.cmake.log"
    ninja -C "$BLD/gl4es" > "$BLD/gl4es.log"
    cp -L "$SRC/gl4es/lib/libGL.so.1" "$SRC/gl4es/lib/libEGL.so.1" "$P/gl4es/"
}

build_openal() {
    tarball openal-soft https://github.com/kcat/openal-soft/archive/refs/tags/$OPENAL.tar.gz $OPENAL_SHA
    cmake -S "$SRC/openal-soft" -B "$BLD/openal" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$BLD/armhf.cmake" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$ARMFLAGS" -DCMAKE_CXX_FLAGS="$ARMFLAGS" \
        -DCMAKE_SHARED_LINKER_FLAGS="-static-libstdc++ -static-libgcc" \
        -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF -DALSOFT_REQUIRE_ALSA=ON \
        -DALSOFT_BACKEND_PIPEWIRE=OFF -DALSOFT_BACKEND_PULSEAUDIO=OFF -DALSOFT_BACKEND_JACK=OFF \
        -DALSOFT_BACKEND_OSS=OFF -DALSOFT_BACKEND_SNDIO=OFF -DALSOFT_BACKEND_PORTAUDIO=OFF \
        -DALSOFT_BACKEND_SDL2=OFF -DALSOFT_BACKEND_SDL3=OFF > "$BLD/openal.cmake.log"
    ninja -C "$BLD/openal" > "$BLD/openal.log"
    cp -L "$BLD/openal/libopenal.so.1" "$P/lib/"
}

build_lz4() {
    tarball lz4 https://github.com/lz4/lz4/archive/refs/tags/v$LZ4.tar.gz $LZ4_SHA
    arm-linux-gnueabihf-gcc $ARMFLAGS -shared -fPIC -I"$SRC/lz4/lib" "$HERE/lz4shim.c" "$SRC/lz4/lib/lz4.c" \
        -o "$P/lib/liblwjgl_lz4.so"
}

# Debian's Mono, relocatable: bin/mono finds lib/mono and etc/mono next to itself
build_mono() {
    local d=$W/debs r=$BLD/mono-root m=$BLD/mono p n=0
    mkdir -p "$d"
    for p in $MONO_PKGS; do ls "$d/${p%%:*}_"*.deb >/dev/null 2>&1 || n=1; done
    if [ $n = 1 ]; then
        apt-get update -qq
        (cd "$d" && apt-get download -qq $(for p in $MONO_PKGS; do echo "$p=$MONO"; done) 2>&1 | grep -v unsandboxed || true)
    fi
    rm -rf "$r" "$m"
    mkdir -p "$r" "$m/bin" "$m/lib" "$m/etc"
    for p in "$d"/*.deb; do dpkg-deb -x "$p" "$r"; done
    cp "$r/usr/bin/mono-sgen" "$m/bin/mono"
    cp -a "$r"/usr/lib/libmono-native.so* "$r/usr/lib/libMonoPosixHelper.so" "$m/lib/"
    cp -a "$r/usr/lib/mono" "$m/lib/"
    cp -a "$r/etc/mono" "$m/etc/"
    arm-linux-gnueabihf-gcc $ARMFLAGS -shared -fPIC -Wl,-soname,libgssapi_krb5.so.2 \
        -Wl,--version-script=<(echo 'gssapi_krb5_2_MIT { global: *; };') "$HERE/gssstub.c" -o "$m/lib/libgssapi_krb5.so.2"
    cp -rL "$m" "$P/mono"
}

# The game's managed code and Content, macOS (Contents/MacOS + Contents/Resources) or Linux/Windows layout
game_dirs() {
    BIN=$(dirname "$(find /game -maxdepth 3 \( -name StardewValley.exe -o -name "Stardew Valley.exe" \) | head -1)")
    CONTENT=$BIN/Content
    [ -d "$CONTENT" ] || CONTENT=$(dirname "$BIN")/Resources/Content
    [ -f "$BIN/StardewValley.exe" ] && [ -d "$CONTENT" ]
}

build_patches() {
    cp "$HERE/stardew.sh" "$P/"
    mcs -nologo -optimize+ -out:"$P/SVLoader.exe" "$HERE/patches/SVLoader.cs"
    mcs -nologo -optimize+ -r:"$P/dlls/MonoGame.Framework.dll" -out:"$P/SdvIcon.exe" "$HERE/patches/SdvIcon.cs"
    mcs -nologo -optimize+ -out:"$P/SdvLoader.exe" "$HERE/patches/SdvLoader.cs"
    mcs -nologo -optimize+ -r:System.Xml -out:"$P/SdvXmlGen.exe" "$HERE/patches/SdvXmlGen.cs"
    if ! game_dirs 2>/dev/null; then
        echo "no game in SDV_GAME: PortMaster's StardewPatches.dll (built for 1.6.12) stays"
        return
    fi
    mcs -nologo -target:library -optimize+ -lib:"$BIN" -lib:"$P/dlls" -r:"$BIN/StardewValley.exe" -r:xTile.dll \
        -r:MonoGame.Framework.dll -r:0Harmony.dll -out:"$P/dlls/StardewPatches.dll" "$HERE/patches/StardewPatches.cs"
    MONO_PATH=$P/dlls mono "$P/SdvIcon.exe" "$CONTENT/Minigames/TitleButtons.xnb" "$P/icon.png"
    echo "StardewPatches.dll built against $(strings "$BIN/StardewValley.exe" | grep -m1 -oE '^1\.[0-9]+\.[0-9]+' || echo '?')"
}

# The game minus what Mono armhf and the port provide (the macOS build bundles its own Mono and natives)
build_game() {
    local g=/repo/dev/out/stardew/gamedata f
    game_dirs || { echo "no StardewValley.exe under SDV_GAME"; exit 1; }
    rm -rf "$g"
    mkdir -p "$g"
    for f in "$BIN"/*.exe "$BIN"/*.dll "$BIN"/*.dll.config; do
        case $(basename "$f") in
            System.Data.HashFunction.*) ;;
            MonoGame.Framework.*|mscorlib.dll|Mono.*|System*|WindowsBase.dll|lib*) continue ;;
        esac
        cp "$f" "$g/"
    done
    cp -r "$CONTENT" "$g/Content"
    ls "$g"
    du -sh "$g"
}

# Only what the game loads; an image whose assembly changed is ignored by Mono (JIT again), so rerun after
# build.sh patches or build.sh game. The game's images come from the player's files and stay in gamedata.
AOT_BCL="mscorlib System System.Core System.Xml System.Configuration System.Numerics System.Runtime.Serialization
    System.Security System.ServiceModel.Internals System.Drawing Mono.Security"
AOT_PORT="0Harmony MonoGame.Framework Lidgren.Network StardewPatches"
AOT_GAME="StardewValley.exe StardewValley.GameData.dll xTile.dll BmFont.dll GalaxyCSharp.dll SkiaSharp.dll
    System.Data.HashFunction.Core.dll System.Data.HashFunction.Interfaces.dll System.Data.HashFunction.xxHash.dll"
build_aot() {
    local m=$P/mono g=/repo/dev/out/stardew/gamedata n f files=()
    for n in $AOT_BCL; do
        if [ $n = mscorlib ]; then files+=("$m/lib/mono/4.5/mscorlib.dll"); else files+=("$m"/lib/mono/gac/$n/*/$n.dll); fi
    done
    for n in $AOT_PORT; do files+=("$P/dlls/$n.dll"); done
    for n in $AOT_GAME; do [ -f "$g/$n" ] && files+=("$g/$n"); done
    export LD_LIBRARY_PATH=$P/lib:$m/lib MONO_PATH=$P/dlls:$P:$g
    for f in "${files[@]}"; do
        rm -f "$f.so"
        if qemu-arm "$m/bin/mono" -O=all --aot=tool-prefix=arm-linux-gnueabihf-${AOT_PROFILE:+,profile=$AOT_PROFILE} "$f" > "$BLD/aot-$(basename "$f").log" 2>&1 &&
                arm-linux-gnueabihf-strip --strip-debug "$f.so"; then
            printf '%-40s %6s KB\n' "$(basename "$f")" "$(( $(stat -c %s "$f.so") / 1024 ))"
        else
            echo "$(basename "$f"): failed, $(tail -1 "$BLD/aot-$(basename "$f").log")"
        fi
    done
}

# The serializer DLL is IL; its AOT image is fine here (one-off code, where AOT's slower steady state does not count)
build_xmlgen() {
    local m=$P/mono g=/repo/dev/out/stardew/gamedata f
    f=$g/StardewValley.XmlSerializers.dll
    export LD_LIBRARY_PATH=$P/lib:$m/lib MONO_PATH=$P/dlls:$P:$g HOME=/tmp
    rm -f "$f" "$f.so"
    (cd "$g" && qemu-arm "$m/bin/mono" "$P/SdvXmlGen.exe" "$g")
    qemu-arm "$m/bin/mono" -O=all --aot=tool-prefix=arm-linux-gnueabihf- "$f" > "$BLD/aot-xmlserializers.log" 2>&1
    arm-linux-gnueabihf-strip --strip-debug "$f.so"
    ls -la "$f" "$f.so"
}

fetch_portmaster() {
    local f
    for f in $PM_FILES; do
        [ -f "$SRC/portmaster/$f" ] || { mkdir -p "$SRC/portmaster/$(dirname "$f")"; curl -fsSL -o "$SRC/portmaster/$f" "$PM/$f"; }
        cp "$SRC/portmaster/$f" "$P/$f"
    done
}

build() {
    mkdir -p "$SRC" "$BLD"
    rm -rf "$P"
    mkdir -p "$P/lib" "$P/gl4es" "$P/dlls" "$P/test" "$P/gamedata"
    toolchain
    echo "== PortMaster files";  fetch_portmaster
    echo "== Mono $MONO";        build_mono
    echo "== gl4es $GL4ES_REV";  build_gl4es
    echo "== OpenAL Soft $OPENAL"; build_openal
    echo "== lz4 shim $LZ4";     build_lz4
    echo "== StardewPatches, SVLoader"; build_patches
    echo "== HelloMG"
    mcs -nologo -out:"$P/test/HelloMG.exe" -r:System.Core -r:"$P/dlls/MonoGame.Framework.dll" "$HERE/HelloMG.cs"
    arm-linux-gnueabihf-gcc $ARMFLAGS -I"$SRC/openal-soft/include" "$HERE/altone.c" -o "$(dirname "$P")/altone" \
        -L"$P/lib" -l:libopenal.so.1 -lm
    cp "$HERE/stardew.sh" "$P/"
    cp "$HERE/apps.puppy-entry" "$(dirname "$P")/"
    echo "== native libraries (armhf, newest glibc symbol)"
    for f in "$P"/lib/*.so* "$P"/gl4es/*; do
        printf '%-22s %s\n' "$(basename "$f")" \
            "$(arm-linux-gnueabihf-objdump -T "$f" | grep -oE 'GLIBC_[0-9.]+' | sort -Vu | tail -1)"
    done
    du -sh "$P" "$P/mono"
}

smoke() {
    local m=$P/mono
    cat > /tmp/hello.cs <<'EOF'
class H { static void Main() {
    System.Console.WriteLine("mono ok: " + System.Environment.Version + ", corlib " + typeof(object).Assembly.Location);
    System.Console.WriteLine("linq/xml ok: " + new System.Xml.Linq.XElement("x", System.Linq.Enumerable.Count(System.Linq.Enumerable.Range(1, 3))));
    System.Console.WriteLine("lz4 bound 1000 = " + LZ4CompressBound(System.IntPtr.Zero, System.IntPtr.Zero, 1000));
}
    [System.Runtime.InteropServices.DllImport("liblwjgl_lz4", EntryPoint = "Java_org_lwjgl_util_lz4_LZ4_LZ4_1compressBound")]
    static extern int LZ4CompressBound(System.IntPtr env, System.IntPtr clazz, int size);
}
EOF
    mcs -nologo -out:/tmp/hello.exe -r:$m/lib/mono/4.5/System.Xml.Linq.dll -r:System.Core /tmp/hello.cs
    export LD_LIBRARY_PATH=$P/lib:$m/lib MONO_PATH=$P/dlls:$P
    qemu-arm $m/bin/mono /tmp/hello.exe
    echo "== HelloMG (no display: it should get as far as SDL/GL init)"
    (cd "$P/test" && SDL_VIDEODRIVER=offscreen timeout 120 qemu-arm $m/bin/mono HelloMG.exe 2>&1 | head -20) || true
}

case ${1:-build} in
    build) build ;;
    game) build_game ;;
    smoke) smoke ;;
    patches) build_patches ;;
    aot) mkdir -p "$BLD"; build_aot ;;
    xmlgen) mkdir -p "$BLD"; build_xmlgen ;;
    *) echo "usage: dev/stardew/build.sh [build|game|smoke|patches|aot|xmlgen]"; exit 1 ;;
esac
