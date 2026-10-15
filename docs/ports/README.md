# Ports

Games that run natively on the console, not in an emulator: PC versions built for its 32-bit ARM CPU and its OpenGL ES 2 GPU. Apart from Luanti, none of them comes with its game: you supply your own copy (the game's files or the cartridge's ROM), and nothing from the games is in this repository.

All four are work in progress, each on its own branch, and have only run on my console (GA36-MB, A33, 512 MB of RAM). The screenshots are from it.

| Game | Built on | You supply | On the A33 | Branch |
| --- | --- | --- | --- | --- |
| [Luanti](#luanti) | Luanti 5.17, Minetest Game | nothing | 20 FPS in a forest, 10 over a lake | `feat/luanti` |
| [Stardew Valley](#stardew-valley) | Mono, MonoGame, gl4es | the game, from Steam | about 19 FPS on the farm | `feat/stardew` |
| [Ocarina of Time](#ocarina-of-time) | Ship of Harkinian 9.3.0 | your ROM | 20 FPS, as on the N64 | `feat/zelda` |
| [Majora's Mask](#majoras-mask) | 2 Ship 2 Harkinian 5.0.1 | your ROM | not measured yet | `feat/zelda` |

## Installing a port

A port is a folder in `HOME/ports/` and an entry in `HOME/apps.puppy`, which puts it in the launcher's Games tab. The launcher reads `apps.puppy` when it starts, so restart the console after editing it.

There are no downloads: the games can't be shared, and this fork has no releases. Each port is built on a PC from its branch, in the dev container of [dev/README.md](../../dev/README.md) (Docker, on Intel or Apple Silicon; `dev/gl image` once). The result holds your game's files, so it is for your own console only.

The examples copy to the card in a card reader on a Mac (`/Volumes/HOME`). MTP works too, at ~10 MB/s. Before ejecting, `dot_clean /Volumes/HOME` removes the `._` files macOS leaves on FAT.

## Luanti

![Luanti on the console: a lake, with the far shore in view](luanti.png)

Luanti is an open-source engine for Minecraft-like games, and Minetest Game, its classic game, is free. Patches fit it to the Mali-400 and 512 MB (far terrain from simplified meshes, a fog fix for 16-bit shaders), and mods bring it closer to classic Minecraft: Survival or Creative, hunger, monsters, armor, a crafting table. At 640x480: 20 FPS in a forest, 10 to 11 looking across a lake, capped at 30.

**Install:** Luanti is part of the system image (a Buildroot package), so there is nothing to copy. Build the rootfs from `feat/luanti` and write it to the card (`dev/gl rootfs`, `dev/gl ext4`, `dev/sdcard-mac.sh`, see [dev/README.md](../../dev/README.md)), and it shows up in the Games tab. Worlds and settings are kept in `HOME/.minetest`. The controls are in that branch's README.

## Stardew Valley

![Stardew Valley on the console: the farm on a rainy morning](stardew-valley.png)

The PC build from Steam's "compatibility" branch (1.6.15) is a .NET Framework program, so it runs on Mono, built here for 32-bit ARM. PortMaster's port supplies the rest: JohnnyonFlame's MonoGame, which streams the music from the card instead of RAM, and gl4es, which turns the game's OpenGL into OpenGL ES 2. Our patches cut work the game repeats every frame, and the save serializers are generated ahead of time. About 19 FPS on the farm, the title screen in ~25 s, a save loaded in ~75 s.

**You supply:** Stardew Valley on Steam, switched to the compatibility branch (Properties > Betas > compatibility), in its macOS or Linux version (the one with `StardewValley.exe`). Tested with the macOS one.

**Build and install** (`SDV_GAME` is the game's folder; Steam's on a Mac is the default):

```sh
git checkout feat/stardew
dev/stardew/build.sh          # the port in dev/out/stardew/stardewvalley, its patches built against your game
dev/stardew/build.sh game     # your game's files in dev/out/stardew/gamedata
dev/stardew/build.sh xmlgen   # the save serializers, into gamedata
mkdir -p /Volumes/HOME/ports
cp -R dev/out/stardew/stardewvalley /Volumes/HOME/ports/
cp -R dev/out/stardew/gamedata/. /Volumes/HOME/ports/stardewvalley/gamedata/
```

Add to `HOME/apps.puppy`:

```ini
[ENTRY]
CATEGORY=Games
NAME=Stardew Valley
DESCRIPTION=Your own game files, compatibility branch
COMMAND=sh /home/player/ports/stardewvalley/stardew.sh
ICON=/home/player/ports/stardewvalley/icon.png
```

The icon comes from your game's title logo, and the game follows the launcher's language. Log: `HOME/logs/stardew.log`.

## Ocarina of Time

![Ocarina of Time on the console: the title screen, with Ship of Harkinian's frame counter at 20 FPS](ocarina-of-time.png)

Ship of Harkinian is the PC port built from the decompiled N64 game. Its renderer needs OpenGL ES 3, which the Mali-400 lacks, so this port brings one written for OpenGL ES 2, plus a fix for 32-bit builds, where the sky, the logo and the text went missing. It runs at 480p and 20 FPS, the frame rate of the N64 cartridge, with the cartridge's look by default.

**You supply:** your Ocarina of Time ROM as `.z64`, in a version Ship of Harkinian supports (N64 1.0 to 1.2 or PAL, or GameCube, Master Quest included). Tested with the N64 USA 1.0.

**Build and install:**

```sh
git checkout feat/zelda
dev/gl rootfs                      # once, 1-2 h: the port brings only the libraries the console lacks
mkdir -p dev/out/zelda/roms/oot
cp "Legend of Zelda, The - Ocarina of Time (USA).z64" dev/out/zelda/roms/oot/
python3 dev/zelda/cover.py         # optional: launcher icons for both games, from libretro-thumbnails (needs Pillow)
GL_JOBS=3 dev/zelda/build.sh oot   # dev/out/zelda/soh.tar, ~40 min on an M1
mkdir -p /Volumes/HOME/ports && tar -xf dev/out/zelda/soh.tar -C /Volumes/HOME/ports
```

Add to `HOME/apps.puppy`:

```ini
[ENTRY]
CATEGORY=Games
NAME=Ocarina of Time
DESCRIPTION=Ship of Harkinian, from your own rom
COMMAND=sh /home/player/ports/soh/soh.sh
ICON=/home/player/ports/soh/icon.png
```

Saves and settings stay in `HOME/ports/soh`. Log: `HOME/logs/soh.log`.

## Majora's Mask

![Majora's Mask on the console: Clock Town in the title demo](majoras-mask.png)

2 Ship 2 Harkinian is the same kind of port for Majora's Mask, on the same libraries, so it uses the same OpenGL ES 2 renderer. On the console the title demo plays through Clock Town at 480p; the frame rate isn't measured yet.

**You supply:** your Majora's Mask ROM as `.z64`, the N64 USA version (1.0): 2 Ship 2 Harkinian takes only the USA versions.

**Build and install**, with the branch checked out and the rootfs built as for Ocarina of Time:

```sh
mkdir -p dev/out/zelda/roms/mm
cp "Legend of Zelda, The - Majora's Mask (USA).z64" dev/out/zelda/roms/mm/
GL_JOBS=3 dev/zelda/build.sh mm    # dev/out/zelda/2ship.tar
mkdir -p /Volumes/HOME/ports && tar -xf dev/out/zelda/2ship.tar -C /Volumes/HOME/ports
```

Add to `HOME/apps.puppy`:

```ini
[ENTRY]
CATEGORY=Games
NAME=Majora's Mask
DESCRIPTION=2 Ship 2 Harkinian, from your own rom
COMMAND=sh /home/player/ports/2ship/2ship.sh
ICON=/home/player/ports/2ship/icon.png
```

Saves and settings stay in `HOME/ports/2ship`. Log: `HOME/logs/2ship.log`.
