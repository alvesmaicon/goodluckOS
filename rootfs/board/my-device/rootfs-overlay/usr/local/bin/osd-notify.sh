#!/bin/sh
# On-screen feedback for the volume/brightness hotkeys.
#   osd-notify.sh volume|brightness <percent> [muted]
# Puppy shows /dev/shm/osd as a bar; RetroArch gets a notification through its network commands
# (network_cmd_enable in retroarch.cfg). Other apps show nothing.

kind=$1
pct=$2

echo "$kind $pct $3" > /dev/shm/osd.tmp && mv /dev/shm/osd.tmp /dev/shm/osd

if pidof retroarch >/dev/null; then
    case "$kind" in
        volume)     label=$(/usr/local/bin/gl-tr Volume) ;;
        brightness) label=$(/usr/local/bin/gl-tr Brightness) ;;
        *)          label=$kind ;;
    esac
    if [ "$3" = "muted" ]; then msg="$label: $(/usr/local/bin/gl-tr muted)"; else msg="$label: $pct%"; fi
    retroarch --command "SHOW_MSG $msg" >/dev/null 2>&1 &
fi
