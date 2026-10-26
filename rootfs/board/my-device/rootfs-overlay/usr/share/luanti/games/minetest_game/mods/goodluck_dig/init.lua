-- Digging as in Minecraft (Java): a block takes ceil(30 * hardness / speed) ticks of 1/20 s with a tool that can
-- harvest it, else ceil(100 * hardness / speed) and it drops nothing (stone by hand); a block a tick breaks goes at
-- once. A tool's speed counts on its own blocks only (1 elsewhere, as the hand), and it wears one use a block, a
-- sword two. The engine adds the 0.25 s between blocks and the slowdown off the ground and with the head in water.
-- Nodes keep their groups for other mods: mc_* groups carry the Minecraft class, the node's level in their name,
-- so the engine neither divides the times nor multiplies the uses by the difference of levels.
local PICK, SHOVEL, AXE, LEAVES, WEB = "pickaxe", "shovel", "axe", "leaves", "web"
local CREATIVE_HAND = "goodluck_creative:hand"

-- hardness, the tool that digs it fast, and the tier its drops need (0 wood, 1 stone, 2 iron, 3 diamond; none: any)
local BLOCKS = {}
local function blocks(names, data)
	for _, name in ipairs(names) do
		BLOCKS[name] = data
	end
end
blocks({"default:stone", "default:stonebrick", "default:desert_stone", "default:desert_stonebrick",
	"default:permafrost", "default:permafrost_with_moss", "default:permafrost_with_stones",
	"default:coral_brown", "default:coral_orange", "default:coral_skeleton", "goodluck_amethyst:amethyst_block",
	"mobs:mob_repellent", "mobs:trader_block"}, {1.5, PICK, 0})
blocks({"default:cobble", "default:mossycobble", "default:desert_cobble", "default:stone_block",
	"default:desert_stone_block", "default:sandstone_block", "default:desert_sandstone_block",
	"default:silver_sandstone_block", "default:brick", "walls:cobble", "walls:desertcobble", "walls:mossycobble",
	"x_enchanting:grindstone"}, {2, PICK, 0})
blocks({"default:sandstone", "default:desert_sandstone", "default:silver_sandstone", "default:sandstonebrick",
	"default:desert_sandstone_brick", "default:silver_sandstone_brick"}, {0.8, PICK, 0})
blocks({"default:obsidian", "default:obsidianbrick", "default:obsidian_block"}, {50, PICK, 3})
blocks({"default:stone_with_coal"}, {3, PICK, 0})
blocks({"default:stone_with_iron", "default:stone_with_copper", "goodluck_lapis:stone_with_lapis"}, {3, PICK, 1})
blocks({"default:stone_with_gold", "default:stone_with_diamond", "goodluck_redstone:stone_with_redstone",
	"goodluck_redstone:stone_with_redstone_lit", "goodluck_emerald:stone_with_emerald"}, {3, PICK, 2})
blocks({"default:coalblock"}, {5, PICK, 0})
blocks({"default:furnace", "default:furnace_active"}, {3.5, PICK, 0})
blocks({"default:steelblock"}, {5, PICK, 1})
blocks({"default:copperblock", "goodluck_lapis:block"}, {3, PICK, 1})
blocks({"default:goldblock"}, {3, PICK, 2})
blocks({"default:diamondblock", "goodluck_emerald:block"}, {5, PICK, 2})
blocks({"goodluck_redstone:block"}, {5, PICK, 0})
blocks({"default:ice", "default:cave_ice"}, {0.5, PICK})
blocks({"goodluck_amethyst:amethyst_cluster"}, {1.5, PICK})
blocks({"goodluck_amethyst:calcite"}, {0.75, PICK, 0})
blocks({"goodluck_anvil:anvil", "goodluck_anvil:anvil_chipped", "goodluck_anvil:anvil_damaged",
	"x_enchanting:table", "mobs:spawner", "doors:trapdoor_steel", "doors:trapdoor_steel_open", "xpanes:bar",
	"xpanes:bar_flat", "xpanes:trapdoor_steel_bar", "xpanes:trapdoor_steel_bar_open"}, {5, PICK, 0})
