#!/bin/sh
# FN + D-pad up: shows/hides the Gallium HUD of the running app (GALLIUM_HUD_TOGGLE_SIGNAL=34).
# The signal goes only to the processes of appd's app group that catch it: for the others (su,
# the shell around the app) a real-time signal's default action would end them.
SIG=34
for pid in $(cat /sys/fs/cgroup/appd/app/cgroup.procs 2>/dev/null); do
    caught=$(sed -n 's/^SigCgt:[[:space:]]*//p' "/proc/$pid/status" 2>/dev/null)
    [ -n "$caught" ] || continue
    [ $(( (0x$caught >> (SIG - 1)) & 1 )) -eq 1 ] && kill -$SIG "$pid" 2>/dev/null
done
exit 0
