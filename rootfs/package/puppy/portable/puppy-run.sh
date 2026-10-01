#!/bin/sh
# Runs Puppy on firmwares other than goodluckOS: shows the launcher, runs what was picked in it and
# comes back to it, until Puppy is left with "Quit Puppy" (it then exits without a pick).
# goodluckOS does the same with puppy-bootstrap.sh.
#
# Usage: puppy-run.sh [puppy.conf]     (default: the puppy.conf next to this script)

DIR=$(cd "$(dirname "$0")" && pwd)
CONF=${1:-$DIR/puppy.conf}
PUPPY=${PUPPY_BIN:-$DIR/puppy}

# libraries shipped next to Puppy, if any
[ -d "$DIR/libs" ] && export LD_LIBRARY_PATH="$DIR/libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# the launch_file of puppy.conf (relative to it, like Puppy reads it)
LAUNCH=$(sed -n 's/^[[:space:]]*launch_file[[:space:]]*=[[:space:]]*//p' "$CONF" 2>/dev/null | tail -n 1)
case "$LAUNCH" in
    "") LAUNCH=/dev/shm/launch ;;
    "~/"*) LAUNCH="$HOME/${LAUNCH#\~/}" ;;
    /*) ;;
    *) LAUNCH="$(cd "$(dirname "$CONF")" && pwd)/$LAUNCH" ;;
esac

# a game set to autolaunch (SELECT in Puppy) starts first
AUTO=$(sed -n 's/^[[:space:]]*autolaunch_file[[:space:]]*=[[:space:]]*//p' "$CONF" 2>/dev/null | tail -n 1)
case "$AUTO" in "~/"*) AUTO="$HOME/${AUTO#\~/}" ;; esac
if [ -n "$AUTO" ] && [ -f "$AUTO" ]; then
    sh -c "$(grep -v '^#' "$AUTO")"
fi

while true; do
    rm -f "$LAUNCH"
    "$PUPPY" --config "$CONF" || break
    [ -s "$LAUNCH" ] || break       # Quit Puppy
    sh -c "$(cat "$LAUNCH")"
done
rm -f "$LAUNCH"