blocks({"carts:rail", "carts:powerrail", "carts:brakerail"}, {0.7, PICK})
blocks({"default:ladder_steel"}, {0.4, PICK})
blocks({"default:sign_wall_steel"}, {1, PICK})
blocks({"default:glass", "default:obsidian_glass", "goodluck_redstone:lamp", "goodluck_redstone:lamp_on",
	"xpanes:pane", "xpanes:pane_flat", "xpanes:obsidian_pane", "xpanes:obsidian_pane_flat"}, {0.3})
blocks({"goodluck_food:pumpkin", "goodluck_food:melon", "goodluck_food:jack_o_lantern"}, {1, AXE})
blocks({"goodluck_food:cocoa_1", "goodluck_food:cocoa_2", "goodluck_food:cocoa_3"}, {0.2, AXE})
blocks({"goodluck_food:cake", "goodluck_food:cake_1", "goodluck_food:cake_2", "goodluck_food:cake_3",
	"goodluck_food:cake_4", "goodluck_food:cake_5", "goodluck_food:cake_6"}, {0.5})
blocks({"default:dirt", "default:dry_dirt", "default:dirt_with_rainforest_litter",
	"default:dirt_with_coniferous_litter", "default:sand", "default:desert_sand", "default:silver_sand",
	"mobs:fallback_node"}, {0.5, SHOVEL})
blocks({"default:dirt_with_grass", "default:dirt_with_grass_footsteps", "default:dirt_with_dry_grass",
	"default:dry_dirt_with_dry_grass", "default:dirt_with_snow", "default:gravel", "default:clay", "farming:soil",
	"farming:soil_wet", "farming:dry_soil", "farming:dry_soil_wet", "farming:desert_sand_soil",
	"farming:desert_sand_soil_wet"}, {0.6, SHOVEL})
blocks({"default:snowblock"}, {0.2, SHOVEL, 0})
blocks({"default:snow"}, {0.1, SHOVEL, 0})
blocks({"default:tree", "default:jungletree", "default:pine_tree", "default:acacia_tree", "default:aspen_tree",
	"default:bush_stem", "default:acacia_bush_stem", "default:pine_bush_stem", "default:wood", "default:junglewood",
	"default:pine_wood", "default:acacia_wood", "default:aspen_wood", "mobs:fence_wood", "mobs:fence_top"},
	{2, AXE})
blocks({"default:bookshelf", "vessels:shelf"}, {1.5, AXE})
blocks({"default:chest", "default:chest_open", "default:chest_locked", "default:chest_locked_open",
	"goodluck_chest:left", "goodluck_chest:left_open", "goodluck_chest:right", "goodluck_chest:right_open",
	"goodluck_craft:crafting_table"}, {2.5, AXE})
blocks({"doors:trapdoor", "doors:trapdoor_open"}, {3, AXE})
blocks({"default:ladder_wood"}, {0.4, AXE})
blocks({"default:sign_wall_wood"}, {1, AXE})
blocks({"mobs:beehive"}, {0.6, AXE})
blocks({"default:cactus"}, {0.4})
blocks({"wool:white", "wool:grey", "wool:dark_grey", "wool:black", "wool:violet", "wool:blue", "wool:cyan",
	"wool:dark_green", "wool:green", "wool:yellow", "wool:brown", "wool:orange", "wool:red", "wool:magenta",
	"wool:pink", "mobs:meatblock", "mobs:meatblock_raw"}, {0.8})
blocks({"farming:straw", "x_bows:target", "mobs:cheeseblock"}, {0.5})
blocks({"beds:bed_bottom", "beds:bed_top", "beds:fancy_bed_bottom", "beds:fancy_bed_top"}, {0.2})
blocks({"mobs:hearing_vines", "mobs:hearing_vines_active"}, {0.2, LEAVES})
blocks({"mobs:cobweb"}, {4, WEB, 0})
-- minetest_game's bones dig in half a second by hand
blocks({"bones:bones"}, {0.33})
blocks({"default:coral_cyan", "default:coral_green", "default:coral_pink", "default:apple",
	"default:large_cactus_seedling", "default:sand_with_kelp", "default:papyrus", "default:dry_shrub",
	"default:junglegrass", "mobs:egg", "mobs:honey_block", "tnt:tnt", "tnt:gunpowder", "tnt:gunpowder_burning",
	"fireflies:firefly_bottle"}, {0})
