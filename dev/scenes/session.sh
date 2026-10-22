#!/bin/sh
# launch_command of the play time scenes: what appctl logs when the game ($1) ends after 75 minutes
mkdir -p /home/player/.local/state
printf '%s\t4500\t%s\n' "$FAKE_EPOCH" "$1" >>/home/player/.local/state/sessions
