-- Minecraft's foods and crops. Hunger points are Minecraft's: stamina's bar is its 20
local S = core.get_translator("goodluck_food")
local stamina = core.global_exists("stamina") and stamina
goodluck_food = {}

-- a crop of Minecraft's 8 ages drawn in its 4 pictures, grown by Minetest Game's node timers with goodluck_farming's
-- rules (dry farmland, light from the sky or a torch)
local PICTURE = {1, 1, 2, 2, 3, 3, 3, 4}

local function crop(name, young, ripe)
	for age = 1, 8 do
		core.register_node("goodluck_food:" .. name .. "_" .. age, {
			drawtype = "plantlike",
			waving = 1,
			tiles = {"goodluck_food_" .. name .. "_" .. PICTURE[age] .. ".png"},
			paramtype = "light",
			paramtype2 = "meshoptions",
			place_param2 = 3,
			walkable = false,
			buildable_to = true,
			drop = age < 8 and young or ripe,
			selection_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, -0.5 + PICTURE[age] * 3 / 16, 0.5}},
			groups = {snappy = 3, flammable = 2, plant = 1, attached_node = 1, not_in_creative_inventory = 1,
				[name] = age},
			sounds = default.node_sound_leaves_defaults(),
			next_plant = age < 8 and "goodluck_food:" .. name .. "_" .. age + 1 or nil,
			on_timer = farming.grow_plant,
			minlight = 13,
			maxlight = default.LIGHT_MAX,
		})
	end
end

-- planted on farmland with the item itself, as in Minecraft (beetroot with its seeds)
local function planting(plant)
	return function(itemstack, placer, pointed_thing)
		local under = pointed_thing.under and core.get_node(pointed_thing.under)
		local def = under and core.registered_nodes[under.name]
		if def and def.on_rightclick and not (placer and placer:get_player_control().sneak) then
			return def.on_rightclick(pointed_thing.under, under, placer, itemstack, pointed_thing) or itemstack
		end
		itemstack = farming.place_seed(itemstack, placer, pointed_thing, plant)
		if pointed_thing.above and core.get_node(pointed_thing.above).name == plant then
			core.swap_node(pointed_thing.above, {name = plant, param2 = 3})
		end
		return itemstack
	end
end

goodluck_food.planting = planting

