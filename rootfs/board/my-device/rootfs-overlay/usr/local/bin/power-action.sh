#!/bin/sh
# power-action.sh reboot|poweroff - "Restarting..." or "Shutting down..." on the console, which stays
# on screen once the launcher closes, then restarts or powers off (POWER menu, Resize Home)
case "$1" in
    reboot)   msg="Restarting..." ;;
    poweroff) msg="Shutting down..." ;;
    *) echo "usage: $0 reboot|poweroff" >&2; exit 2 ;;
esac
/usr/local/bin/console-message.sh "$(/usr/local/bin/gl-tr "$msg")"
exec /sbin/"$1"
