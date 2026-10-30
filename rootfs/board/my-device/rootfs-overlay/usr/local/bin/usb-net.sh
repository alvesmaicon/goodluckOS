#!/bin/sh
# usb-net.sh check|renew: the USB network (usb-mode.sh network, S31usb-net)
#   check   fetches Google's connectivity page over HTTPS (DNS, route and the CA bundle in one go),
#           leaves "ok" or "fail" in /tmp/usb-net.check and shows the address and the result on the
#           screen. Run from the udhcpc hook and the Network page.
#   renew   udhcpc asks the PC or phone for an address now
RESULT=/tmp/usb-net.check

case "$1" in
    check)
        echo checking > $RESULT
        code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' https://connectivitycheck.gstatic.com/generate_204)
        if [ "$code" = 204 ]; then echo ok > $RESULT; msg="Internet OK"; else echo fail > $RESULT; msg="No internet"; fi
        ip=$(ip -4 addr show usb0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p')
        /usr/local/bin/osd-notify.sh network "$ip: $(/usr/local/bin/gl-tr "$msg")"
        ;;
    renew)
        [ -f /run/udhcpc.usb0.pid ] && kill -USR1 "$(cat /run/udhcpc.usb0.pid)" 2>/dev/null
        ;;
    *) echo "usage: $0 check|renew" >&2; exit 2 ;;
esac
exit 0
