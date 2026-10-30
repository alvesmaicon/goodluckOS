-- Minecraft's witch (26.x): she keeps 10 nodes from whoever she has in her sights and throws a splash potion every
-- 3 s (Slowness at 8 or more away, Poison on someone with 8 of health or more, Weakness now and then up close,
-- else Harming), and drinks one in 1.6 s, slower meanwhile, when she needs it: Water Breathing under water, Fire
-- Resistance on fire, Healing when hurt, Swiftness after someone 11 away. 85 % of magic misses her, her own
-- potions all of it. She drops redstone, 1 to 3 picks of glowstone dust, sugar, spider eyes, bottles, gunpowder
-- and sticks, and a quarter of the time the potion she was drinking (as on Bedrock). goodluck_swamp's huts keep one
local S = core.get_translator("goodluck_monsters")
local NAME = "goodluck_monsters:witch"
local mob_class = mobs.mob_class
local WALK, RUN = 1, 2
local DRINK, LASTS = 1.6, 180
local RANGE, THROW = 10, 3

local function chance(p, dtime)
	-- a chance Minecraft rolls each tick, over dtime
	return math.random() < 1 - (1 - p) ^ (dtime * 20)
end

local function eyes(obj)
	local p = obj:get_pos()
	return p and vector.offset(p, 0, obj:is_player() and obj:get_properties().eye_height or 1.5, 0)
end

local function has(obj, effect)
	return obj:is_player() and core.global_exists("goodluck_effects") and goodluck_effects.get(obj, effect) ~= nil
end

local function in_group(pos, group)
	return core.get_item_group(core.get_node(pos).name, group) > 0
end

-- the potion she drinks now: the nose up with it, slower; done, it works on her
local function sip(self, id)
	self._drinking, self._drink_left = id, DRINK
	self:mob_sound({name = "goodluck_monsters_witch_drink", gain = 0.8})
	local potions = core.global_exists("goodluck_potions") and goodluck_potions
	self.object:set_properties({textures = {self.base_texture[1], potions and potions.image(id) or "blank.png"}})
	self:set_animation(self._anim or "stand", true)
end

local function drunk(self)
	local id = self._drinking
	self._drinking = nil
	self.object:set_properties({textures = {self.base_texture[1], "blank.png"}})
	self:set_animation(self._anim or "stand", true)
	if id == "healing" then
		if core.global_exists("goodluck_potions") then
			goodluck_potions.apply(self.object, id, 1)
		end
	else
		self._fx = self._fx or {}
		self._fx[id] = core.get_gametime() + LASTS
	end
end

local function active(self, id)
	return self._fx and (self._fx[id] or 0) > core.get_gametime()
end

-- Minecraft's picks, a tick at a time: the first that holds
local function want(self, dtime)
	local pos = self.object:get_pos()
	if chance(0.15, dtime) and in_group(vector.offset(pos, 0, 1.6, 0), "water") and not active(self, "water_breathing")
	then
		return "water_breathing"
	elseif chance(0.15, dtime) and (in_group(pos, "fire") or in_group(pos, "lava") or (self._hot or 0) > 0) and
			not active(self, "fire_resistance") then
		return "fire_resistance"
	elseif chance(0.05, dtime) and self.health < self.prop.hp_max then
		return "healing"
	elseif chance(0.5, dtime) and self.attack and self.attack:get_pos() and not active(self, "swiftness") and
			vector.distance(pos, self.attack:get_pos()) > 11 then
		return "swiftness"
	end
end

