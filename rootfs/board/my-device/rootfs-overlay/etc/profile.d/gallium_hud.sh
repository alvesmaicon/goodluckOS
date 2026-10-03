. /usr/share/goodluck/defaults/gallium_hud.conf
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
# the in-game status bar's items, and its clock as a strftime format (the Date & Time settings)
hud_status=""
[ "$HUD_STATUS_CLOCK" = true ] && hud_status=clock
[ "$HUD_STATUS_BATTERY" = true ] && hud_status="${hud_status:+$hud_status,}battery"
[ "$HUD_STATUS_AUDIO" = true ] && hud_status="${hud_status:+$hud_status,}audio"
export GALLIUM_HUD_STATUS="${hud_status:-0}"
export GALLIUM_HUD_STATUS_OPACITY=$HUD_STATUS_OPACITY
hud_clock=""
[ "$HUD_DATE" = true ] && hud_clock=$HUD_DATE_FORMAT
[ "$HUD_24H" = true ] && hud_time=%H:%M || hud_time="%I:%M %p"
[ "$HUD_TIME" = true ] && hud_clock="${hud_clock:+$hud_clock }$hud_time"
export GALLIUM_HUD_STATUS_CLOCK="$hud_clock"
unset HUD_VISIBLE HUD_ITEMS HUD_STYLE HUD_POSITION HUD_STATUS_CLOCK HUD_STATUS_BATTERY HUD_STATUS_AUDIO HUD_STATUS_OPACITY HUD_DATE HUD_TIME HUD_24H HUD_DATE_FORMAT hud_x hud_y hud_time hud_clock hud_status
