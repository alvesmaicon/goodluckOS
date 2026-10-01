#!/bin/sh
# POWER key: screen off/on.
#   toggle-screen.sh       - from the key (triggerhappy). In the launcher, with the screen on, does
#                            nothing: Puppy opens its power menu instead.
#   toggle-screen.sh off   - turn the screen off (Puppy's "Display off", through power-manager.sh)
BL=/sys/class/backlight/backlight/brightness
current_brightness=$(cat "$BL")

if [ "$current_brightness" -eq 0 ]; then
    [ "$1" = "off" ] && exit 0
    if [ -f /tmp/last-brightness ]; then
        cat /tmp/last-brightness > "$BL"
    else
        echo "5" > "$BL"
    fi
    echo "0" > /sys/class/leds/blue:status/brightness
else
    # no active app means Puppy is in the foreground
    [ "$1" != "off" ] && [ ! -f /dev/shm/puppy-active-process-id ] && exit 0
    echo "$current_brightness" > /tmp/last-brightness
    echo "0" > "$BL"
    echo "1" > /sys/class/leds/blue:status/brightness
fi