-- the splash potion for her target, thrown from her eyes at it, a little above to make up for the fall
local function throw(self, target)
	if not core.global_exists("goodluck_potions") then
		return
	end
	local pos, tp = self.object:get_pos(), target:get_pos()
	local v = target:get_velocity() or vector.zero()
	local d = vector.new(tp.x + v.x / 20 - pos.x, eyes(target).y - 1.1 - pos.y, tp.z + v.z / 20 - pos.z)
	local g = math.sqrt(d.x * d.x + d.z * d.z)
	local id = "harming"
	if g >= 8 and not has(target, "slowness") then
		id = "slowness"
	elseif target:get_hp() >= 8 and not has(target, "poison") then
		id = "poison"
	elseif g <= 3 and not has(target, "weakness") and math.random() < 0.25 then
		id = "weakness"
	end
	d.y = d.y + g * 0.2
	-- Minecraft's spread: 0.0075 times 8 of a gaussian on each axis of the direction
	local function wobble()
		return (math.random() + math.random() + math.random() - 1.5) * 2 * 0.06
	end
	local dir = vector.normalize(d)
	dir = vector.add(dir, vector.new(wobble(), wobble(), wobble()))
	local speed = g <= 2 and 9 or 15
	goodluck_potions.launch(vector.offset(pos, 0, 1.55, 0), "goodluck_potions:splash_" .. id,
		vector.multiply(vector.normalize(dir), speed), self.object)
	self:mob_sound({name = "goodluck_monsters_witch_throw", gain = 0.8})
end

-- her own way after someone: closer while over 10 away or not seen for a quarter of a second, a potion every 3 s
-- when she sees them; she forgets them 3 s out of sight or past twice her view. She looks and decides 4 times a
-- second (dt: the time since)
local function attack(self, dt)
	local t = self.attack
	local pos = self.object:get_pos()
	local tp = t and t:get_pos()
	if not tp or t:get_hp() <= 0 or vector.distance(pos, tp) > self.view_range * 2 then
		self:stop_attack()
		return
	end
	local see = self:line_of_sight(vector.offset(pos, 0, 1.55, 0), eyes(t))
	self._see = see
	self._seen = see and (self._seen or 0) + dt or 0
	self._lost = see and 0 or (self._lost or 0) + dt
	if self._lost > 3 then
		self:stop_attack()
		return
	end
	self:yaw_to_pos(tp)
	if vector.distance(pos, tp) <= RANGE and self._seen >= 0.25 then
		self:set_velocity(0)
		self:set_animation("stand")
	else
		self:set_velocity(self.run_velocity)
		self:set_animation("run")
	end
end

-- now and then a puff of her purple sparks, as Minecraft's entity event 15
local function sparks(self, dt)
	if chance(0.00075, dt) then
		local p = self.object:get_pos()
		core.add_particlespawner({amount = math.random(10, 35), time = 0.2,
			pos = {min = vector.offset(p, -0.3, 2.2, -0.3), max = vector.offset(p, 0.3, 2.7, 0.3)},
			vel = {min = vector.new(-0.3, 0.3, -0.3), max = vector.new(0.3, 1, 0.3)}, exptime = {min = 0.5, max = 1},
			size = {min = 1, max = 2}, glow = 10, texture = "goodluck_effects_particle.png^[multiply:#b030c8"})
	end
end

local function think(self, dt)
	self._hot = math.max(0, (self._hot or 0) - dt)
	if not self._drinking then
		local id = want(self, dt)
		if id then
			sip(self, id)
		end
	end
	local k = (self._drinking and 0.75 or 1) * (active(self, "swiftness") and 1.2 or 1)
	self.walk_velocity, self.run_velocity = WALK * k, RUN * k
	local proof = active(self, "fire_resistance")
	self.fire_damage, self.lava_damage = proof and 0 or 1, proof and 0 or 4
	sparks(self, dt)
	self._ambient = (self._ambient or math.random() * 6) - dt
	if self._ambient <= 0 then
		self._ambient = 4 + math.random() * 6
		self:mob_sound({name = "goodluck_monsters_witch", gain = 0.4})
	end
	if self.state == "attack" and self.attack then
		attack(self, dt)
	end
end

