-- Fly only in creative mode (as in Minecraft): the privilege is given there and taken away in survival
core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local fly = core.is_creative_enabled(name) or nil
	local privs = core.get_player_privs(name)
	if privs.fly ~= fly then
		privs.fly = fly
		core.set_player_privs(name, privs)
	end
end)
