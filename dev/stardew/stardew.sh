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
# The game's language follows Puppy's whenever Puppy's changes; a choice made in the game sticks until then
prefs=/home/player/.config/StardewValley/startup_preferences
puppy=$(sed -n 's/^language=//p' /home/player/.config/puppy/settings 2>/dev/null | tail -n 1)
if [ "$puppy" != "$(cat "$dir/.language" 2>/dev/null)" ]; then
    case $puppy in pt*) lang=pt ;; es*) lang=es ;; *) lang=en ;; esac
    if [ -f "$prefs" ]; then
        sed -i "s|<languageCode>[^<]*</languageCode>|<languageCode>$lang</languageCode>|" "$prefs"
    else
        mkdir -p "${prefs%/*}"
        printf '<?xml version="1.0" encoding="utf-8"?>\n<StartupPreferences xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n  <languageCode>%s</languageCode>\n</StartupPreferences>\n' "$lang" > "$prefs"
    fi
    echo "$puppy" > "$dir/.language"
fi

xnb=$dir/gamedata/Content/Minigames/TitleButtons.xnb
[ -f "$dir/icon.png" ] || [ ! -f "$xnb" ] || mono "$dir/SdvIcon.exe" "$xnb" "$dir/icon.png"

{
    date
    grep -E "MemTotal|MemAvailable|SwapFree|Shmem:" /proc/meminfo
    if [ "$1" = test ]; then
        cd "$dir/test" && mono HelloMG.exe
    else
        cd "$dir/gamedata" && mono StardewValley.exe
    fi
    echo "exit $?"
} > "$log" 2>&1
