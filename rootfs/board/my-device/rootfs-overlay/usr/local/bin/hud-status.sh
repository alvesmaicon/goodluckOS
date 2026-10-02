#!/bin/sh
# Writes "<volume> <muted> <headphones>" to /dev/shm/hud-status for the status bar of the Gallium HUD
hp=$(amixer -c 0 sget Headphone 2>/dev/null)
vol=$(echo "$hp" | grep -o '\[[0-9]*%\]' | head -n 1 | tr -d '[]%')
[ -n "$vol" ] || exit 0
vol=$(( (vol + 2) / 5 * 5 ))   # 64 hardware levels: back to the multiple of 5 that was set
echo "$hp" | grep -q '\[off\]' && muted=1 || muted=0
amixer -c 0 cget name='Speaker Switch' 2>/dev/null | grep -q ': values=off' && headphones=1 || headphones=0
echo "$vol $muted $headphones" > /dev/shm/hud-status.tmp && mv /dev/shm/hud-status.tmp /dev/shm/hud-status
