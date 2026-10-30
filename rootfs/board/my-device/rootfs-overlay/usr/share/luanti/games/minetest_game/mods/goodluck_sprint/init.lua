-- Aux1 while moving forward runs at goodluck_sprint_speed times the walk; less than half forward ends it
local speed = tonumber(core.settings:get("goodluck_sprint_speed") or "") or 1.5
-- and widens the view by goodluck_sprint_fov (1 for none), so the run shows, as in Minecraft
local fov = tonumber(core.settings:get("goodluck_sprint_fov") or "") or 1.1
local FOV_TIME = 0.2
-- with stamina on, running drains hunger as stamina's own sprint does and needs more than 6 points (not in creative)
local hunger = core.get_modpath("stamina") and stamina
local DRAIN_TICK = 0.5
local running, held, stopped = {}, {}, {}
local drain_timer = 0

goodluck_sprint = {}

local function hungry(name)
	return hunger and hunger.players[name] and not core.is_creative_enabled(name)
end

local function fed(player, name)
	return not hungry(name) or hunger.get_saturation(player) > 6
end

local function set_running(player, name, on)
	if running[name] == on then
		return
	end
	local was = running[name]
	running[name] = on
	-- never on the first step: in the engine a FOV transition that changes nothing never ends
	if fov ~= 1 and (on or was) then
		player:set_fov(on and fov or 0, on, FOV_TIME)
	end
	goodluck_physics.set(player, "goodluck_sprint", on and {speed = speed} or nil)
end

function goodluck_sprint.running(player)
	return running[player:get_player_name()] or false
end

-- another mod (the shield, the binoculars) ends the run and keeps a new one from starting until every one lets go
function goodluck_sprint.stop(player, on, by)
	local name = player:get_player_name()
	stopped[name] = stopped[name] or {}
	stopped[name][by or "?"] = on or nil
	if on then
		set_running(player, name, false)
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
		if forward < 0.5 or next(stopped[name] or {}) or not fed(player, name) then
			set_running(player, name, false)
		elseif ctrl.aux1 and not held[name] then
			set_running(player, name, true)
		end
		held[name] = ctrl.aux1
		if drain and running[name] and hungry(name) then
			-- swimming tires a tenth of running, as in Minecraft
			local swim = player:get_physics_override().swim and 0.1 or 1
			hunger.change_saturation(player, -hunger.SPRINT_DRAIN * DRAIN_TICK * swim)
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	running[name], held[name], stopped[name] = nil, nil, nil
end)
