# Fork changelog

What this fork ([alvesmaicon/goodluckOS](https://github.com/alvesmaicon/goodluckOS), branch `develop`) adds on top of [CodeZombie/goodluckOS](https://github.com/CodeZombie/goodluckOS) `main`, and where each change stands on its way upstream.

> [!WARNING]
> **Everything here is under review and testing.** Most of it has only run on one GA36-MB v1.1 (A33), and none of it is part of an official goodluckOS release. It was written with an AI coding assistant and is still being reviewed line by line.
>
> If you want to try this early version, go ahead, **at your own risk**. There is no prebuilt image: build it from `develop` (see [BUILD.md](BUILD.md)), and back up your whole SD card first. Report problems on this fork, not upstream.

Status:

- **Merged upstream**: in CodeZombie/goodluckOS `main`.
- **Waiting for a PR**: done and tested here; the pull request isn't open yet. Changes go upstream as small, separate PRs, in the order below.
- **Fork only**: not meant for upstream.

## Merged upstream

- Shutdown and reboot no longer hang when no USB cable is plugged in.
- Power off works: the AXP223 is the system power controller.

## Waiting for a PR: fixes

- RetroArch: A/B and Select/Start mapped right on the GA36-MB gamepad, and FN hotkeys (menu, save/load state, fast forward, pause, quit).
- System Settings: the brightness shows its real level, the volume slider works, and both are saved on change.
- Brightness, volume and CPU mode are kept across reboots.
- SELECT+START closes the active app cleanly (RetroArch saves first).
- Silent boot, with "Starting system...", "Restarting..." and "Shutting down..." on screen.
- The image build no longer starts two power managers, and incremental builds work.
- Launcher: Game Boy entries, and zip/7z games.
- FN+D-pad up's FPS/CPU overlay (Gallium HUD) is configurable: content, graph or text, corner, shown on game start ([#23](https://github.com/CodeZombie/goodluckOS/issues/23)).

## Waiting for a PR: hardware

- HOME shows up on the PC over USB (MTP), like a phone, with a kernel fix for USB copies that hung. The serial console stays available.
- Headphones play on both sides, and FN+D-pad down switches the sound between the speaker and the headphones only. There's no automatic jack detection on this board ([#7](https://github.com/CodeZombie/goodluckOS/issues/7)).
- The speaker gets a 500 Hz high-pass filter, so it stays clean instead of buzzing on bass. There's also no more digital clipping.

## Waiting for a PR: interface

These are bigger and will be proposed in an issue first.

- **Launcher (Puppy) redesign:**
  - tabs per system, plus All Games and My List (favourites), and you choose which tabs show;
  - grid and list views, and search with an on-screen keyboard;
  - names, descriptions and covers from `gamelist.xml`;
  - game options: rename, move to trash;
  - power and START menus, analog sticks;
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
  - an optional status bar with the date and time, the battery, the volume and the output.

  RetroArch's own notifications, menu clock and battery are turned off, so nothing overlaps.
- **Date and time:**
  - set from System Settings, and kept by the clock chip while the console is off;
  - time zone, 12/24-hour and the date format.

## Fork only

- README notes about this fork and the AI-assisted workflow.
