#!/bin/sh
# Stardew Valley ("compatibility" branch) on Mono + PortMaster's MonoGame + gl4es.
# stardew.sh [test]: "test" runs HelloMG instead of the game. Log: HOME/logs/stardew[-test].log.
# Overrides (LIBGL_*, MONO_*...) go in <port>/env, one VAR=value per line.
dir=$(cd "$(dirname "$0")" && pwd)
mono=$dir/mono
log=/home/player/logs/stardew${1:+-$1}.log
mkdir -p /home/player/logs

export PATH=$mono/bin:$PATH
export LD_LIBRARY_PATH=$dir/lib:$mono/lib
export MONO_PATH=$dir/dlls:$dir
export MONOGAME_PATCH=$dir/dlls/StardewPatches.dll
export SDL_VIDEO_GL_DRIVER=$dir/gl4es/libGL.so.1
export SDL_VIDEO_EGL_DRIVER=$dir/gl4es/libEGL.so.1
export LIBGL_ES=2 LIBGL_GL=21
[ -f "$dir/env" ] && { set -a; . "$dir/env"; set +a; }
xnb=$dir/gamedata/Content/Minigames/TitleButtons.xnb
[ -f "$dir/icon.png" ] || [ ! -f "$xnb" ] || mono "$dir/SdvIcon.exe" "$xnb" "$dir/icon.png"

{
    date
    grep -E "MemTotal|MemAvailable|SwapFree|Shmem:" /proc/meminfo
    if [ "$1" = test ]; then
        cd "$dir/test" && mono HelloMG.exe
    else
        cd "$dir/gamedata" && mono "$dir/SVLoader.exe" StardewValley.exe
    fi
    echo "exit $?"
} > "$log" 2>&1
