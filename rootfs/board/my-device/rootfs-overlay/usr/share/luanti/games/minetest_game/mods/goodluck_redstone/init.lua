-- Redstone in mese's place, as in Minecraft: the ore, lit for a while when punched, 4 or 5 dust from it, the block
-- and the lamp. No circuits yet: a block of redstone next to a lamp lights it. Mese is gone; worlds from before find
-- redstone where it was, its lamps lit, and diamond tools for mese ones
local S = core.get_translator("goodluck_redstone")
local DUST = "goodluck_redstone:redstone"
local ORE, LIT = "goodluck_redstone:stone_with_redstone", "goodluck_redstone:stone_with_redstone_lit"
local BLOCK = "goodluck_redstone:block"
local LAMP, LAMP_ON = "goodluck_redstone:lamp", "goodluck_redstone:lamp_on"
local SIDES = {vector.new(1, 0, 0), vector.new(-1, 0, 0), vector.new(0, 1, 0), vector.new(0, -1, 0),
	vector.new(0, 0, 1), vector.new(0, 0, -1)}
local sparks = {}

core.register_craftitem(DUST, {
	description = S("Redstone Dust"),
	inventory_image = "goodluck_redstone_dust.png",
})

local function unlight(pos)
	local key = core.hash_node_position(pos)
	if sparks[key] then
		core.delete_particlespawner(sparks[key])
		sparks[key] = nil
	end
end

-- lit while punched and for a while after (Minecraft: until a random tick); red dust floats around it meanwhile
local function light(pos)
	local seconds = math.random(20, 60)
	if core.get_node(pos).name ~= LIT then
		core.swap_node(pos, {name = LIT})
	end
	unlight(pos)
	sparks[core.hash_node_position(pos)] = core.add_particlespawner({
		amount = seconds * 2,
		time = seconds,
		minpos = vector.subtract(pos, 0.6),
		maxpos = vector.add(pos, 0.6),
		minexptime = 0.5,
		maxexptime = 1,
		minsize = 0.6,
		maxsize = 1,
		texture = "[fill:2x2:0,0:#ff3020",
		glow = 9,
	})
	core.get_node_timer(pos):start(seconds)
end

local ore = {
	description = S("Redstone Ore"),
	tiles = {"default_stone.png^goodluck_redstone_mineral.png"},
	groups = table.copy(core.registered_nodes["default:stone_with_diamond"].groups),
	-- 4 or 5 as in Minecraft
	drop = {max_items = 2, items = {{items = {DUST .. " 4"}}, {items = {DUST}, rarity = 2}}},
	sounds = default.node_sound_stone_defaults(),
	on_punch = function(pos, node, puncher, pointed_thing)
		light(pos)
		return core.node_punch(pos, node, puncher, pointed_thing)
	end,
}
core.register_node(ORE, ore)

local lit = table.copy(ore)
lit.light_source = 9
lit.groups.not_in_creative_inventory = 1
lit.on_timer = function(pos)
	unlight(pos)
	core.swap_node(pos, {name = ORE})
end
-- dug as the unlit ore, so its drops, silk touch and experience are the ore's
lit.on_dig = function(pos, node, digger)
	unlight(pos)
	core.swap_node(pos, {name = ORE})
	return core.node_dig(pos, core.get_node(pos), digger)
end
core.register_node(LIT, lit)

local function update_lamp(pos)
	local name = core.get_node(pos).name
	if name ~= LAMP and name ~= LAMP_ON then
		return
	end
	local powered = false
	for _, side in ipairs(SIDES) do
		powered = powered or core.get_node(vector.add(pos, side)).name == BLOCK
	end
	local want = powered and LAMP_ON or LAMP
	if name ~= want then
		core.swap_node(pos, {name = want})
	end
end

local function update_lamps(pos)
	for _, side in ipairs(SIDES) do
		update_lamp(vector.add(pos, side))
	end
end

core.register_node(BLOCK, {
	description = S("Block of Redstone"),
	tiles = {"goodluck_redstone_block.png"},
	is_ground_content = false,
	groups = {cracky = 1, level = 2},
	sounds = default.node_sound_metal_defaults(),
	on_construct = update_lamps,
	after_destruct = update_lamps,
})

-- its recipe (four dust around glowstone) comes with the Nether
core.register_node(LAMP, {
	description = S("Redstone Lamp"),
	tiles = {"goodluck_redstone_lamp.png"},
	is_ground_content = false,
	groups = {cracky = 3, oddly_breakable_by_hand = 3},
	sounds = default.node_sound_glass_defaults(),
	on_construct = update_lamp,
})

core.register_node(LAMP_ON, {
	description = S("Redstone Lamp"),
	tiles = {"goodluck_redstone_lamp_on.png"},
	light_source = core.LIGHT_MAX,
	is_ground_content = false,
	groups = {cracky = 3, oddly_breakable_by_hand = 3, not_in_creative_inventory = 1},
	drop = LAMP,
	sounds = default.node_sound_glass_defaults(),
})

core.register_craft({
	output = BLOCK,
	recipe = {
		{DUST, DUST, DUST},
		{DUST, DUST, DUST},
		{DUST, DUST, DUST},
	},
})

core.register_craft({
	output = DUST .. " 9",
	recipe = {{BLOCK}},
})

-- Minecraft's powered rail: six gold ingots around a stick, redstone under it
if core.get_modpath("carts") then
	core.clear_craft({output = "carts:powerrail"})
	core.register_craft({
		output = "carts:powerrail 6",
		recipe = {
			{"default:gold_ingot", "", "default:gold_ingot"},
			{"default:gold_ingot", "group:stick", "default:gold_ingot"},
			{"default:gold_ingot", DUST, "default:gold_ingot"},
		},
	})
end

-- dungeon chests have it in Minecraft
if core.get_modpath("dungeon_loot") then
	dungeon_loot.register({name = DUST, chance = 0.3, count = {1, 4}})
end

-- as in Minecraft before 1.18: 8 veins of ~6 (its size 8) a 16x16 column up to its y 16 (ours -46, see
-- goodluck_ores) and on down, as diamonds; new terrain only
core.register_ore({
	ore_type = "scatter",
	ore = ORE,
	wherein = "default:stone",
	clust_scarcity = 16 * 16 * 16 / 8,
	clust_num_ores = 6,
	clust_size = 2,
	y_max = -46,
	y_min = -31000,
})

-- mese goes (other mods' recipes and drops of it get redstone through the aliases)
local GONE = {
	["default:stone_with_mese"] = ORE,
	["default:mese"] = BLOCK,
	["default:mese_crystal"] = DUST,
	["default:mese_crystal_fragment"] = DUST,
	["default:meselamp"] = LAMP_ON,
	["default:mese_post_light"] = LAMP_ON,
	["default:mese_post_light_acacia_wood"] = LAMP_ON,
	["default:mese_post_light_aspen_wood"] = LAMP_ON,
	["default:mese_post_light_junglewood"] = LAMP_ON,
	["default:mese_post_light_pine_wood"] = LAMP_ON,
	["default:pick_mese"] = "default:pick_diamond",
	["default:shovel_mese"] = "default:shovel_diamond",
	["default:axe_mese"] = "default:axe_diamond",
	["default:sword_mese"] = "default:sword_diamond",
	["farming:hoe_mese"] = "farming:hoe_diamond",
}
for old, new in pairs(GONE) do
	if core.registered_items[old] then
		if core.get_all_craft_recipes(old) then
			core.clear_craft({output = old})
		end
		core.unregister_item(old)
	end
	core.register_alias(old, new)
end
