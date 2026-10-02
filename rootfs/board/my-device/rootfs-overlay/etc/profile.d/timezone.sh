# Time zone as a POSIX TZ string, e.g. <-03>3 for UTC-3 (there is no zoneinfo); UTC without the file
if [ -s /home/player/.config/timezone ]; then export TZ="$(cat /home/player/.config/timezone)"; else unset TZ; fi
