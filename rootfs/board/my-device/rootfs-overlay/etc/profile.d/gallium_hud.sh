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
# the in-game status bar's items, and its clock as a strftime format (format and 12/24 hours
# from Date & Time)
hud_clock=""
[ "$HUD_STATUS_DATE" = true ] && hud_clock=$HUD_DATE_FORMAT
[ "$HUD_24H" = true ] && hud_time=%H:%M || hud_time="%I:%M %p"
[ "$HUD_STATUS_TIME" = true ] && hud_clock="${hud_clock:+$hud_clock }$hud_time"
hud_status=""
[ "$HUD_STATUS_CPU_TEMP" = true ] && hud_status=cputemp
[ "$HUD_STATUS_PMIC_TEMP" = true ] && hud_status="${hud_status:+$hud_status,}pmictemp"
[ -n "$hud_clock" ] && hud_status="${hud_status:+$hud_status,}clock"
[ "$HUD_STATUS_BATTERY" = true ] && hud_status="${hud_status:+$hud_status,}battery"
[ "$HUD_STATUS_AUDIO" = true ] && hud_status="${hud_status:+$hud_status,}audio"
export GALLIUM_HUD_STATUS="${hud_status:-0}"
export GALLIUM_HUD_STATUS_OPACITY=$HUD_STATUS_OPACITY
export GALLIUM_HUD_STATUS_CLOCK="$hud_clock"
# the volume / brightness feedback's colour: the launcher's accent (Interface -> Accent color)
export GALLIUM_HUD_ACCENT=$HUD_ACCENT
unset HUD_VISIBLE HUD_ITEMS HUD_STYLE HUD_POSITION HUD_STATUS_DATE HUD_STATUS_TIME HUD_STATUS_BATTERY HUD_STATUS_AUDIO HUD_STATUS_CPU_TEMP HUD_STATUS_PMIC_TEMP HUD_STATUS_OPACITY HUD_24H HUD_DATE_FORMAT HUD_ACCENT hud_x hud_y hud_time hud_clock hud_status
