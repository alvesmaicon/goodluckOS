-- The Nether's monsters as Minecraft (26.x) has them, in goodluck_models' meshes: the ghast floats about and fires at
-- whoever it sees; the blaze keeps its distance and fires bursts of three; the magma cube hops, in three sizes, the
-- bigger splitting in smaller; zombified piglins leave you alone until one of them is hit; the wither skeleton hits
-- with Wither. Blazes and wither skeletons come out only in fortresses (the next wave: their eggs until then);
-- ghasts, magma cubes and zombified piglins anywhere in the Nether whatever the light, and now and then a zombified
-- piglin out of a portal in the Overworld. Their fireballs, the ghast's blast, being on fire, the fire charge, and
-- what they drop
local S = core.get_translator("goodluck_nether")
local R = goodluck_nether
local N = "goodluck_nether:"
local PORTAL, RACK = N .. "portal", N .. "netherrack"
local mob_class = mobs.mob_class
local sword_gold = core.get_modpath("goodluck_metals") and "goodluck_metals_sword_gold.png" or "blank.png"
local bone = core.registered_items["goodluck_monsters:bone"] and "goodluck_monsters:bone"
local flesh = core.registered_items["goodluck_monsters:rotten_flesh"] and "goodluck_monsters:rotten_flesh"
local gunpowder = core.registered_items["tnt:gunpowder"] and "tnt:gunpowder"

