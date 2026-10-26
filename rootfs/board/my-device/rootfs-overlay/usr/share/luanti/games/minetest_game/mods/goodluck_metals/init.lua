-- Minecraft's metals: copper in the place of tin and bronze, with what Minecraft makes of it since 1.21.9 (tools,
-- hoe, armor, nuggets), its ore giving 2 to 5 raw copper; and golden tools. Copper hits as stone and gold as wood
-- (goodluck_dig gives their speeds and uses). Worlds from before find copper where tin and bronze were
local S = core.get_translator("goodluck_metals")
local COPPER, GOLD = "default:copper_ingot", "default:gold_ingot"
local NUGGET = "goodluck_metals:copper_nugget"
local GOLD_NUGGET = "goodluck_food:gold_nugget"

local METALS = {
	copper = {ingot = COPPER, like = "stone", enchantability = 13, uses = 190, nugget = NUGGET,
		names = {pick = S("Copper Pickaxe"), shovel = S("Copper Shovel"), axe = S("Copper Axe"),
			sword = S("Copper Sword"), hoe = S("Copper Hoe")}},
	gold = {ingot = GOLD, like = "wood", enchantability = 22, uses = 32, nugget = GOLD_NUGGET,
		names = {pick = S("Golden Pickaxe"), shovel = S("Golden Shovel"), axe = S("Golden Axe"),
			sword = S("Golden Sword"), hoe = S("Golden Hoe")}},
}
local SHAPES = {
	pick = {{"m", "m", "m"}, {"", "s", ""}, {"", "s", ""}},
	shovel = {{"m"}, {"s"}, {"s"}},
	axe = {{"m", "m"}, {"m", "s"}, {"", "s"}},
	sword = {{"m"}, {"m"}, {"s"}},
}

local function recipe(shape, material)
	local r = {}
	for i, row in ipairs(shape) do
		r[i] = {}
		for j, c in ipairs(row) do
			r[i][j] = c == "m" and material or c == "s" and "group:stick" or ""
		end
	end
	return r
end

