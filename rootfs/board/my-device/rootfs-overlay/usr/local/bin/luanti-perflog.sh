#!/bin/sh
# luanti-perflog.sh <pid> [seconds] - while Luanti runs, appends memory, GPU and temperature to
# /home/player/logs/luanti-perf-<start>.csv and each thread's CPU and faults to luanti-threads-<start>.csv.
# Started by luanti.sh when ~/.minetest/perf.env exists.
pid=$1
INTERVAL=${2:-5}
stamp=$(date +%Y%m%d-%H%M%S)
LOG=/home/player/logs/luanti-perf-$stamp.csv
TLOG=/home/player/logs/luanti-threads-$stamp.csv
mkdir -p "${LOG%/*}"

kswapd=
for p in /proc/[0-9]*; do
    [ "$(cat $p/comm 2>/dev/null)" = kswapd0 ] && kswapd=$p/stat
done

{
    echo "# LIMA_DEBUG=$LIMA_DEBUG; $(grep -E '^[a-z0-9_]+ *=' "${HOME:-/home/player}/.minetest/minetest.conf" | tr -d ' ' | tr '\n' ';')"
    echo "time,uptime,mem_avail_kb,shmem_kb,swap_free_kb,rss_kb,swap_kb,dri_maps,dri_kb,cpu_busy,cpu_idle,cpu_iowait,load1,cpu_c,gpu_mhz"
} > "$LOG"
echo "uptime,tid,name,utime,stime,minflt" > "$TLOG"

while [ -d /proc/$pid ]; do
    up=$(cut -d' ' -f1 /proc/uptime)
    mem=$(awk '/^MemAvailable:/ { a = $2 } /^Shmem:/ { s = $2 } /^SwapFree:/ { f = $2 } END { print a "," s "," f }' /proc/meminfo)
    vm=$(awk '/^VmRSS:/ { r = $2 } /^VmSwap:/ { w = $2 } END { print r + 0 "," w + 0 }' /proc/$pid/status 2>/dev/null)
    # Mesa maps the GPU buffers it writes (meshes) through the DRM fd
    dri=$(awk '$6 ~ /^\/dev\/dri\// { n++; split($1, r, "-"); kb += (("0x" r[2]) - ("0x" r[1])) / 1024 } END { print n + 0 "," int(kb) }' /proc/$pid/maps 2>/dev/null)
    cpu=$(awk '/^cpu / { print $2 + $3 + $4 + $7 + $8 + $9 "," $5 "," $6; exit }' /proc/stat)
    t=$(awk '{ printf "%.1f", $1 / 1000 }' /sys/class/thermal/thermal_zone0/temp)
    gpu=$(cat /sys/class/devfreq/*.gpu/cur_freq 2>/dev/null | head -n 1)
    echo "$(date '+%T'),$up,$mem,${vm:-0,0},${dri:-0,0},$cpu,$(cut -d' ' -f1 /proc/loadavg),$t,$(( ${gpu:-0} / 1000000 ))" >> "$LOG"
    # each thread's utime, stime and minor faults (the name sits between the first "(" and the last ")")
    awk -v up="$up" '{ b = length($0); while (b > 0 && substr($0, b, 1) != ")") b--
        a = index($0, "("); split(substr($0, b + 2), f, " ")
        print up "," $1 "," substr($0, a + 1, b - a - 1) "," f[12] "," f[13] "," f[8] }' /proc/$pid/task/*/stat $kswapd >> "$TLOG" 2>/dev/null
    sync
    sleep "$INTERVAL"
done
