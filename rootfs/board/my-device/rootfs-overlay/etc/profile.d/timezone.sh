# Time zone as a POSIX TZ string, e.g. <-03>3 for UTC-3 (there is no zoneinfo); UTC without the file
[ -s /home/player/.config/timezone ] && export TZ="$(cat /home/player/.config/timezone)"
