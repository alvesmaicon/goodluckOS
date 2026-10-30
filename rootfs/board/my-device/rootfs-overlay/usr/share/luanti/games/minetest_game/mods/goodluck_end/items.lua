-- The ender pearl and the eye of ender as Minecraft (26.x) has them. A pearl is thrown as a snowball is (1.5 a tick,
-- 0.03 of gravity, 0.99 of its speed kept a tick) and takes its thrower where it lands, hurting them 5; one a second.
-- An eye (blaze powder and a pearl) thrown in the Overworld rises toward the nearest stronghold, 12 at most and 8 up,
-- for 4 s, then drops (4 in 5) or breaks; on an end portal frame it goes in (stronghold.lua)
local S = core.get_translator("goodluck_end")
local E = goodluck_end
local TICK = 0.05
local PARTICLE = "goodluck_nether_portal_particle.png"

local function creative(player)
	return core.is_creative_enabled(player:get_player_name())
end

-- the purple specks of Minecraft's portal particle, n of them about pos
function E.specks(pos, n, spread, height)
	core.add_particlespawner({amount = n, time = 0.1, pos = {min = vector.offset(pos, -spread, 0, -spread),
		max = vector.offset(pos, spread, height or 2, spread)}, vel = {min = vector.new(-0.6, -0.3, -0.6),
		max = vector.new(0.6, 0.6, 0.6)}, exptime = {min = 0.5, max = 1.2}, size = {min = 0.6, max = 1.4}, glow = 12,
		texture = PARTICLE})
end

local function eyes(player)
	return vector.offset(player:get_pos(), 0, player:get_properties().eye_height, 0)
end

-- the pearl: a tick at a time, a ray from where it was to where it goes; its thrower is out of reach for 2 ticks
core.register_entity("goodluck_end:thrown_pearl", {
	initial_properties = {physical = false, pointable = false, static_save = false, visual = "sprite",
		visual_size = {x = 0.25, y = 0.25}, textures = {"goodluck_end_ender_pearl.png"}},
	on_step = function(self, dtime)
		self._t = (self._t or 0) + dtime
		local owner = self._owner and core.get_player_by_name(self._owner)
		while self._t >= TICK do
			self._t = self._t - TICK
			self._ticks = (self._ticks or 0) + 1
			local pos = self.object:get_pos()
			local to = vector.add(pos, self._v)
			for hit in core.raycast(pos, to, true, false) do
				local obj = hit.type == "object" and hit.ref
				local ent = obj and obj:get_luaentity()
				if hit.type == "node" and (core.registered_nodes[core.get_node(hit.under).name] or {}).walkable ~= false or
						obj and obj ~= self.object and not (ent and ent.name == "__builtin:item") and
						(obj ~= owner or self._ticks > 2) then
					return self:land(pos, owner, obj)
				end
			end
			if (core.registered_nodes[core.get_node(to).name] or {}).liquidtype ~= "none" then
				self._v = vector.multiply(self._v, 0.8)
			else
				self._v = vector.multiply(self._v, 0.99)
			end
			self._v.y = self._v.y - 0.03
			self.object:set_pos(to)
			if self._ticks > 600 or core.get_node(to).name == "ignore" then
				self.object:remove()
				return
			end
		end
	end,
	land = function(self, at, owner, obj)
		self.object:remove()
		if obj and obj ~= owner then
			obj:punch(self.object, 1, {full_punch_interval = 1, damage_groups = {fleshy = 0}})
		end
		E.specks(at, 32, 0.3)
		if not owner or owner:get_hp() <= 0 then
			return
		end
		owner:set_pos(at)
		owner:add_velocity(vector.multiply(owner:get_velocity(), -1))
		core.sound_play("goodluck_end_teleport", {pos = at, gain = 1}, true)
		if not creative(owner) then
			owner:set_hp(owner:get_hp() - 5, {type = "set_hp", cause = "goodluck_end:ender_pearl"})
		end
	end,
})

local thrown = {}
local function throw_pearl(itemstack, user)
	if not user or not user:is_player() then
		return itemstack
	end
	local name = user:get_player_name()
	local now = core.get_us_time()
	if thrown[name] and now - thrown[name] < 1000000 then
		return itemstack
	end
	thrown[name] = now
	local dir = user:get_look_dir()
	local obj = core.add_entity(eyes(user), "goodluck_end:thrown_pearl")
	if obj then
		local ent = obj:get_luaentity()
		ent._owner, ent._v = name, vector.add(vector.multiply(dir, 1.5), vector.multiply(user:get_velocity(), TICK))
		core.sound_play("goodluck_end_pearl_throw", {pos = user:get_pos(), gain = 0.5, pitch = 0.4 + math.random() * 0.2},
			true)
	end
	if not creative(user) then
		itemstack:take_item()
	end
	return itemstack
