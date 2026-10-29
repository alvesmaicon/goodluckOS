-- The brewing stand, as Minecraft's: three bottles below, an ingredient above, blaze powder as its fuel (20 brews a
-- powder). It brews for 20 s while the ingredient can make something of at least one bottle, then makes it of each
-- one that it can and takes one ingredient; Minecraft's mixes (26.x, but Slow Falling's, Turtle Master's and 1.21's).
-- Its arms show which bottles it holds; it gives a faint light, and drops what it holds when broken
local S = core.get_translator("goodluck_potions")
local F = core.formspec_escape
local N = "goodluck_potions:"
local P = goodluck_potions
local STAND = N .. "brewing_stand"
local BLAZE = "goodluck_nether:blaze_powder"
local GLOWSTONE, REDSTONE = "goodluck_nether:glowstone_dust", "goodluck_redstone:redstone"
local FERMENTED, GUNPOWDER = N .. "fermented_spider_eye", "tnt:gunpowder"
local BREW, USES = 20, 20

local MIXES, INGREDIENT = {}, {[GUNPOWDER] = true}
local function mix(from, item, to)
	MIXES[from] = MIXES[from] or {}
	MIXES[from][item] = to
	INGREDIENT[item] = true
end
-- an ingredient makes its potion of the awkward one and the mundane one of water
local function start(item, to)
	mix("water", item, "mundane")
	mix("awkward", item, to)
end
mix("water", GLOWSTONE, "thick")
mix("water", REDSTONE, "mundane")
mix("water", "goodluck_nether:nether_wart", "awkward")
mix("awkward", "goodluck_food:golden_carrot", "night_vision")
mix("night_vision", REDSTONE, "long_night_vision")
mix("night_vision", FERMENTED, "invisibility")
mix("long_night_vision", FERMENTED, "long_invisibility")
mix("invisibility", REDSTONE, "long_invisibility")
start("goodluck_nether:magma_cream", "fire_resistance")
mix("fire_resistance", REDSTONE, "long_fire_resistance")
start(N .. "rabbit_foot", "leaping")
mix("leaping", REDSTONE, "long_leaping")
mix("leaping", GLOWSTONE, "strong_leaping")
mix("leaping", FERMENTED, "slowness")
mix("long_leaping", FERMENTED, "long_slowness")
mix("slowness", REDSTONE, "long_slowness")
mix("slowness", GLOWSTONE, "strong_slowness")
mix("swiftness", FERMENTED, "slowness")
mix("long_swiftness", FERMENTED, "long_slowness")
start("goodluck_food:sugar", "swiftness")
mix("swiftness", REDSTONE, "long_swiftness")
mix("swiftness", GLOWSTONE, "strong_swiftness")
mix("awkward", "goodluck_food:pufferfish", "water_breathing")
mix("water_breathing", REDSTONE, "long_water_breathing")
start(N .. "glistering_melon_slice", "healing")
mix("healing", GLOWSTONE, "strong_healing")
mix("healing", FERMENTED, "harming")
mix("strong_healing", FERMENTED, "strong_harming")
mix("harming", GLOWSTONE, "strong_harming")
mix("poison", FERMENTED, "harming")
mix("long_poison", FERMENTED, "harming")
mix("strong_poison", FERMENTED, "strong_harming")
start("goodluck_monsters:spider_eye", "poison")
mix("poison", REDSTONE, "long_poison")
mix("poison", GLOWSTONE, "strong_poison")
start("goodluck_nether:ghast_tear", "regeneration")
mix("regeneration", REDSTONE, "long_regeneration")
mix("regeneration", GLOWSTONE, "strong_regeneration")
start(BLAZE, "strength")
mix("strength", REDSTONE, "long_strength")
mix("strength", GLOWSTONE, "strong_strength")
mix("water", FERMENTED, "weakness")
mix("weakness", REDSTONE, "long_weakness")
P.mixes = MIXES

-- what item makes of the potion in a bottle, if anything: gunpowder makes it a splash one
function P.brew(bottle, item)
	local def = core.registered_items[bottle]
	if not def or not def._potion then
		return
	end
	if item == GUNPOWDER then
		return not def._splash and N .. "splash_" .. def._potion or nil
	end
	local to = MIXES[def._potion] and MIXES[def._potion][item]
	return to and N .. (def._splash and "splash_" or "") .. to
end

local function brewable(inv)
	local item = inv:get_stack("ingredient", 1):get_name()
	for i = 1, 3 do
		if P.brew(inv:get_stack("bottles", i):get_name(), item) then
			return true
		end
	end
	return false
