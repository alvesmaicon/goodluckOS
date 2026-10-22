#!/bin/sh
# battery-care.sh [limit] [floor] - on a computer's USB, charge up to <limit> % (90) and then stop, so a console
# left on the data cable for days doesn't sit full and warm. Charging comes back when the cable comes out, or at
# <floor> % (50) if a game drains the battery while still on it. A charger with no computer behind it charges to
# full as before. It also learns the battery's resistance for the fuel gauge. Started at boot by S32battery-care.
LIMIT=${1:-90}
FLOOR=${2:-50}
B=/sys/class/power_supply/axp20x-battery
U=/sys/class/power_supply/axp20x-usb
UDC=/sys/class/udc/$(ls /sys/class/udc 2>/dev/null | head -n 1)/state
SAVED=/var/lib/battery-care/resistance

charge() {
    # status turns the PMIC's charger on or off, but reading it back gives the current's direction
    case $1 in on) echo Charging > $B/status ;; off) echo "Not charging" > $B/status ;; esac
    logger -t battery-care "charging $1: $2"
}

# the resistance in mOhm from load steps (an app starting, a cable coming in): dV/dI, away from full
learn() {
    read v < $B/voltage_now; read i < $B/current_now
    v=$((v / 1000)); i=$((i / 1000)); di=$((i - pi))
    if [ $pv -lt 4150 ] && [ $v -lt 4150 ] && { [ $di -ge 100 ] || [ $di -le -100 ]; }; then
        r=$(((v - pv) * 1000 / di))
        if [ $r -ge 50 ] && [ $r -le 2000 ]; then
            # the first steps are averaged, then each moves the estimate by an eighth
            steps=$((steps + 1)); k=$steps; [ $k -gt 8 ] && k=8
            rdc=$((rdc + (r - rdc) / k))
            d=$((rdc - set)); [ $d -lt 0 ] && d=$((-d))
            if [ $((d * 20)) -gt $set ] && echo $((rdc * 1000)) > $B/resistance; then
                set=$rdc; echo $rdc > $SAVED
                logger -t battery-care "battery resistance $rdc mOhm"
            fi
        fi
    fi
    pv=$v; pi=$i
}

if [ -e $B/resistance ]; then
    mkdir -p ${SAVED%/*}
    rdc=; read rdc < $SAVED 2>/dev/null
    if [ -n "$rdc" ]; then
        echo $((rdc * 1000)) > $B/resistance; steps=8
    else
        read rdc < $B/resistance; rdc=$((rdc / 1000)); steps=0
    fi
    set=$rdc; pv=9999; pi=0
else
    learn() { :; }
fi

charge on "start"
held=0
host=0
while :; do
    learn
    read usb < $U/online
    read cap < $B/capacity
    state=; read state < $UDC 2>/dev/null
    if [ "$usb" != 1 ]; then
        host=0
        [ $held = 1 ] && { held=0; charge on "cable out at $cap %"; }
    else
        # a computer enumerates the gadget and a charger never does; once seen, it counts until the cable comes
        # out, so also while the computer sleeps
        [ "$state" = configured ] && host=1
        if [ $held = 0 ]; then
            [ $host = 1 ] && [ "$cap" -ge "$LIMIT" ] && { held=1; charge off "on a computer at $cap %"; }
        elif [ "$cap" -le "$FLOOR" ]; then
            held=0
            charge on "down to $cap % on the cable"
        fi
    fi
    sleep 10
done
