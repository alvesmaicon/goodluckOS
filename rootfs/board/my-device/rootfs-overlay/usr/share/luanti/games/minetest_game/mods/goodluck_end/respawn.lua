-- Calling the dragon back, as Minecraft 26.3 does (EnderDragonFight.tryRespawn, DragonRespawnStage): the end crystal
-- (glass about an eye of ender over a ghast tear) goes on obsidian or bedrock; once the dragon is dead, four of them
-- on the exit portal's rim, 3 out from its middle, put the portal out and aim their beams over the island for 5 s;
-- then each pillar in turn, 2 s each, is struck, blown up and built anew with a crystal no one can break yet; 5 s
-- more and the four blow up and a new dragon comes. Breaking one of the four on the way stops it all
local S = core.get_translator("goodluck_end")
local E = goodluck_end
local YMIN = E.ymin
local storage = core.get_mod_storage()
local CRYSTAL = "goodluck_end:end_crystal"
local SKY = {x = 0, y = YMIN + 128, z = 0}

local function crystals_at(pos)
	local out = {}
	for _, obj in ipairs(core.get_objects_in_area(vector.offset(pos, -0.5, -0.5, -0.5), vector.offset(pos, 0.5, 1.5, 0.5))) do
		local ent = obj:get_luaentity()
		if ent and ent.name == CRYSTAL then
			out[#out + 1] = obj
		end
	end
	return out
end

-- EndCrystalItem: on obsidian or bedrock, with two of room over it and nothing in the way
local function place(itemstack, placer, pointed_thing)
	if pointed_thing.type ~= "node" then
		return itemstack
	end
	local under = pointed_thing.under
	local n = core.get_node(under).name
	if n ~= "default:obsidian" and n ~= "goodluck_nether:bedrock" then
		return itemstack
	end
	local above = vector.offset(under, 0, 1, 0)
	if core.get_node(above).name ~= "air" or core.get_node(vector.offset(above, 0, 1, 0)).name ~= "air" or
			#core.get_objects_in_area(vector.offset(above, -0.5, -0.5, -0.5), vector.offset(above, 0.5, 1.5, 0.5)) > 0 then
		return itemstack
	end
	core.add_entity(vector.offset(above, 0, -0.5, 0), CRYSTAL, "nobase")
	if not (placer and core.is_creative_enabled(placer:get_player_name())) then
		itemstack:take_item()
	end
	if E.inside(above) then
		E.try_respawn()
	end
	return itemstack
end
core.register_craftitem(CRYSTAL, {
	description = S("End Crystal"),
	inventory_image = "goodluck_end_end_crystal_item.png",
	on_place = place,
})
core.register_craft({output = CRYSTAL, recipe = {{"default:glass", "default:glass", "default:glass"},
	{"default:glass", "goodluck_end:ender_eye", "default:glass"},
	{"default:glass", "goodluck_nether:ghast_tear", "default:glass"}}})

-- a pillar built anew (EndSpikeFeature): obsidian up to its top, room over it, its cage, bedrock, fire and a crystal
local c_obsidian = core.get_content_id("default:obsidian")
local c_bars = core.get_content_id("xpanes:bar")
local c_air = core.CONTENT_AIR
local function rebuild(s)
	local top = YMIN + s.height
	local r = s.radius
	local vm = VoxelManip()
	local lo, hi = {x = s.x - 10, y = YMIN, z = s.z - 10}, {x = s.x + 10, y = top + 10, z = s.z + 10}
	local emin, emax = vm:read_from_map(lo, hi)
	local area, data = VoxelArea(emin, emax), vm:get_data()
	-- Minecraft takes out everything within 10 of its top first
	for i in area:iterp({x = s.x - 10, y = top - 10, z = s.z - 10}, hi) do
		data[i] = c_air
	end
	for z = s.z - r, s.z + r do
		for x = s.x - r, s.x + r do
			if (x - s.x) ^ 2 + (z - s.z) ^ 2 <= r * r + 1 then
				for y = YMIN, top - 1 do
					data[area:index(x, y, z)] = c_obsidian
				end
			end
		end
	end
	if s.guarded then
		for dx = -2, 2 do
			for dz = -2, 2 do
				for dy = 0, 3 do
					if math.abs(dx) == 2 or math.abs(dz) == 2 or dy == 3 then
						data[area:index(s.x + dx, top + dy, s.z + dz)] = c_bars
					end
				end
			end
		end
	end
	vm:set_data(data)
	vm:write_to_map(true)
	core.set_node({x = s.x, y = top, z = s.z}, {name = "goodluck_nether:bedrock"})
	core.set_node({x = s.x, y = top + 1, z = s.z}, {name = "fire:permanent_flame"})
	for _, obj in ipairs(crystals_at({x = s.x, y = top + 1, z = s.z})) do
		obj:remove()
	end
	return core.add_entity({x = s.x, y = top + 0.5, z = s.z}, CRYSTAL, "guarded")
end

local calling
local function stop(beams)
	for _, b in ipairs(beams or {}) do
		if b.object:get_pos() then
			b.object:remove()
		end
	end
end
local function aim_all(c, target)
	stop(c.beams)
	c.beams = {}
	for _, obj in ipairs(c.crystals) do
		if obj:get_pos() then
			c.beams[#c.beams + 1] = E.beam_to(obj, target)
		end
	end
end
local function unguard()
	for _, ent in pairs(core.luaentities) do
		if ent.name == CRYSTAL and ent._guarded then
			ent._guarded = false
		end
	end
end
local function cancel(why)
	if not calling then
		return
	end
	core.log("action", "[goodluck_end] calling the dragon back stops: " .. why)
	stop(calling.beams)
	calling = nil
	unguard()
	E.exit_portal(true)
end

-- the stages, a step at a time (a game tick each)
local function step(c)
	if calling ~= c then
		return
	end
	c.t = c.t + 1
	local t = c.t
	if c.stage == "preparing" then
		if t >= 100 then
			c.stage, c.t = "pillars", -1
		end
	elseif c.stage == "pillars" then
		local j = math.floor(t / 40)
		local s = E.spikes[j + 1]
		if not s then
			c.stage, c.t = "dragon", -1
			aim_all(c, SKY)
		elseif t % 40 == 0 then
			aim_all(c, {x = s.x, y = YMIN + s.height + 1, z = s.z})
		elseif t % 40 == 39 then
			local top = {x = s.x, y = YMIN + s.height, z = s.z}
			rebuild(s)
			E.boom(vector.offset(top, 0.5, 0, 0.5), 5)
		end
	elseif c.stage == "dragon" then
		if t == 0 or t == 80 then
			core.sound_play("goodluck_end_dragon", {pos = SKY, gain = 2, max_hear_distance = 256}, true)
		end
		if t >= 100 then
			calling = nil
			stop(c.beams)
			for _, obj in ipairs(c.crystals) do
				local p = obj:get_pos()
				if p then
					obj:remove()
					E.boom(vector.offset(p, 0, 1, 0), 6)
				end
			end
			unguard()
			storage:set_string("dragon", "")
			core.log("action", "[goodluck_end] the ender dragon is called back")
			E.spawn_dragon()
			return
		end
	end
	core.after(0.05, step, c)
end

function E.try_respawn()
	local o = E.podium()
	if calling or not o or storage:get_string("dragon") ~= "dead" or E.dragon_entity() then
		return
	end
	local found = {}
	for _, d in ipairs({{3, 0}, {-3, 0}, {0, 3}, {0, -3}}) do
		local here = crystals_at({x = o.x + d[1], y = o.y + 1, z = o.z + d[2]})
		if not here[1] then
			return
		end
		for _, obj in ipairs(here) do
			found[#found + 1] = obj
		end
	end
	core.log("action", "[goodluck_end] four crystals on the exit portal: calling the dragon back")
	E.exit_portal(false)
	calling = {crystals = found, stage = "preparing", t = -1}
	aim_all(calling, SKY)
	step(calling)
end

-- one of the four broken on the way stops it (and the dragon's own rule still holds)
local destroyed = E.on_crystal_destroyed
function E.on_crystal_destroyed(pos, puncher)
	if calling then
		for _, obj in ipairs(calling.crystals) do
			if not obj:get_pos() then
				cancel("a crystal was broken")
				break
			end
		end
	end
	return destroyed(pos, puncher)
end