-- the given drops that exist (an optional mod's may not)
local function drops(...)
	local list = {}
	for i = 1, select("#", ...) do
		local d = select(i, ...)
		if d and d.name then
			list[#list + 1] = d
		end
	end
	return list
end

local function creative(obj)
	return obj:is_player() and core.is_creative_enabled(obj:get_player_name())
end

-- their sound now and then, every 4 to 10 s as in Minecraft (goodluck_monsters' monsters do the same)
local AMBIENT = {}
local function ambient(self, dtime)
	self._ambient = (self._ambient or math.random() * 6) - dtime
	if self._ambient <= 0 then
		self._ambient = 4 + math.random() * 6
		local sound = AMBIENT[self.name]
		if type(sound) == "function" then
			sound = sound(self)
		end
		self:mob_sound({name = sound, gain = 0.6})
	end
end

-- a fire where the air is: for ever on netherrack, as in Minecraft
local function set_fire(pos, by)
	if core.get_node(pos).name ~= "air" or core.is_protected(pos, by or "") then
		return
	end
	local below = core.get_node(vector.offset(pos, 0, -1, 0)).name
	if below == RACK then
		core.set_node(pos, {name = "fire:permanent_flame"})
	elseif (core.registered_nodes[below] or {}).walkable then
		core.set_node(pos, {name = "fire:basic_flame"})
	end
end

-- on fire, as a small fireball leaves the player: 1 a second while it lasts, out in water; flames around them and in
-- the lower corners of their view. Its hurt says it is fire, which Fire Resistance keeps away
local burning = {}
local function douse(player)
	local b = burning[player:get_player_name()]
	if b then
		core.delete_particlespawner(b.flames)
		for _, id in ipairs(b.hud) do
			player:hud_remove(id)
		end
		burning[player:get_player_name()] = nil
	end
end

function R.ignite(obj, seconds)
	if not obj:is_player() or creative(obj) or obj:get_hp() <= 0 then
		return
	end
	local b = burning[obj:get_player_name()]
	if b then
		b.left = math.max(b.left, seconds)
		return
	end
	local corner = function(x)
		return obj:hud_add({type = "image", position = {x = x, y = 1}, alignment = {x = 1 - 2 * x, y = -1},
			scale = {x = 8, y = 8}, text = "fire_basic_flame.png"})
	end
	burning[obj:get_player_name()] = {left = seconds, tick = 0, hud = {corner(0), corner(1)},
		flames = core.add_particlespawner({amount = 10, time = 0, attached = obj,
			pos = {min = vector.new(-0.3, 0, -0.3), max = vector.new(0.3, 1.7, 0.3)},
			vel = {min = vector.new(0, 0.5, 0), max = vector.new(0, 1.2, 0)},
			exptime = {min = 0.3, max = 0.6}, size = {min = 2, max = 4}, glow = 14, texture = "fire_basic_flame.png"})}
end

core.register_globalstep(function(dtime)
	for name, b in pairs(burning) do
		local player = core.get_player_by_name(name)
		if not player then
			burning[name] = nil
		else
			local pos = player:get_pos()
			local wet = core.get_item_group(core.get_node(pos).name, "water") > 0 or
				core.get_item_group(core.get_node(vector.offset(pos, 0, 1, 0)).name, "water") > 0
			b.left, b.tick = b.left - dtime, b.tick + dtime
			if b.tick >= 1 and not wet then
				b.tick = b.tick - 1
				player:set_hp(player:get_hp() - 1, {type = "set_hp", cause = "goodluck_nether:burning", fire = true})
			end
			if wet or b.left <= 0 or player:get_hp() <= 0 then
				douse(player)
			end
		end
	end
end)
core.register_on_dieplayer(douse)
core.register_on_leaveplayer(douse)

-- Minecraft's blast resistance of what a small blast can get through; stone and anything harder (6 and up) stops it
local RESIST = {[RACK] = 0.4, [N .. "soul_sand"] = 0.5, [N .. "glowstone"] = 0.3, [N .. "magma"] = 0.5,
	[N .. "quartz_ore"] = 3, [N .. "gold_ore"] = 3, [PORTAL] = 0, ["default:gravel"] = 0.6, ["default:clay"] = 0.6,
	["default:sandstone"] = 0.8, ["default:desert_sandstone"] = 0.8, ["default:silver_sandstone"] = 0.8,
	["default:glass"] = 0.3, ["default:ice"] = 0.5, ["default:cactus"] = 0.4, ["default:bookshelf"] = 1.5}
local resist = {}
local function resistance(name)
	local r = resist[name] or RESIST[name]
	if r then
		return r
	end
	local def = core.registered_nodes[name] or {}
	local g = def.groups or {}
	if def.liquidtype and def.liquidtype ~= "none" then
		r = 100
	elseif def.diggable == false or g.unbreakable or g.immortal then
		r = 3600000
	elseif not def.walkable or g.dig_immediate or g.attached_node then
		r = 0
	elseif g.leaves or g.snappy then
		r = 0.2
	elseif g.wool then
		r = 0.8
	elseif g.tree then
		r = 2
	elseif g.choppy then
		r = 3
	elseif g.crumbly then
		r = 0.5
	else
		r = 6
	end
	resist[name] = r
	return r
end

-- clear between two points: nothing solid in the way
local function clear(a, b)
	for pointed in core.raycast(a, b, false, false) do
		if pointed.type == "node" and (core.registered_nodes[core.get_node(pointed.under).name] or {}).walkable then
			return false
		end
	end
	return true
end

-- Minecraft's explosion: rays from the middle (here one through each block around) start at 0.7 to 1.3 times the
-- power and lose 0.225 each 0.3 they go, and (resistance + 0.3) * 0.3 more at each step in a block; the blocks they
-- reach with strength left break (dropping what they drop) and a third of the air they reach with ground under it
-- catches fire (fire = true).
-- Within twice the power, whoever sees the middle is hurt 7 * 2 * power * (i * i + i) / 2 + 1 and pushed, i being 1
-- less the share of that distance (times the share of them in view). by: who punches (the fireball, or who sent it
-- back), owner: whose blast it is for protection
local function explode(pos, power, fire, by, owner)
	core.sound_play("tnt_explode", {pos = pos, gain = 1.5, max_hear_distance = 64}, true)
	core.add_particlespawner({amount = 24, time = 0.2, pos = {min = vector.offset(pos, -power, -power, -power),
		max = vector.offset(pos, power, power, power)}, vel = {min = vector.new(-1, 0, -1), max = vector.new(1, 2, 1)},
		exptime = {min = 0.5, max = 1.2}, size = {min = 6, max = 12}, texture = "tnt_smoke.png"})
	local center, reach, names = vector.round(pos), math.ceil(power * 1.3 / 0.225 * 0.3), {}
	local function name_at(p)
		local h = core.hash_node_position(p)
		names[h] = names[h] or core.get_node(p).name
		return names[h]
	end
	local blown, marked = {}, {}
	for dx = -reach, reach do
		for dy = -reach, reach do
			for dz = -reach, reach do
				local target = vector.offset(center, dx, dy, dz)
				local d = vector.distance(pos, target)
				if d > 0 and d <= reach then
					local dir = vector.divide(vector.subtract(target, pos), d)
					local f, t = power * (0.7 + math.random() * 0.6), 0
					while f > 0 do
						local cell = vector.round(vector.add(pos, vector.multiply(dir, t)))
						local name = name_at(cell)
						if name ~= "air" then
							f = f - (resistance(name) + 0.3) * 0.3
						end
						local h = core.hash_node_position(cell)
						if f > 0 and not marked[h] then
							marked[h] = true
							blown[#blown + 1] = cell
						end
						f, t = f - 0.225, t + 0.3
					end
				end
			end
		end
	end
	local who = owner and owner:is_player() and owner:get_player_name() or ""
	for _, p in ipairs(blown) do
		local name = name_at(p)
		local def = core.registered_nodes[name]
		if name ~= "air" and def and not core.is_protected(p, who) then
			local items
			if def.on_blast then
				items = def.on_blast(p, 1)
			else
				items = core.get_node_drops(name, "")
				core.remove_node(p)
				core.check_for_falling(p)
			end
			for _, item in ipairs(items or {}) do
				core.add_item(vector.offset(p, math.random() - 0.5, 0, math.random() - 0.5), item)
			end
		end
	end
	if fire then
		for _, p in ipairs(blown) do
			if math.random(3) == 1 then
				set_fire(p, who)
			end
		end
	end
	local radius = power * 2
	for _, obj in ipairs(core.get_objects_inside_radius(pos, radius + 1)) do
		local ent = obj:get_luaentity()
		local p = obj:get_pos()
		if p and (obj:is_player() or ent and ent._cmi_is_mob) and (not ent or ent.health > 0) then
			local d = vector.distance(p, pos) / radius
			local box = obj:get_properties().collisionbox
			if d <= 1 then
				local inview = 0
				for _, y in ipairs({box[2] + 0.1, (box[2] + box[5]) / 2, box[5] - 0.1}) do
					inview = inview + (clear(pos, vector.offset(p, 0, y, 0)) and 1 or 0)
				end
				local i = (1 - d) * inview / 3
				if i > 0 then
					local dir = vector.direction(pos, vector.offset(p, 0, (box[2] + box[5]) / 2, 0))
					obj:punch(by and by:is_valid() and by or obj, 1.0, {full_punch_interval = 1.0,
						damage_groups = {fleshy = math.floor((i * i + i) / 2 * 7 * radius + 1)}}, dir)
					if obj:is_valid() then
						obj:add_velocity(vector.multiply(dir, i * 10))
					end
				end
			end
		end
	end
end
R.explode = explode

-- the fireballs: sprites of the fire charge lit as fire is, trailing smoke; each tick Minecraft adds 0.1 a tick along
-- its way and keeps 0.95 of its speed, so that it starts slow and goes on to 38 nodes a second. A ghast's (power) can
-- be hit back by whoever punches it: where they look, theirs then, and it kills a ghast it hits
local TOP = 38
local function fireball(name, def)
	core.register_entity(name, {
		initial_properties = {
			visual = "sprite",
			textures = {"goodluck_nether_fire_charge.png"},
			visual_size = {x = def.size, y = def.size},
			collisionbox = {-def.box, -def.box, -def.box, def.box, def.box, def.box},
			physical = false,
			pointable = def.power ~= nil,
			glow = 15,
			static_save = false,
		},
		_fire = true,
		on_activate = function(self)
			self.object:set_armor_groups({immortal = 1})
			core.add_particlespawner({amount = 12, time = 0, attached = self.object,
				exptime = {min = 0.3, max = 0.6}, size = {min = def.size * 2, max = def.size * 4},
				texture = "tnt_smoke.png"})
		end,
		on_step = function(self, dtime)
			self._life = (self._life or 0) + dtime
			local pos = self.object:get_pos()
			if self._life > 10 then
				self.object:remove()
				return
			end
			local v = self.object:get_velocity()
			local speed = vector.length(v)
			local dir = speed > 0 and vector.divide(v, speed) or vector.new(0, 0, 1)
			self.object:set_velocity(vector.multiply(dir, TOP + (speed - TOP) * 0.95 ^ (dtime * 20)))
			local last = self._last or pos
			self._last = pos
			for pointed in core.raycast(last, pos, true, false) do
				if pointed.type == "object" and pointed.ref ~= self.object then
					local obj = pointed.ref
					local ent = obj:get_luaentity()
					if (obj:is_player() or ent and ent._cmi_is_mob) and (self._back or obj ~= self._owner) then
						def.hit(self, obj, pointed.intersection_point)
						self.object:remove()
						return
					end
				elseif pointed.type == "node" and
						(core.registered_nodes[core.get_node(pointed.under).name] or {}).walkable then
					def.land(self, pointed)
					self.object:remove()
					return
				end
			end
		end,
		on_punch = function(self, puncher)
			if def.power and puncher and puncher:is_player() then
				local v = self.object:get_velocity()
				self.object:set_velocity(vector.multiply(puncher:get_look_dir(), math.max(20, vector.length(v))))
				self._owner, self._back, self._last = puncher, true, self.object:get_pos()
			end
			return true
		end,
	})
end

local function sender(self)
	return self._back and self._owner and self._owner:is_valid() and self._owner or self.object
end

fireball(N .. "fireball", {size = 1.5, box = 0.5, power = 1,
	-- 6 to what it hits (a ghast's own sent back: death), then the blast, a fiery one
	hit = function(self, obj, at)
		local ent = obj:get_luaentity()
		local damage = self._back and ent and ent.name == N .. "ghast" and 1000 or 6
		local dir = vector.normalize(self.object:get_velocity())
		obj:punch(sender(self), 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = damage}}, dir)
		explode(vector.subtract(at, vector.multiply(dir, 0.5)), 1, true, sender(self), self._owner)
	end,
	land = function(self, pointed)
		explode(vector.add(pointed.intersection_point, vector.multiply(pointed.intersection_normal, 0.5)), 1, true,
			sender(self), self._owner)
	end,
})
fireball(N .. "small_fireball", {size = 0.375, box = 0.15625,
	-- 5 and 5 s on fire to what it hits, unless fire can't hurt it; a fire where it lands
	hit = function(self, obj)
		local ent = obj:get_luaentity()
		if ent and ent._fire_immune then
			return
		end
		obj:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = 5}},
			vector.normalize(self.object:get_velocity()))
		R.ignite(obj, 5)
	end,
	land = function(self, pointed)
		set_fire(pointed.above, self._owner and self._owner:is_player() and self._owner:get_player_name())
	end,
})

