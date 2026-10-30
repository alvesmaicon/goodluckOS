-- Amethyst as in Minecraft: geodes underground (mapgen.lua, run in the map generator's threads) whose clusters give
-- the shards, and four shards make a block
local S = core.get_translator("goodluck_amethyst")
local SHARD = "goodluck_amethyst:amethyst_shard"

core.register_craftitem(SHARD, {
	description = S("Amethyst Shard"),
	inventory_image = "goodluck_amethyst_shard.png",
})

core.register_node("goodluck_amethyst:amethyst_block", {
	description = S("Block of Amethyst"),
	tiles = {"goodluck_amethyst_block.png"},
	groups = {cracky = 3},
	sounds = default.node_sound_glass_defaults(),
})

core.register_node("goodluck_amethyst:calcite", {
	description = S("Calcite"),
	tiles = {"goodluck_amethyst_calcite.png"},
	groups = {cracky = 3},
	sounds = default.node_sound_stone_defaults(),
})

-- on any face of a block, glowing a little; a pickaxe gets four shards, anything else two
core.register_node("goodluck_amethyst:amethyst_cluster", {
	description = S("Amethyst Cluster"),
	drawtype = "plantlike",
	tiles = {"goodluck_amethyst_cluster.png"},
	inventory_image = "goodluck_amethyst_cluster.png",
	wield_image = "goodluck_amethyst_cluster.png",
	paramtype = "light",
	paramtype2 = "wallmounted",
	sunlight_propagates = true,
	walkable = false,
	light_source = 5,
	selection_box = {
		type = "wallmounted",
		wall_bottom = {-6 / 16, -0.5, -6 / 16, 6 / 16, 7 / 16, 6 / 16},
		wall_top = {-6 / 16, -7 / 16, -6 / 16, 6 / 16, 0.5, 6 / 16},
		wall_side = {-0.5, -6 / 16, -6 / 16, 7 / 16, 6 / 16, 6 / 16},
	},
	groups = {cracky = 3, oddly_breakable_by_hand = 1, attached_node = 1},
	drop = {
		max_items = 1,
		items = {
			{items = {SHARD .. " 4"}, tool_groups = {"pickaxe"}},
			{items = {SHARD .. " 2"}},
		},
	},
	sounds = default.node_sound_glass_defaults(),
})

core.register_craft({
	output = "goodluck_amethyst:amethyst_block",
	recipe = {
		{SHARD, SHARD},
		{SHARD, SHARD},
	},
})

core.register_mapgen_script(core.get_modpath("goodluck_amethyst") .. "/mapgen.lua")
