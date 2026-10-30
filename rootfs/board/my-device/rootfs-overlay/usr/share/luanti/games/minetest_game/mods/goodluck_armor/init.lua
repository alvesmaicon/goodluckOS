-- Minecraft's armor where 3d_armor has its own: leather armor in place of wood and cactus armor, and one shield,
-- Minecraft's, in place of eleven. Worlds from before find leather armor and the shield instead
local S = core.get_translator("goodluck_armor")
local LEATHER = "mobs:leather"
local SHIELD = "shields:shield_enhanced_wood"

-- Minecraft's leather against its iron (1, 3, 2, 1 points to 2, 6, 5, 2; 5 times the uses to 15) on 3d_armor's steel
local PIECES = {
	helmet = {S("Leather Cap"), 1 / 2, {{"m", "m", "m"}, {"m", "", "m"}}},
	chestplate = {S("Leather Tunic"), 3 / 6, {{"m", "", "m"}, {"m", "m", "m"}, {"m", "m", "m"}}},
	leggings = {S("Leather Pants"), 2 / 5, {{"m", "m", "m"}, {"m", "", "m"}, {"m", "", "m"}}},
	boots = {S("Leather Boots"), 1 / 2, {{"m", "", "m"}, {"m", "", "m"}}},
}
for piece, p in pairs(PIECES) do
	local steel = core.registered_tools["3d_armor:" .. piece .. "_steel"]
	local name = "3d_armor:" .. piece .. "_leather"
	local groups = table.copy(steel.groups)
	groups.armor_use = math.floor(groups.armor_use * 15 / 5)
	groups.physics_speed, groups.physics_gravity = nil, nil
	local recipe = {}
	for i, row in ipairs(p[3]) do
		recipe[i] = {}
		for j, c in ipairs(row) do
			recipe[i][j] = c == "m" and LEATHER or ""
		end
	end
	armor:register_armor(":" .. name, {
		description = p[1],
		inventory_image = "3d_armor_inv_" .. piece .. "_leather.png",
		groups = groups,
		armor_groups = {fleshy = math.floor(steel.armor_groups.fleshy * p[2] + 0.5)},
		damage_groups = table.copy(steel.damage_groups),
	})
	core.register_craft({output = name, recipe = recipe})
end

-- the shield: six planks and an iron ingot; no armor points of its own, only blocking (goodluck_shield), and
-- Minecraft's 336 uses at 4 a zombie's hit (a blocked hit costs 1 + its damage)
local shield_groups = table.copy(core.registered_items[SHIELD].groups)
shield_groups.armor_use = 800
core.override_item(SHIELD, {
	description = S("Shield"),
	groups = shield_groups,
	armor_groups = {fleshy = 0},
	reciprocate_damage = false,
})
core.clear_craft({output = SHIELD})
core.register_craft({
	output = SHIELD,
	recipe = {
		{"group:wood", "default:steel_ingot", "group:wood"},
		{"group:wood", "group:wood", "group:wood"},
		{"", "group:wood", ""},
	},
})

local GONE = {}
for _, piece in ipairs({"helmet", "chestplate", "leggings", "boots"}) do
	GONE["3d_armor:" .. piece .. "_wood"] = "3d_armor:" .. piece .. "_leather"
	GONE["3d_armor:" .. piece .. "_cactus"] = "3d_armor:" .. piece .. "_leather"
end
for _, kind in ipairs({"wood", "cactus", "enhanced_cactus", "steel", "bronze", "gold", "diamond", "crystal",
		"mithril", "nether", "admin"}) do
	GONE["shields:shield_" .. kind] = SHIELD
end
for old, new in pairs(GONE) do
	if core.registered_items[old] then
		if core.get_all_craft_recipes(old) then
			core.clear_craft({output = old})
		end
		-- wooden armor and shields burned; leather armor and the shield don't
		if core.get_craft_result({method = "fuel", width = 1, items = {old}}).time > 0 then
			core.clear_craft({type = "fuel", recipe = old})
		end
		core.unregister_item(old)
	end
	core.register_alias(old, new)
end
