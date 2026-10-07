# goodluckOS fork: notes for Claude

This is **alvesmaicon/goodluckOS**, a personal fork of **CodeZombie/goodluckOS** (author: Jeremy). It adds features and fixes for one console, a **GA36-MB v1.1 (Allwinner A33)** R36S clone. Fixes go upstream as small PRs; the rest stays here. `FORK-CHANGELOG.md` lists what is ahead of upstream and the state of each change.

## Building: never the full image for a small change

A full image takes 1-2 hours and is only needed for a new card. Use `dev/gl` (see `dev/README.md`):

- C++ app (`puppy`, `system-settings`, `are-you-sure`, `resize-home`): `dev/gl app <name>`, a few seconds.
- Overlay files (`rootfs/board/my-device/rootfs-overlay/...`): no build, just `dev/gl deploy <paths>`.
- Mesa patch: `dev/gl rootfs mesa3d-rebuild`, then copy `libgallium-*.so`.
- Kernel/DTS: `dev/gl kernel`, then write `android_boot_a33.img` at sector 172032.
- UI check without the console: `dev/gl shot <app> <name> "<keys> |"`, then look at the PNG.

On the Mac, `dev/gl` runs everything in a native arm64 Debian container (Colima). The upstream `rootfs/start.sh` and `image/build.sh` are not for daily work: the compose file bind-mounts `out/` onto the case-insensitive macOS disk, and `image/Dockerfile` installs `linux-image-amd64` and `qemu-system-x86`, so it only runs on x86 or under slow emulation.

## Workflow rules (from the owner)

- Commit before every deploy to the console. Put the commit and the send in separate steps, and say what is going out and how long it takes. A serial send shows no progress and looks frozen.
- Code comments: few and one line, like Jeremy's code. The reasoning goes in the commit body.
- Any UI change (System Settings, launcher): in the same commit, update the settings tree in `README.md`, retake the affected screenshots in `docs/screenshots/` (interface in English), and add every new `tr("...")` string to `usr/share/goodluck/lang/pt-BR.lang`.
- Update `FORK-CHANGELOG.md` when something user-visible changes or a PR changes state.
- Never bump versions or edit upstream's `CHANGELOG.md`: Jeremy does that.
- Commits that touch a fork issue cite it as `alvesmaicon/goodluckOS#N`, so a cherry-pick upstream doesn't link to the wrong issue.
- Upstream PRs: open an issue first, keep each PR small and on a branch from `origin/main` (cherry-picked from `develop`), test the PR's own image on the device, and say that AI was used. The owner reviews every diff before it goes out.
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
- Upstream PRs merged: #48 (Jeferson's A/B fix), #52 (MTP HOME), #55 (boot: appctl path, no power-manager respawn), #56 (headphones + FN+DOWN), #60 (idempotent `post-build.sh`). Open: #59 (TF-2 slot, draft). `pr/external-mtp` waits on #59 (rebase, then open).
- Upstream issues that the fork's code already answers: #23 (Gallium HUD options, branch `feat/overlay` ready), #24 (Mesa overlay), #5 (System Settings), #13/#14 (LED, partly). #46 is the owner's "features from my fork" list.
- Fork issues: #1 screen artifacts (thermal suspected, `debug/thermal-log` logs to `HOME/logs/templog.csv`); #2 Wi-Fi dongle on OTG (no VBUS: DTS lacks `x-powers,drive-vbus-en` and `usb0_vbus-supply`).

## Hardware facts

- The CPU is an A33 (4x Cortex-A7, armv7 hard-float), with a Mali-400 GPU (lima, GLES2 only, GLES1 for some ports) and 512 MB of RAM. Mainline Linux 7.2.
- Display: MIPI DSI JD9366 panel, 640x480 (`kernel/drivers/jd9366-ga36mbv1-2.c`). On the A33, card1 is the panel and card0 is lima.
- PMIC: AXP223 over RSB. Battery: `/sys/class/power_supply/axp20x-battery`. Its internal temperature is an IIO device with no `name` file, so find it by its path (`*axp*`). The SoC temperature is `thermal_zone0`. Trip points: passive at 75 °C, hot at 90 °C, critical at 110 °C.
- Audio: ALSA card `GA36mbAudio`, used as `hw:GA36mbAudio`. There is no headphone jack detection in the hardware. Headphones need the HPCOM route, and the speaker has a manual Speaker Switch. FN+DOWN toggles the output (`audio-output.sh`).
- USB-C data port: a configfs gadget with ACM serial (`ttyGS0`, root/root) and MTP (umtprd, HOME plus the TF-2 card). USB id 1d6b:0104. Without VBUS, `S30usb-gadget` falls back to serial only and won't recover by itself (`S30usb-gadget stop; sleep 1; S30usb-gadget start`). Its stop/start can hang the gadget or the reboot.
- The OTG port supplies no 5 V.
- POWER: in the launcher it opens the power menu; inside an app it only turns the screen off (`toggle-screen.sh`). The RESET button is a hardware reset.
- The bottom of the screen repeating the top of the frame, even in the u-boot logo, is physical: a fold in the display flex under L2. Reseating the flex fixes it. Don't chase it in software. Issue #1 is a different symptom (ghosting/shifted bars).

## Known traps

- Buildroot doesn't rebuild local packages on its own: use `<pkg>-rebuild` (or `-dirclean`). `mesa3d-rebuild` doesn't reapply the patch.
- The ImGui apps compile as C++11 in Buildroot (`std::clamp` broke a build); Puppy as C++17. `dev/gl app` uses the same standards and ImGui version (`rootfs/package/imgui/imgui.mk`).
- `post-build.sh` must stay re-runnable (upstream #60).
- Never leave backups (`*.orig`, `*.bak`) in `/etc/init.d`: rcS/rcK run every `S??*` file there.
- A new rootfs on a card with an older HOME: appd needs `HOME/.local/launcher.sh` (contains `/usr/bin/puppy`). Without it the console hangs at "Starting system...".
- Serial: ~10 KB/s. After a cable reconnect the console sits at a login prompt (`dev/glserial.py` logs in). The console has no `pkill`/`pgrep`. `/tmp` is lost on reboot.
- Git Bash on Windows rewrites `/tmp/...` arguments into Windows paths: set `MSYS_NO_PATHCONV=1`.
- MTP is ~10 MB/s; the card reader is 40-80 MB/s. Use the reader for big copies (ROMs).
- The overlay over games is the Gallium HUD patched in Mesa (`rootfs/board/my-device/patches/mesa3d`): a feedback panel (`/dev/shm/hud-osd`) and a status bar (`GALLIUM_HUD_STATUS`, set by `etc/profile.d/gallium_hud.sh`). FN+UP sends signal 34 to the running app.
- The fork's Puppy reads `gamelist.xml` (names, descriptions, images). Upstream's Puppy only shows `icons/<game name>.png`.
- Upstream `main` has no time zone setting and shows UTC. The fork has Date & Time. The owner is in Brazil (UTC-3).
- Emulation limits on this hardware: no viable N64/NDS/Dreamcast core (parallel-n64 runs, badly). Half-Life 1 (Xash3D, gles1) and the native SM64 port run well.
