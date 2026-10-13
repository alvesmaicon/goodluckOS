-- Armor above the hearts, hunger in the hearts' row on the right (stamina_hud_x/y), breath one row above hunger
if not core.settings:get_bool("enable_damage") then
	return
end

local ROW = 22
local HEARTS_Y = -(48 + 24 + 16)

core.hud_replace_builtin("breath", {
	type = "statbar",
	position = {x = 0.5, y = 1},
	text = "bubble.png",
	text2 = "bubble_gone.png",
	number = core.PLAYER_MAX_BREATH_DEFAULT * 2,
	item = core.PLAYER_MAX_BREATH_DEFAULT * 2,
	direction = 0,
	size = {x = 24, y = 24},
	offset = {x = 25, y = HEARTS_Y - ROW},
})

local hunger = core.get_modpath("stamina") and stamina
local armor_mod = core.get_modpath("3d_armor") and armor
local armor_hud = {}

-- 3d_armor's level is the damage it takes away in percent: one chestplate per 10 %
local function armor_points(name)
	local def = armor_mod.def[name]
	return math.min(20, math.floor((def and def.level or 0) / 5 + 0.5))
end

local function update_armor(player)
	local name = player:get_player_name()
	local id = armor_hud[name]
	if not id then
		return
	end
	local points = core.is_creative_enabled(name) and 0 or armor_points(name)
	player:hud_change(id, "number", points)
	player:hud_change(id, "item", points > 0 and 20 or 0)
end

-- creative has no hunger or armor bar, as in Minecraft (goodluck_creative hides the hearts and breath)
local function update_bars(player)
	local name = player:get_player_name()
	local creative = core.is_creative_enabled(name)
	local data = hunger and hunger.players[name]
	if data then
		player:hud_change(data.hud_id, "number", creative and 0 or hunger.get_saturation(player))
		player:hud_change(data.hud_id, "item", creative and 0 or hunger.VISUAL_MAX)
	end
	if armor_mod then
		update_armor(player)
	end
end

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	-- empty drumsticks behind the full ones, as stamina draws only the full ones
	local data = hunger and hunger.players[name]
	if data then
		player:hud_change(data.hud_id, "text2", "stamina_hud_bg.png")
	end
	if armor_mod then
		armor_hud[name] = player:hud_add({
			type = "statbar",
			position = {x = 0.5, y = 1},
			text = "goodluck_armor.png",
			text2 = "goodluck_armor_bg.png",
			number = 0,
			item = 0,
			direction = 0,
			size = {x = 24, y = 24},
			offset = {x = -265, y = HEARTS_Y - ROW},
		})
	end
	update_bars(player)
end)

core.register_on_leaveplayer(function(player)
	armor_hud[player:get_player_name()] = nil
end)

if armor_mod then
	armor:register_on_update(update_armor)
end

if core.get_modpath("goodluck_creative") then
	goodluck_creative.register_on_change(update_bars)
end