-- families by name
local FAMILIES = {
	{"^doors:door_wood_", {3, AXE}},
	{"^doors:door_steel_", {5, PICK, 0}},
	{"^xpanes:door_steel_bar_", {5, PICK, 0}},
	{"^doors:door_glass_", {0.3}},
	{"^doors:door_obsidian_glass_", {0.3}},
	{"^doors:gate_", {2, AXE}},
	{"^default:fence_", {2, AXE}},
	{"leaves", {0.2, LEAVES}},
	{"needles$", {0.2, LEAVES}},
	{"sapling$", {0}},
	{"^default:torch", {0}},
	{"grass_%d$", {0}},
	{"^default:fern_", {0}},
	{"^flowers:", {0}},
	{"^farming:cotton_", {0}},
	{"^farming:wheat_", {0}},
	{"^farming:seed_", {0}},
	{"^goodluck_food:", {0}},
	{"^fire:", {0}},
	{"^vessels:", {0}},
}

-- anything else by its minetest_game groups
local function by_groups(def)
	local g = def.groups
	if (g.dig_immediate or 0) == 3 then
		return {0}
	elseif (g.dig_immediate or 0) == 2 then
		return {0.33}
	elseif (g.cracky or 0) > 0 then
		if (g.level or 0) >= 2 then
			return {50, PICK, 3}
		end
		return ({{5, PICK, 2}, {3, PICK, 1}, {1.5, PICK, 0}})[math.min(g.cracky, 3)]
	elseif (g.crumbly or 0) > 0 then
		return ({{1, SHOVEL}, {0.6, SHOVEL}, {0.5, SHOVEL}})[math.min(g.crumbly, 3)]
	elseif (g.choppy or 0) > 0 then
		return ({{3, AXE}, {2, AXE}, {1.5, AXE}})[math.min(g.choppy, 3)]
	elseif (g.snappy or 0) > 0 then
		if g.snappy >= 3 and def.drawtype ~= "allfaces_optional" and def.drawtype ~= "normal" then
			return {0}
		end
		return ({{1}, {0.4}, {0.2, LEAVES}})[math.min(g.snappy, 3)]
	end
	return ({{1}, {0.5}, {0.3}})[math.min(g.oddly_breakable_by_hand or 3, 3)]
end

