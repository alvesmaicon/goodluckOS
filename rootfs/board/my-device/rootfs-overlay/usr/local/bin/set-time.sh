#!/bin/sh
# set-time.sh <seconds since the epoch> - sets the clock and keeps it in the RTC
# (System Settings -> Date & Time, through doas)
case "$1" in ''|*[!0-9]*) echo "usage: $0 <seconds since the epoch>" >&2; exit 2 ;; esac
date -u -s "@$1" >/dev/null && hwclock -w -u
