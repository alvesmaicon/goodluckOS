#!/bin/sh
# Graceful exit of the active app (Select+Start): SIGTERM lets RetroArch flush SRAM/config.
# Falls back to SIGKILL after 3 s. FN+Select+Start remains the immediate kill.
PIDFILE=/dev/shm/puppy-active-process-id
[ -f "$PIDFILE" ] || exit 0
pid=$(cat "$PIDFILE")
case "$pid" in
    ''|*[!0-9]*) exit 0 ;;   # not a valid number, bail
esac

kill -TERM "$pid" 2>/dev/null || exit 0
for i in 1 2 3; do
    kill -0 "$pid" 2>/dev/null || exit 0
    sleep 1
done
kill -9 "$pid" 2>/dev/null