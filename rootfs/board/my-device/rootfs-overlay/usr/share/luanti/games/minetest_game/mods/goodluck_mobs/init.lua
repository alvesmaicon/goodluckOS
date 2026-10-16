-- Monsters chase at 2 nodes a second and walk at 1, half and a quarter of a walking player (4); mobs_monster's run at
-- 3, the sand monster at 4, close to a running player. The entity definitions are what each mob reads its speeds from
local RUN, WALK = 2, 1

core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_entities) do
		if name:find("^mobs_monster:") and def.run_velocity then
			def.run_velocity = math.min(def.run_velocity, RUN)
			def.walk_velocity = math.min(def.walk_velocity or WALK, WALK)
		end
	end
end)

if not core.get_modpath("mobs") then return end

-- As on Minecraft Bedrock, monsters under the open sky and in caves have their own caps around the player, so a
-- cave below can't take the surface's
local CAP = {surface = 8, cave = 6}
local RADIUS = 64

local function where(pos)
	return (core.get_natural_light(pos, 0.5) or 0) >= 15 and "surface" or "cave"
end

local function is_monster(ent)
	return ent and ent._cmi_is_mob and ent.type == "monster" and not ent.tamed
end

local spawn_abm_check = mobs.spawn_abm_check
function mobs:spawn_abm_check(pos, node, name)
	if spawn_abm_check(self, pos, node, name) then return true end
	local def = core.registered_entities[name]
	if not def or def.type ~= "monster" then return end
	local kind = where(vector.offset(pos, 0, 1, 0))
	local n = 0
	for _, obj in ipairs(core.get_objects_inside_radius(pos, RADIUS)) do
		local ent = obj:get_luaentity()
		if is_monster(ent) and where(obj:get_pos()) == kind then
			n = n + 1
			if n >= CAP[kind] then return true end
		end
	end
end

-- As on Minecraft Java, a monster 32 nodes or more from every player for 30 s goes away at 1 in 40 a second, and
-- at once past 128: the monsters stay where the player is, and those left far behind stop running their AI
local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 1 then return end
	timer = 0
	local players = core.get_connected_players()
	for _, ent in pairs(core.luaentities) do
		local pos = is_monster(ent) and not ent._nametag and ent.object:get_pos()
		if pos then
			local far = math.huge
			for _, player in ipairs(players) do
				far = math.min(far, vector.distance(pos, player:get_pos()))
			end
			if far > 128 then
				ent.object:remove()
			elseif far >= 32 and ent.state ~= "attack" then
				ent._goodluck_far = (ent._goodluck_far or 0) + 1
				if ent._goodluck_far > 30 and math.random(40) == 1 then ent.object:remove() end
			else
				ent._goodluck_far = 0
			end
		end
	end
end)
