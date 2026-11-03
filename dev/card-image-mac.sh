#!/usr/bin/env bash
# Writes a whole card image (e.g. dev/out/rk3326/r36h-card.img) to a card in a Mac card reader,
# 64 MiB at a time with the progress, then reads it back to check it.
#
#   dev/card-image-mac.sh <diskN> <image> [--daily-card]
#
# diskN comes from `diskutil list external`. Refuses internal disks, disks over 70 GB, stock cards
# (.card-name ending in -stock, on any partition) and the daily card (extreme-daily) unless
# --daily-card is given too.
set -euo pipefail

[ $# -ge 2 ] || { sed -n '2,10p' "$0"; exit 1; }
DISK=${1#/dev/}; IMG=$2; DAILY=${3:-}
SIZE=$(stat -f %z "$IMG")
[ $((SIZE % 1048576)) -eq 0 ] || { echo "$IMG is not a whole number of MiB"; exit 1; }

info=$(diskutil info "$DISK")
echo "$info" | grep -qE 'Device Location: +External|Removable Media: +Removable' || { echo "$DISK is not an external disk"; exit 1; }
bytes=$(echo "$info" | sed -n 's/.*Disk Size:.*(\([0-9]*\) Bytes).*/\1/p')
[ -n "$bytes" ] && [ "$bytes" -le $((70 * 1024 * 1024 * 1024)) ] || { echo "$DISK: unexpected size ($bytes)"; exit 1; }
[ "$bytes" -ge "$SIZE" ] || { echo "$DISK is smaller than $IMG"; exit 1; }

name=$(for p in s1 s2 s3; do m=$(diskutil info "${DISK}$p" 2>/dev/null | sed -n 's/.*Mount Point: *//p')
    [ -n "$m" ] && head -n 1 "$m/.card-name" 2>/dev/null && break; done || true)
echo "$DISK: $((bytes / 1000000000)) GB, card: ${name:-?}"
case $name in
    *-stock) echo "a stock card: refused"; exit 1 ;;
    extreme-daily) [ "$DAILY" = --daily-card ] || { echo "the daily card: refused (add --daily-card to really write it)"; exit 1; } ;;
esac

read -r -p "write $IMG ($((SIZE / 1048576)) MiB) over the whole of $DISK? [y/N] " ok
[ "$ok" = y ] || exit 1

diskutil unmountDisk "$DISK" >/dev/null
chunks=$((SIZE / 67108864)); rest=$(( (SIZE % 67108864) / 1048576 ))
start=$(date +%s)
for ((i = 0; i < chunks; i++)); do
    sudo dd if="$IMG" of=/dev/r"$DISK" bs=1m skip=$((i * 64)) seek=$((i * 64)) count=64 conv=notrunc 2>/dev/null
    el=$(( $(date +%s) - start + 1 ))
    echo "  $(( (i + 1) * 64 )) of $((SIZE / 1048576)) MiB, ~$(( el * (chunks - i - 1) / (i + 1) )) s left"
done
[ $rest -eq 0 ] || sudo dd if="$IMG" of=/dev/r"$DISK" bs=1m skip=$((chunks * 64)) seek=$((chunks * 64)) count=$rest conv=notrunc 2>/dev/null
sync
want=$(shasum -a 256 "$IMG" | cut -d' ' -f1)
have=$(sudo dd if=/dev/r"$DISK" bs=1m count=$((SIZE / 1048576)) 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
echo "image: $want"; echo "card:  $have"
[ "$want" = "$have" ] || { echo MISMATCH; exit 1; }
echo MATCH
diskutil eject "$DISK" >/dev/null && echo "$DISK ejected"