local function block(name, def)
	if BLOCKS[name] then
		return BLOCKS[name]
	end
	for _, family in ipairs(FAMILIES) do
		if name:find(family[1]) then
			return family[2]
		end
	end
	-- stairs and slabs as their material
	local material = name:match("^stairs:stair_inner_(.+)$") or name:match("^stairs:stair_outer_(.+)$")
		or name:match("^stairs:stair_(.+)$") or name:match("^stairs:slab_(.+)$")
	if material then
		for base, data in pairs(BLOCKS) do
			if base:sub(-#material - 1) == ":" .. material then
				return data
			end
		end
	end
	return by_groups(def)
end

-- category, speed, tier, durability; the lava pick is netherite
local TOOLS = {["mobs:pick_lava"] = {PICK, 9, 4, 2031}}
local MATERIALS = {wood = {2, 0, 59}, stone = {4, 1, 131}, copper = {5, 1, 190}, steel = {6, 2, 250},
	gold = {12, 0, 32}, diamond = {8, 3, 1561}}
for material, m in pairs(MATERIALS) do
	TOOLS["default:pick_" .. material] = {PICK, m[1], m[2], m[3]}
	TOOLS["default:shovel_" .. material] = {SHOVEL, m[1], m[2], m[3]}
	TOOLS["default:axe_" .. material] = {AXE, m[1], m[2], m[3]}
	TOOLS["default:sword_" .. material] = {"sword", 1, m[2], m[3]}
end
-- a tool of another mod by its minetest_game groupcaps: the category of its group, the tier of its maxlevel
local LEGACY_TOOL = {cracky = PICK, crumbly = SHOVEL, choppy = AXE, snappy = "sword"}
local TIERS = {{2, 0, 59}, {4, 1, 131}, {6, 2, 250}, {8, 3, 1561}}

local function seconds(hardness, speed, harvest)
	local ticks = (harvest and 30 or 100) * hardness / speed
	if ticks <= 1 then
		return 0
	end
	return math.ceil(ticks - 1e-6) / 20
end

-- the Minecraft classes in use, and the node levels they come with
local classes, class_of, levels = {}, {}, {}
local node_class = {}

local function groupcaps(tool, efficiency, unbreaking, instant)
	local caps = {
		mc_instant = {times = {[1] = 0}, uses = 0, maxlevel = 0},
		-- present, so the engine doesn't dig dig_immediate nodes in its own fixed times
		dig_immediate = {times = {}, uses = 0, maxlevel = 0},
	}
	local uses = 0
	if tool then
		uses = math.max(1, math.floor(tool[4] * (1 + (unbreaking or 0)) / (tool[1] == "sword" and 2 or 1)))
	end
	local any = {}
	for r, c in ipairs(classes) do
		any[r] = instant and 0 or seconds(c[1], 1, c[3] == nil)
	end
	for level in pairs(levels) do
		caps["mc_l" .. level] = {times = any, uses = uses, maxlevel = level}
	end
	if tool and not instant then
		local speeds = {[tool[1]] = tool[2] + ((efficiency or 0) > 0 and efficiency * efficiency + 1 or 0)}
		if tool[1] == "sword" then
			speeds = {[LEAVES] = 1.5, [WEB] = 15}
		end
		for category, speed in pairs(speeds) do
			local times = {}
			for r, c in ipairs(classes) do
				if c[2] == category then
					times[r] = seconds(c[1], speed, c[3] == nil or tool[3] >= c[3])
				end
			end
			for level in pairs(levels) do
				caps["mc_" .. category .. "_l" .. level] = {times = times, uses = uses, maxlevel = level}
			end
		end
	end
	return caps
end

-- whether the tool in hand gets the block's drops
local function harvests(node_name, stack)
	local c = node_class[node_name]
	if not c or not c[3] then
		return true
	end
	local tool = TOOLS[stack:get_name()]
	if not tool then
		return false
	end
	return (tool[1] == "sword" and WEB or tool[1]) == c[2] and tool[3] >= c[3]
end

local LEGACY = {"cracky", "crumbly", "choppy", "snappy", "oddly_breakable_by_hand", "dig_immediate"}

core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_nodes) do
		local legacy
		for _, group in ipairs(LEGACY) do
			if (def.groups[group] or 0) > 0 then
				legacy = legacy or group
			end
		end
		if legacy then
			local c = block(name, def)
			local groups = table.copy(def.groups)
			if c[1] == 0 then
				groups.mc_instant = 1
			else
				local level = groups.level or 0
				local key = c[1] .. "|" .. (c[2] or "") .. "|" .. (c[3] or "")
				if not class_of[key] then
					classes[#classes + 1] = c
					class_of[key] = #classes
				end
				groups["mc_l" .. level] = class_of[key]
				if c[2] then
					groups["mc_" .. c[2] .. "_l" .. level] = class_of[key]
				end
				levels[level] = true
			end
			node_class[name] = c
			local override = {groups = groups}
			-- the dig sound named by the group that digs (the engine's "__group") is still minetest_game's
			local dig = def.sounds and def.sounds.dig
			if not dig or (type(dig) == "table" and dig.name == "__group") then
				override.sounds = table.copy(def.sounds or {})
				override.sounds.dig = {name = "default_dig_" .. legacy, gain = 0.5}
			end
			core.override_item(name, override)
		end
	end

	for name, def in pairs(core.registered_items) do
		local caps = def.tool_capabilities
		local tool = TOOLS[name]
		if not tool and caps and caps.groupcaps and name ~= "" and name ~= CREATIVE_HAND then
			for group, cap in pairs(caps.groupcaps) do
				if LEGACY_TOOL[group] then
					local t = TIERS[math.max(1, math.min((cap.maxlevel or 0) + 1, 4))]
					tool = {LEGACY_TOOL[group], t[1], t[2], t[3]}
					TOOLS[name] = tool
				end
			end
		end
		if tool or name == "" or name == CREATIVE_HAND then
			caps = table.copy(caps or {})
			caps.groupcaps = groupcaps(tool, 0, 0, name == CREATIVE_HAND)
			core.override_item(name, {tool_capabilities = caps})
		end
	end

	-- no drops when the tool can't harvest the block (outermost, so silk touch and fortune don't add them back)
	local get_node_drops = core.get_node_drops
	local skip
	function core.get_node_drops(node, toolname, tool, digger, pos)
		local drops = get_node_drops(node, toolname, tool, digger, pos)
		local name = type(node) == "table" and node.name or node
		skip = nil
		if pos and digger and digger:is_player() and not core.is_creative_enabled(digger:get_player_name())
				and not harvests(name, tool or ItemStack(toolname)) then
			skip = core.hash_node_position(pos)
			return {}
		end
		return drops
	end
	local handle_node_drops = core.handle_node_drops
	function core.handle_node_drops(pos, drops, digger)
		if skip and skip == core.hash_node_position(pos) then
			skip = nil
			return
		end
		return handle_node_drops(pos, drops, digger)
	end
end)

