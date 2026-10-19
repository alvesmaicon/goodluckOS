#!/bin/sh
# battery-care.sh [limit] [floor] - on a computer's USB, charge up to <limit> % (90) and then stop, so a console
# left on the data cable for days doesn't sit full and warm (alvesmaicon/goodluckOS#8). Charging comes back when
# the cable comes out, or at <floor> % (50) if a game drains the battery while still on it. A charger with no
# computer behind it charges to full as before. Started at boot by S32battery-care.
LIMIT=${1:-90}
FLOOR=${2:-50}
B=/sys/class/power_supply/axp20x-battery
U=/sys/class/power_supply/axp20x-usb
UDC=/sys/class/udc/$(ls /sys/class/udc 2>/dev/null | head -n 1)/state

charge() {
    # status turns the PMIC's charger on or off, but reading it back gives the current's direction
    case $1 in on) echo Charging > $B/status ;; off) echo "Not charging" > $B/status ;; esac
    logger -t battery-care "charging $1: $2"
}

charge on "start"
held=0
while :; do
    read usb < $U/online
    read cap < $B/capacity
    state=; read state < $UDC 2>/dev/null
    if [ "$usb" != 1 ]; then
        [ $held = 1 ] && { held=0; charge on "cable out at $cap %"; }
    elif [ $held = 0 ]; then
        # a computer enumerated the gadget (or is asleep with it): a plain charger never gets past "powered"
        case $state in configured|suspended|addressed|default)
            [ "$cap" -ge "$LIMIT" ] && { held=1; charge off "on a computer at $cap %"; } ;;
        esac
    elif [ "$cap" -le "$FLOOR" ]; then
        held=0; charge on "down to $cap % on the cable"
    fi
    sleep 5
done
