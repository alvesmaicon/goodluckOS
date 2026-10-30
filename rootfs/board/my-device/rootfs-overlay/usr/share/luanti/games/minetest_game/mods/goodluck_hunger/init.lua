-- Hunger costs as in Minecraft: walking, placing and crafting are free, digging and jumping cost little
-- (stamina takes a point for every 160 of exhaustion); running drains stamina_sprint_drain points a second
if not core.get_modpath("stamina") then
	return
end
local S = core.get_translator("goodluck_hunger")
stamina.EXHAUST_MOVE = 0
stamina.EXHAUST_PLACE = 0
stamina.EXHAUST_CRAFT = 0
stamina.EXHAUST_DIG = 0.2  -- 800 nodes a point
stamina.EXHAUST_JUMP = 2   -- about 80 jumps a point

-- Minecraft's Hunger effect (rotten flesh, goodluck_effects): the drumsticks go green while it lasts, 30 s, and hunger
-- drains 0.1 exhaustion a second a level (4 here: a point is 160, Minecraft's 4)
goodluck_hunger = {}
local LENGTH, DRAIN = 30, 4
local GREEN, NORMAL = "stamina_hud_poison.png", "stamina_hud_fg.png"

local function show(player, green)
	local data = stamina.players[player:get_player_name()]
	if data and not stamina.is_poisoned(player) and not stamina.is_drunk(player) then
		player:hud_change(data.hud_id, "text", green and GREEN or NORMAL)
	end
end

function goodluck_hunger.hungry(player, seconds)
	if core.global_exists("goodluck_effects") then
		goodluck_effects.apply(player, "hunger", seconds or LENGTH, 1)
	end
end

if core.global_exists("goodluck_effects") then
	goodluck_effects.register("hunger", {description = S("Hunger"), color = "#587653", bad = true,
		interval = function() return 1 end,
		-- stamina puts its own texture back when its poison ends
		on_interval = function(player, level)
			stamina.exhaust_player(player, DRAIN * level)
			show(player, true)
		end,
		on_start = function(player) show(player, true) end,
		on_stop = function(player) show(player, false) end})
end
