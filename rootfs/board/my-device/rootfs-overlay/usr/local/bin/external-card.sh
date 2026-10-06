#!/bin/sh
# The TF-2 card: its largest FAT partition at /media/external
#   add / remove   from udev (90-external-card.rules)
#   detect         look for a card again: rebinds the slot's controller (System Settings)
#   eject          unmount and power the slot down, so the card can come out (System Settings)
#   mtp            show a mounted card on the PC too (S30usb-gadget, once umtprd is up)
M=/media/external
L=/run/external-card.lock
SLOT=1c10000.mmc
DRV=/sys/bus/platform/drivers/sunxi-mmc

# Shows or hides the card on the PC (MTP). Only while umtprd runs: started by -cmd, it'd become the daemon
mtp() {
    [ -f /run/umtprd.pid ] && kill -0 "$(cat /run/umtprd.pid)" 2>/dev/null && umtprd "-cmd:$1:External card" >/dev/null 2>&1
}

unmount() {
    mountpoint -q "$M" && mtp unmount
    sync
    while mountpoint -q "$M"; do umount "$M" 2>/dev/null || umount -l "$M"; done
}

# udev runs one copy per partition at once: take turns
n=0
until mkdir "$L" 2>/dev/null; do n=$((n + 1)); [ $n -ge 30 ] && break; sleep 1; done
trap 'rmdir "$L"' EXIT

case "$1" in
    add)
        # already mounted and readable; a mount left from a card that came out isn't
        mountpoint -q "$M" && df "$M" >/dev/null 2>&1 && exit 0
        while mountpoint -q "$M"; do umount -l "$M"; done
        best=""; size=0
        for p in /sys/block/mmcblk1/mmcblk1p*; do
            d=${p##*/}; s=$(cat "$p/size")
            blkid "/dev/$d" | grep -q 'TYPE="vfat"' && [ "$s" -gt "$size" ] && { best=$d; size=$s; }
        done
        [ -n "$best" ] || exit 0
        mkdir -p "$M"
        mount -t vfat -o rw,noatime,uid=1000,gid=1000,umask=022 "/dev/$best" "$M" || exit 0
        # a card without roms/ gets the same system folders as HOME
        if [ ! -d "$M/roms" ]; then
            for d in nes snes gba gbc gb psx genesis sms gg segacd; do mkdir -p "$M/roms/$d/icons"; done
            mkdir -p "$M/media/music" "$M/media/videos"
        fi
        mtp mount
        ;;
    remove)
        unmount
        ;;
    detect)
        [ -e "$DRV/$SLOT" ] && echo "$SLOT" > "$DRV/unbind"
        sleep 1
        echo "$SLOT" > "$DRV/bind"
        ;;
    mtp)
        mountpoint -q "$M" && mtp mount
        ;;
    eject)
        unmount
        [ -e "$DRV/$SLOT" ] && echo "$SLOT" > "$DRV/unbind"
        ;;
esac
exit 0
