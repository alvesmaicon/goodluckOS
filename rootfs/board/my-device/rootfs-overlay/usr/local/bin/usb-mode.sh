#!/bin/sh
# usb-mode.sh get|files|network: what the PC sees on the USB data port, next to the serial shell.
#   files    HOME as a drive (MTP), the default
#   network  an Ethernet adapter the PC can share its internet through (CDC NCM)
# The controller can't do both at once (S30usb-gadget). A switch is kept across reboots.

case "$1" in
    get) [ "$(cat /etc/player-flags/usb-mode 2>/dev/null)" = network ] && echo network || echo files ;;
    files|network)
        # out of appd's launcher group, which it empties when a game starts: umtprd and udhcpc must stay
        echo $$ > /sys/fs/cgroup/cgroup.procs 2>/dev/null
        exec /etc/init.d/S30usb-gadget switch "$1" ;;
    *) echo "usage: $0 get|files|network" >&2; exit 2 ;;
esac
