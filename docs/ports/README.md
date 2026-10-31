# Ports

Games that run natively on the console, not in an emulator: PC versions built for its 32-bit ARM CPU and its OpenGL ES 2 GPU. Apart from Luanti, none of them comes with its game: you supply your own copy (the game's files or the cartridge's ROM), and nothing from the games is in this repository.

All four are work in progress and have only run on my console (GA36-MB, A33, 512 MB of RAM). The screenshots are from it.

| Game | Built on | You supply | On the A33 | Where |
| --- | --- | --- | --- | --- |
| [Luanti](luanti.md) | Luanti 5.18 with 45 patches, Minetest Game, 63 mods | nothing | 20 FPS in a forest, 10 over a lake | `rootfs/package/luanti` |
| [Stardew Valley](#stardew-valley) | Mono, MonoGame, gl4es | the game, from Steam | about 19 FPS on the farm | `dev/stardew` |
| [Ocarina of Time](#ocarina-of-time) | Ship of Harkinian 9.3.0 | your ROM | 20 FPS, as on the N64 | `dev/zelda` |
| [Majora's Mask](#majoras-mask) | 2 Ship 2 Harkinian 5.0.1 | your ROM | not measured yet | `dev/zelda` |

## Installing a port

A port is a folder in `HOME/ports/` and an entry in `HOME/apps.puppy`, which puts it in the launcher's Games tab and, tagged "Ports", in All Games. The launcher reads `apps.puppy` when it starts, so restart the console after editing it.

There are no downloads: the games can't be shared, and this fork has no releases. Each port is built on a PC, in the dev container of [dev/README.md](../../dev/README.md) (Docker, on Intel or Apple Silicon; `dev/gl image` once). The result holds your game's files, so it is for your own console only.

The examples copy to the card in a card reader on a Mac (`/Volumes/HOME`). MTP works too, at ~10 MB/s. Before ejecting, `dot_clean /Volumes/HOME` removes the `._` files macOS leaves on FAT.

## Luanti

![Luanti on the console: a lake, with the far shore in view](luanti.png)

Luanti is a block-building engine, here with Minetest Game and 63 mods that bring it close to Minecraft. It is part of the system image, so there is nothing to supply or install. It has [a page of its own](luanti.md): how it plays and its controls, updating it, the engine and its 45 patches, the mods and their licenses, and the art made for it.

## Stardew Valley

![Stardew Valley on the console: the farm on a rainy morning](stardew-valley.png)

The PC build from Steam's "compatibility" branch (1.6.15) is a .NET Framework program, so it runs on Mono, built here for 32-bit ARM. PortMaster's port supplies the rest: JohnnyonFlame's MonoGame, which streams the music from the card instead of RAM, and gl4es, which turns the game's OpenGL into OpenGL ES 2. Our patches cut work the game repeats every frame, and the save serializers are generated ahead of time. About 19 FPS on the farm, the title screen in ~20 s, a save loaded in ~55 s.

**You supply:** Stardew Valley on Steam, switched to the compatibility branch (Properties > Betas > compatibility), in its macOS or Linux version (the one with `StardewValley.exe`). Tested with the macOS one.

**Build and install** (`SDV_GAME` is the game's folder; Steam's on a Mac is the default):

```sh
dev/stardew/build.sh          # the port in dev/out/stardew/stardewvalley, its patches built against your game
dev/stardew/build.sh game     # your game's files in dev/out/stardew/gamedata, the .xnb ones recompressed as LZ4
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

**Credits:** Stardew Valley is ConcernedApe's, and the copy is yours. The port is built on [PortMaster's](https://github.com/PortsMaster/PortMaster-New) port of the game: JohnnyonFlame's MonoGame with streamed audio (the MonoGame Team, Ms-PL) and his loader and game patches (BSD), [gl4es](https://github.com/ptitSeb/gl4es) by ptitSeb and Ryan Hileman (MIT), [Mono](https://www.mono-project.com/) (MIT, some parts BSD-3-Clause), [OpenAL Soft](https://github.com/kcat/openal-soft) (LGPL 2) and [lz4](https://github.com/lz4/lz4) (BSD-2-Clause). PortMaster's license files stay in the port's folder.

## Ocarina of Time

![Ocarina of Time on the console: the title screen](ocarina-of-time.png)

Ship of Harkinian is the PC port built from the decompiled N64 game. Its renderer needs OpenGL ES 3, which the Mali-400 lacks, so this port brings one written for OpenGL ES 2, plus a fix for 32-bit builds, where the sky, the logo and the text went missing. It runs at 480p and 20 FPS, the frame rate of the N64 cartridge, with the cartridge's look by default.

**You supply:** your Ocarina of Time ROM as `.z64`, in a version Ship of Harkinian supports (N64 1.0 to 1.2 or PAL, or GameCube, Master Quest included). Tested with the N64 USA 1.0.

**Build and install:**

```sh
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

**Credits:** [Ship of Harkinian](https://github.com/HarbourMasters/Shipwright) is by HarbourMasters; its repository has no license file. It runs on their [libultraship](https://github.com/Kenix3/libultraship) (Kenix3 and contributors, MIT) and builds its assets with Torch (Lywx, MIT); [libzip](https://libzip.org/) is BSD-3-Clause. The game is Nintendo's, from your own ROM.

## Majora's Mask

![Majora's Mask on the console: Clock Town at night, in the title demo](majoras-mask.png)

2 Ship 2 Harkinian is the same kind of port for Majora's Mask, on the same libraries, so it uses the same OpenGL ES 2 renderer. On the console the title demo plays through Clock Town at 480p; the frame rate isn't measured yet.

**You supply:** your Majora's Mask ROM as `.z64`, the N64 USA version (1.0): 2 Ship 2 Harkinian takes only the USA versions.

**Build and install**, with the rootfs built as for Ocarina of Time:

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

**Credits:** [2 Ship 2 Harkinian](https://github.com/HarbourMasters/2ship2harkinian) is by HarbourMasters (CC0), on the same libultraship (MIT), with ZAPDTR (the Zelda Reverse Engineering Team, MIT) and OTRExporter (HarbourMasters, MIT). The game is Nintendo's, from your own ROM.
