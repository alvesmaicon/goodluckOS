#!/bin/sh
# Persist screen brightness and ALSA volume across reboots.
#   save    - store the current brightness and ALSA state
#   restore - apply the stored brightness and CPU governor (volume is restored by S40alsa)
#   governor <name> - switch the CPU governor and remember it
#   later   - debounced save: a burst of calls (held key) becomes a single save

STATE_DIR=/etc/player-flags
BRIGHT_FILE=$STATE_DIR/brightness
ALSA_STATE=/var/lib/alsa/asound.state
BL=/sys/class/backlight/backlight
STAMP=/tmp/.persist-stamp
GOV_FILE=$STATE_DIR/governor
CPUFREQ=/sys/devices/system/cpu

save() {
    mkdir -p "$STATE_DIR"
    # brightness 0 means the screen was blanked with the power button, not a user preference
    b=$(cat "$BL/brightness")
    if [ "$b" -ge 1 ] 2>/dev/null; then echo "$b" > "$BRIGHT_FILE.tmp" && mv "$BRIGHT_FILE.tmp" "$BRIGHT_FILE"; fi
    alsactl store -f "$ALSA_STATE"
    sync
}

restore() {
    v=$(cat "$BRIGHT_FILE" 2>/dev/null)
    max=$(cat "$BL/max_brightness")
    case "$v" in
        ''|*[!0-9]*) ;;
        *) [ "$v" -ge 1 ] && [ "$v" -le "$max" ] && echo "$v" > "$BL/brightness" ;;
    esac
    g=$(cat "$GOV_FILE" 2>/dev/null)
    [ -n "$g" ] && set_governor "$g"
    return 0
}

set_governor() {
    case "$1" in ''|*[!a-z]*) return 1 ;; esac
    for p in $CPUFREQ/cpu[0-9]*/cpufreq; do
        grep -qw "$1" "$p/scaling_available_governors" 2>/dev/null || return 1
        echo "$1" > "$p/scaling_governor"
    done
}

governor() {
    set_governor "$1" || return 1
    mkdir -p "$STATE_DIR"
    echo "$1" > "$GOV_FILE.tmp" && mv "$GOV_FILE.tmp" "$GOV_FILE"
    sync
}

later() {
    stamp=$(cut -d' ' -f1 /proc/uptime)
    echo "$stamp" > "$STAMP"
    ( sleep 2; [ "$(cat "$STAMP" 2>/dev/null)" = "$stamp" ] && save ) >/dev/null 2>&1 &
}

case "$1" in
    save)    save ;;
    restore) restore ;;
    later)   later ;;
    governor) governor "$2" ;;
    *)       echo "usage: $0 {save|restore|later|governor <name>}"; exit 1 ;;
esac