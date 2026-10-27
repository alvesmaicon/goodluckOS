#!/bin/sh
# dev/audio-test.sh beeps|reboot [--speaker]
# A listening test over the serial. beeps: five half-second tones with the gaps mixed (8 s, when the
# DACs have powered down, and 2 s, when they are still on), each step labeled on the screen, the
# time each tone takes printed (~0.65 s; ~1.25 s meant the amplifier had to power up). The listener
# notes which ones click without knowing the gaps. reboot: reboots and waits for the console.
set -e
DEV=$(cd "$(dirname "$0")" && pwd)
OUT=$DEV/out/audio
GL=$DEV/glserial.py
mode=$1; shift || true
out=headphones; [ "${1:-}" = --speaker ] && out=speaker
[ "$mode" = beeps ] || [ "$mode" = reboot ] || { sed -n '2,6p' "$0"; exit 2; }

if [ "$mode" = reboot ]; then
    "$GL" cmd "date +%T; reboot" | tail -1
    sleep 55
    i=0; until ls /dev/cu.usbmodem* >/dev/null 2>&1 || [ $i -ge 45 ]; do sleep 2; i=$((i + 1)); done
    sleep 12
    "$GL" cmd uptime | tail -1
    exit 0
fi

mkdir -p "$OUT"
[ -f "$OUT/beep.raw" ] || python3 - "$OUT/beep.raw" <<'EOF'
import math, struct, sys
sr, n, fade = 48000, 24000, 480    # 0.5 s of 440 Hz, 10 ms fades so the tone itself can't click
out = bytearray()
for i in range(n):
    g = min(1.0, i / fade, (n - 1 - i) / fade)
    v = int(32767 * 0.25 * g * math.sin(2 * math.pi * 440 * i / sr))
    out += struct.pack('<hh', v, v)
open(sys.argv[1], 'wb').write(out)
EOF

cat > "$OUT/beeps.sh" <<EOF
#!/bin/sh
BEEP=/home/player/beep.raw
osd() { printf 'Audio test\n%s\n-1\n' "\$1" > /dev/shm/hud-osd.tmp && mv /dev/shm/hud-osd.tmp /dev/shm/hud-osd; }
beep() { s=\$(cut -d' ' -f1 /proc/uptime); aplay -q -D default -t raw -f S16_LE -r 48000 -c 2 "\$BEEP"; e=\$(cut -d' ' -f1 /proc/uptime); echo "\$(date +%T) \$1 (gap \$2 s): \$(awk -v a=\$s -v b=\$e 'BEGIN{print b-a}') s"; }
sw=\$(amixer -c0 cget name='Speaker Switch' | grep -o ': values=[a-z]*' | cut -d= -f2)
amixer -q -c0 cset name='Speaker Switch' $([ $out = speaker ] && echo on || echo off)
echo "output $out, pmdown_time \$(cat /sys/devices/platform/sound/*/pmdown_time) ms"
osd "5 beeps"
sleep 8; beep 1 8
sleep 2; beep 2 2
sleep 8; beep 3 8
sleep 8; beep 4 8
sleep 2; beep 5 2
sleep 8
osd "done"
amixer -q -c0 cset name='Speaker Switch' "\$sw"
EOF

"$GL" send "$OUT/beep.raw" /home/player/beep.raw | tail -1
"$GL" send "$OUT/beeps.sh" /tmp/beeps.sh | tail -1
"$GL" cmd --timeout 120 "sh /tmp/beeps.sh 2>&1"