-- Minecraft's Efficiency (speed + level^2 + 1 on the tool's own blocks) and Unbreaking (level + 1 times the uses);
-- Efficiency doesn't speed up attacks there
if core.global_exists("XEnchanting") then
	local enchanted = XEnchanting.get_enchanted_tool_capabilities
	function XEnchanting.get_enchanted_tool_capabilities(self, tool_def, enchantments)
		local caps = enchanted(self, tool_def, enchantments)
		local tool = TOOLS[tool_def.name]
		if tool then
			local efficiency, unbreaking = 0, 0
			for _, e in ipairs(enchantments) do
				if e.id == "efficiency" then
					efficiency = e.level or 1
				elseif e.id == "unbreaking" then
					unbreaking = e.level or 1
				end
			end
			caps.groupcaps = groupcaps(tool, efficiency, unbreaking)
			caps.full_punch_interval = tool_def.tool_capabilities.full_punch_interval
		end
		return caps
	end

	-- an enchanted tool made before keeps its old capabilities in its meta: they're made again when it's used
	local function refresh(stack)
		local meta = stack:get_meta()
		if meta:get_int("is_enchanted") ~= 1 or not TOOLS[stack:get_name()] then
			return false
		end
		local caps = stack:get_tool_capabilities()
		if caps.groupcaps and caps.groupcaps.mc_instant then
			return false
		end
		local list = {}
		for id, e in pairs(core.deserialize(meta:get_string("x_enchanting")) or {}) do
			local level = 1
			local def = XEnchanting.enchantment_defs[id]
			for l, value in pairs(def and def.level_def or {}) do
				if value == e.value then
					level = l
				end
			end
			list[#list + 1] = {id = id, value = e.value, level = level}
		end
		meta:set_tool_capabilities(XEnchanting:get_enchanted_tool_capabilities(stack:get_definition(), list))
		return true
	end
	core.register_on_punchnode(function(_, _, puncher)
		if puncher and puncher:is_player() then
			local stack = puncher:get_wielded_item()
			if refresh(stack) then
				puncher:set_wielded_item(stack)
			end
		end
	end)
	core.register_on_joinplayer(function(player)
		local inv = player:get_inventory()
		for list, stacks in pairs(inv:get_lists()) do
			for i, stack in ipairs(stacks) do
				if refresh(stack) then
					inv:set_stack(list, i, stack)
				end
			end
		end
	end)
end
