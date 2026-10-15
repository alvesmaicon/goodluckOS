#!/bin/sh
# One sample of a running soh.elf or 2s2h.elf: CPU per thread, GPU time per frequency, temperatures and memory.
# perf.sh [seconds] > HOME/logs/<port>-perf.txt (run it with setsid nohup over serial; default 10 s)
s=${1:-10}
p=$(ps | grep -v grep | grep -E 'soh\.elf|2s2h\.elf' | awk '{print $1}' | head -1)
[ -n "$p" ] || { echo "neither soh.elf nor 2s2h.elf is running"; exit 1; }
gpu=$(ls -d /sys/class/devfreq/*gpu* 2>/dev/null | head -1)
ticks() { for t in /proc/$p/task/*; do echo "${t##*/} $(tr ' ' _ < $t/comm) $(cut -d' ' -f14,15 $t/stat)"; done; }
date
ticks > /tmp/perf1; cp "$gpu/trans_stat" /tmp/gpu1 2>/dev/null; head -1 /proc/stat > /tmp/cpu1
sleep "$s"
ticks > /tmp/perf2; cp "$gpu/trans_stat" /tmp/gpu2 2>/dev/null; head -1 /proc/stat > /tmp/cpu2
echo "threads (% of one core over ${s}s):"
awk -v s="$s" 'NR==FNR { a[$1] = $3 + $4; next } { d = $3 + $4 - a[$1]; if (d > 0) printf "  %-6s %-16s %3d%%\n", $1, $2, d / s }' /tmp/perf1 /tmp/perf2 | sort -k3 -n -r
awk '{ for (i = 2; i <= NF; i++) t += $i; idle = $5 } END { print t, idle }' /tmp/cpu1 > /tmp/cpu1s
awk '{ for (i = 2; i <= NF; i++) t += $i; idle = $5 } END { print t, idle }' /tmp/cpu2 > /tmp/cpu2s
paste /tmp/cpu1s /tmp/cpu2s | awk '{ printf "all cpus busy: %d%%\n", 100 - 100 * ($4 - $2) / ($3 - $1) }'
echo "gpu $gpu, ms at each frequency during the sample:"
awk 'NR==FNR { if ($NF ~ /^[0-9]+$/ && $1 ~ /[0-9]:$/) a[$1] = $NF; next }
     $NF ~ /^[0-9]+$/ && $1 ~ /[0-9]:$/ { printf "  %s %d\n", $1, $NF - a[$1] }' /tmp/gpu1 /tmp/gpu2
echo "soc $(cat /sys/class/thermal/thermal_zone0/temp) cpu MHz $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)"
grep -E "MemAvailable|SwapFree|Shmem:" /proc/meminfo
grep -E "VmRSS|VmSwap" /proc/$p/status
