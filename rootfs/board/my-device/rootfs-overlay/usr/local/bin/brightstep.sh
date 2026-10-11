#!/bin/sh
# triggerhappy doesn't wait for a run: a repeat that comes while a step is still going is dropped
exec 9<"$0"
flock -n 9 || exit 0

BL=$(echo /sys/class/backlight/*)
max=$(cat "$BL/max_brightness")
cur=$(cat "$BL/brightness")
step=$((max / 10)); [ "$step" -lt 1 ] && step=1

case "$1" in
    up)   new=$((cur + step)); [ "$new" -gt "$max" ] && new=$max ;;
    down) new=$((cur - step)); [ "$new" -lt 1 ] && new=1 ;;
esac

echo "$new" > "$BL/brightness"
/usr/local/bin/osd-notify.sh brightness $((new * 100 / max))

exec 9<&-   # before persist-settings' 2 s timer, which would inherit the lock
/usr/local/bin/persist-settings.sh later