end

local function formspec(meta)
	local fuel, left = meta:get_int("fuel"), meta:get_int("time")
	local parts = {
		"size[8.5,7.95]",
		"padding[0.01,0.01]",
		"no_prepend[]",
		"bgcolor[#080808BB;true]",
		"listcolors[#00000069;#5A5A5A;#141318;#30434C;#FFF]",
		"background9[-0.2,-0.3;8.9,8.55;gui_formbg.png;false;10]",
		"container[0.25,0]",
		"label[0,-0.15;", F(S("Brewing Stand")), "]",
		"image[0.6,0.4;1,1;goodluck_potions_slot_fuel.png]",
		"list[context;fuel;0.6,0.4;1,1;]",
		"list[context;ingredient;3.75,0.25;1,1;]",
	}
	for i, at in ipairs({{2.55, 1.6}, {3.75, 1.9}, {4.95, 1.6}}) do
		parts[#parts + 1] = ("image[%g,%g;1,1;goodluck_potions_slot_bottle.png]list[context;bottles;%g,%g;1,1;%d]")
			:format(at[1], at[2], at[1], at[2], i - 1)
	end
	-- the fuel left, and while it brews the arrow filling down and the bubbles rising
	if fuel > 0 then
		local w = math.max(1, math.floor(18 * fuel / USES + 0.5))
		parts[#parts + 1] = ("image[0.62,1.45;%g,0.22;%s]"):format(0.96 * w / 18,
			F("[combine:" .. w .. "x4:0,0=goodluck_potions_fuel.png"))
	end
	if left > 0 then
		local h = math.max(1, math.floor(28 * (BREW - left) / BREW + 0.5))
		parts[#parts + 1] = ("image[4.85,0.25;0.5,%g;%s]"):format(1.4 * h / 28,
			F("[combine:9x" .. h .. ":0,0=goodluck_potions_progress.png"))
		local b = ({100, 83, 69, 55, 38, 21, 0})[left % 7 + 1]
		if b > 0 then
			parts[#parts + 1] = ("image[3.05,0.25;0.65,1.5;%s]"):format(
				F("blank.png^[resize:12x29^[lowpart:" .. b .. ":goodluck_potions_bubbles.png"))
		end
	end
	parts[#parts + 1] = table.concat({
		"list[current_player;main;0,3.3;8,3;8]",
		goodluck_craft and goodluck_craft.hotbar(6.45) or "list[current_player;main;0,6.45;8,1;]",
		"listring[context;bottles]listring[current_player;main]",
		"listring[context;ingredient]listring[current_player;main]",
		"listring[context;fuel]listring[current_player;main]",
		"container_end[]",
	})
	return table.concat(parts)
end

-- the arms with bottles show them
local function show(pos)
	local inv = core.get_meta(pos):get_inventory()
	local bits = 0
	for i = 1, 3 do
		if not inv:get_stack("bottles", i):is_empty() then
			bits = bits + 2 ^ (i - 1)
		end
	end
	local name = bits == 0 and STAND or STAND .. "_" .. bits
	local node = core.get_node(pos)
	if node.name ~= name then
		core.swap_node(pos, {name = name, param2 = node.param2})
	end
end

local function tick(pos)
	local meta = core.get_meta(pos)
	local inv = meta:get_inventory()
	local fuel, left = meta:get_int("fuel"), meta:get_int("time")
	local powder = inv:get_stack("fuel", 1)
	if fuel <= 0 and powder:get_name() == BLAZE then
		fuel = USES
		powder:take_item()
		inv:set_stack("fuel", 1, powder)
	end
	local can = brewable(inv)
	local item = inv:get_stack("ingredient", 1):get_name()
	if left > 0 then
		left = left - 1
		if left == 0 and can then
			local ingredient = inv:get_stack("ingredient", 1)
			for i = 1, 3 do
				local out = P.brew(inv:get_stack("bottles", i):get_name(), item)
				if out then
					inv:set_stack("bottles", i, out)
				end
			end
			ingredient:take_item()
			inv:set_stack("ingredient", 1, ingredient)
			core.sound_play("goodluck_potions_brew", {pos = pos, gain = 0.6, max_hear_distance = 16}, true)
		elseif not can or item ~= meta:get_string("ingredient") then
			left = 0
		end
	elseif can and fuel > 0 then
		fuel, left = fuel - 1, BREW
		meta:set_string("ingredient", item)
	end
	meta:set_int("fuel", fuel)
	meta:set_int("time", left)
	meta:set_string("formspec", formspec(meta))
	show(pos)
	return left > 0
