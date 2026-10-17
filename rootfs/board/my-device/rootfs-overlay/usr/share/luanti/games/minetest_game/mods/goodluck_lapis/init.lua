-- Lapis lazuli: the enchanting table's payment (goodluck_enchanting), mined from y -32 down, as rare as tin
local S = core.get_translator("goodluck_lapis")

core.register_craftitem("goodluck_lapis:lapis", {
	description = S("Lapis Lazuli"),
	inventory_image = "goodluck_lapis.png",
	groups = {enchanting_trade = 1},
})

-- 4 to 9 as in Minecraft: four always, and five more at one in two each
local drops = {{items = {"goodluck_lapis:lapis 4"}}}
for _ = 1, 5 do
	drops[#drops + 1] = {items = {"goodluck_lapis:lapis"}, rarity = 2}
end

core.register_node("goodluck_lapis:stone_with_lapis", {
	description = S("Lapis Lazuli Ore"),
	tiles = {"default_stone.png^goodluck_lapis_mineral.png"},
	groups = {cracky = 2},
	drop = {max_items = 9, items = drops},
	sounds = default.node_sound_stone_defaults(),
})

core.register_node("goodluck_lapis:block", {
	description = S("Lapis Lazuli Block"),
	tiles = {"goodluck_lapis_block.png"},
	is_ground_content = false,
	groups = {cracky = 1, level = 1},
	sounds = default.node_sound_stone_defaults(),
})

core.register_craft({
	output = "goodluck_lapis:block",
	recipe = {
		{"goodluck_lapis:lapis", "goodluck_lapis:lapis", "goodluck_lapis:lapis"},
		{"goodluck_lapis:lapis", "goodluck_lapis:lapis", "goodluck_lapis:lapis"},
		{"goodluck_lapis:lapis", "goodluck_lapis:lapis", "goodluck_lapis:lapis"},
	},
})

core.register_craft({
	output = "goodluck_lapis:lapis 9",
	recipe = {{"goodluck_lapis:block"}},
})

-- tin's numbers, between copper (from -64) and gold (from -256); new terrain only, old caves stay as they are
core.register_ore({
	ore_type = "scatter",
	ore = "goodluck_lapis:stone_with_lapis",
	wherein = "default:stone",
	clust_scarcity = 13 * 13 * 13,
	clust_num_ores = 4,
	clust_size = 3,
	y_max = -32,
	y_min = -255,
})

core.register_ore({
	ore_type = "scatter",
	ore = "goodluck_lapis:stone_with_lapis",
	wherein = "default:stone",
	clust_scarcity = 10 * 10 * 10,
	clust_num_ores = 5,
	clust_size = 3,
	y_max = -256,
	y_min = -31000,
})
