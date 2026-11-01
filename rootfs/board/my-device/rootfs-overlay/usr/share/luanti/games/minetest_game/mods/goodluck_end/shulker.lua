-- Minecraft's shulker (Shulker, ShulkerBullet): a purpur shell on any of a block's six faces with its head inside. Now
-- and then it peeks (its lid 30 % up for 1 to 3 s); at a player in survival within 16 that it sees it opens wide and,
-- while they are within 20, shoots every 1 to 5.5 s a bullet that flies along one axis at a time toward them, turning
-- when it lines up with them or meets a block, speeding up as it goes, and on a hit does 4 and gives Levitation for
-- 10 s. Closed, its armor of 20 keeps most of a hit out and arrows glance off; hurt under half its 30 it teleports
-- (1 time in 4) to a free face within 8, as it does when its block goes. Dead, a shell half the time and 5 of
-- experience. Only the End cities place them, and its spawn egg
local S = core.get_translator("goodluck_end")
local E = goodluck_end
local N, BULLET = "goodluck_end:shulker", "goodluck_end:shulker_bullet"
local PX = 10 / 16

-- the faces it can hold to, in Minecraft's order of trying them, and the turn that puts its base on each
local FACES = {vector.new(0, -1, 0), vector.new(0, 1, 0), vector.new(0, 0, -1), vector.new(0, 0, 1),
	vector.new(-1, 0, 0), vector.new(1, 0, 0)}
local TURN = {vector.new(0, 0, 0), vector.new(math.pi, 0, 0), vector.new(-math.pi / 2, 0, 0),
	vector.new(math.pi / 2, 0, 0), vector.new(math.pi / 2, math.pi / 2, 0), vector.new(math.pi / 2, -math.pi / 2, 0)}

local function solid(pos)
	local def = core.registered_nodes[core.get_node(pos).name]
	return def and def.walkable and (def.drawtype == "normal" or def.drawtype == "glasslike" or
		def.drawtype == "glasslike_framed" or def.drawtype == "allfaces_optional")
end
local function free(pos)
	local def = core.registered_nodes[core.get_node(pos).name]
	return def and not def.walkable and (def.liquidtype or "none") == "none"
end
local function shulker_at(pos, but)
	for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.9)) do
		local ent = obj:get_luaentity()
		if ent and ent.name == N and ent ~= but then
			return true
		end
	end
end
-- the first face at pos it can hold to (canStayAt: the block there solid, the place free); waiting: else one not
-- loaded yet
local function attachable(pos, waiting)
	if not free(pos) then
		return
	end
	for i, f in ipairs(FACES) do
		if solid(vector.add(pos, f)) then
			return i
		end
	end
	for i, f in ipairs(waiting and FACES or {}) do
		if core.get_node(vector.add(pos, f)).name == "ignore" then
			return i
		end
	end
end

local function sound(self, name, gain)
	core.sound_play(name, {object = self.object, gain = gain or 1, max_hear_distance = 16}, true)
end

-- the lid: Minecraft's 16 + 8 sin((0.5 + peek) pi), from its rest 24, a 20th of the way a tick
local function lid(self, peek)
	if self._peek == peek then
		return
	end
	local up = 8 * (1 - math.cos(peek * math.pi)) * PX
	self.object:set_bone_override("lid", {position = {vec = vector.new(0, up, 0), absolute = false,
		interpolation = math.abs(peek - (self._peek or 0))}})
	if (self._peek or 0) == 0 and peek > 0 then
		sound(self, "goodluck_end_shulker_open")
	elseif peek == 0 and (self._peek or 0) > 0 then
		sound(self, "goodluck_end_shulker_close")
	end
	self._peek = peek
	-- closed: Minecraft's armor of 20, about 70 % of a hit kept out
	self.object:set_armor_groups({fleshy = peek == 0 and 30 or 100})
end

local function attach(self, face)
	self._face = face
	self.object:set_rotation(TURN[face])
end

