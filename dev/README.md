# Partial builds and deploys (fork only)

A full image (kernel + Buildroot + image) takes 1-2 hours and is only needed for a new card. Almost every change only needs one piece rebuilt and copied to the console. `dev/gl` does each piece. It works in a Debian container (Docker or Colima, native on Intel and Apple Silicon), or directly on a Debian/WSL that has the packages from `dev/Dockerfile`.

| Changed | Build | Put on the console |
| --- | --- | --- |
| `rootfs/package/{puppy,system-settings,are-you-sure,resize-home}/*.cpp`, `common/*.h` | `dev/gl app system-settings` (seconds) | `dev/gl deploy` → HOME → `tar -xzf` |
| A file in `rootfs/board/my-device/rootfs-overlay/` | nothing | `dev/gl deploy etc/init.d/S30usb-gadget ...` → HOME → `tar -xzf` |
| The Mesa patch (`rootfs/board/my-device/patches/mesa3d`) | `dev/gl rootfs mesa3d-rebuild` (see below) | `libgallium-*.so` → HOME → `cp` to `/usr/lib` |
| Kernel, DTS, kernel patches | `dev/gl kernel` (~5 min after the first) | `android_boot_a33.img` → HOME → `dd` at sector 172032 |
| Buildroot config, new packages | `dev/gl rootfs` | `dev/gl ext4` → card reader → `dev/sdcard-mac.sh` |
| A UI change you want to see | `dev/gl shot system-settings overlay "Down Return \|"` | (no console needed) |

The console needs the real binary built for armhf. `dev/gl app` also builds a native one (`dev/out/<app>.aarch64` on a Mac, `.x86_64` on a PC) for screenshots in Xvfb.

## Setup on macOS (Apple Silicon)

```sh
brew install colima docker docker-buildx libmtp
colima start --arch aarch64 --vm-type vz --mount-type virtiofs --cpu 4 --memory 5 --disk 100
pip3 install pyserial
dev/gl image          # the dev container, ~10 min once
```

- `--arch aarch64` keeps everything native. Never use `--platform linux/amd64` or an x86 Colima: under emulation Buildroot takes many hours.
- 8 GB of RAM: give Colima 5 GB, and if Buildroot gets killed (OOM) run it with `GL_JOBS=2`.
- Colima's disk holds the `goodluck-work` volume (Buildroot ~15 GB, the kernel tree ~3 GB, downloads). After a restart, `colima start` brings the volume back.

## Commands

```sh
dev/gl app system-settings puppy        # dev/out/<app>.armhf and dev/out/<app>.<native arch>
dev/gl deploy etc/profile.d/gallium_hud.sh usr/share/goodluck/lang/pt-BR.lang
                                        # dev/out/deploy.tar.gz: built apps in usr/bin + these overlay files
dev/gl shot system-settings overlay "Down Down Down Return |"
                                        # dev/out/shots/overlay-1.png (keys are xdotool names)
dev/gl scenes dev/out/scenes-before     # one launcher screenshot per line of dev/scenes/scenes.txt
dev/gl scenes-diff dev/out/scenes-before dev/out/scenes-after
                                        # the scenes that changed, pixel by pixel
dev/gl rootfs                           # first time: full Buildroot (1-2 h on an M1)
dev/gl rootfs system-settings-rebuild   # then: one package, seconds; output in the work volume
dev/gl ext4                             # dev/out/rootfs.ext4 from dev/out/rootfs.tar
dev/gl kernel                           # dev/out/android_boot_a33.img
dev/gl shell                            # a shell in the container (/repo, /work)
```

`dev/gl scenes` checks that a change to Puppy draws what it drew before (or shows exactly what it changed). The fake games of `dev/scenes/games.txt` get generated covers. A shim (`dev/scenes/shim.c`) freezes the clock and fakes the mixer, and a mount namespace gives each scene an empty HOME and a fake battery. Two runs of the same code give the same pixels. Run it before a refactor and again after, then diff the two runs. The scenes are not for the README: those screenshots need real covers.

Buildroot runs with its tree in the `goodluck-work` volume, not in the repo. A macOS folder is case-insensitive (the kernel headers have files that differ only in case) and slow through virtiofs. `dev/gl rootfs` copies `rootfs/{board,configs,package}` in on each run, then runs `make` with whatever targets you pass. Things to know:

- Buildroot does not notice changes in local packages (`puppy`, `system-settings`...). Pass `<pkg>-rebuild`, then `all` (or nothing) to remake `rootfs.tar`.
- Mesa: `mesa3d-rebuild` does not apply the patch again. To change the patch, either `mesa3d-dirclean mesa3d` (slow) or edit `out/build/mesa3d-*/src/gallium/auxiliary/hud/hud_context.c` in `dev/gl shell`, `make mesa3d-rebuild`, and regenerate the patch with `diff -u` against a copy you reverted with `patch -R`. The library to copy is `/work/br/out/target/usr/lib/libgallium-<version>.so` (16 MB).
- The defconfig is only applied again when `rootfs/configs/goodluck_defconfig` changed.

## Getting files onto the console

The console's USB-C data port is a composite gadget: a serial shell (ACM, `ttyGS0`, root/root) and MTP (HOME, like a phone).

**HOME (fast):** copy the file to HOME, then install it from the serial shell.
- MTP: `mtp-files` lists, `mtp-sendfile dev/out/deploy.tar.gz deploy.tar.gz` sends (~10 MB/s). If macOS grabs the device first, run `killall ptpcamerad`. OpenMTP (a GUI) also works.
- Card reader: HOME is FAT and mounts as `/Volumes/HOME` (40-80 MB/s). Eject before putting the card back.

**Serial (small files, commands):** `dev/glserial.py` finds the port (`/dev/cu.usbmodem*` on a Mac, `COMn` on Windows):

```sh
dev/glserial.py cmd "tar -xzf /home/player/deploy.tar.gz -C / && rm /home/player/deploy.tar.gz && sync"
dev/glserial.py cmd "cp /home/player/libgallium-26.1.8.so /usr/lib/ && sync"
dev/glserial.py cmd "dd if=/home/player/android_boot_a33.img of=/dev/mmcblk0 bs=512 seek=172032 conv=fsync"
dev/glserial.py send dev/out/are-you-sure.armhf /usr/bin/are-you-sure   # ~1-2 min per 650 KB
dev/glserial.py get /home/player/logs/templog.csv templog.csv
dev/glserial.py get --cmd "dmesg" dmesg.txt
```

Then reboot (`reboot`), or close and reopen the app. The rootfs is mounted read-write. The console has no `pkill`/`pgrep`: use `ps | grep`, `awk` and `kill`.

**The whole rootfs or the kernel with the card in the reader:** `dev/sdcard-mac.sh <diskN> boot|rootfs <file>` writes only that region. It backs the region up first and checks the write by reading it back. It refuses the daily card unless you pass `--daily-card`. Before writing a new rootfs to a card with an older HOME, check what the new rootfs expects in HOME (e.g. appd needs `HOME/.local/launcher.sh`).

## Console screenshots

`dev/drmshot.c` reads the screen even while a KMS game runs. Build it with `arm-linux-gnueabihf-gcc -O2 -I/usr/arm-linux-gnueabihf/include/drm dev/drmshot.c -o dev/out/drmshot` in `dev/gl shell` and send it to `/tmp`. Then run `/tmp/drmshot /dev/dri/card1 > /tmp/shot.ppm` (card1 is the panel, card0 is lima) and bring the file back with `glserial.py get`.
