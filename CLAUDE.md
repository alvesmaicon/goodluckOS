# goodluckOS fork: notes for Claude

This is **alvesmaicon/goodluckOS**, a personal fork of **CodeZombie/goodluckOS** (author: Jeremy). It adds features and fixes for one console, a **GA36-MB v1.1 (Allwinner A33)** R36S clone. Fixes go upstream as small PRs; the rest stays here. Discussion [#3](https://github.com/alvesmaicon/goodluckOS/discussions/3) lists what is ahead of upstream and the state of each change. It is edited on GitHub, not in the repo.

## Building: never the full image for a small change

A full image takes 1-2 hours and is only needed for a new card. Use `dev/gl` (see `dev/README.md`):

- Puppy, the launcher with System Settings in it (`rootfs/package/puppy/src/`): `dev/gl app puppy`, a few seconds.
- Overlay files (`rootfs/board/my-device/rootfs-overlay/...`): no build, just `dev/gl deploy <paths>`.
- Mesa patch: `dev/gl rootfs mesa3d-rebuild`, then copy `libgallium-*.so`.
- Kernel/DTS: `dev/gl kernel`, then write `android_boot_a33.img` at sector 172032.
- Luanti (`feat/luanti*`): `dev/gl luanti-pkg <commit>`, then `dev/luanti-console.sh send <card> <package>` runs Update Luanti on the console.
- UI check without the console: `dev/gl shot puppy <name> "<keys> |"`, then look at the PNG.
- Regression check: `dev/gl scenes <dir>` before and after a change, then `dev/gl scenes-diff <dir> <dir>` (pixel for pixel, `dev/scenes/scenes.txt`). Its games are fake; README screenshots need the real covers (the owner's `readme-shots.sh` set).

On the Mac, `dev/gl` runs everything in a native arm64 Debian container (Colima). The upstream `rootfs/start.sh` and `image/build.sh` are not for daily work: the compose file bind-mounts `out/` onto the case-insensitive macOS disk, and `image/Dockerfile` installs `linux-image-amd64` and `qemu-system-x86`, so it only runs on x86 or under slow emulation.

## Workflow rules (from the owner)

- Commit before every deploy to the console. Put the commit and the send in separate steps, and say what is going out and how long it takes. A serial send shows no progress and looks frozen.
- Code comments: few and one line, like Jeremy's code. The reasoning goes in the commit body.
- Any UI change (System Settings, launcher): in the same commit, update the settings tree in `README.md`, retake the affected screenshots in `docs/screenshots/` (interface in English), and add every new `tr("...")` string to `usr/share/goodluck/lang/pt-BR.lang`.
- When something user-visible changes or a PR changes state, give the owner the lines to update in discussion #3 (no commit for it).
- Never bump versions or edit upstream's `CHANGELOG.md`: Jeremy does that.
- Commits that touch a fork issue cite it as `alvesmaicon/goodluckOS#N`, so a cherry-pick upstream doesn't link to the wrong issue.
- A fork-only commit message (CLAUDE.md, `dev/`, merges of upstream) never writes an upstream number as `#N`: GitHub resolves it to CodeZombie and puts the commit on that issue's timeline, where nobody can remove it. Write `upstream PR 70`. Only commits meant for an upstream PR cite upstream issues.
- Upstream PRs: open an issue first, keep each PR small and on a branch from `origin/main` (cherry-picked from `develop`), test the PR's own image on the device. The Co-Authored-By lines in the commits already say that AI was used; the PR text doesn't repeat it. The owner reviews every diff before it goes out.
- Upstream issue or PR comments never link this fork: say the feature is ready and tested on the owner's console, and offer a PR. The owner doesn't want to pull users away from upstream.
- The owner writes in Brazilian Portuguese. Repository text (code, commits, README, PRs) is in English.

## SD cards: be careful

The owner's daily card carries `HOME/.card-name` = `extreme-daily`. Never write an image or a rootfs to it unless the owner explicitly asks for that card. Before any raw write, identify the card: read `.card-name` on the PC, or `cat /sys/block/mmcblk0/device/{name,serial}` on the console. `dev/sdcard-mac.sh` refuses that card unless you pass `--daily-card`.

Card layout (A33):

| Region | Contents |
| --- | --- |
| Sectors `[1, 172032)` | Stock boot0/u-boot/script.bin |
| Stock FAT, 36-68 MB | Contains `bootlogo.bmp`. Not in the MBR, so it is invisible |
| Sector 172032 | `android_boot_a33.img` (zImage + DTB) |
| Partition 1, 128-512 MiB | ext4 `linux` rootfs, mounted rw |
| Partition 2, 512 MiB to the end | FAT `HOME` = `/home/player` (ROMs, configs, saves, `logs/`) |

## Branches and remotes

- `origin` is upstream CodeZombie; `fork` is alvesmaicon. `develop` is the fork's main branch: start new work from it on `feat/*`, `fix/*` or `debug/*`, then merge back. `pr/*` branches start from `origin/main`.
- A branch merged into `develop` is deleted in the same step: `git worktree remove` its worktree, `git branch -d` it, and `git push fork --delete` it if it is on the fork. A `pr/*` branch goes the same way once upstream merges or closes its PR. The commits stay in `develop`, and the merge commit keeps the branch's name. Before removing a worktree, check `git status` there: uncommitted work gets committed or the owner decides.
- Upstream PRs merged: #48 (Jeferson's A/B fix), #52 (MTP HOME), #55 (boot: appctl path, no power-manager respawn), #56 (headphones + FN+DOWN), #59 (TF-2 slot), #60 (idempotent `post-build.sh`), #64 (D-pad hold-to-repeat), #66 (TF-2 card over MTP), #70 (A23 audio), #77 (MTP cancel/rename), #88 (autolaunch at boot). #69 (A23 TF-2 power) was closed: upstream's DTS split already gives both SoCs the supply.
- Upstream PRs open: #89 (charging screen when plugged in while off), #109 (CI: kernel and rootfs workflows, issue #108; branch `pr/ci`, also the fork's `main` on top of upstream's), #119 (battery percentage to 100% at the end of a charge, kernel patches 0006-0009, issue #114; `pr/battery-gauge`), #122 (battery care, issue #121; `pr/battery-care`), #124 (draft: the overlay for issue #24, a leaner Mesa patch than the fork's, two checkboxes in Jeremy's System Settings; `pr/overlay`, test image from `test/overlay-image`). The low battery warning goes upstream after #122 and #124. The learned battery resistance (patch 0010 and battery care's learning) waits for #122, since it changes the same script.
- Audio patches 0011-0016 are in `develop` (15e2260) and on `pr/audio` (from `origin/main`, boot images for both SoCs and panels in its `dev/out/audio-test/`, attached to issue 92): the PR waits for a few days of use and the test on the upstream card.
- Upstream issues that the fork's code already answers: #92/#7/#31 (audio pops, `pr/audio`), #23 (Gallium HUD options, in `develop`), #24 (Mesa overlay), #5 (System Settings), #13/#14 (LED, partly). #46 is the owner's "features from my fork" list.
- `feat/vitrine` holds Jeferson's Vitrine launcher (upstream PR #51), with him as author, plus cc6c44b so it still merges into `origin/main`. It starts from upstream, not `develop`, and is the source for Puppy's modern style, not a branch to merge. Code taken from it keeps Jeferson as author (cherry-pick, or `Co-authored-by: Jeferson Lopes <jefersonftlopes@gmail.com>`), gets a line in Credits, and keeps the OFL files of its fonts.
- Fork issues: #1 screen artifacts (bottom repeats the top; neither the temperature nor the flex explains it, `debug/thermal-log` logs to `HOME/logs/templog.csv`); #2 Wi-Fi dongle on OTG (the board has no OTG boost, the stock firmware gives no 5 V either; host mode works on a powered hub once the PHY takes VBUS as present, test branch `feat/otg-vbus`; Wi-Fi drivers missing); #4 launcher music; #5 headphones reset to volume 0 (fixed in `develop` by patches 0012 and 0014, close after the PR); #8 power cuts under load on battery (gauge, battery care, low battery warning, clean power off at 2 % and Voff 3.0 V in `develop`; next: a full discharge test, then the upstream PR).

## Hardware facts

- The CPU is an A33 (4x Cortex-A7, armv7 hard-float), with a Mali-400 GPU (lima, GLES2 only, GLES1 for some ports) and 512 MB of RAM. Mainline Linux 7.2.
- Display: MIPI DSI JD9366 panel, 640x480 (`kernel/drivers/jd9366-ga36mbv1-2.c`). On the A33, card1 is the panel and card0 is lima.
- DTS: `ga36mb.dtsi` (common) + `ga36mb-<soc>.dtsi` + `panel-<n>.dtsi`, one `ga36mb-<soc>-panel<n>.dts` each. The owner's console is panel 1 (`dev/gl kernel` builds it; `GL_PANEL=2` for the other).
- PMIC: AXP223 over RSB. Battery: `/sys/class/power_supply/axp20x-battery`. Its internal temperature is an IIO device with no `name` file, so find it by its path (`*axp*`). The SoC temperature is `thermal_zone0`. Trip points: passive at 75 °C, hot at 90 °C, critical at 110 °C.
- Audio: ALSA card `GA36mbAudio`, used as `hw:GA36mbAudio`. There is no headphone jack detection in the hardware. Headphones need the HPCOM route, and the speaker has a manual Speaker Switch. FN+DOWN toggles the output (`audio-output.sh`). Patches 0014-0016 keep the headphone amplifier and HPCOM powered from boot, as the vendor driver does (cycling them pops and resets the analog block), mute the amplifier for 50 ms while the DACs power up, and power it down at reboot and power off; a sound starts in ~0.65 s.
- USB-C data port: a configfs gadget with ACM serial (`ttyGS0`, root/root) and, by mode, MTP (umtprd, HOME plus the TF-2 card; `files`, the default) or a CDC NCM network adapter with udhcpc on `usb0` (`network`). `usb-mode.sh get|files|network` switches, the choice lives in `/etc/player-flags/usb-mode`. The A33's MUSB has 5 endpoints each way and the three functions would need 6 IN, so never put MTP and NCM in the same gadget (the bind fails with ENODEV). USB id 1d6b:0104. Without VBUS, `S30usb-gadget` falls back to serial only and won't recover by itself (`usb-mode.sh files` rebuilds it). Its stop/start can hang the gadget or the reboot; closing umtprd unbinds the gadget by itself (FunctionFS). A Mac names a new network adapter only while its screen is unlocked (`echo 'show Plugin:InterfaceNamer' | scutil` lists it under `_Locked_` until then).
- The OTG port supplies no 5 V.
- POWER: in the launcher it opens the power menu; inside an app it only turns the screen off (`toggle-screen.sh`). The RESET button is a hardware reset.
- The bottom of the screen repeating the top of the frame (fork issue #1) is in the hardware, but not the flex: it survives a reboot, shows in the u-boot logo and fades by itself in about 30 minutes, on or off. Reseating the flex only gave it time to fade, and the panel init matches a stock v1.1 dump. Don't chase it in software.

## Known traps

- Buildroot doesn't rebuild local packages on its own: use `<pkg>-rebuild` (or `-dirclean`). `mesa3d-rebuild` doesn't reapply the patch.
- Puppy compiles as C++17 (`puppy.mk`), and `dev/gl app` the same way. Its code: `src/` has the screens (`app` runs a stack of them: launcher, keyboard, dialogs, System Settings, the button tester) and `src/system/` the device and its files, one owner each (mixer, prefs file, HUD file, clock, storage...). Settings code goes through `src/system/`, never straight to a file or a sysfs node.
- `<pkg>-rebuild` doesn't delete a file removed from a local package's source: after deleting or moving sources, run `puppy-dirclean puppy`.
- What Puppy starts in the background dies with it when appd starts an app (cgroup kill): anything that must finish (saving the mixer, a reboot request) runs in the foreground (`runScript(..., true)`).
- `post-build.sh` must stay re-runnable (upstream #60).
- HOME's "Volume was not properly unmounted" on every boot is an old power cut, not the last shutdown: Linux never clears a FAT dirty flag it found at mount, only `fsck.fat -a` does (with HOME unmounted).
- Never leave backups (`*.orig`, `*.bak`) in `/etc/init.d`: rcS/rcK run every `S??*` file there.
- A new rootfs on a card with an older HOME: appd needs `HOME/.local/launcher.sh` (contains `/usr/bin/puppy`). Without it the console hangs at "Starting system...".
- Serial: ~40 KB/s (a 6 MB kernel in ~2.5 min); `glserial.py send` prints a line every 10 % with the time left. Run long sends under Monitor so the owner sees them move. A running binary can't be overwritten ("Text file busy"): send to `/tmp` and `mv`. After a cable reconnect the console sits at a login prompt (`dev/glserial.py` logs in). The console has no `pkill`/`pgrep`. `/tmp` and `/var/log` are lost on reboot (the blackbox in `/var/lib/blackbox` keeps the kernel log).
- Git Bash on Windows rewrites `/tmp/...` arguments into Windows paths: set `MSYS_NO_PATHCONV=1`.
- MTP is ~10 MB/s; the card reader is 40-80 MB/s. Use the reader for big copies (ROMs).
- The overlay over games is the Gallium HUD patched in Mesa (`rootfs/board/my-device/patches/mesa3d`): a feedback panel (`/dev/shm/hud-osd`) and a status bar (`GALLIUM_HUD_STATUS`, set by `etc/profile.d/gallium_hud.sh`). FN+UP sends signal 34 to the running app.
- Autolaunch: `appctl` starts `HOME/autolaunch` once per boot (the first line not starting with `#`); Puppy only writes that file (SELECT). On a new HOME it holds upstream's `glos-setup` (first-boot welcome and headphone warning), which deletes the file when it ends.
- The fork's Puppy reads `gamelist.xml` (names, descriptions, images). Upstream's Puppy only shows `icons/<game name>.png`.
- Upstream `main` has no time zone setting and shows UTC. The fork has Date & Time. The owner is in Brazil (UTC-3).
- Emulation limits on this hardware: no viable N64/NDS/Dreamcast core (parallel-n64 runs, badly). Half-Life 1 (Xash3D, gles1) and the native SM64 port run well.
