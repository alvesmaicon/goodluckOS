-- Pumpkins and melons as in Minecraft: a stem grows from the seeds in 8 ages, then sets its fruit on a free side
-- with dirt under it and bends to it; taking the fruit straightens it again. They also grow wild: pumpkins in
-- patches on the grass of the temperate and cold lands, melons in the rainforest
local S = core.get_translator("goodluck_food")
local DIRS = {{x = 0, y = 0, z = 1}, {x = 1, y = 0, z = 0}, {x = 0, y = 0, z = -1}, {x = -1, y = 0, z = 0}}

local function tick(pos)
	core.get_node_timer(pos):start(math.random(166, 286))
end

local function fruiting(pos)
	local def = core.registered_nodes[core.get_node(pos).name]
	if farming.can_grow(pos) then
		local dir = DIRS[math.random(4)]
		local at = vector.add(pos, dir)
		local below = core.get_node(vector.offset(at, 0, -1, 0)).name
		if core.get_node(at).name == "air" and (core.get_item_group(below, "soil") > 0 or below:find("dirt")) then
			core.set_node(at, {name = def._goodluck_fruit})
			core.swap_node(pos, {name = def._goodluck_attached, param2 = core.dir_to_facedir(dir)})
			return
		end
	end
	tick(pos)
end

local function stems(fruit)
	local base, seeds = "goodluck_food:" .. fruit .. "_stem_", "goodluck_food:" .. fruit .. "_seeds"
	local common = {
		paramtype = "light",
		sunlight_propagates = true,
		walkable = false,
		drop = seeds,
		groups = {snappy = 3, flammable = 2, plant = 1, attached_node = 1, not_in_creative_inventory = 1},
		sounds = default.node_sound_leaves_defaults(),
		minlight = 13,
		maxlight = default.LIGHT_MAX,
		_goodluck_fruit = "goodluck_food:" .. fruit,
		_goodluck_attached = base .. "attached",
	}
	for age = 1, 8 do
		local def = table.copy(common)
		def.drawtype = "plantlike"
		def.tiles = {"goodluck_food_stem_" .. age .. ".png"}
		def.selection_box = {type = "fixed", fixed = {-0.2, -0.5, -0.2, 0.2, -0.5 + age / 8, 0.2}}
		-- the last age names itself, only so that grow_plant keeps the 7th's timer going into it
		def.next_plant = base .. math.min(age + 1, 8)
		def.on_timer = age < 8 and farming.grow_plant or fruiting
		core.register_node(base .. age, def)
	end
	local def = table.copy(common)
	def.drawtype = "nodebox"
	def.paramtype2 = "facedir"
	def.use_texture_alpha = "clip"
	def.tiles = {"blank.png", "blank.png", "goodluck_food_stem_attached.png",
		"goodluck_food_stem_attached.png^[transformFX", "blank.png", "blank.png"}
	def.node_box = {type = "fixed", fixed = {-1 / 64, -0.5, -0.5, 1 / 64, 0.5, 0.5}}
	def.selection_box = {type = "fixed", fixed = {-0.2, -0.5, -0.2, 0.2, 0.5, 0.2}}
	core.register_node(base .. "attached", def)

	core.register_craftitem(seeds, {
		description = fruit == "pumpkin" and S("Pumpkin Seeds") or S("Melon Seeds"),
		inventory_image = "goodluck_food_" .. fruit .. "_seeds.png",
		groups = {seed = 1, flammable = 2},
		on_place = goodluck_food.planting(base .. "1"),
	})
end

-- a fruit taken: the stems bent to it stand up again and set another
local function unhook(pos)
	for _, dir in ipairs(DIRS) do
		local at = vector.subtract(pos, dir)
		local node = core.get_node(at)
		local def = core.registered_nodes[node.name]
		if def and def._goodluck_attached == node.name and vector.equals(core.facedir_to_dir(node.param2), dir) then
			core.swap_node(at, {name = node.name:gsub("attached$", "8")})
			tick(at)
		end
	end
end

local function fruit(name, def)
	def.groups = {choppy = 3, oddly_breakable_by_hand = 2, flammable = 2}
	def.sounds = default.node_sound_wood_defaults()
	def.after_destruct = unhook
	core.register_node("goodluck_food:" .. name, def)
end

fruit("pumpkin", {
	description = S("Pumpkin"),
	tiles = {"goodluck_food_pumpkin_top.png", "goodluck_food_pumpkin_top.png", "goodluck_food_pumpkin_side.png"},
})

-- placed with its face toward the player
core.register_node("goodluck_food:carved_pumpkin", {
	description = S("Carved Pumpkin"),
	tiles = {"goodluck_food_pumpkin_top.png", "goodluck_food_pumpkin_top.png", "goodluck_food_pumpkin_side.png",
		"goodluck_food_pumpkin_side.png", "goodluck_food_pumpkin_side.png", "goodluck_food_carved_pumpkin.png"},
	paramtype2 = "facedir",
	is_ground_content = false,
	groups = {choppy = 3, oddly_breakable_by_hand = 2, flammable = 2},
	sounds = default.node_sound_wood_defaults(),
})