-- teleportSomewhere: five tries at a place within 8 with a face to hold to and no other shulker
local function teleport(self)
	local from = vector.round(self.object:get_pos())
	for _ = 1, 5 do
		local p = vector.offset(from, math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
		local face = attachable(p)
		if face and not shulker_at(p, self) then
			sound(self, "goodluck_end_teleport")
			self.object:set_pos(p)
			attach(self, face)
			lid(self, 0)
			self._target = nil
			sound(self, "goodluck_end_teleport")
			return true
		end
	end
	return false
end

local function spark(pos, n)
	core.add_particlespawner({amount = n, time = 0.1, pos = {min = vector.offset(pos, -0.2, -0.2, -0.2),
		max = vector.offset(pos, 0.2, 0.2, 0.2)}, vel = {min = vector.new(-1, -1, -1), max = vector.new(1, 1, 1)},
		exptime = {min = 0.3, max = 0.8}, size = {min = 0.8, max = 1.4}, glow = 14,
		texture = "goodluck_end_glitter.png"})
end

local function target_ok(obj)
	return obj and obj:is_valid() and obj:is_player() and obj:get_hp() > 0 and
		not core.is_creative_enabled(obj:get_player_name())
end

local function shoot(self, target)
	local pos = vector.round(self.object:get_pos())
	local b = core.add_entity(pos, BULLET)
	if b then
		local ent = b:get_luaentity()
		ent._owner, ent._target = self.object, target
		ent:choose(FACES[self._face].x ~= 0 and "x" or FACES[self._face].y ~= 0 and "y" or "z")
	end
	core.sound_play("goodluck_end_shulker_shoot", {pos = pos, gain = 1, max_hear_distance = 32,
		pitch = 1 + (math.random() - math.random()) * 0.2}, true)
end

-- the head toward a point, in the shell's own turn
local function look(self, at)
	local pos = self.object:get_pos()
	local d = vector.subtract(at, pos)
	local r = self.object:get_rotation()
	-- undo the shell's yaw, then its pitch
	local cy, sy = math.cos(r.y), math.sin(r.y)
	d = vector.new(d.x * cy + d.z * sy, d.y, -d.x * sy + d.z * cy)
	local cp, sp = math.cos(r.x), math.sin(r.x)
	d = vector.new(d.x, d.y * cp - d.z * sp, d.y * sp + d.z * cp)
	local yaw = math.atan2(d.x, d.z)
	local pitch = math.atan2(d.y, math.sqrt(d.x * d.x + d.z * d.z))
	-- a bone turns the other way about y from an object's yaw
	self.object:set_bone_override("head", {rotation = {vec = vector.new(-pitch, yaw, 0), absolute = true,
		interpolation = 0.25}})
end

local THINK = 0.25
core.register_entity(N, {
	initial_properties = {
		hp_max = 30,
		physical = true,
		collide_with_objects = true,
		collisionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
		selectionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
		visual = "mesh",
		mesh = "goodluck_models_shulker.glb",
		textures = {"goodluck_end_shulker.png"},
		static_save = true,
		damage_texture_modifier = "^[colorize:#ff000060",
	},
	_goodluck_xp = 5,
	on_activate = function(self, staticdata)
		local s = core.deserialize(staticdata or "") or {}
		self._think, self._fire, self._peeking = math.random() * THINK, 0, 0
		local pos = vector.round(self.object:get_pos())
		self.object:set_pos(pos)
		attach(self, s.face or attachable(pos, true) or 1)
		self._peek = nil
		lid(self, 0)
	end,
	get_staticdata = function(self)
		return core.serialize({face = self._face})
	end,
	on_step = function(self, dtime)
		self._think = self._think - dtime
		self._fire = self._fire - dtime
		self._peeking = self._peeking - dtime
		if self._think > 0 then
			return
		end
		self._think = THINK
		local pos = self.object:get_pos()
		-- its block gone (not just unloaded): another face here, else elsewhere
		local held = vector.add(vector.round(pos), FACES[self._face])
		if not solid(held) then
			if core.get_node(held).name == "ignore" then
				return
			end
			local face = attachable(vector.round(pos))
			if face then
				attach(self, face)
			else
				teleport(self)
			end
			return
		end
		local target = self._target
		if target and (not target_ok(target) or vector.distance(target:get_pos(), pos) > 20) then
			target = nil
		end
		if not target then
			for _, obj in ipairs(core.get_objects_inside_radius(pos, 16)) do
				if target_ok(obj) and core.line_of_sight(pos, vector.offset(obj:get_pos(), 0, 1.5, 0)) then
					target = obj
					break
				end
			end
			if target then
				self._fire = 1
			end
		end
		self._target = target
		if target then
			lid(self, 1)
			look(self, vector.offset(target:get_pos(), 0, 1.5, 0))
			if self._fire <= 0 then
				self._fire = 1 + math.random(0, 9) * 0.5
				shoot(self, target)
			end
		elseif self._peeking > 0 then
			lid(self, 0.3)
		elseif self._peek > 0 then
			lid(self, 0)
		elseif math.random(1, 8) == 1 then
			self._peeking = math.random(1, 3)
		elseif math.random(1, 32) == 1 then
			sound(self, "goodluck_end_shulker")
		end
	end,
	on_punch = function(self, puncher, _, caps, _, damage)
		local ent = puncher and puncher:get_luaentity()
		-- an arrow glances off it closed
		if self._peek == 0 and ent and ent.name and ent.name:find("arrow") then
			sound(self, "goodluck_end_shulker_hurt_closed")
			return true
		end
		sound(self, self._peek == 0 and "goodluck_end_shulker_hurt_closed" or "goodluck_end_shulker_hurt")
		local hp = self.object:get_hp() - (damage or 0)
		if hp > 0 and hp < 15 and math.random(1, 4) == 1 then
			core.after(0, function()
				if self.object:is_valid() then
					teleport(self)
				end
			end)
		end
		if puncher and puncher:is_player() and not core.is_creative_enabled(puncher:get_player_name()) then
			self._target = puncher
		end
	end,
	on_death = function(self, killer)
		local pos = self.object:get_pos()
		sound(self, "goodluck_end_shulker_death")
		if math.random() < 0.5 then
			core.add_item(pos, "goodluck_end:shulker_shell")
		end
		if killer and killer:is_player() and goodluck_xp then
			goodluck_xp.drop(pos, 5)
		end
	end,
})

-- The bullet: 0.15 a tick toward its next stop along an axis, its speed growing 2.5 % a tick (to 1 at most), 0.2 of the
-- way from where it was going each tick; a new axis every 10 to 50 ticks, at a block ahead or once lined up with its
-- target; without one it falls
local STEP = {x = {vector.new(1, 0, 0), vector.new(-1, 0, 0)}, y = {vector.new(0, 1, 0), vector.new(0, -1, 0)},
	z = {vector.new(0, 0, 1), vector.new(0, 0, -1)}}
local function axis_of(d)
	return d and (d.x ~= 0 and "x" or d.y ~= 0 and "y" or "z")
end

local bullet = {
	initial_properties = {
		physical = false,
		collisionbox = {-0.15, -0.15, -0.15, 0.15, 0.15, 0.15},
		selectionbox = {-0.2, -0.2, -0.2, 0.2, 0.2, 0.2},
		visual = "mesh",
		mesh = "goodluck_models_shulker_bullet.glb",
		textures = {"goodluck_end_shulker_spark.png", "goodluck_end_shulker_spark.png^[opacity:40"},
		visual_size = {x = 0.5, y = 0.5, z = 0.5},
		use_texture_alpha = true,
		glow = 15,
		static_save = false,
	},
	-- selectNextMoveDirection: a step along an axis but the one it came along, toward its target and into air, else
	-- any free way; straight at it once within 2
	choose = function(self, axis)
		local pos = self.object:get_pos()
		local here = vector.round(pos)
		local t = self._target
		local tp = t:get_pos()
		local h = (t:get_properties().collisionbox[5] or 1.8) / 2
		local tb = vector.round(vector.offset(tp, 0, h, 0))
		local goal = vector.new(tb.x, tp.y + h, tb.z)
		local dir
		if vector.distance(tb, pos) >= 2 then
			local list = {}
			for _, a in ipairs({"x", "y", "z"}) do
				if a ~= axis then
					local s = here[a] < tb[a] and 1 or here[a] > tb[a] and 2
					if s and free(vector.add(here, STEP[a][s])) then
						list[#list + 1] = STEP[a][s]
					end
				end
			end
			if #list > 0 then
				dir = list[math.random(1, #list)]
			else
				local all = {}
				for _, a in pairs(STEP) do
					all[#all + 1], all[#all + 2] = a[1], a[2]
				end
				dir = all[math.random(1, 6)]
				for _ = 1, 5 do
					if free(vector.add(here, dir)) then
						break
					end
					dir = all[math.random(1, 6)]
				end
			end
			goal = vector.add(pos, dir)
		end
		self._dir = dir
		local d = vector.subtract(goal, pos)
		local len = vector.length(d)
		self._want = len > 0 and vector.multiply(d, 0.15 / len) or vector.zero()
		self._steps = 10 + math.random(0, 4) * 10
	end,
	on_activate = function(self)
		self._v, self._want, self._acc, self._age = vector.zero(), vector.zero(), 0, 0
		self.object:set_animation({x = 0, y = 2 * math.pi}, 1, 0, true)
		core.add_particlespawner({amount = 12, time = 0, attached = self.object, pos = vector.zero(),
			vel = {min = vector.new(-0.1, -0.1, -0.1), max = vector.new(0.1, 0.1, 0.1)},
			exptime = {min = 0.4, max = 0.8}, size = {min = 0.6, max = 1}, glow = 14,
			texture = "goodluck_end_glitter.png"})
	end,
	burst = function(self, pos)
		spark(pos, 8)
		core.sound_play("goodluck_end_shulker_bullet_hit", {pos = pos, gain = 1, max_hear_distance = 16}, true)
		self.object:remove()
	end,
	on_step = function(self, dtime)
		self._age = self._age + dtime
		if self._age > 60 then
			self.object:remove()
			return
		end
		local pos = self.object:get_pos()
		local t = self._target
		local live = t and t:is_valid() and t:get_hp() > 0
		self._acc = self._acc + dtime
		while self._acc >= 0.05 do
			self._acc = self._acc - 0.05
			local v, w = self._v, self._want
			if live then
				w = vector.new(math.max(-1, math.min(1, w.x * 1.025)), math.max(-1, math.min(1, w.y * 1.025)),
					math.max(-1, math.min(1, w.z * 1.025)))
				self._want = w
				self._v = vector.add(v, vector.multiply(vector.subtract(w, v), 0.2))
			else
				self._v = vector.offset(v, 0, -0.04, 0)
			end
		end
		local to = vector.add(pos, vector.multiply(self._v, dtime * 20))
		-- what it meets on the way: its target or anyone but a shulker, else a block
		for hit in core.raycast(pos, to, true, false) do
			if hit.type == "object" then
				local obj = hit.ref
				local ent = obj:get_luaentity()
				if obj ~= self.object and obj ~= self._owner and not (ent and (ent.name == N or ent.name == BULLET or
						ent.name == "__builtin:item")) then
					obj:punch(self.object, 1, {full_punch_interval = 1, damage_groups = {fleshy = 4}},
						vector.direction(pos, obj:get_pos()))
					if obj:is_player() and goodluck_effects then
						goodluck_effects.apply(obj, "levitation", 10, 1)
					end
					return self:burst(pos)
				end
			elseif hit.type == "node" and solid(hit.under) then
				return self:burst(pos)
			end
		end
		self.object:set_velocity(vector.multiply(self._v, 20))
		if live then
			self._steps = (self._steps or 1) - math.max(1, math.floor(dtime * 20 + 0.5))
			local here = vector.round(to)
			local axis = axis_of(self._dir)
			if self._steps <= 0 then
				self:choose(axis)
			elseif self._dir then
				local tb = vector.round(t:get_pos())
				if not free(vector.add(here, self._dir)) or here[axis] == tb[axis] then
					self:choose(axis)
				end
			end
		end
	end,
	on_punch = function(self)
		self:burst(self.object:get_pos())
		return true
	end,
}
core.register_entity(BULLET, bullet)

core.register_craftitem("goodluck_end:shulker_shell", {
	description = S("Shulker Shell"),
	inventory_image = "goodluck_end_shulker_shell.png",
})

-- the spawn egg: on the face it is used on
core.register_craftitem("goodluck_end:shulker_egg", {
	description = S("Shulker Spawn Egg"),
	inventory_image = "goodluck_end_shulker_egg.png",
	groups = {spawn_egg = 1},
	on_place = function(itemstack, placer, pointed)
		if pointed.type ~= "node" then
			return itemstack
		end
		local pos = pointed.above
		if core.is_protected(pos, placer and placer:get_player_name() or "") or not free(pos) then
			return itemstack
		end
		local obj = core.add_entity(pos, N)
		local face = vector.subtract(pointed.under, pointed.above)
		for i, f in ipairs(FACES) do
			if obj and vector.equals(f, face) then
				attach(obj:get_luaentity(), i)
			end
		end
		if not (placer and core.is_creative_enabled(placer:get_player_name())) then
			itemstack:take_item()
		end
		return itemstack
	end,
})
E.shulker_faces = FACES
