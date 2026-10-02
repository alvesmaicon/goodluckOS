HUD_VISIBLE=false
HUD_ITEMS=fps,cpu
HUD_STYLE=graph
HUD_POSITION=top-left
HUD_STATUS=false
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
export GALLIUM_HUD_STATUS=$HUD_STATUS
unset HUD_VISIBLE HUD_ITEMS HUD_STYLE HUD_POSITION HUD_STATUS hud_x hud_y
