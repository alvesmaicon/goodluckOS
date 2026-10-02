HUD_VISIBLE=false
HUD_ITEMS=fps,cpu
HUD_STYLE=graph
HUD_POSITION=top-left
HUD_STATUS=false
HUD_STATUS_ITEMS=all
HUD_STATUS_OPACITY=50
HUD_DATE=true
HUD_TIME=true
HUD_24H=false
HUD_DATE_FORMAT=%m/%d
[ -f /home/player/.config/gallium_hud.conf ] && . /home/player/.config/gallium_hud.conf

hud_x=10
hud_y=10
if [ "$HUD_STYLE" = text ]; then
    case "$HUD_POSITION" in *right) hud_x=544 ;; esac
    GALLIUM_HUD="simple,.x$hud_x$(echo "$HUD_ITEMS" | tr , +)"
else
    case "$HUD_POSITION" in *right) hud_x=350 ;; esac
    case "$HUD_POSITION" in bottom*) case "$HUD_ITEMS" in *,*) hud_y=200 ;; *) hud_y=342 ;; esac ;; esac
    GALLIUM_HUD=".x$hud_x.y$hud_y$HUD_ITEMS"
fi

export GALLIUM_HUD
export GALLIUM_HUD_VISIBLE=$HUD_VISIBLE
export GALLIUM_HUD_TOGGLE_SIGNAL=34
[ "$HUD_STATUS" = true ] && export GALLIUM_HUD_STATUS=$HUD_STATUS_ITEMS || export GALLIUM_HUD_STATUS=0
export GALLIUM_HUD_STATUS_OPACITY=$HUD_STATUS_OPACITY
# the status bar's clock, as a strftime format
hud_clock=""
[ "$HUD_DATE" = true ] && hud_clock=$HUD_DATE_FORMAT
[ "$HUD_24H" = true ] && hud_time=%H:%M || hud_time="%I:%M %p"
[ "$HUD_TIME" = true ] && hud_clock="${hud_clock:+$hud_clock }$hud_time"
export GALLIUM_HUD_STATUS_CLOCK="$hud_clock"
unset HUD_VISIBLE HUD_ITEMS HUD_STYLE HUD_POSITION HUD_STATUS HUD_STATUS_ITEMS HUD_STATUS_OPACITY HUD_DATE HUD_TIME HUD_24H HUD_DATE_FORMAT hud_x hud_y hud_time hud_clock
