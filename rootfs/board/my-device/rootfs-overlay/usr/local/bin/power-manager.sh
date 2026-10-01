#!/bin/sh
FIFO=/run/power-request
[ -p "$FIFO" ] || mkfifo -m 660 "$FIFO"
chgrp player "$FIFO" 2>/dev/null   # let unprivileged 'player' write requests

exec 3<>"$FIFO"

# Centred on the text console (80x30), which is what's left on screen once the apps are closed
console_message() {
    msg=$(/usr/local/bin/gl-tr "$1")
    printf "\033[2J\033[?25l\033[15;%dH%s" $(( (80 - ${#msg}) / 2 + 1 )) "$msg" > /dev/tty1 2>/dev/null
}

do_shutdown() {
    action="$1"
    if [ "$action" = "reboot" ]; then
        console_message "Restarting..."
        /sbin/reboot
    else
        console_message "Shutting down..."
        /sbin/poweroff
    fi
}

while true; do
    read -r cmd <&3
    [ -n "$cmd" ] || continue
    case "$cmd" in
        poweroff|reboot)
            do_shutdown "$cmd"
            ;;
        save-settings)   # sent by unprivileged apps (e.g. system-settings) after changing volume
            /usr/local/bin/persist-settings.sh save
            ;;
        clear-console)   # sent by Puppy once it's up: drop the boot's "Starting system..." text
            printf "\033[2J" > /dev/tty1 2>/dev/null
            ;;
        screen-off)      # Puppy's power menu: "Display off"
            /usr/local/bin/toggle-screen.sh off
            ;;
        set-governor\ *) # sent by system-settings; persist-settings.sh only accepts governors the kernel offers
            /usr/local/bin/persist-settings.sh governor "${cmd#set-governor }"
            ;;
    esac
done
