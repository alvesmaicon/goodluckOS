-- Minecraft's monster spawner: a cage with its monster small inside, tilted and turning, faster as the next ones come
-- near. While a player is within 16 it puts out up to 4 every 10 to 40 s, up to 4 across and 1 up or down where
-- they fit, unless 6 of them are already about it, with flames and smoke all the while. Breaking it gives 15 to 43
-- experience and nothing else; in creative, a spawn egg sets what it makes
local S = core.get_translator("goodluck_nether")
local N = "goodluck_nether:spawner"
local spawning = core.settings:get_bool("mobs_spawn", true) and not core.settings:get_bool("only_peaceful_mobs")
local display = {}

local function mob_def(pos)
	local def = core.registered_entities[core.get_meta(pos):get_string("mob")]
	return def and def._cmi_is_mob and def
end

-- Minecraft's 0.53125 of a node at most, as big as the cage
local function show(pos)
	local key = core.hash_node_position(pos)
	local obj = display[key]
	local def = mob_def(pos)
	if obj and obj:get_pos() then
		if def and obj:get_luaentity()._mob == def.name then
			return obj
		end
		obj:remove()
	end
	display[key] = nil
	if not def then
		return
	end
	obj = core.add_entity(vector.offset(pos, 0, -0.3, 0), N .. "_mob", def.name)
	display[key] = obj
	return obj
end

-- MC turns it 1000 / (ticks left + 200) degrees a tick while a player is near
local function turn(obj, left)
	if obj then
		local speed = left and math.rad(1000 / (left * 20 + 200) * 20) or 0
		local ent = obj:get_luaentity()
		if math.abs((ent._speed or -1) - speed) > 0.05 then
			ent._speed = speed
			obj:set_properties({automatic_rotate = speed})
		end
	end
end

core.register_entity(N .. "_mob", {
	initial_properties = {physical = false, pointable = false, static_save = false, visual = "mesh",
		textures = {"blank.png"}, automatic_rotate = 0},
	on_activate = function(self, staticdata)
		local def = core.registered_entities[staticdata]
		if not def then
			self.object:remove()
			return
		end
		self._mob = staticdata
		local props = def.initial_properties
		local cb = def.base_colbox
		local scale = 0.53125 / math.max(cb[4] - cb[1], cb[5] - cb[2], 1)
		local vs = def.base_size
		self.object:set_properties({mesh = def.base_mesh, visual = props.visual, textures = def.texture_list[1],
			use_texture_alpha = props.use_texture_alpha, glow = props.glow,
			visual_size = {x = vs.x * scale, y = vs.y * scale, z = (vs.z or vs.x) * scale}})
		self.object:set_rotation({x = math.rad(-30), y = math.random() * 6.28, z = 0})
		local a = def.animation
		if a and a.stand_start then
			self.object:set_animation({x = a.stand_start, y = a.stand_end}, a.speed_normal or 1)
		end
	end,
})

-- a free place for a monster of this box at pos (its feet), out of liquid
local function fits(pos, cb)
	for x = math.floor(pos.x + cb[1] + 0.5), math.floor(pos.x + cb[4] + 0.5) do
		for y = math.floor(pos.y + cb[2] + 0.5), math.floor(pos.y + cb[5] - 0.01 + 0.5) do
			for z = math.floor(pos.z + cb[3] + 0.5), math.floor(pos.z + cb[6] + 0.5) do
				local def = core.registered_nodes[core.get_node({x = x, y = y, z = z}).name]
				if not def or def.walkable or def.liquidtype ~= "none" then
					return false
				end
			end
		end
	end
	return true
end

local function puff(pos, flames)
	core.add_particlespawner({amount = 12, time = 0.1, pos = {min = vector.offset(pos, -0.5, -0.5, -0.5),
		max = vector.offset(pos, 0.5, 0.5, 0.5)}, vel = {min = vector.new(-0.3, 0.2, -0.3),
		max = vector.new(0.3, 0.6, 0.3)}, exptime = {min = 0.5, max = 1}, size = {min = 1.5, max = 3},
		texture = "tnt_smoke.png"})
	if flames then
		core.add_particlespawner({amount = 8, time = 0.1, pos = {min = vector.offset(pos, -0.5, -0.5, -0.5),
			max = vector.offset(pos, 0.5, 0.5, 0.5)}, exptime = {min = 0.4, max = 0.8}, size = {min = 1, max = 2},
			glow = 14, texture = "fire_basic_flame.png"})
	end
end

