#!/bin/sh
# Mounts the TF-2 card's first FAT partition at /media/external (udev, 90-external-card.rules)
M=/media/external
case "$1" in
    add)
        mountpoint -q "$M" && exit 0
        blkid "/dev/$2" | grep -q 'TYPE="vfat"' || exit 0
        mkdir -p "$M"
        mount -t vfat -o rw,noatime,uid=1000,gid=1000,umask=022 "/dev/$2" "$M"
        ;;
    remove)
        grep -q "^/dev/$2 " /proc/mounts && umount -l "$M"
        ;;
esac
exit 0
