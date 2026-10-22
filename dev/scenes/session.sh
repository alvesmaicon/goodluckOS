#!/bin/sh
# launch_command of the play time scenes: what appctl logs when the game ($1) ends after 75 minutes
mkdir -p /dev/shm/application
printf '4500\t%s\n' "$1" >>/dev/shm/application/sessions
