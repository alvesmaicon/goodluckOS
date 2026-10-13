-- Creative mode as in Minecraft: flying, no damage, no hunger, monsters leave you alone; survival takes it all back.
-- no_hunger is stamina's (the level stays put), peaceful_player is mobs_redo's (monsters don't pick you as a target)
local PRIVS = {"fly", "no_hunger", "peaceful_player"}
local hunger = core.get_modpath("stamina") and stamina

local function creative(player)
	return core.is_creative_enabled(player:get_player_name())
end

local function set_privs(name, on)
	local privs = core.get_player_privs(name)
	for _, priv in ipairs(PRIVS) do
		if core.registered_privileges[priv] then
			privs[priv] = on or nil
		end
	end
	core.set_player_privs(name, privs)
end

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	-- no_hunger also keeps the level from being filled
	set_privs(name, false)
	if not creative(player) then
		return
	end
	-- immortal: the engine skips fall, drowning and node damage, Lua can't lower HP, and the hearts and breath hide
	local groups = player:get_armor_groups()
	groups.immortal = 1
	player:set_armor_groups(groups)
	local props = player:get_properties()
	player:set_hp(props.hp_max)
	player:set_breath(props.breath_max)
	if hunger and hunger.players[name] then
		hunger.update_saturation(player, hunger.VISUAL_MAX)
	end
	set_privs(name, true)
end)

-- HP can't go down anyway, but 3d_armor would still wear the armor out on every hit
if core.get_modpath("3d_armor") then
	local punch = armor.punch
	armor.punch = function(self, player, ...)
		if not creative(player) then
			return punch(self, player, ...)
		end
	end
end
