#!/bin/sh
# templog.sh [seconds] - appends temperatures and load to /home/player/logs/templog.csv (issue #1:
# screen artifacts when the console gets hot). Started at boot by S98templog when
# /etc/player-flags/templog exists.
LOG=/home/player/logs/templog.csv
INTERVAL=${1:-10}

pmic=
for d in /sys/bus/iio/devices/iio:device*; do
    case "$(cat "$d/name" 2>/dev/null)" in *axp*) [ -f "$d/in_temp_raw" ] && pmic=$d ;; esac
done

mkdir -p "${LOG%/*}"
[ -s "$LOG" ] || echo "time,uptime,cpu_c,pmic_c,cpu_mhz,cpu_max_mhz,gpu_mhz,load1,bat_ma,bat_status,usb,backlight" > "$LOG"
echo "# boot $(date '+%F %T')" >> "$LOG"

while :; do
    cpu=$(awk '{ printf "%.1f", $1 / 1000 }' /sys/class/thermal/thermal_zone0/temp)
    pt=
    [ -n "$pmic" ] && pt=$(awk -v r="$(cat $pmic/in_temp_raw)" -v o="$(cat $pmic/in_temp_offset)" \
        -v s="$(cat $pmic/in_temp_scale)" 'BEGIN { printf "%.1f", (r + o) * s / 1000 }')
    f=/sys/devices/system/cpu/cpu0/cpufreq
    gpu=$(cat /sys/class/devfreq/*.gpu/cur_freq 2>/dev/null | head -n 1)
    b=/sys/class/power_supply/axp20x-battery
    echo "$(date '+%F %T'),$(cut -d' ' -f1 /proc/uptime),$cpu,$pt,$(( $(cat $f/scaling_cur_freq) / 1000 )),$(( $(cat $f/scaling_max_freq) / 1000 )),$(( ${gpu:-0} / 1000000 )),$(cut -d' ' -f1 /proc/loadavg),$(( $(cat $b/current_now) / 1000 )),$(cat $b/status),$(cat /sys/class/power_supply/axp20x-usb/online),$(cat /sys/class/backlight/backlight/brightness)" >> "$LOG"
    sync
    sleep "$INTERVAL"
done
