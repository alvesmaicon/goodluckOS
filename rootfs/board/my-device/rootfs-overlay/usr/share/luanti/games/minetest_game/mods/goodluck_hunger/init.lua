-- Hunger costs as in Minecraft: walking, placing and crafting are free, digging and jumping cost little
-- (stamina takes a point for every 160 of exhaustion); running drains stamina_sprint_drain points a second
if not core.get_modpath("stamina") then
	return
end
stamina.EXHAUST_MOVE = 0
stamina.EXHAUST_PLACE = 0
stamina.EXHAUST_CRAFT = 0
stamina.EXHAUST_DIG = 0.2  -- 800 nodes a point
stamina.EXHAUST_JUMP = 2   -- about 80 jumps a point

-- Minecraft's Hunger effect (rotten flesh): the drumsticks go green for 30 s, eating another starts them again, and
-- hunger drains 0.1 exhaustion a second (4 here: a point is 160, Minecraft's 4); gone on death, kept over a rejoin
goodluck_hunger = {}
local LENGTH, DRAIN = 30, 4
local GREEN, NORMAL = "stamina_hud_poison.png", "stamina_hud_fg.png"
local left = {}

local function show(player, green)
	local data = stamina.players[player:get_player_name()]
	if data and not stamina.is_poisoned(player) and not stamina.is_drunk(player) then
		player:hud_change(data.hud_id, "text", green and GREEN or NORMAL)
	end
end

function goodluck_hunger.hungry(player, seconds)
	left[player:get_player_name()] = seconds or LENGTH
	show(player, true)
end

local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 1 then return end
	timer = timer - 1
	for name, t in pairs(left) do
		local player = core.get_player_by_name(name)
		if player then
			stamina.exhaust_player(player, DRAIN)
			-- stamina puts its own texture back when its poison ends
			show(player, t > 1)
			left[name] = t > 1 and t - 1 or nil
		else
			left[name] = nil
		end
	end
end)

core.register_on_dieplayer(function(player)
	if left[player:get_player_name()] then
		left[player:get_player_name()] = nil
		show(player, false)
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	player:get_meta():set_int("goodluck_hunger:hungry", left[name] or 0)
	left[name] = nil
end)

core.register_on_joinplayer(function(player)
	local t = player:get_meta():get_int("goodluck_hunger:hungry")
	if t > 0 then
		-- after stamina's own join, which makes the bar
		local name = player:get_player_name()
		core.after(0, function()
			player = core.get_player_by_name(name)
			if player then goodluck_hunger.hungry(player, t) end
		end)
	end
end)
