#!/bin/sh
# audio-output.sh toggle|speaker|headphones|get|apply
# headphones = speaker off. Plugging headphones in or out runs headphones|speaker (triggerhappy,
# on the jack's input switch); apply, at boot, follows the jack too. FN+DOWN overrides it.
# The speaker gets a high-pass filter: it can't play bass and distorts on it.

CARD=0
SPEAKER_HPF="500 Hz"

cur=$(amixer -c "$CARD" cget name='Speaker Switch' 2>/dev/null | grep -o ': values=[a-z]*' | cut -d= -f2)
[ -n "$cur" ] || exit 1
[ "$cur" = on ] && cur=speaker || cur=headphones

# the jack control (on with headphones in), empty on a kernel without detection
jack() {
    id=$(amixer -c "$CARD" controls | grep -i "jack'" | head -1 | cut -d, -f1)
    [ -n "$id" ] && amixer -c "$CARD" cget "$id" | grep -o ': values=[a-z]*' | cut -d= -f2
}

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
    apply)
        j=$(jack)
        if [ -n "$j" ]; then
            [ "$j" = on ] && cur=headphones || cur=speaker
            [ "$cur" = headphones ] && sw=off || sw=on
            amixer -q -c "$CARD" cset name='Speaker Switch' "$sw"
        fi
        filter "$cur"; exit 0 ;;
    toggle) [ "$cur" = speaker ] && new=headphones || new=speaker ;;
    speaker|headphones) new=$1 ;;
    *)      echo "usage: $0 toggle|speaker|headphones|get|apply" >&2; exit 2 ;;
esac

[ "$new" = headphones ] && sw=off || sw=on
amixer -q -c "$CARD" cset name='Speaker Switch' "$sw"
filter "$new"

/usr/local/bin/osd-notify.sh output 0 "$new"
/usr/local/bin/persist-settings.sh later
