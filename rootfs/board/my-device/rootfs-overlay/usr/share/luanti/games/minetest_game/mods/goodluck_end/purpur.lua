-- The End cities' blocks: purpur (four popped chorus fruits), its pillar (two slabs), stairs and slab, and the end
-- rod (a blaze rod on a popped chorus fruit), light 14, standing out from the face it is put on
local S = core.get_translator("goodluck_end")
local POPPED = "goodluck_end:chorus_fruit_popped"

core.register_node("goodluck_end:purpur_block", {
	description = S("Purpur Block"),
	tiles = {"goodluck_end_purpur_block.png"},
	groups = {cracky = 3, stone = 1},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
})
core.register_craft({output = "goodluck_end:purpur_block 4", recipe = {{POPPED, POPPED}, {POPPED, POPPED}}})

if stairs then
	stairs.register_stair_and_slab("purpur_block", "goodluck_end:purpur_block", {cracky = 3},
		{"goodluck_end_purpur_block.png"}, S("Purpur Stairs"), S("Purpur Slab"), default.node_sound_stone_defaults(),
		true)
end

core.register_node("goodluck_end:purpur_pillar", {
	description = S("Purpur Pillar"),
	tiles = {"goodluck_end_purpur_pillar_top.png", "goodluck_end_purpur_pillar_top.png",
		"goodluck_end_purpur_pillar_side.png"},
	paramtype2 = "facedir",
	groups = {cracky = 3, stone = 1},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
	on_place = core.rotate_node,
})
if stairs then
	core.register_craft({output = "goodluck_end:purpur_pillar",
		recipe = {{"stairs:slab_purpur_block"}, {"stairs:slab_purpur_block"}}})
end

core.register_node("goodluck_end:end_rod", {
	description = S("End Rod"),
	drawtype = "mesh",
	mesh = "goodluck_models_end_rod.obj",
	tiles = {"goodluck_end_end_rod.png"},
	use_texture_alpha = "clip",
	paramtype = "light",
	paramtype2 = "wallmounted",
	sunlight_propagates = true,
	light_source = 14,
	selection_box = {type = "wallmounted", wall_bottom = {-2 / 16, -0.5, -2 / 16, 2 / 16, 0.5, 2 / 16},
		wall_top = {-2 / 16, -0.5, -2 / 16, 2 / 16, 0.5, 2 / 16}, wall_side = {-0.5, -2 / 16, -2 / 16, 0.5, 2 / 16, 2 / 16}},
	groups = {dig_immediate = 3},
	is_ground_content = false,
	sounds = default.node_sound_glass_defaults(),
})
core.register_craft({output = "goodluck_end:end_rod 4", recipe = {{"goodluck_nether:blaze_rod"}, {POPPED}}})