local function shoot(name, owner, from, to)
	local ball = core.add_entity(from, name)
	local ent = ball and ball:get_luaentity()
	if ent then
		ent._owner = owner
		ball:set_velocity(vector.multiply(vector.direction(from, to), 2))
		core.sound_play("goodluck_nether_fireball", {pos = from, gain = 1, max_hear_distance = 32}, true)
	end
end

-- a target: who they had while still in range and seen in the last 3 s, else the nearest player in range they see
-- (when: more that must hold of a new one); looked for 4 times a second, _seen the time since they last saw it
local function eyes(obj)
	local p = obj:get_pos()
	return p and vector.offset(p, 0, obj:is_player() and obj:get_properties().eye_height or 1, 0)
end
local function target(self, dtime, from, range, when)
	self._seen = (self._seen or 0) + dtime
	self._think = (self._think or 0) - dtime
	if self._think > 0 then
		local t = self._target
		return t and t:is_valid() and t or nil
	end
	self._think = 0.25
	local t = self._target
	if t and t:is_valid() and t:get_hp() > 0 and vector.distance(from, t:get_pos()) <= range then
		if self:line_of_sight(from, eyes(t)) then
			self._seen = 0
		end
		if (self._seen or 0) < 3 then
			return t
		end
	end
	self._target = nil
	local best, near = nil, range
	for _, player in ipairs(core.get_connected_players()) do
		local p = player:get_pos()
		local d = vector.distance(from, p)
		if d < near and player:get_hp() > 0 and not mobs:is_invisible(self, player:get_player_name()) and
				(not when or when(p)) and self:line_of_sight(from, eyes(player)) then
			best, near = player, d
		end
	end
	self._target, self._seen = best, 0
	return best
