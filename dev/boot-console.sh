#!/usr/bin/env bash
# The R36H's boot files onto its BOOT partition over the USB data port, without the card reader: MTP into HOME,
# checked, then moved to BOOT over serial. The console reboots into them when asked (--reboot).
#   dev/boot-console.sh <card> [--reboot] [files...]    default files: dev/out/rk3326/{Image,*.dtb,uboot.env}
# The card must be named (HOME/.card-name); the daily card is refused.
set -euo pipefail
DEV=$(cd "$(dirname "$0")" && pwd)
H=/home/player
die() { echo "$*"; exit 1; }
g() { python3 "$DEV/glserial.py" cmd "$@" | tr -d '\r'; }
sha() { shasum -a 256 "$1" | cut -c1-64; }

[ $# -ge 1 ] || { sed -n 's/^#   //p' "$0"; exit 1; }
card=$1; shift
reboot=
[ "${1:-}" = --reboot ] && { reboot=1; shift; }
[ $# -gt 0 ] || set -- "$DEV/out/rk3326/Image" "$DEV/out/rk3326/rk3326-gameconsole-r36h.dtb" "$DEV/out/rk3326/uboot.env"
[ "$card" != extreme-daily ] || die "extreme-daily is the daily card"
command -v mtp-sendfile >/dev/null || die "no mtp-sendfile (brew install libmtp)"
for f in "$@"; do [ -f "$f" ] || die "no $f"; done

have=$(g "echo card=\$(head -n 1 $H/.card-name 2>/dev/null)" | sed -n 's/^card=//p')
[ "$have" = "$card" ] || die "the console has the card '$have', not $card: nothing was done"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in "$@"; do
    part=${f##*/}.$$.part
    cp "$f" "$tmp/$part"
    echo "== ${f##*/} ($(($(wc -c < "$f") / 1048576)) MB) to HOME over MTP"
    # a Mac's ptpcamerad takes the console as a camera: kept away while mtp-sendfile holds it
    (while :; do killall -9 ptpcamerad 2>/dev/null; sleep 0.2; done) & keeper=$!
    perl -e 'alarm shift; exec @ARGV' 180 mtp-sendfile "$tmp/$part" "$part" > "$tmp/log" 2>&1 || true
    kill $keeper 2>/dev/null || true
    rm -f "$tmp/$part"
    [ "$(g "sha256sum $H/$part | cut -c1-64" --timeout 60 | grep -E '^[0-9a-f]{64}$' || true)" = "$(sha "$f")" ] ||
        { cat "$tmp/log"; g "rm -f $H/$part" >/dev/null; die "the copy in HOME isn't ${f##*/}: BOOT unchanged"; }
done

echo "== into BOOT"
cmds="mkdir -p /tmp/boot && mount /dev/mmcblk0p1 /tmp/boot"
for f in "$@"; do cmds="$cmds && cp $H/${f##*/}.$$.part /tmp/boot/${f##*/} && rm $H/${f##*/}.$$.part"; done
g "$cmds && sync" >/dev/null
for f in "$@"; do
    [ "$(g "sha256sum /tmp/boot/${f##*/} | cut -c1-64" --timeout 60 | grep -E '^[0-9a-f]{64}$' || true)" = "$(sha "$f")" ] ||
        { g "umount /tmp/boot" >/dev/null; die "${f##*/} on BOOT isn't the file sent"; }
    echo "   ${f##*/} ok"
done
g "umount /tmp/boot" >/dev/null
[ -z "$reboot" ] || { echo "== reboot"; g "reboot" --timeout 5 >/dev/null 2>&1 || true; }
