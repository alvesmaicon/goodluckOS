-- Emeralds: what the villagers trade in (goodluck_villages); the ore digs as diamond ore does
local S = core.get_translator("goodluck_emerald")

core.register_craftitem("goodluck_emerald:emerald", {
	description = S("Emerald"),
	inventory_image = "goodluck_emerald.png",
})

core.register_node("goodluck_emerald:stone_with_emerald", {
	description = S("Emerald Ore"),
	tiles = {"default_stone.png^goodluck_emerald_mineral.png"},
	groups = table.copy(core.registered_nodes["default:stone_with_diamond"].groups),
	drop = "goodluck_emerald:emerald",
	sounds = default.node_sound_stone_defaults(),
})

core.register_node("goodluck_emerald:block", {
	description = S("Block of Emerald"),
	tiles = {"goodluck_emerald_block.png"},
	is_ground_content = false,
	groups = table.copy(core.registered_nodes["default:diamondblock"].groups),
	sounds = default.node_sound_stone_defaults(),
})

core.register_craft({
	output = "goodluck_emerald:block",
	recipe = {
		{"goodluck_emerald:emerald", "goodluck_emerald:emerald", "goodluck_emerald:emerald"},
		{"goodluck_emerald:emerald", "goodluck_emerald:emerald", "goodluck_emerald:emerald"},
		{"goodluck_emerald:emerald", "goodluck_emerald:emerald", "goodluck_emerald:emerald"},
	},
})

core.register_craft({
	output = "goodluck_emerald:emerald 9",
	recipe = {{"goodluck_emerald:block"}},
})

-- as in Minecraft before 1.18: 3 to 8 single ores a 16x16 column between its y 4 and 31 (ours -58 and -31, see
-- goodluck_ores), only under its mountains, here the cold forests; new terrain only. An ore's biome is the one at
-- the top of its mapchunk, and down there that is the forest's _ocean part
core.register_ore({
	ore_type = "scatter",
	ore = "goodluck_emerald:stone_with_emerald",
	wherein = "default:stone",
	clust_scarcity = math.floor(16 * 16 * 28 / 5.5),
	clust_num_ores = 1,
	clust_size = 1,
	y_max = -31,
	y_min = -58,
	biomes = {"taiga", "taiga_ocean", "coniferous_forest", "coniferous_forest_ocean", "snowy_grassland",
		"snowy_grassland_ocean"},
})
