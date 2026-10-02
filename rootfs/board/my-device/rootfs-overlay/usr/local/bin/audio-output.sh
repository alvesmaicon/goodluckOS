#!/bin/sh
# audio-output.sh toggle|speaker|headphones|get
# headphones = speaker off (there is no headphone detection)

CARD=0

cur=$(amixer -c "$CARD" cget name='Speaker Switch' 2>/dev/null | grep -o ': values=[a-z]*' | cut -d= -f2)
[ -n "$cur" ] || exit 1
[ "$cur" = on ] && cur=speaker || cur=headphones

case "$1" in
    get)    echo "$cur"; exit 0 ;;
    toggle) [ "$cur" = speaker ] && new=headphones || new=speaker ;;
    speaker|headphones) new=$1 ;;
    *)      echo "usage: $0 toggle|speaker|headphones|get" >&2; exit 2 ;;
esac

[ "$new" = headphones ] && sw=off || sw=on
amixer -q -c "$CARD" cset name='Speaker Switch' "$sw"

/usr/local/bin/osd-notify.sh output 0 "$new"
/usr/local/bin/persist-settings.sh later
