#!/bin/sh
# Ship of Harkinian (Ocarina of Time) with the GLES2 renderer. Saves and settings stay in this folder.
# Log: HOME/logs/soh.log. Overrides go in <port>/env, one VAR=value per line.
dir=$(cd "$(dirname "$0")" && pwd)
log=/home/player/logs/soh.log
mkdir -p /home/player/logs

export LD_LIBRARY_PATH=$dir/libs
export SHIP_HOME=$dir
# First run: the cartridge's look at 480p (bilinear, N64 logo only, no SoH quest types)
[ -f "$dir/shipofharkinian.json" ] || cp "$dir/defaults.json" "$dir/shipofharkinian.json"
[ -f "$dir/env" ] && { set -a; . "$dir/env"; set +a; }

{
    date
    grep -E "MemTotal|MemAvailable|SwapFree|Shmem:" /proc/meminfo
    cd "$dir" && ./soh.elf
    echo "exit $?"
    grep -E "MemAvailable|SwapFree" /proc/meminfo
} > "$log" 2>&1
