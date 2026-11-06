#!/bin/sh
# blackbox.sh [seconds] - power cut log (alvesmaicon/goodluckOS#8): battery, PMIC, temperatures, clocks and
# memory every second, plus kernel messages and POWER key events, synced to the rootfs so a cut keeps all
# but the last second. Started at boot by S97blackbox when /etc/player-flags/blackbox exists. The last five
# boots are kept as prev.1.gz (newest) to prev.5.gz, and the end of the newest is copied to
# HOME/logs/blackbox-prev.txt.
DIR=/var/lib/blackbox
LOG=$DIR/current.log
INTERVAL=${1:-1}
# the battery and the inputs by type: axp20x-battery, axp20x-usb and axp20x-ac on the A33; rk817-battery,
# rk817-charger and the charge port's dc-charger on the RK3326
supply() { for p in /sys/class/power_supply/*; do [ "$(cat $p/type 2>/dev/null)" = "$1" ] && { echo $p; return; }; done; }
B=$(supply Battery)
U=$(supply USB)
AC=$(supply Mains)
R=/sys/kernel/debug/regmap/sunxi-rsb-3a3/registers

mkdir -p $DIR
if [ -s $LOG ]; then
    mkdir -p /home/player/logs
    tail -n 3000 $LOG > /home/player/logs/blackbox-prev.txt
    for i in 4 3 2 1; do
        [ -f $DIR/prev.$i.gz ] && mv $DIR/prev.$i.gz $DIR/prev.$((i + 1)).gz
    done
    gzip -c $LOG > $DIR/prev.1.gz && rm $LOG
    sync
fi
[ -f $R ] || mount -t debugfs none /sys/kernel/debug 2>/dev/null
[ -f $R ] || R=   # the AXP's registers over RSB, only on the A33

BV=$B/voltage_now; [ -f $BV ] || BV=$B/voltage_avg
BI=$B/current_now; [ -f $BI ] || BI=$B/current_avg
CN=$B/charge_now; [ -f $CN ] || CN=   # the coulomb counter, only on the RK817
pmic=
for d in /sys/bus/iio/devices/iio:device*; do
    case "$(readlink -f "$d")" in *axp*) pmic=$d ;; esac   # the AXP's IIO device has no name file
done
pek=
for e in /sys/class/input/event*; do
    case "$(cat $e/device/name)" in axp20x-pek|"rk805 pwrkey") pek=/dev/input/${e##*/} ;; esac   # the POWER key
done
udc=$(ls /sys/class/udc 2>/dev/null | head -n 1)
vcpu=$(grep -l -E '^vdd[-_](cpu|arm)$' /sys/class/regulator/*/name | head -n 1); vcpu=${vcpu%/name}

{
    echo "# boot $(date '+%F %T')"
    echo "# pmic_c = (pmic_raw + $(cat $pmic/in_temp_offset 2>/dev/null)) * $(cat $pmic/in_temp_scale 2>/dev/null) / 1000"
    echo "# time uptime bat_mv bat_ma capacity status usb udc reg00:reg01 cpu_mc pmic_raw cpu_mhz vcpu_mv gpu_mhz load1 mem_avail_kb swap_free_kb backlight ac charge_mah"
} >> $LOG

cat /dev/kmsg >> $LOG &
K=$!
(
    [ -n "$pek" ] && exec 3<$pek || exit 0
    while :; do
        e=$(dd bs=24 count=1 2>/dev/null <&3 | od -An -tx1 | tr -d ' \n')   # one event, 16 or 24 bytes
        [ -n "$e" ] || exit 0
        case ${#e}:$e in 32:????????????????0100*|48:????????????????????????????????0100*) echo "P $(date '+%T') $e" >> $LOG ;; esac   # EV_KEY only
    done
) &
P=$!
trap 'echo "# stop $(date "+%F %T")" >> $LOG; sync; kill $K $P 2>/dev/null; exit 0' TERM INT

n=0
while :; do
    read up _ </proc/uptime
    read la _ </proc/loadavg
    read bv <$BV; read bi <$BI; read cap <$B/capacity; read st <$B/status
    usb=-; [ -n "$U" ] && read usb <$U/online
    ac=-; [ -n "$AC" ] && read ac <$AC/online
    cn=-; [ -n "$CN" ] && { read cn <$CN; cn=$((cn / 1000)); }
    us=-; [ -n "$udc" ] && read us </sys/class/udc/$udc/state
    case $us in "not attached") us=none ;; esac
    reg=-; [ -n "$R" ] && { set -- $(grep -E '^0[01]:' $R); reg=$2:$4; }
    read soc </sys/class/thermal/thermal_zone0/temp
    pt=-; [ -n "$pmic" ] && read pt <$pmic/in_temp_raw
    read f </sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq
    vc=-; [ -n "$vcpu" ] && { read vc <$vcpu/microvolts; vc=$((vc / 1000)); }
    gf=0; for g in /sys/class/devfreq/*.gpu/cur_freq; do read gf <$g; done
    while read k v _; do
        case $k in MemAvailable:) ma=$v ;; SwapFree:) sf=$v ;; esac
    done </proc/meminfo
    read bl </sys/class/backlight/backlight/brightness
    echo "$(date '+%T') $up $((bv / 1000)) $((bi / 1000)) $cap $st $usb $us $reg $soc $pt $((f / 1000)) $vc $((gf / 1000000)) $la $ma $sf $bl $ac $cn" >> $LOG
    sync
    n=$((n + 1))
    # a console left on for days: start over past 10 MB (about 20 hours), the rootfs is small
    [ $((n % 600)) = 0 ] && [ "$(wc -c < $LOG)" -gt 10000000 ] && : > $LOG
    sleep "$INTERVAL"
done
