-- A player's speed, jump and gravity are the product of every mod's share (armor, running, the bow drawn, the shield
-- raised, status effects), so that none undoes another's. 3d_armor's own writes are locked off and its share comes
-- from its update; a bed holds the player still, and getting up puts the shares back in place of what it kept
goodluck_physics = {}
local FIELDS = {"speed", "jump", "gravity"}
local shares, in_bed = {}, {}
local bed = core.global_exists("beds") and beds

local function update(player)
	local name = player:get_player_name()
	local set = {speed = 1, jump = 1, gravity = 1}
	if in_bed[name] then
		set = {speed = 0, jump = 0, gravity = 0}
	else
		for _, share in pairs(shares[name] or {}) do
			for _, field in ipairs(FIELDS) do
				set[field] = set[field] * (share[field] or 1)
			end
		end
	end
	local now = player:get_physics_override()
	if now.speed ~= set.speed or now.jump ~= set.jump or now.gravity ~= set.gravity then
		player:set_physics_override(set)
	end
end

-- id's share of the player's physics, {speed =, jump =, gravity =} (1 where missing), or nil to take it away
function goodluck_physics.set(player, id, share)
	local name = player:get_player_name()
	shares[name] = shares[name] or {}
	shares[name][id] = share
	update(player)
end

if core.global_exists("armor") then
	local function lock(player)
		player:get_meta():set_int("player_physics_locked", 1)
	end
	core.register_on_newplayer(lock)
	core.register_on_joinplayer(lock)
	armor:register_on_update(function(player)
		local def = armor.def[player:get_player_name()]
		goodluck_physics.set(player, "3d_armor", def and {speed = def.speed, jump = def.jump, gravity = def.gravity})
	end)
end

if bed then
	core.register_globalstep(function()
		for _, player in ipairs(core.get_connected_players()) do
			local name = player:get_player_name()
			local lying = bed.player[name] ~= nil
			if lying ~= (in_bed[name] or false) then
				in_bed[name] = lying or nil
				update(player)
			end
		end
	end)
end

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	shares[name], in_bed[name] = nil, nil
end)
