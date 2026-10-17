-- Minecraft's classic monsters with art of our own: the zombie and the skeleton (3d_armor's character model), the
-- spider (mobs_monster's CC0 model) and, in the creeper's place, the bomb mushroom. They come out in the dark, on the
-- surface and in caves (mobs_monster's own spawn no more); the zombie and the skeleton burn in the sun
local S = core.get_translator("goodluck_monsters")
local MOD = "goodluck_monsters:"
local BLANK = "goodluck_monsters_blank.png"
local armor_model = core.get_modpath("3d_armor") ~= nil
local MESH = armor_model and "3d_armor_character.b3d" or "character.b3d"
local bows = core.get_modpath("x_bows") ~= nil
local tnt_mod = core.get_modpath("tnt") ~= nil

-- the given drops that exist (an optional mod's may not)
local function drops(...)
	local list = {}
	for i = 1, select("#", ...) do
		list[#list + 1] = select(i, ...) or nil
	end
	return list
end

-- skin, then 3d_armor's armor layer and the item in the right hand
local function skin(tex, wield)
	return armor_model and {tex, BLANK, wield or BLANK} or {tex}
end

-- the player's animations
local HUMANOID = {
	speed_normal = 30, speed_run = 30,
	stand_start = 0, stand_end = 79,
	walk_start = 168, walk_end = 187,
	run_start = 168, run_end = 187,
	punch_start = 189, punch_end = 198,
	shoot_start = 189, shoot_end = 198,
	die_start = 162, die_end = 166, die_speed = 15, die_loop = false,
}

-- burning in direct sunlight, 1 a second, in flames: mobs_redo's light damage reads the light at the feet, which on
-- ground below y = 0 rounds into the ground; the head's is read here. True when it died
local function burn(self, dtime)
	self._burn_timer = (self._burn_timer or 0) + dtime
	if self._burn_timer < 1 then
		return
	end
	self._burn_timer = 0
	local pos = self.object:get_pos()
	if pos and (core.get_natural_light(vector.offset(pos, 0, 1.5, 0)) or 0) >= 15 then
		self.health = self.health - 1
		core.add_particlespawner({
			amount = 6, time = 1, attached = self.object,
			minpos = {x = -0.3, y = 0, z = -0.3}, maxpos = {x = 0.3, y = 1.8, z = 0.3},
			minvel = {x = 0, y = 0.5, z = 0}, maxvel = {x = 0, y = 1.2, z = 0},
			minexptime = 0.4, maxexptime = 0.8, minsize = 2, maxsize = 4,
			texture = "fire_basic_flame.png", glow = 14,
		})
		return self:check_for_death({type = "light"})
	end
end

-- arms held out in front, on top of whatever the animation does
local function arms_out(self, on)
	if self._arms == on or not self.object.set_bone_override then
		return
	end
	self._arms = on
	local rot = on and {vec = vector.new(math.rad(90), 0, 0), absolute = false} or nil
	self.object:set_bone_override("Arm_Left", rot and {rotation = rot} or nil)
	self.object:set_bone_override("Arm_Right", rot and {rotation = rot} or nil)
end

mobs:register_mob(MOD .. "zombie", {
	type = "monster",
	description = S("Zombie"),
	passive = false,
	attack_type = "dogfight",
	pathfinding = 1,
	reach = 2,
	damage = 3,
	hp_min = 20, hp_max = 20,
	armor = 100,
	collisionbox = {-0.3, 0, -0.3, 0.3, 1.7, 0.3},
	visual = "mesh",
	mesh = MESH,
	textures = {skin("goodluck_monsters_zombie.png")},
	makes_footstep_sound = true,
	sounds = {random = "goodluck_monsters_zombie", damage = "goodluck_monsters_zombie_hurt",
		death = "goodluck_monsters_zombie_hurt"},
	walk_velocity = 1, run_velocity = 2,
	view_range = 16,
	jump = true,
	floats = 1,
	drops = drops(
		{name = MOD .. "rotten_flesh", chance = 1, min = 0, max = 2},
		{name = "default:steel_ingot", chance = 40, min = 1, max = 1}
	),
	water_damage = 0, lava_damage = 4,
	fear_height = 4,
	animation = HUMANOID,
	after_activate = function(self)
		self._arms = nil
		arms_out(self, true)
	end,
	do_custom = function(self, dtime)
		if burn(self, dtime) then
			return false
		end
	end,
})

mobs:register_mob(MOD .. "skeleton", {
	type = "monster",
	description = S("Skeleton"),
	passive = false,
	attack_type = "shoot",
	arrow = MOD .. "arrow",
	shoot_interval = 2,
	shoot_offset = 0.5,
	reach = 2,
	damage = 2,
	hp_min = 20, hp_max = 20,
	armor = 100,
	collisionbox = {-0.3, 0, -0.3, 0.3, 1.7, 0.3},
	visual = "mesh",
	mesh = MESH,
	textures = {skin("goodluck_monsters_skeleton.png", bows and "x_bows_bow_wood.png")},
	use_texture_alpha = true,
	makes_footstep_sound = true,
	sounds = {random = "goodluck_monsters_skeleton", damage = "goodluck_monsters_skeleton",
		death = "goodluck_monsters_skeleton", shoot_attack = bows and "x_bows_bow_shoot" or nil},
	walk_velocity = 1, run_velocity = 2,
	view_range = 16,
	jump = true,
	floats = 1,
	drops = drops(
		{name = MOD .. "bone", chance = 1, min = 0, max = 2},
		bows and {name = "x_bows:arrow_wood", chance = 1, min = 0, max = 2},
		bows and {name = "x_bows:bow_wood", chance = 12, min = 1, max = 1}
	),
	water_damage = 0, lava_damage = 4,
	fear_height = 4,
	animation = HUMANOID,
	after_activate = function(self)
		self._arms = nil
	end,
	do_custom = function(self, dtime)
		if burn(self, dtime) then
			return false
		end
		-- the bow up while it has someone in its sights
		arms_out(self, self.state == "attack")
	end,
})

mobs:register_arrow(MOD .. "arrow", {
	visual = bows and "mesh" or "sprite",
	mesh = bows and "x_bows_arrow.b3d" or nil,
	textures = {bows and "x_bows_arrow_mesh.png" or "goodluck_monsters_bone.png"},
	visual_size = {x = 1, y = 1},
	velocity = 18,
	lifetime = 3,
	do_custom = function(self)
		local v = self.object:get_velocity()
		if v and (v.x ~= 0 or v.z ~= 0) then
			self.object:set_rotation({x = math.atan2(v.y, math.hypot(v.x, v.z)), y = core.dir_to_yaw(v), z = 0})
		end
	end,
	hit_player = function(self, player)
		player:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = 3}}, nil)
	end,
	hit_mob = function(self, mob)
		mob:punch(self.object, 1.0, {full_punch_interval = 1.0, damage_groups = {fleshy = 3}}, nil)
	end,
	hit_node = function() end,
})

mobs:register_mob(MOD .. "spider", {
	type = "monster",
	description = S("Spider"),
	passive = false,
	attack_type = "dogfight",
	reach = 2,
	damage = 2,
	hp_min = 16, hp_max = 16,
	armor = 100,
	collisionbox = {-0.7, -0.5, -0.7, 0.7, 0, 0.7},
	visual = "mesh",
	mesh = "mobs_spider.b3d",
	textures = {{"goodluck_monsters_spider.png"}},
	makes_footstep_sound = false,
	sounds = {random = "mobs_spider", attack = "mobs_spider"},
	walk_velocity = 1.5, run_velocity = 2.5,
	view_range = 16,
	jump = true,
	jump_height = 2,
	floats = 0,
	drops = drops({name = "farming:string", chance = 1, min = 0, max = 2}),
	water_damage = 0, lava_damage = 5,
	light_damage = 0,
	fall_damage = false,
	fear_height = 8,
	animation = {
		speed_normal = 15,
		stand_start = 0, stand_end = 0,
		walk_start = 1, walk_end = 21,
		run_start = 1, run_end = 21, run_speed = 30,
		punch_start = 25, punch_end = 45, punch_speed = 30,
	},
	-- as in Minecraft, it leaves you be in the light unless you hit it
	do_punch = function(self)
		self._angry = true
		self.passive = false
	end,
	do_custom = function(self)
		local pos = self.object:get_pos()
		self.passive = not self._angry and pos and (core.get_node_light(pos) or 0) >= 12 or false
	end,
})

-- the bomb mushroom swells and puffs spores while its fuse burns, and walks its legs by bone overrides (its model
-- has bones and no keyframes): a pair forward and the other back, swapped every STEP seconds, eased by the client
local SWELL = 0.3
local STEP, SWING = 0.3, 0.45
local LEGS = {leg_fl = 1, leg_br = 1, leg_fr = -1, leg_bl = -1}

local function walk_legs(self, dtime)
	local v = self.object:get_velocity()
	local moving = v and v.x * v.x + v.z * v.z > 0.04
	self._leg_timer = (self._leg_timer or 0) + dtime
	if moving and self._leg_timer < STEP or not moving and not self._leg_phase then
		return
	end
	self._leg_timer = 0
	self._leg_phase = moving and -(self._leg_phase or 1) or nil
	for bone, side in pairs(LEGS) do
		self.object:set_bone_override(bone, {rotation = {vec = vector.new(SWING * side * (self._leg_phase or 0), 0, 0),
			absolute = true, interpolation = STEP}})
	end
end

mobs:register_mob(MOD .. "mushroom", {
	type = "monster",
	description = S("Bomb Mushroom"),
	passive = false,
	attack_type = "explode",
	explosion_radius = 3,
	explosion_damage_radius = 6,
	explosion_timer = 1.5,
	allow_fuse_reset = true,
	stop_to_explode = true,
	reach = 3,
	damage = 0,
	hp_min = 20, hp_max = 20,
	armor = 100,
	collisionbox = {-0.45, 0, -0.45, 0.45, 1.5, 0.45},
	visual = "mesh",
	mesh = "goodluck_monsters_mushroom.b3d",
	rotate = 180,
	textures = {{"goodluck_monsters_mushroom.png"}},
	makes_footstep_sound = true,
	sounds = {fuse = "goodluck_monsters_mushroom_fuse", explode = "tnt_explode"},
	walk_velocity = 1, run_velocity = 2,
	view_range = 16,
	jump = true,
	floats = 1,
	drops = drops(
		tnt_mod and {name = "tnt:gunpowder", chance = 1, min = 0, max = 2},
		{name = "flowers:mushroom_red", chance = 2, min = 1, max = 1}
	),
	water_damage = 0, lava_damage = 4,
	light_damage = 0,
	fear_height = 4,
	do_custom = function(self, dtime)
		walk_legs(self, dtime)
		local k = self.v_start and 1 + SWELL * math.min(1, (self.explode_timer or 0) / self.explosion_timer) or 1
		if math.abs(k - (self._swell or 1)) < 0.03 then
			return
		end
		if self.v_start and (self._swell or 1) == 1 then
			core.add_particlespawner({
				amount = 30, time = 1.5, attached = self.object,
				minpos = {x = -0.6, y = 1, z = -0.6}, maxpos = {x = 0.6, y = 1.6, z = 0.6},
				minvel = {x = -0.4, y = 0.2, z = -0.4}, maxvel = {x = 0.4, y = 0.8, z = 0.4},
				minexptime = 0.6, maxexptime = 1.2, minsize = 1, maxsize = 2,
				texture = "goodluck_monsters_spore.png",
			})
		end
		self._swell = k
		self.object:set_properties({visual_size = {x = k, y = k}})
	end,
})

-- drops
core.register_craftitem(MOD .. "rotten_flesh", {
	description = S("Rotten Flesh"),
	inventory_image = "goodluck_monsters_rotten_flesh.png",
	groups = {food = 1},
	-- 4 of hunger, and as Minecraft's Hunger effect, 4 times in 5 two of them go again soon after
	on_use = function(itemstack, user, pointed_thing)
		local left = core.item_eat(4)(itemstack, user, pointed_thing)
		if user and math.random(5) <= 4 and core.global_exists("stamina") and stamina.change_saturation then
			local name = user:get_player_name()
			for i = 1, 2 do
				core.after(3 * i, function()
					local player = core.get_player_by_name(name)
					if player then
						stamina.change_saturation(player, -1)
					end
				end)
			end
		end
		return left
	end,
})

core.register_craftitem(MOD .. "bone", {
	description = S("Bone"),
	inventory_image = "goodluck_monsters_bone.png",
	groups = {bone = 1},
})
if core.get_modpath("dye") then
	core.register_craft({output = "dye:white 3", recipe = {{MOD .. "bone"}}})
end

for _, name in ipairs({"zombie", "skeleton", "spider", "mushroom"}) do
	mobs:register_egg(MOD .. name, core.registered_entities[MOD .. name].description,
		"goodluck_monsters_" .. name .. "_egg.png", 0)
end

-- in the dark on the ground, above or below it, as in Minecraft; "<mob name> = chance,count" in the settings tunes
-- each, and goodluck_mobs caps them all together
local GROUND = {"group:soil", "group:sand", "group:stone", "default:gravel", "default:snow", "default:snowblock",
	"default:permafrost", "default:permafrost_with_stones", "default:permafrost_with_moss", "default:dry_dirt",
	"default:dry_dirt_with_dry_grass"}
for _, name in ipairs({"zombie", "skeleton", "spider", "mushroom"}) do
	mobs:spawn({
		name = MOD .. name,
		nodes = GROUND,
		neighbors = {"air"},
		max_light = 7,
		interval = 30,
		chance = 6000,
		active_object_count = 3,
		min_height = -31000,
		max_height = 31000,
	})
end

-- mobs_monster's own monsters stay registered (its spawn.lua is empty), their eggs leave the creative inventory
core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_items) do
		if name:find("^mobs_monster:") and (def.groups or {}).spawn_egg then
			local groups = table.copy(def.groups)
			groups.not_in_creative_inventory = 1
			core.override_item(name, {groups = groups})
		end
	end
end)
