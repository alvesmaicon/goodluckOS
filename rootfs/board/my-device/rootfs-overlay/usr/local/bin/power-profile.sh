#!/bin/sh
# Power profiles: the CPU governor and top speed, and the GPU's speed range.
#   power-profile.sh battery|balanced|performance|default - apply it and remember it
#   power-profile.sh restore                               - apply the remembered one (boot)
#   battery:     CPU up to 816 MHz, GPU up to 240 MHz
#   balanced:    CPU and GPU speed up only when needed (schedutil / simple_ondemand)
#   performance: CPU and GPU always at full speed

STATE=/etc/player-flags/power-profile
DEFAULTS=/usr/share/goodluck/defaults/power.conf
CPUFREQ=/sys/devices/system/cpu/cpufreq
BATTERY_CPU_KHZ=816000
BATTERY_GPU_HZ=240000000

default_profile() {
    POWER_PROFILE=balanced
    [ -f "$DEFAULTS" ] && . "$DEFAULTS"
    echo "$POWER_PROFILE"
}

apply() {
    case "$1" in battery) gov=schedutil ;; balanced) gov=schedutil ;; performance) gov=performance ;; *) return 1 ;; esac
    for p in $CPUFREQ/policy*; do
        max=$(cat "$p/cpuinfo_max_freq")
        top=$max
        [ "$1" = battery ] && [ "$BATTERY_CPU_KHZ" -lt "$max" ] && top=$BATTERY_CPU_KHZ
        echo "$gov" > "$p/scaling_governor"
        echo "$top" > "$p/scaling_max_freq"
    done
    for d in /sys/class/devfreq/*.gpu; do
        [ -d "$d" ] || continue
        freqs=$(cat "$d/available_frequencies")
        low=${freqs%% *}
        high=${freqs##* }
        top=$high
        [ "$1" = battery ] && [ "$BATTERY_GPU_HZ" -lt "$high" ] && top=$BATTERY_GPU_HZ
        bottom=$low
        [ "$1" = performance ] && bottom=$high
        # lower the floor first, so the new ceiling is never below it
        echo "$low" > "$d/min_freq"
        echo "$top" > "$d/max_freq"
        echo "$bottom" > "$d/min_freq"
    done
}

case "$1" in
    restore)
        p=$(cat "$STATE" 2>/dev/null)
        # before the profiles, only "Performance mode" was stored, as the governor
        [ -z "$p" ] && [ "$(cat /etc/player-flags/governor 2>/dev/null)" = performance ] && p=performance
        apply "${p:-$(default_profile)}" || apply "$(default_profile)"
        ;;
    battery|balanced|performance|default)
        p=$1
        [ "$p" = default ] && p=$(default_profile)
        apply "$p" || exit 1
        mkdir -p "${STATE%/*}"
        echo "$p" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
        rm -f /etc/player-flags/governor
        sync
        ;;
    *)
        echo "usage: $0 {battery|balanced|performance|default|restore}"
        exit 1
        ;;
esac