-- Minecraft's ripe carrots and potatoes give 2 and then 3 more at a little over one in two each (2 to 5)
local function ripe(item, extra)
	local items = {{items = {item .. " 2"}}}
	for _ = 1, 3 do
		items[#items + 1] = {items = {item}, rarity = 2}
	end
	items[#items + 1] = extra
	return {items = items}
end

core.register_craftitem("goodluck_food:carrot", {
	description = S("Carrot"),
	inventory_image = "goodluck_food_carrot.png",
	groups = {food = 1, flammable = 2},
	on_use = core.item_eat(3),
	on_place = planting("goodluck_food:carrots_1"),
})
crop("carrots", "goodluck_food:carrot", ripe("goodluck_food:carrot"))

core.register_craftitem("goodluck_food:potato", {
	description = S("Potato"),
	inventory_image = "goodluck_food_potato.png",
	groups = {food = 1, flammable = 2},
	on_use = core.item_eat(1),
	on_place = planting("goodluck_food:potatoes_1"),
})
crop("potatoes", "goodluck_food:potato",
	ripe("goodluck_food:potato", {items = {"goodluck_food:poisonous_potato"}, rarity = 50}))

core.register_craftitem("goodluck_food:baked_potato", {
	description = S("Baked Potato"),
	inventory_image = "goodluck_food_baked_potato.png",
	groups = {food = 1},
	on_use = core.item_eat(5),
})

core.register_craft({
	type = "cooking",
	output = "goodluck_food:baked_potato",
	recipe = "goodluck_food:potato",
	cooktime = 10,
})

-- 2 points, and at 3 in 5 stamina's poison, as Minecraft's Poison
core.register_craftitem("goodluck_food:poisonous_potato", {
	description = S("Poisonous Potato"),
	inventory_image = "goodluck_food_poisonous_potato.png",
	groups = {food = 1},
	on_use = function(itemstack, user, pointed_thing)
		local full = stamina and stamina.get_saturation(user) or 0
		itemstack = core.do_item_eat(2, nil, itemstack, user, pointed_thing)
		local data = stamina and stamina.players[user:get_player_name()]
		if data and full < stamina.VISUAL_MAX and math.random() < 0.6 then
			data.poisoned = 4
			user:hud_change(data.hud_id, "text", "stamina_hud_poison.png")
		end
		return itemstack
	end,
})

core.register_craftitem("goodluck_food:beetroot", {
	description = S("Beetroot"),
	inventory_image = "goodluck_food_beetroot.png",
	groups = {food = 1, flammable = 2},
	on_use = core.item_eat(1),
})

core.register_craftitem("goodluck_food:beetroot_seeds", {
	description = S("Beetroot Seeds"),
	inventory_image = "goodluck_food_beetroot_seeds.png",
	groups = {seed = 1, flammable = 2},
	on_place = planting("goodluck_food:beetroots_1"),
})

-- ripe: a beetroot and 1 to 4 seeds
local beet = {{items = {"goodluck_food:beetroot"}}, {items = {"goodluck_food:beetroot_seeds"}}}
for _ = 1, 3 do
	beet[#beet + 1] = {items = {"goodluck_food:beetroot_seeds"}, rarity = 2}
end
crop("beetroots", "goodluck_food:beetroot_seeds", {items = beet})

core.register_craftitem("goodluck_food:bowl", {
	description = S("Bowl"),
	inventory_image = "goodluck_food_bowl.png",
	groups = {flammable = 2},
})

core.register_craft({
	output = "goodluck_food:bowl 4",
	recipe = {
		{"group:wood", "", "group:wood"},
		{"", "group:wood", ""},
	},
})

core.register_craftitem("goodluck_food:mushroom_stew", {
	description = S("Mushroom Stew"),
	inventory_image = "goodluck_food_mushroom_stew.png",
	stack_max = 1,
	groups = {food = 1},
	on_use = core.item_eat(6, "goodluck_food:bowl"),
})

core.register_craft({
	type = "shapeless",
	output = "goodluck_food:mushroom_stew",
	recipe = {"flowers:mushroom_red", "flowers:mushroom_brown", "goodluck_food:bowl"},
})

core.register_craftitem("goodluck_food:beetroot_soup", {
	description = S("Beetroot Soup"),
	inventory_image = "goodluck_food_beetroot_soup.png",
	stack_max = 1,
	groups = {food = 1},
	on_use = core.item_eat(6, "goodluck_food:bowl"),
})

local B = "goodluck_food:beetroot"
core.register_craft({
	output = "goodluck_food:beetroot_soup",
	recipe = {
		{B, B, B},
		{B, B, B},
		{"", "goodluck_food:bowl", ""},
	},
})

core.register_craftitem("goodluck_food:sugar", {
	description = S("Sugar"),
	inventory_image = "goodluck_food_sugar.png",
})

core.register_craft({
	type = "shapeless",
	output = "goodluck_food:sugar",
	recipe = {"default:papyrus"},
})

core.register_craftitem("goodluck_food:gold_nugget", {
	description = S("Gold Nugget"),
	inventory_image = "goodluck_food_gold_nugget.png",
})

core.register_craft({
	type = "shapeless",
	output = "goodluck_food:gold_nugget 9",
	recipe = {"default:gold_ingot"},
})

local N = "goodluck_food:gold_nugget"
core.register_craft({
	output = "default:gold_ingot",
	recipe = {{N, N, N}, {N, N, N}, {N, N, N}},
})

core.register_craftitem("goodluck_food:golden_carrot", {
	description = S("Golden Carrot"),
	inventory_image = "goodluck_food_golden_carrot.png",
	groups = {food = 1},
	on_use = core.item_eat(6),
})

core.register_craft({
	output = "goodluck_food:golden_carrot",
	recipe = {{N, N, N}, {N, "goodluck_food:carrot", N}, {N, N, N}},
})

local path = core.get_modpath("goodluck_food")
dofile(path .. "/stems.lua")
dofile(path .. "/cocoa.lua")
dofile(path .. "/cake.lua")
