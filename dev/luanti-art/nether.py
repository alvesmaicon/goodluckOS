#!/usr/bin/env python3
# goodluck_nether's textures when the player has no Minecraft of their own: Pixel Perfection's, by XSSheep and Nova
# Wostra's Legacy (CC BY-SA 4.0), as Mineclonia 0.124.0 carries them (mods/ITEMS/mcl_nether, mcl_core's bedrock and
# crying obsidian, mcl_portals' portal and its particle, mcl_blackstone; its LEGAL.md), copied under goodluck_nether's
# names
#   python3 dev/luanti-art/nether.py <mineclonia checkout> [out dir]
import os, shutil, sys

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
SRC = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else \
    ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods/goodluck_nether/textures"
NETHER = {
    "netherrack": "netherrack", "glowstone": "glowstone", "glowstone_dust": "glowstone_dust",
    "soul_sand": "soul_sand", "magma": "magma", "quartz": "quartz", "quartz_ore": "quartz_ore", "gold_ore": "gold_ore",
    "quartz_block_top": "quartz_block_top", "quartz_block_side": "quartz_block_side",
    "quartz_block_bottom": "quartz_block_bottom", "quartz_pillar_top": "quartz_pillar_top",
    "quartz_pillar_side": "quartz_pillar_side", "quartz_chiseled_top": "quartz_chiseled_top",
    "quartz_chiseled_side": "quartz_chiseled_side", "brick": "netherbrick", "bricks": "nether_brick",
    "wart": "nether_wart", "wart_0": "nether_wart_stage_0", "wart_1": "nether_wart_stage_1",
    "wart_2": "nether_wart_stage_2",
}

os.makedirs(OUT, exist_ok=True)
for name, mcl in NETHER.items():
    shutil.copyfile(f"{SRC}/mods/ITEMS/mcl_nether/textures/mcl_nether_{mcl}.png", f"{OUT}/goodluck_nether_{name}.png")
shutil.copyfile(SRC + "/mods/ITEMS/mcl_core/textures/mcl_core_bedrock.png", OUT + "/goodluck_nether_bedrock.png")
shutil.copyfile(SRC + "/mods/ITEMS/mcl_portals/textures/mcl_portals_portal.png", OUT + "/goodluck_nether_portal.png")
shutil.copyfile(SRC + "/mods/ITEMS/mcl_portals/textures/mcl_particles_nether_portal.png",
                OUT + "/goodluck_nether_portal_particle.png")
ITEMS = {
    "mcl_core/textures/mcl_core_crying_obsidian": "crying_obsidian",
    "mcl_core/textures/mcl_core_crying_obsidian_tear2": "tear",
    "mcl_blackstone/textures/mcl_blackstone_side": "blackstone",
    "mcl_blackstone/textures/mcl_blackstone_top": "blackstone_top",
    "mcl_blackstone/textures/mcl_blackstone_polished": "polished_blackstone",
    "mcl_blackstone/textures/mcl_blackstone_polished_bricks": "polished_blackstone_bricks",
}
for mcl, name in ITEMS.items():
    shutil.copyfile(f"{SRC}/mods/ITEMS/{mcl}.png", f"{OUT}/goodluck_nether_{name}.png")
