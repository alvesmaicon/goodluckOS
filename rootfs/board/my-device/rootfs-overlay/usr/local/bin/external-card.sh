#!/bin/sh
# Mounts the TF-2 card's first FAT partition at /media/external (udev, 90-external-card.rules)
M=/media/external
case "$1" in
    add)
        mountpoint -q "$M" && exit 0
        blkid "/dev/$2" | grep -q 'TYPE="vfat"' || exit 0
        mkdir -p "$M"
        mount -t vfat -o rw,noatime,uid=1000,gid=1000,umask=022 "/dev/$2" "$M" || exit 0
        # a card without roms/ gets the same system folders as HOME
        if [ ! -d "$M/roms" ]; then
            for d in nes snes gba gbc gb psx genesis sms gg segacd; do mkdir -p "$M/roms/$d/icons"; done
            mkdir -p "$M/media/music" "$M/media/videos"
        fi
        ;;
    remove)
        grep -q "^/dev/$2 " /proc/mounts && umount -l "$M"
        ;;
esac
exit 0
