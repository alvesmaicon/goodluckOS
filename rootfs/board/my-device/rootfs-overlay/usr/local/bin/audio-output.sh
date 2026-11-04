#!/bin/sh
# audio-output.sh toggle|speaker|headphones|get|apply
# headphones = speaker off. Plugging headphones in or out runs headphones|speaker (triggerhappy,
# on the jack's input switch); apply, at boot, follows the jack too. FN+DOWN overrides it.
# The speaker gets a high-pass filter: it can't play bass and distorts on it.

CARD=0
SPEAKER_HPF="500 Hz"

# the jack control (on with headphones in), empty on a kernel without detection
jack() {
    id=$(amixer -c "$CARD" controls | grep -i "jack'" | head -1 | cut -d, -f1)
    [ -n "$id" ] && amixer -c "$CARD" cget "$id" | grep -o ': values=[a-z]*' | cut -d= -f2
}

# The GA36-MB's codec switches the speaker next to the headphones. The R36H's speakers hang on the
# RK817's headphone output through an amplifier, and the jack itself switches between them: the mux
# stays on HP (its SPK output drives nothing) and the output is whatever the jack says.
fixed=0
if amixer -c "$CARD" cget name='Speaker Switch' >/dev/null 2>&1; then
    output() { amixer -c "$CARD" cget name='Speaker Switch' | grep -q ': values=on' && echo speaker || echo headphones; }
    set_output() { [ "$1" = headphones ] && v=off || v=on; amixer -q -c "$CARD" cset name='Speaker Switch' "$v"; }
elif amixer -c "$CARD" cget name='Playback Mux' >/dev/null 2>&1; then
    fixed=1
    output() { [ "$(jack)" = on ] && echo headphones || echo speaker; }
    set_output() { amixer -q -c "$CARD" cset name='Playback Mux' HP; }
else
    exit 1
fi
cur=$(output)

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
            set_output "$cur"
        fi
        filter "$cur"; exit 0 ;;
    toggle) [ "$cur" = speaker ] && new=headphones || new=speaker; [ $fixed = 1 ] && new=$cur ;;   # nothing to override: shows it
    speaker|headphones) new=$1 ;;
    *)      echo "usage: $0 toggle|speaker|headphones|get|apply" >&2; exit 2 ;;
esac

set_output "$new"
filter "$new"

/usr/local/bin/osd-notify.sh output 0 "$new"
/usr/local/bin/persist-settings.sh later
