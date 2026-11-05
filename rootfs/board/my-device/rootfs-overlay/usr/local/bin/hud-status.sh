#!/bin/sh
# Writes "<volume> <muted> <headphones>" to /dev/shm/hud-status for the status bar of the Gallium HUD
# the GA36-MB's Headphone and Speaker Switch, or the R36H's RK817 Master (amixer's mapped curve, as
# in volstep.sh) and its jack (the mux stays on HP: the speakers hang on that output)
hp=$(amixer -c 0 sget Headphone 2>/dev/null) || hp=$(amixer -M -c 0 sget Master 2>/dev/null)
vol=$(echo "$hp" | grep -o '\[[0-9]*%\]' | head -n 1 | tr -d '[]%')
[ -n "$vol" ] || exit 0
vol=$(( (vol + 2) / 5 * 5 ))   # the hardware's levels: back to the multiple of 5 that was set
echo "$hp" | grep -q '\[off\]' && muted=1 || muted=0
if amixer -c 0 cget name='Speaker Switch' 2>/dev/null | grep -q ': values=off' ||
   amixer -c 0 cget iface=CARD,name='Headphones Jack' 2>/dev/null | grep -q ': values=on'; then headphones=1; else headphones=0; fi
echo "$vol $muted $headphones" > /dev/shm/hud-status.tmp && mv /dev/shm/hud-status.tmp /dev/shm/hud-status
