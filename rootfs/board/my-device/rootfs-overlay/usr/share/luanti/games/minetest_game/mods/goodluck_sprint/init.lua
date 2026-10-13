-- Aux1 while moving forward runs at goodluck_sprint_speed times the walk; less than half forward ends it
local speed = tonumber(core.settings:get("goodluck_sprint_speed") or "") or 1.5
-- with stamina on, running drains hunger as stamina's own sprint does and needs more than 6 points
local hunger = core.get_modpath("stamina") and stamina
-- 3d_armor sets the walk speed (heavy armor is slower) each time the armor changes
local armor_mod = core.get_modpath("3d_armor") and armor
local DRAIN_TICK = 0.5
local running, held = {}, {}
local drain_timer = 0

local function fed(player, name)
	return not hunger or not hunger.players[name] or hunger.get_saturation(player) > 6
end

local function walk_speed(name)
	local def = armor_mod and armor_mod.def[name]
	return def and def.speed or 1
end

local function set_running(player, name, on)
	if running[name] == on then
		return
	end
	running[name] = on
	local walk = walk_speed(name)
	if on then
		player:set_physics_override({speed = walk * speed})
	-- a bed or another mod may have changed the speed meanwhile: leave theirs
	elseif math.abs(player:get_physics_override().speed - walk * speed) < 0.001 then
		player:set_physics_override({speed = walk})
	end
end

core.register_globalstep(function(dtime)
	drain_timer = drain_timer + dtime
	local drain = drain_timer >= DRAIN_TICK
	if drain then drain_timer = 0 end
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local ctrl = player:get_player_control()
		local forward = ctrl.movement_y or 0
		if forward < 0.5 or not fed(player, name) then
			set_running(player, name, false)
		elseif ctrl.aux1 and not held[name] then
			set_running(player, name, true)
		end
		held[name] = ctrl.aux1
		if drain and running[name] and hunger and hunger.players[name] then
			hunger.change_saturation(player, -hunger.SPRINT_DRAIN * DRAIN_TICK)
		end
	end
end)

if armor_mod then
	armor:register_on_update(function(player)
		local name = player:get_player_name()
		if running[name] then
			player:set_physics_override({speed = walk_speed(name) * speed})
		end
	end)
end

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	running[name], held[name] = nil, nil
end)