core.register_node("goodluck_food:jack_o_lantern", {
	description = S("Jack o'Lantern"),
	tiles = {"goodluck_food_pumpkin_top.png", "goodluck_food_pumpkin_top.png", "goodluck_food_pumpkin_side.png",
		"goodluck_food_pumpkin_side.png", "goodluck_food_pumpkin_side.png", "goodluck_food_jack_o_lantern.png"},
	paramtype2 = "facedir",
	light_source = default.LIGHT_MAX,
	is_ground_content = false,
	groups = {choppy = 3, oddly_breakable_by_hand = 2, flammable = 2},
	sounds = default.node_sound_wood_defaults(),
})

core.register_craft({
	output = "goodluck_food:jack_o_lantern",
	recipe = {{"goodluck_food:carved_pumpkin"}, {"default:torch"}},
})

-- shears on a pumpkin carve it, as Minecraft's PumpkinBlock: the face on the side clicked (from above or below,
-- toward the player), 4 seeds thrown out of it, one of the shears' 238 uses
local SHEARS = "mobs:shears"
local shears = core.registered_items[SHEARS]
if shears then
	local on_place = shears.on_place
	core.override_item(SHEARS, {on_place = function(itemstack, placer, pointed_thing)
		local pos = pointed_thing.type == "node" and pointed_thing.under
		if not pos or not placer or not placer:is_player() or placer:get_player_control().sneak or
				core.get_node(pos).name ~= "goodluck_food:pumpkin" then
			return on_place(itemstack, placer, pointed_thing)
		end
		local name = placer:get_player_name()
		if core.is_protected(pos, name) then
			core.record_protection_violation(pos, name)
			return itemstack
		end
		local face = vector.subtract(pointed_thing.above, pos)
		if face.y ~= 0 then
			local look = core.facedir_to_dir(core.dir_to_facedir(placer:get_look_dir()))
			face = vector.multiply(look, -1)
		end
		core.set_node(pos, {name = "goodluck_food:carved_pumpkin",
			param2 = core.dir_to_facedir(vector.multiply(face, -1))})
		local seeds = core.add_item(vector.offset(pos, face.x * 0.65, -0.4, face.z * 0.65),
			"goodluck_food:pumpkin_seeds 4")
		if seeds then
			seeds:set_velocity(vector.new(face.x + math.random() * 0.4, 1, face.z + math.random() * 0.4))
		end
		core.sound_play("goodluck_food_pumpkin_carve", {pos = pos, max_hear_distance = 16}, true)
		if not core.is_creative_enabled(name) then
			itemstack:add_wear_by_uses(238)
			if itemstack:is_empty() then
				core.sound_play("default_tool_breaks", {pos = pos, max_hear_distance = 16}, true)
			end
		end
		return itemstack
	end})
end

-- 3 to 7 slices
local slices = {{items = {"goodluck_food:melon_slice 3"}}}
for _ = 1, 4 do
	slices[#slices + 1] = {items = {"goodluck_food:melon_slice"}, rarity = 2}
end
fruit("melon", {
	description = S("Melon"),
	tiles = {"goodluck_food_melon_top.png", "goodluck_food_melon_top.png", "goodluck_food_melon_side.png"},
	drop = {items = slices},
})

core.register_craftitem("goodluck_food:melon_slice", {
	description = S("Melon Slice"),
	inventory_image = "goodluck_food_melon_slice.png",
	groups = {food = 1},
	on_use = core.item_eat(2),
})

local M = "goodluck_food:melon_slice"
core.register_craft({
	output = "goodluck_food:melon",
	recipe = {{M, M, M}, {M, M, M}, {M, M, M}},
})

stems("pumpkin")
stems("melon")

core.register_craft({
	type = "shapeless",
	output = "goodluck_food:pumpkin_seeds 4",
	recipe = {"goodluck_food:pumpkin"},
})

core.register_craft({
	type = "shapeless",
	output = "goodluck_food:melon_seeds",
	recipe = {"goodluck_food:melon_slice"},
})

core.register_craftitem("goodluck_food:pumpkin_pie", {
	description = S("Pumpkin Pie"),
	inventory_image = "goodluck_food_pumpkin_pie.png",
	groups = {food = 1},
	on_use = core.item_eat(8),
})

if core.registered_items["mobs:egg"] then
	core.register_craft({
		type = "shapeless",
		output = "goodluck_food:pumpkin_pie",
		recipe = {"goodluck_food:pumpkin", "goodluck_food:sugar", "mobs:egg"},
	})
end

-- wild, new terrain only: small patches where the noise peaks, about Minecraft's 7 pumpkins on 10000 m2 of grass
-- (offset -0.095 measured 7), melons twice as many in the rainforest
local function wild(name, place_on, biomes, seed, offset)
	core.register_decoration({
		name = "goodluck_food:" .. name,
		deco_type = "simple",
		place_on = place_on,
		sidelen = 16,
		noise_params = {offset = offset, scale = 0.1, spread = {x = 20, y = 20, z = 20}, seed = seed, octaves = 3,
			persist = 0.6},
		biomes = biomes,
		y_max = 31000,
		y_min = 1,
		decoration = "goodluck_food:" .. name,
	})
end

wild("pumpkin", {"default:dirt_with_grass", "default:dirt_with_coniferous_litter", "default:dirt_with_snow"},
	{"grassland", "deciduous_forest", "coniferous_forest", "taiga", "snowy_grassland"}, 2187, -0.095)
wild("melon", {"default:dirt_with_rainforest_litter"}, {"rainforest"}, 7744, -0.08)
