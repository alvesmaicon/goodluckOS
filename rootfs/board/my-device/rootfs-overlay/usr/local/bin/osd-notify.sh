#!/bin/sh
# On-screen feedback for the volume/brightness hotkeys.
#   osd-notify.sh volume|brightness <percent> [muted]
#   osd-notify.sh output 0 speaker|headphones
# Puppy shows /dev/shm/osd as a bar. While it isn't running, every GL app shows /dev/shm/hud-osd
# (label, value and bar percent, -1 for none) through the Gallium HUD patch in Mesa.

kind=$1
pct=$2

echo "$kind $pct $3" > /dev/shm/osd.tmp && mv /dev/shm/osd.tmp /dev/shm/osd
pidof puppy >/dev/null && exit 0

case "$kind" in
    volume)     label=$(/usr/local/bin/gl-tr Volume) ;;
    brightness) label=$(/usr/local/bin/gl-tr Brightness) ;;
    output)     label=$(/usr/local/bin/gl-tr "Audio output") ;;
    *)          label=$kind ;;
esac
if [ "$kind" = output ]; then
    [ "$3" = headphones ] && value=$(/usr/local/bin/gl-tr Headphones) || value=$(/usr/local/bin/gl-tr Speaker)
    bar=-1
elif [ "$3" = muted ]; then
    value=$(/usr/local/bin/gl-tr Muted); bar=0
else
    value="$pct%"; bar=$pct
fi
printf '%s\n%s\n%s\n' "$label" "$value" "$bar" > /dev/shm/hud-osd.tmp && mv /dev/shm/hud-osd.tmp /dev/shm/hud-osd
