#!/bin/sh
CARD=0
CONTROL=Headphone
STEP=5

# triggerhappy doesn't wait for a run: a repeat that comes while a step is still going is dropped
exec 9<"$0"
flock -n 9 || exit 0

cur=$(amixer -c "$CARD" sget "$CONTROL" | grep -m1 -oE '[0-9]+%' | tr -d '%')
cur=$(( (cur + 2) / 5 * 5 ))   # 64 hardware levels: back to the multiple of 5 that was set

case "$1" in
    up)   new=$((cur + STEP)); [ "$new" -gt 100 ] && new=100 ;;
    down) new=$((cur - STEP)); [ "$new" -lt 0 ] && new=0 ;;
esac

if [ "$new" -eq 0 ]; then
    amixer -q -c "$CARD" sset "$CONTROL" 0% mute
    /usr/local/bin/osd-notify.sh volume 0 muted
else
    amixer -q -c "$CARD" sset "$CONTROL" "${new}%" unmute
    /usr/local/bin/osd-notify.sh volume "$new"
fi

exec 9<&-   # before persist-settings' 2 s timer, which would inherit the lock
/usr/local/bin/persist-settings.sh later