end
core.register_on_leaveplayer(function(player)
	thrown[player:get_player_name()] = nil
end)

-- with either button, unless the node pointed at does something of its own
local function use_or(fn)
	return function(itemstack, user, pointed)
		if pointed and pointed.type == "node" and user and not user:get_player_control().sneak then
			local node = core.get_node(pointed.under)
			local def = core.registered_nodes[node.name]
			if def and def.on_rightclick then
				return def.on_rightclick(pointed.under, node, user, itemstack, pointed)
			end
		end
		return fn(itemstack, user, pointed)
	end
end

core.register_craftitem("goodluck_end:ender_pearl", {
	description = S("Ender Pearl"),
	inventory_image = "goodluck_end_ender_pearl.png",
	stack_max = 16,
	on_use = throw_pearl,
	on_secondary_use = throw_pearl,
	on_place = use_or(throw_pearl),
})

-- the eye: Minecraft's flight, a tick at a time (its speed eases toward the target across, rises or sinks toward it)
core.register_entity("goodluck_end:eye", {
	initial_properties = {physical = false, pointable = false, static_save = false, visual = "sprite",
		visual_size = {x = 0.4, y = 0.4}, textures = {"goodluck_end_ender_eye.png"}, glow = 10},
	on_step = function(self, dtime)
		self._t = (self._t or 0) + dtime
		while self._t >= TICK do
			self._t = self._t - TICK
			local pos = vector.add(self.object:get_pos(), self._v)
			local dx, dz = self._target.x - pos.x, self._target.z - pos.z
			local d = math.sqrt(dx * dx + dz * dz)
			local h = math.sqrt(self._v.x ^ 2 + self._v.z ^ 2)
			local speed, vy = h + (d - h) * 0.0025, self._v.y
			if d < 1 then
				speed, vy = speed * 0.8, vy * 0.8
			end
			local want = pos.y - self._v.y < self._target.y and 1 or -1
			d = math.max(d, 1e-4)
			self._v = {x = dx * speed / d, y = vy + (want - vy) * 0.015, z = dz * speed / d}
			self.object:set_pos(pos)
			self._life = (self._life or 0) + 1
			if self._life % 2 == 0 then
				core.add_particle({pos = vector.offset(pos, math.random() * 0.6 - 0.3, -0.5, math.random() * 0.6 - 0.3),
					velocity = vector.multiply(self._v, 4), expirationtime = 0.8, size = 1, glow = 12, texture = PARTICLE})
			end
			if self._life > 80 then
				self.object:remove()
				core.sound_play("goodluck_end_eye_death", {pos = pos, gain = 1}, true)
				if self._survive then
					core.add_item(pos, "goodluck_end:ender_eye")
				else
					core.add_particlespawner({amount = 24, time = 0.1, pos = pos, vel = {min = vector.new(-1.5, 0, -1.5),
						max = vector.new(1.5, 2, 1.5)}, acc = vector.new(0, -6, 0), exptime = {min = 0.4, max = 0.9},
						size = {min = 1, max = 2}, texture = "goodluck_end_ender_eye.png^[resize:4x4"})
				end
				return
			end
		end
	end,
})

local function throw_eye(itemstack, user)
	if not user or not user:is_player() or not E.overworld(user:get_pos()) then
		return itemstack
	end
	local from = eyes(user)
	local target = E.strongholds.nearest(from)
	local obj = core.add_entity(from, "goodluck_end:eye")
	if not obj then
		return itemstack
	end
	local ent = obj:get_luaentity()
	local dx, dz = target.x - from.x, target.z - from.z
	local d = math.sqrt(dx * dx + dz * dz)
	ent._target = d > 12 and {x = from.x + dx / d * 12, y = from.y + 8, z = from.z + dz / d * 12} or
		{x = target.x, y = target.y, z = target.z}
	ent._v, ent._survive = {x = 0, y = 0, z = 0}, math.random(5) > 1
	core.sound_play("goodluck_end_eye_launch", {pos = from, gain = 1, pitch = 0.33 + math.random() * 0.17}, true)
	core.log("action", ("[goodluck_end] %s throws an eye of ender at %d,%d,%d toward %d,%d"):format(
		user:get_player_name(), from.x, from.y, from.z, target.x, target.z))
	if not creative(user) then
		itemstack:take_item()
	end
	return itemstack
end

core.register_craftitem("goodluck_end:ender_eye", {
	description = S("Eye of Ender"),
	inventory_image = "goodluck_end_ender_eye.png",
	on_use = throw_eye,
	on_secondary_use = throw_eye,
	on_place = use_or(throw_eye),
})

core.register_craft({type = "shapeless", output = "goodluck_end:ender_eye",
	recipe = {"goodluck_nether:blaze_powder", "goodluck_end:ender_pearl"}})