local function step(self, dtime)
	if self._drinking then
		self._drink_left = self._drink_left - dtime
		if self._drink_left <= 0 then
			drunk(self)
		end
	end
	self._think = (self._think or math.random() * 0.25) + dtime
	if self._think >= 0.25 then
		think(self, self._think)
		self._think = 0
	end
	if self.state == "attack" and self.attack then
		self._throw = (self._throw or THROW) - dtime
		if self._throw <= 0 then
			self._throw = THROW
			if self._see and not self._drinking then
				throw(self, self.attack)
			end
		end
		return false
	end
end

-- drinking, her stand and walk are the ones with the nose up
local function set_animation(self, anim, force)
	if anim ~= "die" then
		self._anim = anim
		if self._drinking then
			anim = (anim == "walk" or anim == "run") and "drink_walk" or "drink_stand"
		end
	end
	return mob_class.set_animation(self, anim, force)
end

local LOOT = {{"goodluck_nether:glowstone_dust", 1}, {"goodluck_food:sugar", 1}, {"goodluck_monsters:spider_eye", 1},
	{"vessels:glass_bottle", 1}, {"tnt:gunpowder", 1}, {"default:stick", 2}}

local function loot(self)
	local list = {}
	local function add(name, n)
		if n > 0 and core.registered_items[name] then
			list[#list + 1] = {name = name, chance = 1, min = n, max = n}
		end
	end
	add("goodluck_redstone:redstone", math.random(4, 8))
	for _ = 1, math.random(1, 3) do
		local r = math.random(1, 7)
		for _, e in ipairs(LOOT) do
			r = r - e[2]
			if r <= 0 then
				add(e[1], math.random(0, 2))
				break
			end
		end
	end
	if self._drinking and math.random(4) == 1 then
		add("goodluck_potions:" .. self._drinking, 1)
	end
	return list
end

mobs:register_mob(NAME, {
	type = "monster",
	description = S("Witch"),
	passive = false,
	attack_type = "shoot",
	arrow = "goodluck_monsters:none",
	hp_min = 26, hp_max = 26,
	armor = 100,
	collisionbox = {-0.3, 0, -0.3, 0.3, 1.95, 0.3},
	visual = "mesh",
	mesh = "goodluck_models_witch.glb",
	textures = {{"goodluck_monsters_witch.png", "blank.png"}},
	use_texture_alpha = true,
	makes_footstep_sound = true,
	sounds = {damage = "goodluck_monsters_witch_hurt", death = "goodluck_monsters_witch_death", distance = 16},
	walk_velocity = WALK, run_velocity = RUN,
	view_range = 16,
	jump = true,
	floats = 1,
	water_damage = 0, lava_damage = 4, fire_damage = 1,
	light_damage = 0,
	fear_height = 4,
	animation = {
		speed_normal = 1, speed_run = 1,
		stand_start = 0, stand_end = 1,
		walk_start = 1, walk_end = 2,
		run_start = 3, run_end = 3.5,
		die_start = 4, die_end = 5, die_loop = false,
		drink_stand_start = 6, drink_stand_end = 6.1,
		drink_walk_start = 7, drink_walk_end = 8,
	},
	after_activate = function(self)
		self.set_animation = set_animation
		self.drops = function()
			return loot(self)
		end
		self._magic_resist = 0.15
		if #self.base_texture ~= 2 then
			self.base_texture = {"goodluck_monsters_witch.png", "blank.png"}
		end
		self.object:set_properties({textures = {self.base_texture[1],
			self._drinking and core.global_exists("goodluck_potions") and goodluck_potions.image(self._drinking) or
			"blank.png"}})
		-- a hut's witch stays (goodluck_swamp)
		if self._hut then
			self.lifetimer = 20000
			self.object:set_properties({static_save = true})
		end
	end,
	-- a fireball's hit sets her on fire as the fire she stands in does
	do_punch = function(self, hitter)
		local ent = hitter and hitter:get_luaentity()
		if ent and ent._fire then
			self._hot = 1
		end
	end,
	do_custom = step,
})
