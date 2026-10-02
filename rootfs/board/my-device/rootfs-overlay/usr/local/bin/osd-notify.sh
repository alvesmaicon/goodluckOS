#!/bin/sh
# On-screen feedback for the volume/brightness hotkeys.
#   osd-notify.sh volume|brightness <percent> [muted]
#   osd-notify.sh output 0 speaker|headphones
# Every GL app, Puppy included, shows /dev/shm/hud-osd (label, value and bar percent, -1 for none)
# through the Gallium HUD patch in Mesa. Its font is ASCII only, so accents are dropped.
# Puppy also reads /dev/shm/osd to refresh its top bar.

kind=$1
pct=$2

echo "$kind $pct $3" > /dev/shm/osd.tmp && mv /dev/shm/osd.tmp /dev/shm/osd
[ "$kind" = brightness ] || /usr/local/bin/hud-status.sh

ascii() {
    printf '%s' "$1" | sed 's/á/a/g; s/à/a/g; s/â/a/g; s/ã/a/g; s/é/e/g; s/ê/e/g; s/í/i/g;
        s/ó/o/g; s/ô/o/g; s/õ/o/g; s/ú/u/g; s/ç/c/g; s/Á/A/g; s/É/E/g; s/Í/I/g; s/Ó/O/g;
        s/À/A/g; s/Â/A/g; s/Ã/A/g; s/Ê/E/g; s/Ô/O/g; s/Õ/O/g; s/Ú/U/g; s/Ç/C/g'
}

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
printf '%s\n%s\n%s\n' "$(ascii "$label")" "$(ascii "$value")" "$bar" > /dev/shm/hud-osd.tmp &&
    mv /dev/shm/hud-osd.tmp /dev/shm/hud-osd