end

local function wake(pos)
	local timer = core.get_node_timer(pos)
	if not timer:is_started() then
		timer:start(1)
	end
	local meta = core.get_meta(pos)
	meta:set_string("formspec", formspec(meta))
	show(pos)
end

local function protected(pos, player)
	local name = player and player:get_player_name() or ""
	if core.is_protected(pos, name) then
		core.record_protection_violation(pos, name)
		return true
	end
end

local def = {
	description = S("Brewing Stand"),
	drawtype = "mesh",
	mesh = "goodluck_models_brewing_stand.obj",
	inventory_image = "goodluck_potions_brewing_stand_item.png",
	wield_image = "goodluck_potions_brewing_stand_item.png",
	use_texture_alpha = "clip",
	paramtype = "light",
	sunlight_propagates = true,
	light_source = 1,
	selection_box = {type = "fixed", fixed = {{-7 / 16, -0.5, -7 / 16, 7 / 16, -6 / 16, 7 / 16},
		{-1 / 16, -6 / 16, -1 / 16, 1 / 16, 6 / 16, 1 / 16}}},
	collision_box = {type = "fixed", fixed = {{-7 / 16, -0.5, -7 / 16, 7 / 16, -6 / 16, 7 / 16},
		{-1 / 16, -6 / 16, -1 / 16, 1 / 16, 6 / 16, 1 / 16}}},
	groups = {cracky = 3},
	is_ground_content = false,
	drop = STAND,
	sounds = default.node_sound_metal_defaults(),
	on_construct = function(pos)
		local meta = core.get_meta(pos)
		local inv = meta:get_inventory()
		inv:set_size("bottles", 3)
		inv:set_size("ingredient", 1)
		inv:set_size("fuel", 1)
		meta:set_string("formspec", formspec(meta))
	end,
	on_timer = tick,
	allow_metadata_inventory_put = function(pos, list, index, stack, player)
		if protected(pos, player) then
			return 0
		end
		local name = stack:get_name()
		if list == "fuel" then
			return name == BLAZE and stack:get_count() or 0
		elseif list == "ingredient" then
			return INGREDIENT[name] and stack:get_count() or 0
		end
		local item = core.registered_items[name]
		return (item and item._potion or name == "vessels:glass_bottle") and 1 or 0
	end,
	allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
		if protected(pos, player) then
			return 0
		end
		local stack = core.get_meta(pos):get_inventory():get_stack(from_list, from_index)
		stack:set_count(count)
		return core.registered_nodes[STAND].allow_metadata_inventory_put(pos, to_list, to_index, stack, player)
	end,
	allow_metadata_inventory_take = function(pos, list, index, stack, player)
		return protected(pos, player) and 0 or stack:get_count()
	end,
	on_metadata_inventory_put = wake,
	on_metadata_inventory_move = wake,
	on_metadata_inventory_take = wake,
	-- what it holds falls out
	on_dig = function(pos, node, digger)
		if protected(pos, digger) then
			return false
		end
		local inv = core.get_meta(pos):get_inventory()
		local drops = {}
		for _, list in ipairs({"bottles", "ingredient", "fuel"}) do
			for _, stack in ipairs(inv:get_list(list) or {}) do
				if not stack:is_empty() then
					drops[#drops + 1] = stack
				end
			end
		end
		if core.node_dig(pos, node, digger) == false then
			return false
		end
		for _, stack in ipairs(drops) do
			core.add_item(vector.offset(pos, math.random() * 0.6 - 0.3, 0.2, math.random() * 0.6 - 0.3), stack)
		end
		return true
	end,
}
-- one node for each set of bottles it can hold (arms empty are the arm's texture flipped)
local ARM, EMPTY = "goodluck_potions_brewing_stand.png", "goodluck_potions_brewing_stand.png^[transformFX"
for bits = 0, 7 do
	local d = table.copy(def)
	d.tiles = {ARM, "goodluck_potions_brewing_stand_base.png"}
	for i = 0, 2 do
		d.tiles[3 + i] = math.floor(bits / 2 ^ i) % 2 == 1 and ARM or EMPTY
	end
	if bits > 0 then
		d.groups = {cracky = 3, not_in_creative_inventory = 1}
	end
	core.register_node(bits == 0 and STAND or STAND .. "_" .. bits, d)
end

core.register_craft({output = STAND, recipe = {{"", "goodluck_nether:blaze_rod", ""},
	{"group:stone", "group:stone", "group:stone"}}})