-- up to 4 tries; true when one came out or 6 are about already (it waits again either way)
local function spawn(pos, def)
	local near = 0
	for _, obj in ipairs(core.get_objects_in_area(vector.offset(pos, -4.5, -4.5, -4.5),
			vector.offset(pos, 4.5, 4.5, 4.5))) do
		local ent = obj:get_luaentity()
		if ent and ent.name == def.name and (ent.health or 1) > 0 then
			near = near + 1
		end
	end
	local made, full = false, false
	for _ = 1, 4 do
		if near >= 6 then
			full = true
			break
		end
		local p = vector.offset(pos, (math.random() - math.random()) * 4, math.random(-1, 1) - 0.5,
			(math.random() - math.random()) * 4)
		if fits(p, def.base_colbox) then
			local obj = core.add_entity(p, def.name)
			if obj then
				obj:set_yaw(math.random() * 6.28)
				puff(vector.offset(p, 0, 0.5, 0))
				near, made = near + 1, true
			end
		end
	end
	if made then
		puff(pos, true)
	end
	return made or full
end

local function player_near(pos)
	for _, player in ipairs(core.get_connected_players()) do
		if vector.distance(player:get_pos(), pos) <= 16 then
			return true
		end
	end
end

local function tick(pos)
	local meta = core.get_meta(pos)
	local def = mob_def(pos)
	local obj = show(pos)
	if not def or not player_near(pos) then
		turn(obj, nil)
		return true
	end
	core.add_particlespawner({amount = 10, time = 1, pos = {min = vector.offset(pos, -0.5, -0.5, -0.5),
		max = vector.offset(pos, 0.5, 0.5, 0.5)}, exptime = {min = 0.3, max = 0.6}, size = {min = 0.6, max = 1.2},
		glow = 14, texture = "fire_basic_flame.png"})
	core.add_particlespawner({amount = 10, time = 1, pos = {min = vector.offset(pos, -0.5, -0.5, -0.5),
		max = vector.offset(pos, 0.5, 0.5, 0.5)}, vel = {min = vector.new(0, 0.1, 0), max = vector.new(0, 0.3, 0)},
		exptime = {min = 0.6, max = 1.2}, size = {min = 0.8, max = 1.5}, texture = "tnt_smoke.png"})
	local left = meta:get_int("delay") - 1
	if left <= 0 and spawning then
		if spawn(pos, def) then
			left = math.random(10, 39)
		else
			left = 0
		end
	end
	meta:set_int("delay", math.max(left, 0))
	turn(obj, math.max(left, 0))
	return true
end

local function set(pos, mob)
	local meta = core.get_meta(pos)
	meta:set_string("mob", mob or "")
	meta:set_int("delay", 1)
	core.get_node_timer(pos):start(1)
	show(pos)
end
goodluck_nether.set_spawner = set

core.register_node(N, {
	description = S("Monster Spawner"),
	drawtype = "allfaces",
	tiles = {"mob_spawner.png"},
	use_texture_alpha = "clip",
	paramtype = "light",
	sunlight_propagates = true,
	groups = {cracky = 1},
	drop = "",
	is_ground_content = false,
	sounds = default.node_sound_metal_defaults(),
	on_construct = function(pos)
		core.get_node_timer(pos):start(1)
	end,
	on_timer = tick,
	on_destruct = function(pos)
		local key = core.hash_node_position(pos)
		if display[key] then
			display[key]:remove()
			display[key] = nil
		end
	end,
	after_dig_node = function(pos, oldnode, oldmeta, digger)
		if core.global_exists("goodluck_xp") and not (digger and core.is_creative_enabled(digger:get_player_name())) then
			goodluck_xp.drop(pos, 15 + math.random(0, 14) + math.random(0, 14))
		end
	end,
	on_rightclick = function(pos, node, clicker, itemstack)
		local name = itemstack:get_name()
		local def = core.registered_entities[name]
		if def and def._cmi_is_mob and clicker and core.is_creative_enabled(clicker:get_player_name()) and
				not core.is_protected(pos, clicker:get_player_name()) then
			set(pos, name)
		end
		return itemstack
	end,
})

-- a spawner made by the map generator has no timer yet; one loaded back has lost its monster
core.register_lbm({
	label = "Monster spawners at work",
	name = "goodluck_nether:spawner_start",
	nodenames = {N},
	run_at_every_load = true,
	action = function(pos)
		local timer = core.get_node_timer(pos)
		if not timer:is_started() then
			timer:start(1)
		end
	end,
})
