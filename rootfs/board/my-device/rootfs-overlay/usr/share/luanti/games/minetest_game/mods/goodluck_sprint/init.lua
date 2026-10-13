-- Aux1 while moving forward runs at goodluck_sprint_speed times the walk; less than half forward ends it
local speed = tonumber(core.settings:get("goodluck_sprint_speed") or "") or 1.5
local running, held = {}, {}

local function set_running(player, name, on)
	if running[name] == on then
		return
	end
	running[name] = on
	player:set_physics_override({speed = on and speed or 1})
end

core.register_globalstep(function()
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local ctrl = player:get_player_control()
		local forward = ctrl.movement_y or 0
		if ctrl.aux1 and not held[name] and forward >= 0.5 then
			set_running(player, name, true)
		elseif forward < 0.5 then
			set_running(player, name, false)
		end
		held[name] = ctrl.aux1
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	running[name], held[name] = nil, nil
end)
