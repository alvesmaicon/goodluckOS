# Ports

Games that run natively on the console, not in an emulator: PC versions built for its 32-bit ARM CPU and its OpenGL ES 2 GPU. Apart from Luanti, none of them comes with its game: you supply your own copy (the game's files or the cartridge's ROM), and nothing from the games is in this repository.

All four are work in progress and have only run on my console (GA36-MB, A33, 512 MB of RAM). The screenshots are from it.

| Game | Built on | You supply | On the A33 | Where |
| --- | --- | --- | --- | --- |
| [Luanti](#luanti) | Luanti 5.17 with 45 patches, Minetest Game, 63 mods | nothing | 20 FPS in a forest, 10 over a lake | `rootfs/package/luanti` |
| [Stardew Valley](#stardew-valley) | Mono, MonoGame, gl4es | the game, from Steam | about 19 FPS on the farm | `dev/stardew` |
| [Ocarina of Time](#ocarina-of-time) | Ship of Harkinian 9.3.0 | your ROM | 20 FPS, as on the N64 | `dev/zelda` |
| [Majora's Mask](#majoras-mask) | 2 Ship 2 Harkinian 5.0.1 | your ROM | not measured yet | `dev/zelda` |

## Installing a port

A port is a folder in `HOME/ports/` and an entry in `HOME/apps.puppy`, which puts it in the launcher's Games tab and, tagged "Ports", in All Games. The launcher reads `apps.puppy` when it starts, so restart the console after editing it.

There are no downloads: the games can't be shared, and this fork has no releases. Each port is built on a PC, in the dev container of [dev/README.md](../../dev/README.md) (Docker, on Intel or Apple Silicon; `dev/gl image` once). The result holds your game's files, so it is for your own console only.

The examples copy to the card in a card reader on a Mac (`/Volumes/HOME`). MTP works too, at ~10 MB/s. Before ejecting, `dot_clean /Volumes/HOME` removes the `._` files macOS leaves on FAT.

## Luanti

![Luanti on the console: a lake, with the far shore in view](luanti.png)

Luanti is an open-source engine for Minecraft-like games, and Minetest Game, its classic game, is free. Here both run on a 512 MB handheld with a Mali-400: 45 patches make the engine fast enough, fit it to a gamepad and a 640x480 screen, and make it dig, swim, jump and hold things as Minecraft does, and 63 mods, 46 of them written for goodluckOS, bring the game close to Minecraft: Survival or Creative, hunger and status effects, armor and shields, Minecraft's ores, crops and foods, the classic monsters and the witch, villages with traders, horses, experience, enchanting and the anvil, a bow, a compass, maps and a spyglass, recipes learnt as you go, the Nether with its fortresses, potions and the brewing stand, swamps with witch huts, and the End with its strongholds and the ender dragon. At 640x480: 20 FPS in a forest, 10 to 11 looking across a lake, capped at 30. It comes with free textures and sounds, or takes the textures, sounds and music of your own Minecraft: Java Edition, which Update Luanti imports from a copy of your `.minecraft` folder ([Updating Luanti](#updating-luanti)); nothing of Minecraft's is in this repository or in the image.

**Install:** Luanti is part of the system image (a Buildroot package), so there is nothing to copy. Build the rootfs from `develop` and write it to the card (`dev/gl rootfs`, `dev/gl ext4`, `dev/sdcard-mac.sh`, see [dev/README.md](../../dev/README.md)), and it shows up in the Games tab. Worlds and settings are kept in `HOME/.minetest`. The controls, and how each part of the game plays, are in the [README](../../README.md#luanti).

### Updating Luanti

Once a card has Luanti, a new version needs no new system image: it comes as one file, a package named `luanti-<date>-<time>-<commit>.tar.xz` (about 10 MB). A package holds all of Luanti, the engine and the game, so it installs over any older version, without the ones in between.

1. Copy the package to the `updates` folder of HOME, over USB (the console is an MTP device: Windows shows it as a drive) or with the card in a card reader:

   ```sh
   cp luanti-20261017-1610-3a390df.tar.xz /Volumes/HOME/updates/
   dot_clean /Volumes/HOME
   ```

2. In the launcher's Games tab, run **Update Luanti**, right below Luanti. It shows each step on the screen, takes about 20 seconds, and goes back to the menu by itself.

If the new version misbehaves, **Undo Luanti update**, below it, brings back the one installed before; running it again returns to the update.

Worlds and settings in `HOME/.minetest` are never touched. Before it changes anything, Update Luanti checks every file of the package against the package's checksums, that the package holds only Luanti's files and all of them, and that the system has room for it; if any check fails, nothing changes. A package older than the installed version, or the same one, is refused. With several packages in the folder it installs the newest and moves the others to `updates/old`; the installed one goes to `updates/installed`. Each step is written to `HOME/logs/luanti-update.log`.

Update Luanti also gives Luanti the look and the sounds of your own Minecraft: Java Edition. With a copy of its `.minecraft` folder in HOME (as `minecraft` or `.minecraft`), it takes from the client jar with the most textures every texture Luanti has a place for, and from `assets` the sounds and the music (about 160 MB, copied once); a texture or sound that version lacks keeps Luanti's own. With the folder gone, the next Update Luanti puts Luanti's own art back and removes the music. The [README](../../README.md#how-do-i-add-games) lists what it replaces.

Update Luanti is part of the system image: a card with an older image needs a new one first, or gets Update Luanti from a PC over USB. This fork publishes no packages yet; `dev/gl luanti-pkg` makes them on a PC from any branch, tag or commit ([dev/README.md](../../dev/README.md#luanti-packages)).

### The engine: Luanti 5.17 for handhelds

The engine is Luanti 5.17.0 (celeron55 and contributors; code LGPL-2.1+, media CC BY-SA 3.0) with the commits of the `handheld/5.17` branch of [alvesmaicon/luanti](https://github.com/alvesmaicon/luanti/tree/handheld/5.17), which Buildroot applies as patches (`rootfs/package/luanti/`). This tree builds 5.17.0-handheld.26. The patches are under Luanti's license. They were written with AI assistance, which Luanti's AI policy doesn't accept, so they stay in that fork; fixes upstream could use are its issues labelled "upstream candidate".

| Scene on the A33, view range 320 | Luanti 5.17.0 | With the patches and the handheld's settings |
| --- | --- | --- |
| Forest, 320x240 | 3.9 FPS, 1.64 M vertices | 28 FPS |
| Lake view, 320x240 | 3.4 FPS, 1.52 M vertices, 11 MB of RAM free and 54 MB in swap | 10 FPS, 0.53 M vertices, 177 MB free, no swap |
| An inventory page of blocks | 138 ms a frame | 33 ms |

| Patch | What it changes |
| --- | --- |
| | **GPU and memory** |
| 0002 | 2D batches drawn with `glDrawElements`, so menus have text on GLES 2 |
| 0005 | Index buffers created as such, so lima caches their index range: the CPU work per vertex drops about 20 times |
| 0006 | Fog without overflow on GPUs with only 16-bit floats, where everything past 25.6 nodes took the fog's color |
| 0007 | Fog computed per vertex in the nodes shader |
| 0008 | Nodes drawn as opaque cubes, opaque leaves too, hide what is behind them |
| 0009 | Blocks out of view are unloaded too, and kept alive below 5 FPS |
| 0010 to 0013 | Far terrain drawn from simplified meshes (one cube per 2x2x2 nodes, equal faces merged, detail back when close), on by default |
| 0019 | Blocks in the inventory and the hotbar share one depth clear a frame instead of one each |
| 0020 | The HUD isn't drawn under a menu |
| 0027 | The loading screen waits for the terrain in view, so a world opens complete |
| 0039, 0040 | Blocks near the player keep their detail mesh, from the first ones a world sends |
| 0041 | The light curve is set before the terrain loads, so a world doesn't open dark |
| | **Gamepad and screen** |
| 0001 | Without a cursor plane, the gamepad moves a drawn cursor in menus |
| 0004 | Fixed-size forms fit screens under 800x600 |
| 0016, 0025 | An on-screen keyboard for the gamepad, whose OK is the field's Enter |
| 0024 | The right stick scrolls menus, the left one moves the cursor |
| 0029 | The top face button shift-clicks in menus, as on Minecraft Bedrock: a stack goes straight to the other side |
| | **Menus** |
| 0015 | A main menu without what needs a network or a keyboard |
| 0014, 0017, 0026, 0030 | A new world asks for its name, its seed, Survival or Creative (a button, as in Minecraft) and a bonus chest |
| 0018 | Settings open on a Video page with the render distance in chunks |
| 0021 | The world list takes the whole width |
| 0042 | The world list shows the selected world's seed, and Re-create makes the world again |
| | **In game** |
| 0022 | The off-hand item, a shield, is held in the left hand, lowered or raised |
| 0023 | The held item's rest pose is a setting, posed as in Minecraft at 640x480 |
| 0028 | An item moved to or from a chest or a furnace shows in its new slot at once |
| 0031 | The held item and the empty hand drawn and swung as Minecraft draws them |
| 0032 | Digging paced as in Minecraft: a quarter of a second between blocks, slower off the ground and under water |
| 0033, 0034 | The player moves in water as in Minecraft, and a fall into water does no damage |
| 0035 | Jumps and falls as in Minecraft: its jump, its air and its fall damage |
| 0036 | A map held in both hands, as Minecraft holds it |
| 0037 | The item in hand changes, and walking bobs the view and the hand, as in Minecraft |
| 0038 | Music played as Minecraft plays it, from `HOME/.minetest/music`, streamed from the card; nothing ships with the engine |
| 0043 | Night Vision, for the game to set: everything a player sees as lit as its brightest light |
| 0045 | A sun or moon with no transparency, as Minecraft's are, added to the sky as Minecraft draws them |
| | **System** |
| 0003 | Text converted with UCS-4, which minimal glibc builds have built in |
| 0044 | Builds on Windows: no variable named like one of its macros |

### The game: Minetest Game and 63 mods

Every mod sits in the game's `mods/` folder, so every world has them. `rootfs/package/luanti-game/CREDITS.txt` says where each one comes from, under which licenses, and which files goodluckOS leaves out or replaces; each mod keeps its own license file.

| Mod | Author | Version | License | Here |
| --- | --- | --- | --- | --- |
| [Minetest Game](https://github.com/luanti-org/minetest_game) | celeron55 and contributors | c42e4d0 | code LGPL-2.1+, media CC BY-SA 3.0 and others | the game, 34 mods |
| [Mobs Redo](https://codeberg.org/tenplus1/mobs_redo) | TenPlus1 | b1be18b | MIT; media CC0, CC BY-SA 3.0 | animals and monsters |
| [mobs_animal](https://codeberg.org/tenplus1/mobs_animal) | TenPlus1, Krupnov Pavel | ae70977 | MIT; media CC0, WTFPL, MIT, CC BY-SA 3.0 | farm animals |
| [mobs_monster](https://codeberg.org/tenplus1/mobs_monster) | TenPlus1 | 0185683 | MIT; media CC0, WTFPL, MIT, CC BY-SA 3.0 and 4.0 | not spawned: the spider's sound |
| [mobs_npc](https://codeberg.org/tenplus1/mobs_npc) | TenPlus1, MirceaKitsune (model) | 4d6096d | MIT; model CC BY-SA 3.0, textures CC BY-SA 3.0 and 4.0, CC0 | villagers and traders |
| [mob_horse](https://codeberg.org/tenplus1/mob_horse) | TenPlus1, Krupnov Pavel (model) | aa3ad5e | MIT; sounds CC BY 3.0 | not spawned: the horses' sounds, for goodluck_horse |
| [stamina](https://codeberg.org/tenplus1/stamina) | BlockMen, Auke Kok, TenPlus1 | 4b6988d | LGPL-2.1+; media CC BY 3.0, WTFPL, CC0 | hunger |
| [3d_armor](https://github.com/minetest-mods/3d_armor) | Stuart Jones, davidthecreator (textures) | a4f311c | LGPL-2.1; textures CC BY-SA 3.0, sounds CC0 | armor and shields, 9 of its mods |
| [x_enchanting](https://bitbucket.org/minetest_gamers/x_enchanting) | SaKeL | 1.9.3 | LGPL-2.1+; media CC BY-SA 4.0, sounds CC0, CC BY 3.0 and 4.0 | the enchanting table |
| [x_bows](https://bitbucket.org/minetest_gamers/x_bows) | SaKeL | 5.3.1 | LGPL-2.1+; media CC BY-SA 4.0 and 3.0, sounds CC0 | bow and arrows |
| [villages_mtg](https://content.luanti.org/packages/Drix03/villages_mtg/) | Drix03 | 1.0.3 | MIT | its eight buildings, in goodluck_villages |

The 45 `goodluck_*` mods and `invisibility` are goodluckOS's, under its license (GPL-2.0), but for the art from others that CREDITS.txt names (see [the art](#art-made-for-goodluckos)):

| Mod | What it does |
| --- | --- |
| goodluck_amethyst | Amethyst geodes underground: calcite, amethyst and clusters that give shards |
| goodluck_anvil | The anvil: rename, repair with the material or another of the kind, join enchantments, paid in levels |
| goodluck_armor | Minecraft's armor: leather armor in place of wood and cactus armor, one shield in place of eleven |
| goodluck_bonus_chest | Minecraft's bonus chest by the spawn, when the world is made with it |
| goodluck_bow | x_bows' bow played as Minecraft's: L1 held draws it, letting go shoots; arrows come from the inventory and are picked up by walking into them |
| goodluck_chest | Two chests side by side make one big chest of 64 slots, shown 32 a page; no keys for locked ones |
| goodluck_compass | The compass points to the world's spawn; held, it shows where you are |
| goodluck_craft | Minecraft's inventory: armor and player on the left, a 2x2 grid, the 3x3 one at a crafting table, creative items in tabs |
| goodluck_creative | Survival or Creative, chosen with the world and switched in game when allowed |
| goodluck_crouch | Sneaking lowers the camera |
| goodluck_dig | Minecraft's digging: each block's hardness and tool, each tool's speed, tier and durability |
| goodluck_effects | Minecraft's status effects (Speed, Slowness, Jump Boost, Poison, Wither, Regeneration and the others), with their icons, swirls and `/effect` |
| goodluck_emerald | Emeralds as in Minecraft before 1.18: a rare ore under the cold forests, the villagers' money |
| goodluck_enchanting | The enchanting table paid in lapis lazuli and levels, Fortune only on ores |
| goodluck_end | The End: the enderman and the silverfish, the ender pearl and the eye of ender, strongholds with their end portal, the End's island and pillars, and the ender dragon |
| goodluck_farming | Crops grow on dry farmland too (slower) and by night under the sky, and give their seed back when picked green |
| goodluck_food | Minecraft's foods and crops: carrots, potatoes, beetroots, pumpkins and melons, soups and stew, the golden carrot, the pumpkin pie, cocoa and cookies, the cake, and fishing |
| goodluck_held | The item in hand on the player seen from outside, held as Minecraft draws it |
| goodluck_horse | Horses, donkeys and mules: tamed by riding, a saddle, horse armor, an inventory, a charged jump, herds and foals |
| goodluck_hud | Minecraft's survival HUD: armor above the hearts, hunger beside them, breath above hunger, the XP bar below |
| goodluck_hunger | Minecraft's hunger costs: walking, placing and crafting are free, and rotten flesh turns the bar green |
| goodluck_item_drop | Broken blocks fall to the ground, and walking past an item picks it up |
| goodluck_jump | Steps up only from the ground: a jump against a block or a stair is no higher for it |
| goodluck_labels | No text with the crosshair on a block or a thing, as in Minecraft: signs only |
| goodluck_lapis | Lapis lazuli ore, from 30 nodes under sea level down, 4 to 9 lapis each |
| goodluck_map | An empty map becomes the map of where you are, drawn as you go |
| goodluck_mcassets | Draws the game with the textures Update Luanti imports from the player's own Minecraft: Java Edition |
| goodluck_metals | Copper in place of tin and bronze (its tools, hoe, armor and nuggets), and golden tools |
| goodluck_mobs | Monsters as slow as Minecraft's and only in the dark, with caps for the surface and for caves, gone when left far behind; animals in herds that stay; no rats or penguins |
| goodluck_models | Minecraft's shapes for its blocks, things and creatures (the chest, the bed, the sign, the minecart, the boat, the animals, the monsters, the villager...), so that its textures fit them |
| goodluck_monsters | The classic night monsters: zombie, skeleton with a bow, spider, the witch and, in the creeper's place, the bomb mushroom |
| goodluck_nether | The Nether: its realm deep below the world and its blocks, the portal and ruined portals, fortresses with blaze spawners, and the ghast, the blaze, the magma cube, the zombified piglin and the wither skeleton |
| goodluck_ores | Coal, iron, gold and diamonds as in Minecraft before 1.18: its veins' sizes, numbers and heights |
| goodluck_physics | A player's speed, jump and gravity as the product of every mod's share, so none undoes another's |
| goodluck_potions | Potions, the brewing stand and the cauldron: Minecraft's ingredients and mixes, longer, stronger and splash potions |
| goodluck_recipes | Recipes learnt as in Minecraft: the book shows a recipe once its items have been in the inventory (on Minetest Game's mtg_craftguide, MIT) |
| goodluck_redstone | Redstone in mese's place: the ore, the dust, its block and the lamp, no circuits yet |
| goodluck_shield | The shield, held up with L1 or by sneaking, blocks hits and arrows from the front |
| goodluck_solid_leaves | Opaque leaves that don't wave drawn as plain cubes |
| goodluck_sprint | L3 runs, with a slightly wider view |
| goodluck_spyglass | Minetest Game's binoculars become Minecraft's spyglass, made with an amethyst shard and copper |
| goodluck_swamp | Swamps: dark grass and water, swamp oaks with vines, lily pads and blue orchids, and the witch's hut with her cat and her cauldron |
| goodluck_swim | Swimming and breath as in Minecraft: running with the head under water swims where the player looks; 15 s of breath |
| goodluck_villages | Villages with roads, houses, a blacksmith, a church, a library and fields, loot in the chests, villagers and traders paid in emeralds |
| goodluck_xp | Experience: orbs from ores, monsters and the furnace, levels spent at the enchanting table, part of them left in the bones |
| invisibility | What Mobs Redo asks of a mod by that name: whether a player can be seen, here goodluck_effects' Invisibility |

goodluck_nether, goodluck_end, goodluck_swamp and goodluck_amethyst build what they add to the map in Lua, in the map generator's threads, and the console's Luanti has no LuaJIT: on the console a new mapchunk of the Nether took 1.2 s of Lua.

### Art made for goodluckOS

![The textures drawn for goodluckOS's Luanti by October 17, and the creatures that wore them, rendered in the game](luanti-art.png)

By 17 October 2026, 133 textures (the grid), 21 sounds and 2 models were made for this port, under goodluckOS's license (GPL-2.0). Most are new things: amethyst, lapis, the compass and the maps, experience, the HUD, the classic monsters. The others replace media that wasn't free or had no credit: the sheep's textures were CC BY-NC-SA 4.0 (non-commercial only), the rat was credited only as "CCPL", the bow's sounds named no license, and some items had no credit at all. A few are recolors of free art (the black and killer bunnies, the black kitten), and the stone, dirt and sand monsters are redrawn for mobs_monster, which stays in the game without spawning. Not in the grid: the half-drawn bow, redrawn from x_bows' (CC BY-SA 4.0). The lapis ore is drawn over Minetest Game's stone. More has been made since: emeralds, the new foods, redstone, copper and golden tools, leather and copper armor, the bed and the signs, the recipes' notice, the brewing window's arrow and fuel bar, the anvil's and the horse equipment's sounds, and goodluck_models' meshes, Minecraft's shapes built by `dev/luanti-art/models.py` and `animals.py`. The grid's zombie, skeleton and sheep are from before those meshes: they now wear the textures below, and rats and penguins are gone from the game.

When the player has no Minecraft of their own, most of what has Minecraft's shape wears Pixel Perfection's textures: XSSheep's Pixel Perfection and Nova Wostra's Pixel Perfection Legacy after it, both CC BY-SA 4.0, from the pack or as Mineclonia carries them. They dress the chests and the minecart, the farm animals and the horses, the zombie, the skeleton, the spider, the witch and the villagers, the boat and the arrow, and the blocks, creatures and items of the Nether, the End, the potions and the status effects. The scripts in `dev/luanti-art` copy them under the mods' names, and CREDITS.txt says which file comes from where. With a copy of the player's own Minecraft: Java Edition, goodluck_mcassets draws the game with its textures instead, and Update Luanti brings its sounds and music ([Updating Luanti](#updating-luanti)); nothing of Minecraft's is in this repository.

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
