#!/bin/sh
# 2 Ship 2 Harkinian (Majora's Mask) with the GLES2 renderer. Saves and settings stay in this folder.
# Log: HOME/logs/2ship.log. Overrides go in <port>/env, one VAR=value per line.
dir=$(cd "$(dirname "$0")" && pwd)
log=/home/player/logs/2ship.log
mkdir -p /home/player/logs

export LD_LIBRARY_PATH=$dir/libs
export SHIP_HOME=$dir
# First run: the cartridge's look at 480p (bilinear, the authentic boot logo)
[ -f "$dir/2ship2harkinian.json" ] || cp "$dir/defaults.json" "$dir/2ship2harkinian.json"
[ -f "$dir/env" ] && { set -a; . "$dir/env"; set +a; }

{
    date
    grep -E "MemTotal|MemAvailable|SwapFree|Shmem:" /proc/meminfo
    cd "$dir" && ./2s2h.elf
    echo "exit $?"
    grep -E "MemAvailable|SwapFree" /proc/meminfo
} > "$log" 2>&1