end

-- The ghast: 10 of health, 4 a side, flies; picks a spot up to 16 away each way (inside the realm) and drifts there
-- (a nudge of 0.1 every 2 to 6 ticks, 0.91 of its speed kept a tick: some 5 a second), a new one when it gets there,
-- bumps into something or would go far. It spots a player level with it (4 up or down) and keeps them up to 100
-- away; one in 64 it sees, it charges 10 ticks (its warning), opens its eyes and mouth and fires at 20, and waits 2 s
local function ghast_step(self, dtime, moveresult)
	local pos = self.object:get_pos()
	ambient(self, dtime)
	local mid = vector.offset(pos, 0, 2, 0)
	local t = target(self, dtime, mid, 100, function(p)
		return math.abs(p.y - pos.y) <= 4
	end)
	local goal = self._goal
	if not goal or vector.distance(goal, pos) < 1 or vector.distance(goal, pos) > 60 or
			moveresult and moveresult.collides and #moveresult.collisions > 0 and moveresult.collisions[1].type == "node" then
		goal = vector.offset(pos, math.random(-16, 16), math.random(-16, 16), math.random(-16, 16))
		goal.y = math.max(R.ymin + 8, math.min(R.ymax - 8, goal.y))
		self._goal = goal
	end
	local v = vector.multiply(self.object:get_velocity(), 0.91 ^ (dtime * 20))
	v = vector.add(v, vector.multiply(vector.direction(pos, goal), 10 * dtime))
	self.object:set_velocity(v)
	local charge = self._charge or 0
	if t and vector.distance(mid, t:get_pos()) < 64 and self._seen < 0.3 then
		self:yaw_to_pos(t:get_pos())
		local before = charge
		charge = charge + dtime * 20
		if before < 10 and charge >= 10 then
			self:mob_sound({name = "goodluck_nether_ghast_warn", gain = 1})
		end
		if charge >= 20 then
			local look = vector.new(-math.sin(self.object:get_yaw()), 0, math.cos(self.object:get_yaw()))
			local from = vector.add(vector.offset(pos, 0, 2.5, 0), vector.multiply(look, 4))
			shoot(N .. "fireball", self.object, from, vector.offset(t:get_pos(), 0, 0.9, 0))
			charge = -40
		end
	else
		if v.x ~= 0 or v.z ~= 0 then
			self:set_yaw(core.dir_to_yaw(v), 6)
		end
		if charge > 0 then
			charge = math.max(0, charge - dtime * 20)
		end
	end
	self._charge = charge
	local open = charge > 10
	if open ~= (self._open or false) then
		self._open = open
		self.object:set_properties({textures = {open and "goodluck_nether_ghast_shooting.png" or
			"goodluck_nether_ghast.png"}})
	end
	return false
end

-- The blaze: 20 of health, fire can't hurt it, water does; it sinks slowly and rises to who it fights. Within 2 it
-- hits (6, every second); further, up to 48 and in sight, it burns up for 3 s and fires three small fireballs 0.3 s
-- apart, rests 5 s, and again; out of sight it goes after them. Smoke all the time, flames while it burns up
local function charged(self, on)
	if self._flames then
		core.delete_particlespawner(self._flames)
		self._flames = nil
	end
	if on then
		self._flames = core.add_particlespawner({amount = 20, time = 0, attached = self.object,
			pos = {min = vector.new(-0.4, 0.2, -0.4), max = vector.new(0.4, 1.8, 0.4)},
			vel = {min = vector.new(0, 0.6, 0), max = vector.new(0, 1.4, 0)}, exptime = {min = 0.3, max = 0.6},
			size = {min = 2, max = 4}, glow = 14, texture = "fire_basic_flame.png"})
	end
end

local function blaze_step(self, dtime, moveresult)
	local pos = self.object:get_pos()
	ambient(self, dtime)
	self._burn = (self._burn or 0) - dtime
	if self._burn <= 0 then
		self._burn = 1 + math.random() * 2
		core.sound_play("fire_fire", {object = self.object, gain = 0.3, max_hear_distance = 12}, true)
	end
	local mid = vector.offset(pos, 0, 1.6, 0)
	local t = target(self, dtime, mid, 48)
	local v = self.object:get_velocity()
	local ground = moveresult and moveresult.touching_ground
	local up = false
	self._offset_timer = (self._offset_timer or 0) - dtime
	if self._offset_timer <= 0 then
		self._offset_timer = 5
		self._offset = 0.5 + (math.random() + math.random() + math.random() - 1.5) * 2.4
	end
	local move = vector.zero()
	if t then
		local tp = t:get_pos()
		local d = vector.distance(pos, tp)
		self:yaw_to_pos(tp)
		up = eyes(t).y > mid.y + self._offset
		self._attack = (self._attack or 0) - dtime
		if d < 2 then
			move = vector.direction(pos, tp)
			if self._attack <= 0 then
				self._attack = 1
				self:set_animation("punch")
				t:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = 6}}, nil)
			end
		elseif self._seen < 0.3 then
			if self._attack <= 0 then
				self._step = (self._step or 0) + 1
				if self._step == 1 then
					self._attack = 3
					charged(self, true)
				elseif self._step <= 4 then
					self._attack = 0.3
				else
					self._attack, self._step = 5, 0
					charged(self, false)
				end
				if self._step > 1 then
					local spread = 2.297 * math.sqrt(d) * 0.5
					local from = vector.offset(pos, 0, 1.4, 0)
					local aim = vector.offset(tp, (math.random() - math.random()) * spread, 0.9,
						(math.random() - math.random()) * spread)
					shoot(N .. "small_fireball", self.object, from, aim)
				end
			end
		else
			move = vector.direction(pos, tp)
		end
	else
		if self._step and self._step > 0 then
			self._step = 0
			charged(self, false)
		end
		self._wander = (self._wander or 0) - dtime
		if self._wander <= 0 then
			self._wander = 3 + math.random() * 5
			self._heading = math.random(3) == 1 and math.random() * 2 * math.pi or nil
			if self._heading then
				self:set_yaw(self._heading, 6)
			end
		end
		if self._heading then
			move = vector.new(-math.sin(self._heading), 0, math.cos(self._heading)) * 0.4
		end
	end
	if up then
		v.y = 6 + (v.y - 6) * 0.7 ^ (dtime * 20)
	elseif not ground then
		v.y = math.max(v.y - 9.81 * dtime, -2.3)
	end
	v.x, v.z = move.x * 2.5, move.z * 2.5
	self.object:set_velocity(v)
	return false
