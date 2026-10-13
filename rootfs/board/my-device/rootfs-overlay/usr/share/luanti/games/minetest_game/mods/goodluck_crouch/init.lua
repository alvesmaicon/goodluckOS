-- Sneaking lowers the camera 0.35 node, as crouching does in Minecraft (eye offsets are in tenths of a node)
local DROP = 3.5
local crouched = {}

core.register_globalstep(function()
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local sneak = player:get_player_control().sneak or false
		if sneak ~= (crouched[name] or false) then
			crouched[name] = sneak
			local first, third, front = player:get_eye_offset()
			local dy = sneak and -DROP or DROP
			first.y, third.y, front.y = first.y + dy, third.y + dy, front.y + dy
			player:set_eye_offset(first, third, front)
		end
	end
end)

core.register_on_leaveplayer(function(player)
	crouched[player:get_player_name()] = nil
end)
