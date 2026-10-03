#!/bin/sh
# Persist screen brightness and ALSA volume across reboots.
#   save    - store the current brightness and ALSA state
#   restore - apply the stored brightness and power profile (volume is restored by S40alsa)
#   later   - debounced save: a burst of calls (held key) becomes a single save

STATE_DIR=/etc/player-flags
BRIGHT_FILE=$STATE_DIR/brightness
ALSA_STATE=/var/lib/alsa/asound.state
BL=/sys/class/backlight/backlight
STAMP=/tmp/.persist-stamp

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
    /usr/local/bin/power-profile.sh restore
    return 0
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
    *)       echo "usage: $0 {save|restore|later}"; exit 1 ;;
esac