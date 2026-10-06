# Fork changelog

What this fork ([alvesmaicon/goodluckOS](https://github.com/alvesmaicon/goodluckOS), branch `develop`) adds on top of [CodeZombie/goodluckOS](https://github.com/CodeZombie/goodluckOS) `main`, and where each change stands on its way upstream.

> [!IMPORTANT]
> **This is not a goodluckOS distribution.** For goodluckOS, use the official project: [CodeZombie/goodluckOS](https://github.com/CodeZombie/goodluckOS).
>
> This fork is my personal workspace. I use it to improve my own console (a GA36-MB v1.1, A33) and to prepare contributions, which I offer upstream as small pull requests, only the ones Jeremy wants. It is not meant to compete with goodluckOS or to be installed by anyone else: there are no releases or images here, and none are planned. Everything in it was written with an AI coding assistant (Claude Code), has only run on my device, and is still being reviewed.

Status:

- **Merged upstream**: in CodeZombie/goodluckOS `main`.
- **Waiting for a PR**: done and tested here; the pull request isn't open yet. Changes go upstream as small, separate PRs, only if Jeremy wants them.
- **PR open**: the pull request is waiting for review.
- **Fork only**: not meant for upstream.
- **Planned**: not started yet.

## Merged upstream

- Shutdown and reboot no longer hang when no USB cable is plugged in.
- Power off works: the AXP223 is the system power controller.
- HOME shows up on the PC over USB (MTP), like a phone, with a kernel fix for USB copies that hung ([#52](https://github.com/CodeZombie/goodluckOS/pull/52)).
- SELECT+START closes the active app and FN+SELECT+START kills it: Jeremy built it into appctl from this idea.
- Headphones play on both sides, and FN+D-pad down switches between the speaker and the headphones ([#56](https://github.com/CodeZombie/goodluckOS/pull/56), fixes [#7](https://github.com/CodeZombie/goodluckOS/issues/7)).
- Boot on upstream main: the launcher starts again (appctl's full path) and init no longer respawns the removed power-manager.sh ([#55](https://github.com/CodeZombie/goodluckOS/pull/55), [#54](https://github.com/CodeZombie/goodluckOS/issues/54)).

## PR open

- The second SD card (TF-2 slot) works and its games show up in the launcher ([#59](https://github.com/CodeZombie/goodluckOS/pull/59), fixes [#15](https://github.com/CodeZombie/goodluckOS/issues/15)).
- `post-build.sh` can run again on the same target, so incremental builds don't fail ([#60](https://github.com/CodeZombie/goodluckOS/pull/60)).

## Waiting for a PR: fixes

- Shutting down or restarting with the USB cable in no longer hangs on the USB teardown: every step that can block has a timeout, and MTP is waited for before it's taken down.
- RetroArch FN hotkeys: menu, save/load state, fast forward, pause, quit. (The A/B and Select/Start mapping went upstream through [#48](https://github.com/CodeZombie/goodluckOS/pull/48).)
- System Settings: the brightness shows its real level, the volume slider works, and both are saved on change.
- Brightness, volume and CPU mode are kept across reboots.
- Silent boot, with "Starting system...", "Restarting..." and "Shutting down..." on screen.
- The image build no longer starts two power managers, and incremental builds work.
- Resize Home mounts HOME again with its fstab options, so it stays owned by the player instead of root until the next boot.
- Launcher: Game Boy entries, and zip/7z games.
- FN+D-pad up's FPS/CPU overlay (Gallium HUD) is configurable: content, graph or text, corner, shown on game start ([#23](https://github.com/CodeZombie/goodluckOS/issues/23)).

- After upstream's move to appd/appctl, a few things lost their target; fixed here, to offer upstream:
  - the autolaunch entry runs again at boot (nothing read `/home/player/autolaunch` once puppy-bootstrap.sh was gone);
  - FN+D-pad up's FPS overlay finds the running app through appd's cgroup, and signals only the processes that catch it;
  - the POWER key turns the screen off in game again;
  - `exit-active-process.sh` and `kill-active-process.sh` call appctl (S99appd doesn't accept stop-application).

## Waiting for a PR: hardware

- The speaker gets a 500 Hz high-pass filter, so it stays clean instead of buzzing on bass. There's also no more digital clipping.

- **Second SD card (TF-2 slot):** the slot had no power supply in the device tree, so the kernel turned cards down; it now works and is polled, so cards can come and go. A FAT32 card there is mounted at `/media/external` and its `roms/<system>` folders are listed in every system's tab, plus an External Card tab (fork only). PR [#59](https://github.com/CodeZombie/goodluckOS/pull/59) has the part for upstream.

## Waiting for a PR: interface

These are bigger and will be proposed in an issue first.

- **Launcher (Puppy) redesign:**
  - tabs per system, plus All Games and My List (favourites), and you choose which tabs show;
  - grid and list views, and search with an on-screen keyboard;
  - names, descriptions and covers from `gamelist.xml`;
  - game options: rename, move to trash;
  - power and START menus, analog sticks;
  - button hints in the bottom bar;
  - a top bar with the date and time, the volume and the battery.
- **System Settings redesign:**
  - a menu of sections: Display & Audio, Launcher, Interface, Overlay, Date & Time, Storage, System, Input Settings;
  - level-bar sliders;
  - a shortcut list and a button tester;
  - Restore default settings.
- **Translations:** every text can be translated, and Brazilian Portuguese is included.
- **Interface font option:** Inter, ProggyClean, VT323, Pixelify Sans.
- **Overlay over every game, drawn by a patch to Mesa's Gallium HUD** ([#24](https://github.com/CodeZombie/goodluckOS/issues/24)):
  - the volume, brightness and audio output feedback;
  - an optional status bar with the date, the time, the battery and the volume and output, each one on or off.

  RetroArch's own notifications, menu clock and battery, and PCSX-ReARMed's FPS counter, are turned off, so nothing overlaps.
- **Power mode:** Battery saver, Balanced (the default) or Performance, in System Settings > System. Each one sets the CPU governor and top speed and the GPU speed range, and it is kept across reboots. It replaces the Performance mode checkbox.
- **Date and time:**
  - set from System Settings, and kept by the clock chip while the console is off;
  - time zone, 12/24-hour and the date format.
- **Music and video player:**
  - mpv (a Buildroot package), full screen through DRM/KMS, with the console's buttons: A or START pause, B quit, left/right seek 10 s, up/down 1 min, L1/R1 previous/next, X the playlist, Y repeat, L2/R2 the audio/subtitle track;
  - Music and Videos tabs in the launcher for `HOME/media/music` and `HOME/media/videos`, left out of All Games. A folder (an album, a series) is one entry that plays whole, with its `cover.jpg` as the art; a single file plays along with the rest of its folder;
  - songs show the artist, the title, the time and the position in the playlist;
  - the A33 decodes in software: 640x480 H.264 plays smoothly (tested with a full-screen music video and a film), 1080p and H.265 don't. The README has the ffmpeg line to convert bigger videos.

## Planned

- **Launcher themes and options:**
  - a Retro theme (today's look, in the EmulationStation style) and a Modern one (the game's art in the background, rounded cards, button hints drawn like the console's buttons), picked in System Settings;
  - the on-screen keyboard's layout as a setting: QWERTY (default) or ABC;
  - later, the launcher on its own name and package, next to Puppy, so upstream merges stop touching it.
- **Battery:** time left next to the level, and a low-battery warning in game (and maybe save and quit when it's about to run out).

## Fork only

- The console shows up on the PC as "goodluckOS" instead of "GA36MB", the board's code: the system's name is right on every console it runs on.
- The fork follows upstream's appd/appctl and doas: power-manager.sh is gone, and the launcher, System Settings and the power menu run their root actions through doas.
- System Settings > Interface > Show Puppy on loading screens: on by default (the ASCII-art dog, as upstream); off shows a translated "Loading..." instead.
- Restart and Shut down leave "Restarting..." / "Shutting down..." on the screen until the console goes off (since appd, the loading screen stayed there instead).
- README notes about this fork and the AI-assisted workflow.
