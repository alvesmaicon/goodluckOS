-- The ender dragon, Minecraft's (26.3) fight in its phases: it circles the island through the nodes of a ring 60
-- out, now and then strafes a player with a fireball (a cloud of its breath where it lands, 30 s, growing from 3 to
-- 7, Harming every second) or lands on the podium, where it looks for whoever is near, roars and breathes on them, and
-- takes off again; it charges a player far from it. 200 of health; hits on its head do all their damage, on the rest
-- a quarter and 1, and arrows bounce off it while it sits; a crystal within 32 heals it 1 every half second, and
-- blowing up the crystal that heals it hurts it 10. It breaks what players built in its way. Its death: it rises
-- 10 s, gives 12000 of experience the first time (500 after), lights the exit portal and leaves its egg on the podium
local S = core.get_translator("goodluck_end")
local E = goodluck_end
local D = "goodluck_end:ender_dragon"
local MAX = 200
local storage = core.get_mod_storage()

local function players_in_end()
	local list = {}
	for _, p in ipairs(core.get_connected_players()) do
		if E.inside(p:get_pos()) and p:get_hp() > 0 then
			list[#list + 1] = p
		end
	end
	return list
end

local function nearest_player(pos, range, pred)
	local best, near
	for _, p in ipairs(players_in_end()) do
		local d = vector.distance(pos, p:get_pos())
		if d <= range and (not pred or pred(p)) and (not near or d < near) and
				not core.is_creative_enabled(p:get_player_name()) then
			best, near = p, d
		end
	end
	return best, near
end

local function creative(obj)
	return obj:is_player() and core.is_creative_enabled(obj:get_player_name())
end

local function harm(obj, amount)
	if creative(obj) then
		return
	end
	if core.global_exists("goodluck_effects") then
		goodluck_effects.instant(obj, "instant_damage", 2, amount / 12)
	elseif obj:is_player() then
		obj:set_hp(obj:get_hp() - amount, {type = "set_hp", cause = "goodluck_end:dragon_breath"})
	end
end

-- Its breath, where a fireball lands or where it breathes sitting: a cloud that hurts whoever is in it every second
-- (Harming II at half, 6), growing (or not) as Minecraft's AreaEffectCloud
local BREATH = "goodluck_nether_portal_particle.png^[multiply:#d050f0"
core.register_entity("goodluck_end:breath", {
	initial_properties = {physical = false, pointable = false, static_save = false, visual = "sprite",
		textures = {"blank.png"}},
	on_step = function(self, dtime)
		self._age = (self._age or 0) + dtime
		self._t = (self._t or 1) + dtime
		local r = (self._r or 3) + (self._grow or 0) * self._age
		if self._age >= (self._life or 30) then
			self.object:remove()
			return
		end
		if self._t < 1 then
			return
		end
		self._t = 0
		local pos = self.object:get_pos()
		core.add_particlespawner({amount = math.floor(r * r * 3), time = 1, pos = {min = vector.offset(pos, -r, 0, -r),
			max = vector.offset(pos, r, 0.5, r)}, vel = {min = vector.new(-0.1, 0.05, -0.1), max = vector.new(0.1, 0.3, 0.1)},
			exptime = {min = 0.8, max = 1.6}, size = {min = 1.5, max = 3}, glow = 10, texture = BREATH})
		for _, obj in ipairs(core.get_objects_inside_radius(pos, r + 1)) do
			local p = obj:get_pos()
			local ent = obj:get_luaentity()
			if p and math.abs(p.y - pos.y) < 2 and vector.distance({x = p.x, y = 0, z = p.z}, {x = pos.x, y = 0, z = pos.z}) <= r and
					(obj:is_player() or ent and ent._cmi_is_mob and ent.name ~= "goodluck_end:enderman") then
				harm(obj, 6)
			end
		end
	end,
})

local function breath(pos, r, life, grow)
	local obj = core.add_entity(pos, "goodluck_end:breath")
	if obj then
		local e = obj:get_luaentity()
		e._r, e._life, e._grow = r, life, grow
	end
end

-- the fireball: it speeds up along its way (0.1 a tick, 0.95 kept) and breaks into breath on whatever it meets
core.register_entity("goodluck_end:dragon_fireball", {
	initial_properties = {physical = false, pointable = false, static_save = false, visual = "sprite",
		visual_size = {x = 1, y = 1}, textures = {"goodluck_end_dragon_fireball.png"}, glow = 14},
	on_step = function(self, dtime)
		self._t = (self._t or 0) + dtime
		while self._t >= 0.05 do
			self._t = self._t - 0.05
			self._life = (self._life or 0) + 1
			local pos = self.object:get_pos()
			self._v = vector.add(vector.multiply(self._v, 0.95), vector.multiply(self._dir, 0.1))
			local to = vector.add(pos, self._v)
			for hit in core.raycast(pos, to, true, false) do
				local ent = hit.type == "object" and hit.ref:get_luaentity()
				if hit.type == "node" or hit.type == "object" and not (ent and (ent._goodluck_dragon or
						ent.name == "goodluck_end:dragon_head" or ent.name == "goodluck_end:end_crystal" or
						ent.name == "__builtin:item")) then
					self.object:remove()
					local at = hit.type == "node" and hit.above or vector.round(hit.ref:get_pos())
					-- on the ground under it, as the cloud sits on the floor
					for _ = 1, 8 do
						local def = core.registered_nodes[core.get_node(vector.offset(at, 0, -1, 0)).name]
						if def and def.walkable then
							break
						end
						at.y = at.y - 1
					end
					breath(vector.offset(at, 0, -0.4, 0), 3, 30, (7 - 3) / 30)
					core.sound_play("goodluck_nether_fireball", {pos = at, gain = 1, max_hear_distance = 48}, true)
					return
				end
			end
			self.object:set_pos(to)
			if self._life > 200 then
				self.object:remove()
				return
			end
		end
	end,
})

local function fireball(from, to)
	local obj = core.add_entity(from, "goodluck_end:dragon_fireball")
	if obj then
		local e = obj:get_luaentity()
		e._dir = vector.normalize(vector.subtract(to, from))
		e._v = vector.multiply(e._dir, 0.5)
	end
end

-- The head: a box of its own on the head's bone, so that a hit there counts whole
core.register_entity("goodluck_end:dragon_head", {
	initial_properties = {physical = false, pointable = true, static_save = false, visual = "sprite",
		textures = {"blank.png"}, selectionbox = {-1, -0.6, -1.2, 1, 0.8, 1.2}, collisionbox = {-1, -0.6, -1.2, 1, 0.8, 1.2}},
	on_step = function(self, dtime)
		self._t = (self._t or 0) + dtime
		if self._t > 0.5 then
			self._t = 0
			if not self.object:get_attach() then
				self.object:remove()
			end
		end
	end,
	on_punch = function(self, puncher, tflp, caps, dir)
		local parent = self.object:get_attach()
		local e = parent and parent:get_luaentity()
		if e and e.hurt then
			e:hurt(puncher, tflp, caps, true)
		end
		return true
	end,
})

-- the holding pattern's ring: 12 nodes 60 out, Minecraft's outer path nodes, at its heights
local function ring_node(i, y0)
	local a = 2 * math.pi * (i % 12) / 12
	return {x = math.floor(60 * math.cos(a)), y = y0, z = math.floor(60 * math.sin(a))}
end

local function alive_crystals()
	local n = 0
	for _, obj in ipairs(core.get_objects_inside_radius({x = 0, y = E.ymin + 80, z = 0}, 80)) do
		local ent = obj:get_luaentity()
		if ent and ent.name == "goodluck_end:end_crystal" then
			n = n + 1
		end
	end
	return n
end

-- Minecraft's dragon_immune: what it flies through without breaking it
local IMMUNE = {["air"] = true, ["ignore"] = true, ["goodluck_end:end_stone"] = true, ["default:obsidian"] = true,
	["goodluck_nether:bedrock"] = true, ["goodluck_nether:crying_obsidian"] = true, ["xpanes:bar"] = true,
	["xpanes:bar_flat"] = true, ["goodluck_end:portal"] = true, ["goodluck_end:exit_portal"] = true,
	["goodluck_end:frame"] = true, ["goodluck_end:frame_eye"] = true, ["fire:permanent_flame"] = true,
	["goodluck_end:dragon_egg"] = true, ["default:torch_wall"] = true}

local function boss_bars(e)
	e._bars = e._bars or {}
	local seen = {}
	local pos = e.object:get_pos()
	for _, p in ipairs(core.get_connected_players()) do
		local name = p:get_player_name()
		if E.inside(p:get_pos()) and vector.distance(p:get_pos(), pos) < 256 then
			seen[name] = true
			local share = math.max(0, e._hp / MAX)
			local hud = e._bars[name]
			if not hud then
				hud = {
					bg = p:hud_add({type = "image", position = {x = 0.5, y = 0}, offset = {x = 0, y = 22},
						text = "[fill:182x5:0,0:#3b1046", scale = {x = 1.6, y = 1.6}, alignment = {x = 0, y = 0},
						z_index = 20}),
					fill = p:hud_add({type = "image", position = {x = 0.5, y = 0}, offset = {x = -145.6, y = 22},
						text = "[fill:182x5:0,0:#e040e8", scale = {x = 1.6 * share, y = 1.6}, alignment = {x = 1, y = 0},
						z_index = 21}),
					label = p:hud_add({type = "text", position = {x = 0.5, y = 0}, offset = {x = 0, y = 10},
						text = S("Ender Dragon"), number = 0xFFFFFF, alignment = {x = 0, y = 0}, z_index = 22}),
					share = share,
				}
				e._bars[name] = hud
			elseif math.abs(hud.share - share) > 0.001 then
				p:hud_change(hud.fill, "scale", {x = 1.6 * share, y = 1.6})
				hud.share = share
			end
		end
	end
	for name, hud in pairs(e._bars) do
		if not seen[name] then
			local p = core.get_player_by_name(name)
			if p then
				p:hud_remove(hud.bg)
				p:hud_remove(hud.fill)
				p:hud_remove(hud.label)
			end
			e._bars[name] = nil
		end
	end
end

local function clear_bars(e)
	for name, hud in pairs(e._bars or {}) do
		local p = core.get_player_by_name(name)
		if p then
			p:hud_remove(hud.bg)
			p:hud_remove(hud.fill)
			p:hud_remove(hud.label)
		end
	end
	e._bars = {}
end

local function podium_top()
	local o = E.podium()
	return o and vector.offset(o, 0, 4, 0)
end

-- where its head is: 7 ahead and 2.5 up of where it stands, as the model sits
local function head_pos(e)
	local pos = e.object:get_pos()
	local d = core.yaw_to_dir(e.object:get_yaw())
	return vector.offset(vector.add(pos, vector.multiply(d, 7)), 0, 2.5, 0)
end

local PHASE = {}

local function set_phase(e, name, target)
	e._phase, e._ptime, e._target = name, 0, target
	if PHASE[name].begin then
		PHASE[name].begin(e)
	end
end

local function fly_toward(e, target, speed, dt)
	local pos = e.object:get_pos()
	local d = vector.subtract(target, pos)
	local len = vector.length(d)
	local want = len > 0.1 and vector.multiply(d, speed / len) or vector.zero()
	e._v = vector.add(e._v, vector.multiply(vector.subtract(want, e._v), math.min(1, dt * 1.2)))
	e.object:set_velocity(e._v)
	local h = math.sqrt(e._v.x ^ 2 + e._v.z ^ 2)
	if h > 0.5 then
		e.object:set_rotation({x = -math.atan2(e._v.y, h) * 0.5, y = core.dir_to_yaw(e._v), z = 0})
	end
	return len
end

local function hover(e)
	e._v = vector.zero()
	e.object:set_velocity(e._v)
end

local function face(e, pos, dt)
	local d = vector.subtract(pos, e.object:get_pos())
	local want = core.dir_to_yaw(d)
	local yaw = e.object:get_yaw()
	local diff = (want - yaw + math.pi) % (2 * math.pi) - math.pi
	e.object:set_rotation({x = 0, y = yaw + math.max(-1.5 * dt, math.min(1.5 * dt, diff)), z = 0})
	return math.abs(diff)
end

-- circling: on to the next node of the ring, and at each one maybe land (1 in crystals + 3) or strafe the nearest
-- player (more often the nearer they are)
PHASE.hold = {
	begin = function(e)
		e._node = e._node or math.random(0, 11)
		e._dir_step = e._dir_step or 1
		e._target = ring_node(e._node, E.ymin + 73 + math.random() * 20)
	end,
	step = function(e, dt)
		if fly_toward(e, e._target, 13, dt) < 10 then
			local crystals = alive_crystals()
			if math.random(0, crystals + 2) == 0 then
				return set_phase(e, "approach")
			end
			local o = podium_top() or {x = 0, y = E.ymin + 65, z = 0}
			local player, d = nearest_player(o, 128)
			local chance = player and (d * d) / 512 or 64
			if player and (math.random(0, math.floor(chance + 1)) == 0 or math.random(0, crystals + 1) == 0) then
				return set_phase(e, "strafe", player)
			end
			if math.random(8) == 1 then
				e._dir_step = -e._dir_step
			end
			e._node = (e._node + e._dir_step) % 12
			e._target = ring_node(e._node, E.ymin + 73 + math.random() * 20)
		end
	end,
}

-- strafing: toward the player; in reach (64), in sight and facing them within 10 degrees for 5 ticks, a fireball
PHASE.strafe = {
	begin = function(e) e._charge = 0 end,
	step = function(e, dt)
		local p = e._target
		if not p or not p:is_valid() or p:get_hp() <= 0 or not E.inside(p:get_pos()) then
			return set_phase(e, "hold")
		end
		-- Minecraft's height over them: 0.4 + d / 80 - 1, at most 10, so that it comes in level
		local pp, pos = p:get_pos(), e.object:get_pos()
		local d = math.sqrt((pp.x - pos.x) ^ 2 + (pp.z - pos.z) ^ 2)
		fly_toward(e, vector.offset(pp, 0, math.min(0.4 + d / 80 - 1, 10) + 3, 0), 13, dt)
		local hp = head_pos(e)
		local tp = vector.offset(pp, 0, 1, 0)
		-- facing them across within 10 degrees (Minecraft compares its look with the way to them on the level)
		local to = vector.normalize({x = tp.x - pos.x, y = 0, z = tp.z - pos.z})
		local look = core.yaw_to_dir(e.object:get_yaw())
		local angle = math.deg(math.acos(math.max(-1, math.min(1, look.x * to.x + look.z * to.z))))
		if vector.distance(hp, tp) < 64 and core.line_of_sight(hp, tp) then
			e._charge = e._charge + dt * 20
			if e._charge >= 5 and angle < 10 then
				fireball(vector.add(hp, look), tp)
				core.sound_play("goodluck_end_dragon", {pos = hp, gain = 1, max_hear_distance = 96}, true)
				return set_phase(e, "hold")
			end
		elseif e._charge > 0 then
			e._charge = e._charge - dt * 20
		end
		if e._ptime > 15 then
			set_phase(e, "hold")
		end
	end,
}

-- landing: over the podium, then down onto it
PHASE.approach = {
	step = function(e, dt)
		local top = podium_top()
		if not top then
			return set_phase(e, "hold")
		end
		if fly_toward(e, vector.offset(top, 0, 16, 0), 10, dt) < 6 then
			set_phase(e, "landing")
		end
	end,
}
PHASE.landing = {
	step = function(e, dt)
		local top = podium_top()
		if fly_toward(e, top, 5, dt) < 1 then
			e.object:set_pos(top)
			hover(e)
			set_phase(e, "scanning")
		end
	end,
}

-- sitting: turning to the nearest player within 20 (10 up or down) and, after 25 ticks on one, roaring at them; after
-- 100 ticks with none, charging the nearest within 150, else taking off; breathing on them for 10 s, up to 4 times
PHASE.scanning = {
	begin = function(e)
		e.object:set_animation({x = 2, y = 2.5}, 1, 0, true)
		hover(e)
	end,
	step = function(e, dt)
		local p = nearest_player(e.object:get_pos(), 20, function(pl)
			return math.abs(pl:get_pos().y - e.object:get_pos().y) <= 10
		end)
		if p then
			face(e, p:get_pos(), dt)
			if e._ptime > 1.25 then
				return set_phase(e, "roar", p)
			end
		elseif e._ptime >= 5 then
			local far = nearest_player(e.object:get_pos(), 150)
			if far then
				return set_phase(e, "charge", far)
			end
			return set_phase(e, "takeoff")
		end
	end,
}
PHASE.roar = {
	begin = function(e)
		core.sound_play("goodluck_end_dragon", {pos = e.object:get_pos(), gain = 1.5, max_hear_distance = 128}, true)
	end,
	step = function(e, dt)
		if e._target and e._target:is_valid() then
			face(e, e._target:get_pos(), dt)
		end
		if e._ptime >= 2 then
			set_phase(e, "flaming")
		end
	end,
}
PHASE.flaming = {
	begin = function(e)
		local hp = head_pos(e)
		local d = core.yaw_to_dir(e.object:get_yaw())
		local at = vector.round(vector.add(hp, vector.multiply(d, 2.5)))
		for _ = 1, 12 do
			local def = core.registered_nodes[core.get_node(vector.offset(at, 0, -1, 0)).name]
			if def and def.walkable then
				break
			end
			at.y = at.y - 1
		end
		breath(vector.offset(at, 0, -0.4, 0), 5, 10, 0)
		e._flames = (e._flames or 0) + 1
	end,
	step = function(e)
		if e._ptime >= 10 then
			if e._flames >= 4 then
				e._flames = 0
				return set_phase(e, "takeoff")
			end
			set_phase(e, "scanning")
		end
	end,
}

-- taking off: up and out until 10 from the podium, then circling again
PHASE.takeoff = {
	begin = function(e)
		e.object:set_animation({x = 0, y = 1.75}, 1, 0, true)
		local d = core.yaw_to_dir(e.object:get_yaw())
		local pos = e.object:get_pos()
		e._target = {x = pos.x + d.x * 40, y = E.ymin + 105, z = pos.z + d.z * 40}
	end,
	step = function(e, dt)
		fly_toward(e, e._target, 10, dt)
		local top = podium_top() or e.object:get_pos()
		if vector.distance(e.object:get_pos(), top) > 20 or e._ptime > 6 then
			e._node = nil
			set_phase(e, "hold")
		end
	end,
}

-- charging: straight at where the player was, fast, then circling
PHASE.charge = {
	begin = function(e)
		e.object:set_animation({x = 0, y = 1.75}, 1, 0, true)
		e._spot = vector.offset(e._target:get_pos(), 0, 1, 0)
	end,
	step = function(e, dt)
		if fly_toward(e, e._spot, 18, dt) < 10 or e._ptime > 8 then
			set_phase(e, "hold")
		end
	end,
}

-- dying: over the podium, rising slowly for 10 s in bursts of light
PHASE.dying = {
	begin = function(e)
		hover(e)
		clear_bars(e)
		core.sound_play("goodluck_end_dragon_death", {pos = e.object:get_pos(), gain = 2, max_hear_distance = 256}, true)
	end,
	step = function(e, dt)
		local pos = e.object:get_pos()
		e._v = {x = 0, y = 0.6, z = 0}
		e.object:set_velocity(e._v)
		core.add_particlespawner({amount = 6, time = dt, pos = {min = vector.offset(pos, -4, 0, -4),
			max = vector.offset(pos, 4, 4, 4)}, vel = {min = vector.new(-1, 1, -1), max = vector.new(1, 3, 1)},
			exptime = {min = 0.5, max = 1.5}, size = {min = 4, max = 8}, glow = 14, texture = "tnt_boom.png"})
		if e._ptime >= 10 then
			E.dragon_died(e, pos)
		end
	end,
}

local function remember(e)
	storage:set_string("dragon", core.serialize({hp = e._hp, phase = e._phase, pos = e.object:get_pos()}))
end

core.register_entity(D, {
	initial_properties = {
		physical = false,
		collide_with_objects = false,
		pointable = true,
		visual = "mesh",
		mesh = "goodluck_models_ender_dragon.glb",
		textures = {"goodluck_end_dragon.png^goodluck_end_dragon_eyes.png"},
		collisionbox = {-3, 0.5, -3, 3, 4, 3},
		selectionbox = {-3, 0.5, -3, 3, 4, 3},
		static_save = true,
		makes_footstep_sound = false,
	},
	_goodluck_dragon = true,
	on_activate = function(self, staticdata)
		local s = core.deserialize(staticdata or "") or {}
		self._hp = s.hp or MAX
		self._v = vector.zero()
		self._dt, self._heal, self._wreck, self._hit = 0, 0, 0, 0
		self.object:set_armor_groups({immortal = 1, fleshy = 100})
		self.object:set_animation({x = 0, y = 1.75}, 1, 0, true)
		local head = core.add_entity(self.object:get_pos(), "goodluck_end:dragon_head")
		if head then
			head:set_attach(self.object, "head", {x = 0, y = 0, z = 6}, {x = 0, y = 0, z = 0})
		end
		set_phase(self, s.phase == "dying" and "dying" or "hold")
	end,
	get_staticdata = function(self)
		return core.serialize({hp = self._hp, phase = self._phase})
	end,
	on_deactivate = function(self)
		for _, f in pairs(self._forced or {}) do
			core.forceload_free_block(f.pos, true)
		end
		self._forced = nil
	end,
	-- a hit's damage as the engine counts it (the weapon's fleshy, less if hit too soon); explosions and others whole
	hurt = function(self, puncher, tflp, caps, head)
		if self._phase == "dying" then
			return
		end
		local dmg = 1
		if caps and caps.damage_groups and caps.damage_groups.fleshy then
			local full = caps.full_punch_interval or 1
			dmg = caps.damage_groups.fleshy * math.min(1, (tflp or full) / full)
		end
		local shot = caps and caps.damage_groups and caps.damage_groups.knockback ~= nil
		local sitting = self._phase == "scanning" or self._phase == "roar" or self._phase == "flaming"
		if shot and sitting then
			return
		end
		if not head and not (caps and caps._explosion) then
			dmg = dmg / 4 + math.min(dmg, 1)
		end
		if dmg <= 0 then
			return
		end
		self._hp = self._hp - dmg
		core.sound_play("goodluck_end_dragon_hurt", {pos = self.object:get_pos(), gain = 1, max_hear_distance = 64}, true)
		self.object:set_texture_mod("^[colorize:#ff000066")
		core.after(0.25, function()
			if self.object:get_pos() then
				self.object:set_texture_mod("")
			end
		end)
		if sitting then
			self._sat_damage = (self._sat_damage or 0) + dmg
			if self._sat_damage > MAX * 0.25 then
				self._sat_damage = 0
				set_phase(self, "takeoff")
			end
		end
		if self._hp <= 0 then
			self._hp = 0
			self._killer = puncher and puncher:is_player() and puncher:get_player_name() or self._killer
			set_phase(self, "dying")
		end
		remember(self)
	end,
	on_punch = function(self, puncher, tflp, caps)
		self:hurt(puncher, tflp, caps, false)
		return true
	end,
	on_step = function(self, dtime)
		self._dt = self._dt + dtime
		if self._dt < 0.1 then
			return
		end
		local dt = self._dt
		self._dt = 0
		self._ptime = self._ptime + dt
		PHASE[self._phase].step(self, dt)
		if not self.object:get_pos() then
			return
		end
		local pos = self.object:get_pos()
		-- the mapblocks where it is and where it will be in the next 4 s kept active while someone is in the End
		-- (the handheld's active range is 2 blocks, the engine takes them in every 2 s), as it flies out of their reach
		-- and back; let go 8 s later
		self._forced = self._forced or {}
		if #players_in_end() > 0 then
			for k = 0, 4 do
				local p = vector.add(pos, vector.multiply(self._v, k))
				local key = core.hash_node_position(vector.floor(vector.divide(p, 16)))
				if not self._forced[key] then
					core.forceload_block(p, true, -1)
				end
				self._forced[key] = {pos = vector.round(p), t = 8}
			end
		end
		for key, f in pairs(self._forced) do
			f.t = f.t - dt
			if f.t <= 0 then
				core.forceload_free_block(f.pos, true)
				self._forced[key] = nil
			end
		end
		if self._phase == "dying" then
			return
		end
		-- healing from the nearest crystal within 32, its beam drawn
		self._heal = self._heal + dt
		if self._heal >= 0.5 then
			self._heal = 0
			local crystal, near
			for _, obj in ipairs(core.get_objects_inside_radius(pos, 32)) do
				local ent = obj:get_luaentity()
				if ent and ent.name == "goodluck_end:end_crystal" then
					local d = vector.distance(pos, obj:get_pos())
					if not near or d < near then
						crystal, near = obj, d
					end
				end
			end
			self._crystal = crystal and crystal:get_pos()
			if crystal then
				if self._hp < MAX then
					self._hp = math.min(MAX, self._hp + 1)
				end
				local from = vector.offset(crystal:get_pos(), 0, 1, 0)
				local to = vector.offset(pos, 0, 2, 0)
				local n = math.min(24, math.floor(near))
				for i = 0, n do
					core.add_particle({pos = vector.add(from, vector.multiply(vector.subtract(to, from), i / n)),
						expirationtime = 0.55, size = 2, glow = 14, texture = "goodluck_nether_portal_particle.png^[multiply:#f0a0ff"})
				end
			end
			boss_bars(self)
			remember(self)
		end
		-- its wings and head: whoever it flies into is thrown back and hurt 5, by the head 10 (not while it sits)
		self._hit = self._hit + dt
		if self._hit >= 0.5 and self._phase ~= "scanning" and self._phase ~= "roar" and self._phase ~= "flaming" then
			self._hit = 0
			local hp = head_pos(self)
			for _, p in ipairs(players_in_end()) do
				local pp = vector.offset(p:get_pos(), 0, 1, 0)
				if not creative(p) then
					if vector.distance(pp, hp) < 3 then
						p:set_hp(p:get_hp() - 10, {type = "set_hp", cause = "goodluck_end:dragon"})
					elseif vector.distance(pp, vector.offset(pos, 0, 2.5, 0)) < 5 then
						local push = vector.normalize(vector.subtract(pp, pos))
						p:add_velocity({x = push.x * 12, y = 6, z = push.z * 12})
						p:set_hp(p:get_hp() - 5, {type = "set_hp", cause = "goodluck_end:dragon"})
					end
				end
			end
		end
		-- what players built in its way
		self._wreck = self._wreck + dt
		if self._wreck >= 0.5 then
			self._wreck = 0
			for _, p in ipairs(core.find_nodes_in_area(vector.offset(pos, -3, 0, -3), vector.offset(pos, 3, 4, 3),
					{"group:cracky", "group:crumbly", "group:choppy", "group:snappy", "group:oddly_breakable_by_hand"})) do
				if not IMMUNE[core.get_node(p).name] then
					core.remove_node(p)
				end
			end
		end
	end,
})

-- a crystal blown up: if it was the one healing the dragon, the dragon is hurt 10
function E.on_crystal_destroyed(pos, puncher)
	for _, ent in pairs(core.luaentities) do
		if ent.name == D and ent._crystal and vector.distance(ent._crystal, pos) < 1 then
			ent:hurt(puncher, nil, {damage_groups = {fleshy = 10}, _explosion = true}, true)
		end
	end
end

-- The egg it leaves: it teleports away when hit (up to 15 about, on the ground), falls; Creative breaks it
core.register_node("goodluck_end:dragon_egg", {
	description = S("Dragon Egg"),
	drawtype = "nodebox",
	tiles = {"goodluck_end_dragon_egg.png"},
	paramtype = "light",
	light_source = 1,
	node_box = {type = "fixed", fixed = {{-1/16, 7/16, -1/16, 1/16, 8/16, 1/16}, {-2/16, 6/16, -2/16, 2/16, 7/16, 2/16},
		{-3/16, 4/16, -3/16, 3/16, 6/16, 3/16}, {-5/16, 1/16, -5/16, 5/16, 4/16, 5/16},
		{-6/16, -7/16, -6/16, 6/16, 1/16, 6/16}, {-5/16, -8/16, -5/16, 5/16, -7/16, 5/16}}},
	groups = {falling_node = 1, oddly_breakable_by_hand = 3},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
	can_dig = function(_, player)
		return player and core.is_creative_enabled(player:get_player_name())
	end,
	on_punch = function(pos, node, puncher)
		if puncher and core.is_creative_enabled(puncher:get_player_name()) then
			return
		end
		for _ = 1, 1000 do
			local to = vector.offset(pos, math.random(-15, 15), math.random(-7, 7), math.random(-15, 15))
			if core.get_node(to).name == "air" then
				core.remove_node(pos)
				core.set_node(to, node)
				core.check_for_falling(to)
				for i = 0, 16 do
					local f = i / 16
					core.add_particle({pos = vector.add(pos, vector.multiply(vector.subtract(to, pos), f)),
						velocity = {x = math.random() - 0.5, y = math.random() - 0.5, z = math.random() - 0.5},
						expirationtime = 0.8, size = 1.5, glow = 12, texture = "goodluck_nether_portal_particle.png"})
				end
				return
			end
		end
	end,
	on_rightclick = function(pos, node, clicker)
		core.registered_nodes["goodluck_end:dragon_egg"].on_punch(pos, node, clicker)
	end,
})

-- its death: experience, the exit portal lit, the egg the first time; ready for a next one never (respawning it
-- with four crystals is not here)
function E.dragon_died(e, pos)
	local first = storage:get_string("killed") ~= "1"
	storage:set_string("killed", "1")
	storage:set_string("dragon", "dead")
	for _, f in pairs(e._forced or {}) do
		core.forceload_free_block(f.pos, true)
	end
	e.object:remove()
	E.exit_portal(true)
	local top = podium_top()
	if first and top then
		core.set_node(top, {name = "goodluck_end:dragon_egg"})
	end
	if core.global_exists("goodluck_xp") then
		goodluck_xp.drop(vector.offset(top or pos, 0, 2, 0), first and 12000 or 500)
	end
	core.log("action", ("[goodluck_end] the ender dragon is dead%s"):format(e._killer and (", killed by " .. e._killer) or ""))
end

-- the fight: the first time a player comes into the End (its podium made), the dragon comes over the middle
local function dragon_entity()
	for _, ent in pairs(core.luaentities) do
		if ent.name == D and ent.object:get_pos() then
			return ent
		end
	end
end
-- (once: after that it is kept with its mapblock; one left inactive out of everyone's reach has its mapblock
-- forceloaded where it was last, so that it wakes up and flies back)
local waking
function E.spawn_dragon()
	local o = E.podium()
	local kept = storage:get_string("dragon")
	if not o or kept == "dead" or dragon_entity() then
		if waking and dragon_entity() then
			core.forceload_free_block(waking, true)
			waking = nil
		end
		return
	end
	if kept ~= "" then
		local s = core.deserialize(kept) or {}
		if s.pos and not waking then
			waking = vector.round(s.pos)
			core.forceload_block(waking, true, -1)
		end
		return
	end
	local obj = core.add_entity({x = 0, y = E.ymin + 128, z = 0}, D)
	if obj then
		remember(obj:get_luaentity())
		core.log("action", "[goodluck_end] the ender dragon comes")
	end
end
-- the pillars' tops kept active during the fight, so that their crystals heal it out of the players' reach too, as
-- the whole End is loaded in Minecraft
local pillars_held = false
local function hold_pillars(on)
	if on == pillars_held then
		return
	end
	pillars_held = on
	for _, sp in ipairs(E.spikes) do
		local p = {x = sp.x, y = E.ymin + sp.height + 1, z = sp.z}
		if on then
			core.forceload_block(p, true, -1)
		else
			core.forceload_free_block(p, true)
		end
	end
end
local fight_timer = 0
core.register_globalstep(function(dtime)
	fight_timer = fight_timer + dtime
	if fight_timer < 2 then
		return
	end
	fight_timer = 0
	local here = #players_in_end() > 0
	hold_pillars(here and storage:get_string("dragon") ~= "dead" and storage:get_string("dragon") ~= "")
	if here then
		E.spawn_dragon()
	end
end)
E.dragon_entity = dragon_entity
