#!/usr/bin/env bash
# Writes the kernel or the rootfs to its place on a goodluckOS card in a Mac card reader, and nothing
# else: HOME, the stock sectors and the partition table stay. Backs the region up first and checks
# the write by reading it back.
#
#   dev/sdcard-mac.sh <diskN> boot   dev/out/android_boot_a33.img    sector 172032 (84 MiB)
#   dev/sdcard-mac.sh <diskN> rootfs dev/out/rootfs.ext4             sector 262144 (128 MiB), 384 MiB max
#
# diskN comes from `diskutil list external`. Refuses internal disks, disks over 70 GB and the
# daily card (HOME/.card-name = extreme-daily) unless --daily-card is given too.
set -euo pipefail

[ $# -ge 3 ] || { sed -n '2,11p' "$0"; exit 1; }
DISK=${1#/dev/}; WHAT=$2; FILE=$3; DAILY=${4:-}
case $WHAT in
    boot) MIB=84; MAX=$((88 * 1024 * 1024)) ;;
    rootfs) MIB=128; MAX=$((384 * 1024 * 1024)) ;;
    *) echo "boot or rootfs"; exit 1 ;;
esac
SIZE=$(stat -f %z "$FILE")
[ "$SIZE" -le "$MAX" ] || { echo "$FILE is bigger than the $WHAT region"; exit 1; }
[ $((SIZE % 512)) -eq 0 ] || { echo "$FILE is not a whole number of sectors"; exit 1; }

info=$(diskutil info "$DISK")
echo "$info" | grep -qE 'Device Location: +External|Removable Media: +Removable' || { echo "$DISK is not an external disk"; exit 1; }
bytes=$(echo "$info" | sed -n 's/.*Disk Size:.*(\([0-9]*\) Bytes).*/\1/p')
[ -n "$bytes" ] && [ "$bytes" -le $((70 * 1024 * 1024 * 1024)) ] || { echo "$DISK: unexpected size ($bytes)"; exit 1; }

# Which card is it: HOME (partition 2, FAT) carries .card-name
home=$(diskutil info "${DISK}s2" 2>/dev/null | sed -n 's/.*Mount Point: *//p')
if [ -z "$home" ]; then diskutil mount readOnly "${DISK}s2" >/dev/null 2>&1 || true
    home=$(diskutil info "${DISK}s2" 2>/dev/null | sed -n 's/.*Mount Point: *//p'); fi
name=$( [ -n "$home" ] && head -n 1 "$home/.card-name" 2>/dev/null || echo "?")
echo "$DISK: $((bytes / 1000000000)) GB, card: $name, HOME at ${home:-not mounted}"
if [ "$name" = extreme-daily ] && [ "$DAILY" != --daily-card ]; then
    echo "this is the daily card: refused (add --daily-card to really write it)"; exit 1
fi

read -r -p "write $FILE ($SIZE bytes) to $DISK at $MIB MiB? [y/N] " ok
[ "$ok" = y ] || exit 1

backup="dev/out/backup-$WHAT-$name-$(date +%Y%m%d-%H%M%S).img"
diskutil unmountDisk "$DISK" >/dev/null
sudo dd if=/dev/r"$DISK" of="$backup" bs=1m skip=$MIB count=$(( (SIZE + 1048575) / 1048576 )) 2>/dev/null
echo "backup of the region: $backup (restore: same command with that file)"
sudo dd if="$FILE" of=/dev/r"$DISK" bs=1m seek=$MIB conv=notrunc
sync
want=$(shasum -a 256 "$FILE" | cut -d' ' -f1)
have=$(sudo dd if=/dev/r"$DISK" bs=512 skip=$((MIB * 2048)) count=$((SIZE / 512)) 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
echo "file: $want"; echo "card: $have"
[ "$want" = "$have" ] && echo MATCH || { echo MISMATCH; exit 1; }
diskutil eject "$DISK" >/dev/null && echo "ejected"
