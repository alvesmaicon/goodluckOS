#!/bin/sh
# audio-output.sh toggle|speaker|headphones|get|apply
# headphones = speaker off (there is no headphone detection)
# The speaker gets a high-pass filter: it can't play bass and distorts on it.

CARD=0
SPEAKER_HPF="500 Hz"

cur=$(amixer -c "$CARD" cget name='Speaker Switch' 2>/dev/null | grep -o ': values=[a-z]*' | cut -d= -f2)
[ -n "$cur" ] || exit 1
[ "$cur" = on ] && cur=speaker || cur=headphones

filter() {
    if [ "$1" = speaker ]; then
        amixer -q -c "$CARD" cset name='DAC High-Pass Filter Cutoff' "$SPEAKER_HPF" 2>/dev/null
        amixer -q -c "$CARD" cset name='DAC High-Pass Filter Switch' on,on 2>/dev/null
    else
        amixer -q -c "$CARD" cset name='DAC High-Pass Filter Switch' off,off 2>/dev/null
    fi
}

case "$1" in
    get)    echo "$cur"; exit 0 ;;
    apply)  filter "$cur"; exit 0 ;;
    toggle) [ "$cur" = speaker ] && new=headphones || new=speaker ;;
    speaker|headphones) new=$1 ;;
    *)      echo "usage: $0 toggle|speaker|headphones|get|apply" >&2; exit 2 ;;
esac

[ "$new" = headphones ] && sw=off || sw=on
amixer -q -c "$CARD" cset name='Speaker Switch' "$sw"
filter "$new"

/usr/local/bin/osd-notify.sh output 0 "$new"
/usr/local/bin/persist-settings.sh later
