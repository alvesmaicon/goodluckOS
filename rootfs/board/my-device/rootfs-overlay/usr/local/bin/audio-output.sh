#!/bin/sh
# audio-output.sh toggle|speaker|headphones|get|apply
# headphones = speaker off (there is no headphone detection)
# The speaker gets a high-pass filter: it can't play bass and distorts on it.
# The path stays powered pmdown_time after a sound: an hour on the headphones, which hear the
# amplifier powering up and down, 5 s on the speaker, which hisses while it is on.

CARD=0
SPEAKER_HPF="500 Hz"
PMDOWN=$(ls /sys/devices/platform/sound/*/pmdown_time 2>/dev/null | head -1)

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

pmdown() {
    [ -n "$PMDOWN" ] || return 0
    if [ "$1" = headphones ]; then echo 3600000 > "$PMDOWN"; return 0; fi
    echo 5000 > "$PMDOWN"
    # a short sound puts back the headphones' pending hour, or the speaker would hiss through it
    [ "$2" = flush ] && { head -c 960 /dev/zero | aplay -N -q -D default -t raw -f S16_LE -r 48000 -c 2; } >/dev/null 2>&1 &
}

case "$1" in
    get)    echo "$cur"; exit 0 ;;
    apply)  filter "$cur"; pmdown "$cur"; exit 0 ;;
    toggle) [ "$cur" = speaker ] && new=headphones || new=speaker ;;
    speaker|headphones) new=$1 ;;
    *)      echo "usage: $0 toggle|speaker|headphones|get|apply" >&2; exit 2 ;;
esac

[ "$new" = headphones ] && sw=off || sw=on
amixer -q -c "$CARD" cset name='Speaker Switch' "$sw"
filter "$new"
[ "$cur" = headphones ] && pmdown "$new" flush || pmdown "$new"

/usr/local/bin/osd-notify.sh output 0 "$new"
/usr/local/bin/persist-settings.sh later