end

-- The magma cube: 1, 2 or 4 a size (health its square, hits for size + 2), lit as fire is; moves only by hopping
-- (Minecraft's 0.42 + 0.1 a size up: 1.8, 2.5 and 4.2 nodes high), every 2 to 6 s, three times as often after
-- someone; one of 2 or 4 splits into 2 to 4 of half its size
local HOP = {[1] = 1.83, [2] = 2.52, [4] = 4.15}
local function size_up(self)
	local s = self._size or ({1, 2, 4})[math.random(3)]
	if not self._sized then
		self._size, self._sized, self.health = s, true, s * s
	end
	local w = 0.26 * s
	local box = {-w, 0, -w, w, 0.52 * s, w}
	self.object:set_properties({visual_size = {x = s, y = s, z = s}, collisionbox = box, selectionbox = box,
		hp_max = s * s})
	self.object:set_armor_groups({fleshy = 100 - ({[1] = 2, [2] = 12, [4] = 36})[s]})
	self.prop = self.object:get_properties()
	self.damage, self.reach, self.run_velocity, self.walk_velocity = s + 2, 0.6 * s + 0.6, 1 + s * 0.5, 0.5 + s * 0.25
	self.drops = s > 1 and {{name = N .. "magma_cream", chance = 4, min = 1, max = 1}} or {}
	self._goodluck_xp = s
	local small = s == 1 and "_small" or ""
	self.sounds = {damage = "goodluck_nether_magma_cube_hurt" .. small, death = "goodluck_nether_magma_cube_hurt" .. small,
		distance = 16}
end

local function hop(self, dtime, moveresult)
	local grounded = moveresult and moveresult.touching_ground
	if self._air then
		if grounded and self.object:get_velocity().y <= 0 then
			self._air = false
			self.object:set_velocity(vector.zero())
			mob_class.set_animation(self, "stand", true)
			self:mob_sound({name = "goodluck_nether_magma_cube_squish" .. (self._size == 1 and "_small" or ""), gain = 0.6})
		end
		return
	end
	self._hop = (self._hop or 0) - dtime
	if not grounded or self._hop > 0 or (self.state ~= "walk" and self.state ~= "attack") then
		return
	end
	self._hop = math.random(10, 29) * 4 / 20 / (self.state == "attack" and 3 or 1)
	self._air = true
	mob_class.set_animation(self, "jump", true)
	local yaw = self.object:get_yaw() + (self.rotate or 0)
	local g = math.abs(self.fall_speed or 9.81)
	self.object:set_velocity({x = -math.sin(yaw) * self.run_velocity, y = math.sqrt(2 * g * HOP[self._size or 1]),
		z = math.cos(yaw) * self.run_velocity})
	self:mob_sound({name = "goodluck_nether_magma_cube_jump", gain = 0.6})
end

-- The zombified piglin: 20 of health, a golden sword (8); left alone until one is hit by a player, then it and every
-- one within 35 (10 up or down) go after them for 20 to 39 s
local function anger(self, who)
	self._angry = core.get_gametime() + math.random(20, 39)
	self.passive = false
	self:do_attack(who, true)
end

local HUMANOID = {
	speed_normal = 1, speed_run = 1,
	stand_start = 0, stand_end = 1,
	walk_start = 1, walk_end = 2,
	run_start = 3, run_end = 3.5,
	punch_start = 6, punch_end = 6.5,
	die_start = 4, die_end = 5, die_loop = false,
}

mobs:register_mob(N .. "ghast", {
	type = "monster",
	description = S("Ghast"),
	attack_type = "dogfight",
	hp_min = 10, hp_max = 10,
	armor = 100,
	collisionbox = {-2, 0, -2, 2, 4, 2},
	visual = "mesh",
	mesh = "goodluck_models_ghast.glb",
	visual_size = {x = 4.5, y = 4.5, z = 4.5},
	textures = {{"goodluck_nether_ghast.png"}},
	sounds = {damage = "goodluck_nether_ghast_hurt", death = "goodluck_nether_ghast_death", distance = 80},
	fly = true, fly_in = {"air"},
	walk_velocity = 2, run_velocity = 2,
	view_range = 64,
	jump = false,
	fall_damage = false,
	fear_height = 0,
	water_damage = 0, lava_damage = 0, fire_damage = 0, light_damage = 0, suffocation = 0,
	drops = drops({name = N .. "ghast_tear", chance = 2, min = 1, max = 1},
		{name = gunpowder, chance = 1, min = 0, max = 2}),
	animation = {speed_normal = 1, stand_start = 0, stand_end = 1.047, walk_start = 0, walk_end = 1.047,
		die_start = 4, die_end = 5, die_loop = false},
	do_custom = ghast_step,
})

mobs:register_mob(N .. "blaze", {
	type = "monster",
	description = S("Blaze"),
	attack_type = "dogfight",
	hp_min = 20, hp_max = 20,
	armor = 76,
	collisionbox = {-0.3, 0, -0.3, 0.3, 1.8, 0.3},
	visual = "mesh",
	mesh = "goodluck_models_blaze.glb",
	textures = {{"goodluck_nether_blaze.png"}},
	glow = 15,
	sounds = {damage = "goodluck_nether_blaze_hurt", death = "goodluck_nether_blaze_death", distance = 16},
	fly = true, fly_in = {"air"},
	walk_velocity = 2.5, run_velocity = 2.5,
	view_range = 48,
	jump = false,
	fall_damage = false,
	fear_height = 0,
	water_damage = 2, lava_damage = 0, fire_damage = 0, light_damage = 0,
	drops = drops({name = N .. "blaze_rod", chance = 1, min = 0, max = 1}),
	animation = {speed_normal = 1, stand_start = 0, stand_end = 10, walk_start = 0, walk_end = 10,
		punch_start = 0, punch_end = 10, die_start = 11, die_end = 12, die_loop = false},
	after_activate = function(self)
		core.add_particlespawner({amount = 4, time = 0, attached = self.object,
			pos = {min = vector.new(-0.4, 0.2, -0.4), max = vector.new(0.4, 1.8, 0.4)},
			vel = {min = vector.new(0, 0.3, 0), max = vector.new(0, 0.8, 0)}, exptime = {min = 1, max = 2},
			size = {min = 3, max = 5}, texture = "tnt_smoke.png"})
		self._step, self._flames = 0, nil
	end,
	do_custom = blaze_step,
})

mobs:register_mob(N .. "magma_cube", {
	type = "monster",
	description = S("Magma Cube"),
	passive = false,
	attack_type = "dogfight",
	hp_min = 1, hp_max = 16,
	armor = 100,
	collisionbox = {-0.52, 0, -0.52, 0.52, 1.04, 0.52},
	visual = "mesh",
	mesh = "goodluck_models_magma_cube.glb",
	textures = {{"goodluck_nether_magma_cube.png"}},
	glow = 15,
	walk_velocity = 1, run_velocity = 2,
	view_range = 16,
	jump = false,
	floats = 1,
	fall_damage = false,
	fear_height = 8,
	water_damage = 0, lava_damage = 0, fire_damage = 0, light_damage = 0,
	animation = {speed_normal = 1, stand_start = 0, stand_end = 1, walk_start = 0, walk_end = 1, run_start = 0,
		run_end = 1, punch_start = 0, punch_end = 1, jump_start = 1, jump_end = 2, jump_loop = false,
		die_start = 4, die_end = 5, die_loop = false},
	after_activate = size_up,
	do_custom = function(self, dtime, moveresult)
		hop(self, dtime, moveresult)
	end,
	-- the halves come out where it was
	on_die = function(self, pos)
		local s = self._size or 1
		if s > 1 then
			for l = 0, math.random(2, 4) - 1 do
				core.add_entity(vector.offset(pos, (l % 2 - 0.5) * s / 4, 0.3, (math.floor(l / 2) - 0.5) * s / 4),
					self.name, core.serialize({_size = s / 2}))
			end
		end
		core.add_particlespawner({amount = 12, time = 0.2, pos = {min = vector.offset(pos, -0.3 * s, 0, -0.3 * s),
			max = vector.offset(pos, 0.3 * s, 0.5 * s, 0.3 * s)}, exptime = {min = 0.4, max = 0.8},
			size = {min = 2, max = 4}, texture = "tnt_smoke.png"})
	end,
})
-- on the ground it waits for its next hop, and its animation is the hop's while in the air
local magma = core.registered_entities[N .. "magma_cube"]
function magma.set_velocity(self, v)
	return mob_class.set_velocity(self, self._air and v or 0)
end
function magma.set_animation(self, anim, force)
	if not self._air or anim == "die" then
		return mob_class.set_animation(self, anim, force)
	end
end

mobs:register_mob(N .. "zombified_piglin", {
	type = "monster",
	description = S("Zombified Piglin"),
	passive = true,
	attack_type = "dogfight",
	pathfinding = 1,
	reach = 2,
	damage = 8,
	hp_min = 20, hp_max = 20,
	armor = 92,
	collisionbox = {-0.3, 0, -0.3, 0.3, 1.95, 0.3},
	visual = "mesh",
	mesh = "goodluck_models_zombified_piglin.glb",
	textures = {{"goodluck_nether_zombified_piglin.png", sword_gold}},
	use_texture_alpha = true,
	makes_footstep_sound = true,
	sounds = {damage = "goodluck_nether_zombified_piglin_hurt", death = "goodluck_nether_zombified_piglin_death",
		distance = 16},
	walk_velocity = 1, run_velocity = 2,
	view_range = 35,
	jump = true,
	floats = 1,
	fear_height = 4,
	water_damage = 0, lava_damage = 0, fire_damage = 0, light_damage = 0,
	drops = drops({name = flesh, chance = 1, min = 0, max = 1},
		{name = "goodluck_food:gold_nugget", chance = 1, min = 0, max = 1},
		{name = "default:gold_ingot", chance = 40, min = 1, max = 1},
		{name = sword_gold ~= "blank.png" and "default:sword_gold", chance = 12, min = 1, max = 1}),
	animation = HUMANOID,
	do_punch = function(self, hitter)
		if not hitter or not hitter:is_player() then
			return
		end
		local pos = self.object:get_pos()
		for _, obj in ipairs(core.get_objects_inside_radius(pos, 35)) do
			local ent = obj:get_luaentity()
			if ent and ent.name == self.name and ent.health > 0 and math.abs(obj:get_pos().y - pos.y) <= 10 then
				anger(ent, hitter)
			end
		end
		self:mob_sound({name = "goodluck_nether_zombified_piglin_angry", gain = 1})
	end,
	do_custom = function(self, dtime)
		ambient(self, dtime)
		if self._angry and core.get_gametime() > self._angry then
			self._angry, self.passive = nil, true
			self:stop_attack()
		end
	end,
})

-- The wither skeleton: 20 of health, 1.2 times the skeleton, a stone sword (8) and Wither for 10 s on whoever it
-- hits; fire can't hurt it
mobs:register_mob(N .. "wither_skeleton", {
	type = "monster",
	description = S("Wither Skeleton"),
	passive = false,
	attack_type = "dogfight",
	pathfinding = 1,
	reach = 2,
	damage = 8,
	hp_min = 20, hp_max = 20,
	armor = 100,
	collisionbox = {-0.35, 0, -0.35, 0.35, 2.4, 0.35},
	visual = "mesh",
	mesh = "goodluck_models_wither_skeleton.glb",
	visual_size = {x = 1.2, y = 1.2, z = 1.2},
	textures = {{"goodluck_nether_wither_skeleton.png", "default_tool_stonesword.png"}},
	use_texture_alpha = true,
	makes_footstep_sound = true,
	sounds = {damage = "goodluck_nether_wither_skeleton_hurt", death = "goodluck_nether_wither_skeleton_death",
		distance = 16},
	walk_velocity = 1, run_velocity = 2.5,
	view_range = 16,
	jump = true,
	floats = 1,
	fear_height = 4,
	water_damage = 0, lava_damage = 0, fire_damage = 0, light_damage = 0,
	drops = drops({name = "default:coal_lump", chance = 3, min = 1, max = 1},
		{name = bone, chance = 1, min = 0, max = 2},
		{name = N .. "wither_skeleton_skull", chance = 40, min = 1, max = 1},
		{name = "default:sword_stone", chance = 12, min = 1, max = 1}),
	animation = HUMANOID,
	do_custom = ambient,
})
core.register_on_punchplayer(function(player, hitter)
	local ent = hitter and hitter:get_luaentity()
	if ent and ent.name == N .. "wither_skeleton" and core.global_exists("goodluck_effects") then
		goodluck_effects.apply(player, "wither", 10, 1)
	end
end)

-- fire can't hurt them (the small fireball goes by them); Minecraft's experience for them
for name, xp in pairs({ghast = 5, blaze = 10, magma_cube = 1, zombified_piglin = 5, wither_skeleton = 5}) do
	local def = core.registered_entities[N .. name]
	def._fire_immune, def._goodluck_xp = true, xp
	mobs:register_egg(N .. name, def.description, "goodluck_nether_" .. name .. "_egg.png", 0)
end
if core.global_exists("goodluck_effects") then
	goodluck_effects.undead[N .. "zombified_piglin"], goodluck_effects.undead[N .. "wither_skeleton"] = true, true
end

AMBIENT[N .. "ghast"] = "goodluck_nether_ghast"
AMBIENT[N .. "blaze"] = "goodluck_nether_blaze"
AMBIENT[N .. "wither_skeleton"] = "goodluck_nether_wither_skeleton"
AMBIENT[N .. "zombified_piglin"] = function(self)
	return self._angry and "goodluck_nether_zombified_piglin_angry" or "goodluck_nether_zombified_piglin"
end

-- items
core.register_craftitem(N .. "blaze_rod", {
	description = S("Blaze Rod"),
	inventory_image = "goodluck_nether_blaze_rod.png",
})
core.register_craftitem(N .. "blaze_powder", {
	description = S("Blaze Powder"),
	inventory_image = "goodluck_nether_blaze_powder.png",
})
core.register_craftitem(N .. "ghast_tear", {
	description = S("Ghast Tear"),
	inventory_image = "goodluck_nether_ghast_tear.png",
})
core.register_craftitem(N .. "magma_cream", {
	description = S("Magma Cream"),
	inventory_image = "goodluck_nether_magma_cream.png",
})
core.register_craft({output = N .. "blaze_powder 2", recipe = {{N .. "blaze_rod"}}})
-- a rod burns 120 s in a furnace, as in Minecraft (12 items)
core.register_craft({type = "fuel", recipe = N .. "blaze_rod", burntime = 120})

-- the fire charge lights what flint and steel lights, with either button, and is used up
local flint = core.registered_items["fire:flint_and_steel"]
local function light(itemstack, user, pointed)
	if pointed.type ~= "node" or not user then
		return
	end
	local node = core.get_node(pointed.under)
	local def = core.registered_nodes[node.name]
	if def and def.on_rightclick and not user:get_player_control().sneak then
		return def.on_rightclick(pointed.under, node, user, itemstack, pointed)
	end
	flint.on_use(ItemStack("fire:flint_and_steel"), user, pointed)
	if not core.is_creative_enabled(user:get_player_name()) then
		itemstack:take_item()
	end
	return itemstack
end
core.register_craftitem(N .. "fire_charge", {
	description = S("Fire Charge"),
	inventory_image = "goodluck_nether_fire_charge.png",
	on_use = light,
	on_place = light,
})
if gunpowder then
	core.register_craft({type = "shapeless", output = N .. "fire_charge 3",
		recipe = {N .. "blaze_powder", "default:coal_lump", gunpowder}})
end

-- the wither skeleton's skull: its head, half a node, turned to whoever places it
local function face(x, y)
	return "goodluck_nether_wither_skeleton.png^[sheet:8x4:" .. x .. "," .. y
end
core.register_node(N .. "wither_skeleton_skull", {
	description = S("Wither Skeleton Skull"),
	drawtype = "nodebox",
	node_box = {type = "fixed", fixed = {-0.25, -0.5, -0.25, 0.25, 0, 0.25}},
	tiles = {face(1, 0), face(2, 0), face(2, 1), face(0, 1), face(3, 1), face(1, 1)},
	paramtype = "light",
	paramtype2 = "facedir",
	sunlight_propagates = true,
	groups = {oddly_breakable_by_hand = 2, cracky = 3},
	sounds = default.node_sound_stone_defaults(),
	on_place = core.rotate_node,
})

-- where they come out in the Nether: zombified piglins (in groups of up to 4) and magma cubes on any of its ground with
-- air over it, ghasts in the open (below), whatever the light; 8 monsters at most within 64 of the nearest player, of
-- them 5 zombified piglins, 1 magma cube and 2 ghasts, so that the piglins never take the ghasts' room
local GROUND = {RACK, N .. "soul_sand", N .. "quartz_ore", N .. "gold_ore", "default:gravel"}
local CAP, LIMIT = 8, {[N .. "ghast"] = 2, [N .. "magma_cube"] = 1, [N .. "zombified_piglin"] = 5}
local function crowded(pos, name)
	local player, near = nil, 128
	for _, p in ipairs(core.get_connected_players()) do
		local d = vector.distance(pos, p:get_pos())
		if d < near then
			player, near = p, d
		end
	end
	if not player then
		return true
	end
	local all, same = 0, 0
	for _, obj in ipairs(core.get_objects_inside_radius(player:get_pos(), 64)) do
		local ent = obj:get_luaentity()
		if ent and ent._cmi_is_mob and ent.type == "monster" then
			all = all + 1
			same = same + (ent.name == name and 1 or 0)
		end
	end
	return all >= CAP or same >= (LIMIT[name] or CAP)
end
R.spawns = {[N .. "zombified_piglin"] = crowded, [N .. "magma_cube"] = crowded}

local function stand(p)
	return core.get_node(p).name == "air" and core.get_node(vector.offset(p, 0, 1, 0)).name == "air" and
		(core.registered_nodes[core.get_node(vector.offset(p, 0, -1, 0)).name] or {}).walkable
end
local function group(self, pos)
	for _ = 1, math.random(1, 3) do
		local p = vector.offset(vector.round(pos), math.random(-2, 2), 0, math.random(-2, 2))
		if stand(p) and not crowded(p, self.name) then
			core.add_entity(p, self.name)
		end
	end
end

for name, def in pairs({zombified_piglin = {chance = 4000, count = 5, on_spawn = group},
		magma_cube = {chance = 60000, count = 1}}) do
	mobs:spawn({name = N .. name, nodes = GROUND, neighbors = {"air"}, min_light = 0, max_light = 15, interval = 30,
		chance = def.chance, active_object_count = def.count, min_height = R.ymin, max_height = R.ymax,
		on_spawn = def.on_spawn})
end

-- a ghast needs 5x5x5 of air, which a block of ground picked at random seldom has (1 in 280 in the realm's caves):
-- every 30 s, one time in 2, up to 8 spots in the open 24 to 48 away from a player in the Nether are tried instead
local spawning = core.settings:get_bool("mobs_spawn", true) and not core.settings:get_bool("only_peaceful_mobs")
local ghast_timer = 0
core.register_globalstep(function(dtime)
	ghast_timer = ghast_timer + dtime
	if ghast_timer < 30 or not spawning then
		return
	end
	ghast_timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		local pos = player:get_pos()
		if R.inside(pos) and math.random(2) == 1 and not crowded(pos, N .. "ghast") then
			for _ = 1, 8 do
				local a, r = math.random() * 2 * math.pi, 24 + math.random() * 24
				local p = vector.round(vector.offset(pos, math.cos(a) * r, math.random(-8, 12), math.sin(a) * r))
				p.y = math.max(R.sea + 3, math.min(R.ymax - 8, p.y))
				if #core.find_nodes_in_area(vector.offset(p, -2, 0, -2), vector.offset(p, 2, 4, 2), {"air"}) == 125 then
					core.add_entity(p, N .. "ghast")
					break
				end
			end
		end
	end
end)

-- a portal in the Overworld lets a zombified piglin out now and then, at its foot: Minecraft's 1 in 1000 for each of
-- its blocks each random tick (every 68 s), on Normal
core.register_abm({
	label = "Zombified piglins out of nether portals",
	nodenames = {PORTAL},
	interval = 68,
	chance = 1000,
	catch_up = false,
	action = function(pos)
		if R.inside(pos) then
			return
		end
		local p = vector.copy(pos)
		while core.get_node(vector.offset(p, 0, -1, 0)).name == PORTAL do
			p.y = p.y - 1
		end
		if not crowded(p, N .. "zombified_piglin") then
			core.add_entity(p, N .. "zombified_piglin")
		end
	end,
})
