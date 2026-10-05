#!/bin/sh
# Centred text on the console (tty1), left on screen when the app on top closes,
# e.g. are-you-sure's "Shutting down..."; the console is 80x30 (640x480, 8x16 font)
msg=$(printf '%s' "$1" | tr -d '\000-\037' | cut -c1-80)
printf '\033[2J\033[H\033[?25l\033[15;%dH%s' $(( (80 - ${#msg}) / 2 + 1 )) "$msg" > /dev/tty1