local smelts = {copper = {}, gold = {}}
for metal, m in pairs(METALS) do
	for kind, shape in pairs(SHAPES) do
		local name = "default:" .. kind .. "_" .. metal
		local def = table.copy(core.registered_tools["default:" .. kind .. "_" .. m.like])
		def.description = m.names[kind]
		def.inventory_image = "goodluck_metals_" .. kind .. "_" .. metal .. ".png"
		def.groups.flammable = nil
		def.groups.enchantability = m.enchantability
		core.register_tool(":" .. name, def)
		core.register_craft({output = name, recipe = recipe(shape, m.ingot)})
		smelts[metal][#smelts[metal] + 1] = name
	end
	farming.register_hoe(":farming:hoe_" .. metal, {
		description = m.names.hoe,
		inventory_image = "goodluck_metals_hoe_" .. metal .. ".png",
		max_uses = m.uses,
		material = m.ingot,
		groups = {hoe = 1},
	})
	smelts[metal][#smelts[metal] + 1] = "farming:hoe_" .. metal
end
-- Minecraft lets the axe's head face either way
core.register_craft({output = "default:axe_copper", recipe = {{COPPER, COPPER}, {"group:stick", COPPER},
	{"group:stick", ""}}})
core.register_craft({output = "default:axe_gold", recipe = {{GOLD, GOLD}, {"group:stick", GOLD},
	{"group:stick", ""}}})

-- Minecraft's copper armor against its iron (2, 4, 3, 1 points to 2, 6, 5, 2; 11 times the uses to 15) on
-- 3d_armor's steel
if core.get_modpath("3d_armor") then
	local ARMOR = {
		helmet = {S("Copper Helmet"), 2 / 2, {{"m", "m", "m"}, {"m", "", "m"}}},
		chestplate = {S("Copper Chestplate"), 4 / 6, {{"m", "", "m"}, {"m", "m", "m"}, {"m", "m", "m"}}},
		leggings = {S("Copper Leggings"), 3 / 5, {{"m", "m", "m"}, {"m", "", "m"}, {"m", "", "m"}}},
		boots = {S("Copper Boots"), 1 / 2, {{"m", "", "m"}, {"m", "", "m"}}},
	}
	for piece, a in pairs(ARMOR) do
		local steel = core.registered_tools["3d_armor:" .. piece .. "_steel"]
		local name = "3d_armor:" .. piece .. "_copper"
		local groups = table.copy(steel.groups)
		groups.armor_use = math.floor(groups.armor_use * 15 / 11)
		armor:register_armor(":" .. name, {
			description = a[1],
			inventory_image = "3d_armor_inv_" .. piece .. "_copper.png",
			groups = groups,
			armor_groups = {fleshy = math.floor(steel.armor_groups.fleshy * a[2] + 0.5)},
			damage_groups = table.copy(steel.damage_groups),
		})
		core.register_craft({output = name, recipe = recipe(a[3], COPPER)})
		smelts.copper[#smelts.copper + 1] = name
		smelts.gold[#smelts.gold + 1] = "3d_armor:" .. piece .. "_gold"
	end
end

core.register_craftitem(NUGGET, {
	description = S("Copper Nugget"),
	inventory_image = "goodluck_metals_copper_nugget.png",
})
core.register_craft({type = "shapeless", output = NUGGET .. " 9", recipe = {COPPER}})
core.register_craft({output = COPPER, recipe = {{NUGGET, NUGGET, NUGGET}, {NUGGET, NUGGET, NUGGET},
	{NUGGET, NUGGET, NUGGET}}})

-- copper and golden gear melts down to a nugget
for metal, names in pairs(smelts) do
	if core.registered_items[METALS[metal].nugget] then
		for _, name in ipairs(names) do
			if core.registered_items[name] then
				core.register_craft({type = "cooking", output = METALS[metal].nugget, recipe = name, cooktime = 10})
			end
		end
	end
end

-- 2 to 5 as in Minecraft, each as likely: the first entry that comes up is the drop
core.override_item("default:stone_with_copper", {drop = {max_items = 1, items = {
	{items = {"default:copper_lump 5"}, rarity = 4},
	{items = {"default:copper_lump 4"}, rarity = 3},
	{items = {"default:copper_lump 3"}, rarity = 2},
	{items = {"default:copper_lump 2"}},
}}})

-- tin and bronze go (other mods' recipes and drops that name them get copper through the aliases)
local GONE = {
	["default:stone_with_tin"] = "default:stone_with_copper",
	["default:tin_lump"] = "default:copper_lump",
	["default:tin_ingot"] = COPPER,
	["default:bronze_ingot"] = COPPER,
	["default:tinblock"] = "default:copperblock",
	["default:bronzeblock"] = "default:copperblock",
	["farming:hoe_bronze"] = "farming:hoe_copper",
	["shields:shield_bronze"] = "shields:shield_steel",
}
for _, kind in ipairs({"pick", "shovel", "axe", "sword"}) do
	GONE["default:" .. kind .. "_bronze"] = "default:" .. kind .. "_copper"
end
for _, piece in ipairs({"helmet", "chestplate", "leggings", "boots"}) do
	GONE["3d_armor:" .. piece .. "_bronze"] = "3d_armor:" .. piece .. "_copper"
end
for _, block in ipairs({"tinblock", "bronzeblock"}) do
	for _, shape in ipairs({"stair", "stair_inner", "stair_outer", "slab"}) do
		GONE["stairs:" .. shape .. "_" .. block] = "stairs:" .. shape .. "_copperblock"
	end
end
for old, new in pairs(GONE) do
	if core.registered_items[old] then
		if core.get_all_craft_recipes(old) then
			core.clear_craft({output = old})
		end
		core.unregister_item(old)
	end
	core.register_alias(old, new)
end
