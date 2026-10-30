-- The enderman and the silverfish as Minecraft (26.x) has them, in goodluck_models' meshes. The enderman minds its
-- own business until a player looks it in the face (or hits it): then it screams, and goes after them for 20 to 39 s,
-- teleporting away when stared at close and back when they get far. It dodges whatever is thrown or shot at it,
-- water and the sun drive it off, and it picks up blocks and puts them down elsewhere. The silverfish is small and
-- quick and comes out of the strongholds' spawners
local S = core.get_translator("goodluck_end")
local E = goodluck_end
local N = "goodluck_end:"
local TICK = 0.05

local function creative(obj)
	return obj:is_player() and core.is_creative_enabled(obj:get_player_name())
end

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

-- room for an enderman (3 high) standing at p, on ground that is not water, Minecraft's randomTeleport: from the
-- spot picked it drops to the first block that holds it
local function landing(p)
	p = vector.round(p)
	for _ = 1, 64 do
		local below = core.get_node(vector.offset(p, 0, -1, 0)).name
		if below == "ignore" then
			return
		end
		local def = core.registered_nodes[below]
		if def and def.walkable then
			if (def.groups or {}).water then
				return
			end
			for y = 0, 2 do
				local n = core.registered_nodes[core.get_node(vector.offset(p, 0, y, 0)).name]
				if not n or n.walkable or n.liquidtype ~= "none" then
					return
				end
			end
			return p
		end
		p.y = p.y - 1
	end
end

local function teleport_to(self, x, y, z)
	local from = self.object:get_pos()
	local p = landing({x = x, y = y, z = z})
	if not p then
		return false
	end
	E.specks(from, 32, 0.4, 2.9)
	self.object:set_pos(p)
	E.specks(p, 32, 0.4, 2.9)
	core.sound_play("goodluck_end_teleport", {pos = from, gain = 1, max_hear_distance = 16}, true)
	core.sound_play("goodluck_end_teleport", {pos = p, gain = 1, max_hear_distance = 16}, true)
	return true
end

-- anywhere within 32 across and up or down
local function teleport(self)
	local p = self.object:get_pos()
	return teleport_to(self, p.x + (math.random() - 0.5) * 64, p.y + math.random(0, 63) - 32,
		p.z + (math.random() - 0.5) * 64)
end

local function keep_teleporting(self)
	for _ = 1, 64 do
		if teleport(self) then
			return true
		end
	end
end

-- 16 toward who it is after, give or take
local function teleport_toward(self, obj)
	local p, t = self.object:get_pos(), obj:get_pos()
	local d = vector.normalize(vector.subtract(vector.offset(p, 0, 1.45, 0), vector.offset(t, 0, 1.5, 0)))
	return teleport_to(self, p.x + (math.random() - 0.5) * 8 - d.x * 16, p.y + math.random(0, 15) - 8 - d.y * 16,
		p.z + (math.random() - 0.5) * 8 - d.z * 16)
end

-- a player looking it in the face: their view within 0.025 (less, further away) of its eyes, nothing in between
local function stared_by(self, player)
	local eye = vector.offset(self.object:get_pos(), 0, 2.55, 0)
	local from = vector.offset(player:get_pos(), 0, player:get_properties().eye_height, 0)
	local to = vector.subtract(eye, from)
	local d = vector.length(to)
	if d > 64 or d < 0.1 then
		return false
	end
	return vector.dot(player:get_look_dir(), vector.divide(to, d)) > 1 - 0.025 / d and
		core.line_of_sight(from, eye)
end

local function anger(self, who)
	if not self._angry then
		self:mob_sound({name = "goodluck_end_enderman_scream", gain = 1})
	end
	self._angry = core.get_gametime() + math.random(20, 39)
	self._target_time = core.get_gametime()
	self.passive = false
	self:do_attack(who, true)
end

local function calm(self)
	self._angry, self.passive = nil, true
	self:stop_attack()
end

-- what it picks up: Minecraft's enderman_holdable, in this game's blocks (its small flowers, dirts and grasses, sand,
-- gravel, mushrooms, TNT, cactus, clay, pumpkins and melons, moss)
local HOLDABLE = {}
for _, name in ipairs({"default:dirt", "default:dirt_with_grass", "default:dirt_with_dry_grass",
		"default:dirt_with_snow", "default:dirt_with_rainforest_litter", "default:dirt_with_coniferous_litter",
		"default:dry_dirt", "default:dry_dirt_with_dry_grass", "default:moss", "default:sand", "default:desert_sand",
		"default:silver_sand", "default:gravel", "default:cactus", "default:clay", "flowers:mushroom_brown",
		"flowers:mushroom_red", "tnt:tnt", "goodluck_food:pumpkin", "goodluck_food:carved_pumpkin",
		"goodluck_food:melon", "farming:soil", "farming:soil_wet"}) do
	HOLDABLE[name] = true
end
core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_nodes) do
		if (def.groups or {}).flower and def.drawtype == "plantlike" then
			HOLDABLE[name] = true
		end
	end
end)

-- the block in its hands: the node's own image, half a node, held ahead at its belly, tilted and turned as Minecraft
-- holds it (on the body's bone, which turns with what is drawn)
core.register_entity(N .. "carried", {
	initial_properties = {physical = false, pointable = false, static_save = false, visual = "item",
		visual_size = {x = 0.25, y = 0.25}},
	on_activate = function(self)
		core.after(0, function()
			if self.object:get_pos() and not self.object:get_attach() then
				self.object:remove()
			end
		end)
	end,
})

local function show_carried(self)
	if self._carry_obj and self._carry_obj:get_pos() then
		self._carry_obj:remove()
	end
	self._carry_obj = nil
	local arms = self._carried and {rotation = {vec = vector.new(0.5, 0, 0), absolute = false}} or nil
	if self.object.set_bone_override then
		self.object:set_bone_override("right_arm", arms)
		self.object:set_bone_override("left_arm", arms)
	end
	if not self._carried then
		return
	end
	local obj = core.add_entity(self.object:get_pos(), N .. "carried")
	if obj then
		obj:set_properties({wield_item = self._carried})
		obj:set_attach(self.object, "body", {x = 0, y = -15, z = 6}, {x = 20, y = 45, z = 0})
		self._carry_obj = obj
	end
end

-- 2 tries a second at a block 2 about and up to 3 up that it can see; 1 in 50 a second it puts it down on top of a
-- whole block next to it, where nothing stands
local function take(self)
	local p = self.object:get_pos()
	local x, y, z = math.floor(p.x - 2 + math.random() * 4), math.floor(p.y + math.random() * 3),
		math.floor(p.z - 2 + math.random() * 4)
	local at = {x = x, y = y, z = z}
	local node = core.get_node(at)
	if not HOLDABLE[node.name] or core.is_protected(at, "") then
		return
	end
	local from = {x = math.floor(p.x) + 0.5, y = y + 0.5, z = math.floor(p.z) + 0.5}
	for hit in core.raycast(from, {x = x + 0.5, y = y + 0.5, z = z + 0.5}, false, false) do
		if hit.type == "node" then
			if not vector.equals(hit.under, at) then
				return
			end
			break
		end
	end
	core.remove_node(at)
	core.check_for_falling(at)
	self._carried = node.name
	show_carried(self)
end

local function put(self)
	local p = self.object:get_pos()
	local at = {x = math.floor(p.x - 1 + math.random() * 2), y = math.floor(p.y + math.random() * 2),
		z = math.floor(p.z - 1 + math.random() * 2)}
	local below = core.registered_nodes[core.get_node(vector.offset(at, 0, -1, 0)).name]
	if core.get_node(at).name ~= "air" or not below or not below.walkable or below.drawtype ~= "normal" or
			core.get_node(vector.offset(at, 0, -1, 0)).name:find("bedrock") or core.is_protected(at, "") or
			#core.get_objects_in_area(at, vector.offset(at, 1, 1, 1)) > 0 then
		return
	end
	core.set_node(at, {name = self._carried})
	self._carried = nil
	show_carried(self)
end

local function wet(self)
	local p = self.object:get_pos()
	for _, y in ipairs({0.2, 1.4}) do
		local def = core.registered_nodes[core.get_node(vector.offset(p, 0, y, 0)).name]
		if def and (def.groups or {}).water then
			return true
		end
	end
end

local function enderman_step(self, dtime)
	ambient(self, dtime)
	self._t = (self._t or 0) + dtime
	if self._t < 0.25 then
		return
	end
	local step = self._t
	self._t = 0
	local now = core.get_gametime()
	local pos = self.object:get_pos()
	local target = self.attack
	if self._angry and (now > self._angry or not target or not target:get_pos()) then
		calm(self)
		target = nil
	end
	if target and target:is_player() then
		local d = vector.distance(pos, target:get_pos())
		-- stared at close, it goes; far from them for 1.5 s, it comes
		if stared_by(self, target) and d < 4 then
			teleport(self)
			self._far = 0
		elseif d > 16 then
			self._far = (self._far or 0) + step
			if self._far >= 1.5 and teleport_toward(self, target) then
				self._far = 0
			end
		end
	else
		-- a player that looks it in the face for a quarter of a second sets it off
		for _, player in ipairs(core.get_connected_players()) do
			if player:get_hp() > 0 and not creative(player) and stared_by(self, player) then
				local name = player:get_player_name()
				self._stare = self._stare or {}
				self._stare[name] = (self._stare[name] or 0) + step
				if self._stare[name] >= 0.25 then
					self._stare = nil
					core.sound_play("goodluck_end_enderman_stare", {to_player = name, gain = 1}, true)
					anger(self, player)
				end
				break
			end
		end
	end
	-- water hurts it (1 every half second) and sends it off 9 times in 10
	self._wet = (self._wet or 0) + step
	if self._wet >= 0.5 then
		self._wet = 0
		if wet(self) then
			self.health = self.health - 1
			if self:check_for_death({type = "environment", pos = pos}) then
				return false
			end
			if math.random(10) > 1 then
				keep_teleporting(self)
			end
		end
	end
	-- in the sun by day, after 30 s with its target, it gives up and goes (Minecraft's (light - 0.4) * 2 / 30 a tick)
	local tod = core.get_timeofday()
	local light = core.get_natural_light(vector.offset(pos, 0, 2.6, 0))
	if tod > 0.24 and tod < 0.76 and light and light >= 15 and now - (self._target_time or 0) >= 30 then
		local b = core.get_node_light(vector.offset(pos, 0, 2.6, 0)) / 15
		if b > 0.5 and math.random() < 1 - (1 - (b - 0.4) * 2 / 30) ^ (step / TICK) then
			if self._angry then
				calm(self)
			end
			teleport(self)
		end
	end
	-- its blocks
	if not self._carried then
		self._take = (self._take or 0) + step
		if self._take >= 0.5 then
			self._take = 0
			take(self)
		end
	elseif math.random() < step / 50 then
		put(self)
	end
end

mobs:register_mob(N .. "enderman", {
	type = "monster",
	description = S("Enderman"),
	passive = true,
	attack_type = "dogfight",
	pathfinding = 1,
	reach = 2,
	damage = 7,
	hp_min = 40, hp_max = 40,
	armor = 100,
	collisionbox = {-0.3, 0, -0.3, 0.3, 2.9, 0.3},
	visual = "mesh",
	mesh = "goodluck_models_enderman.glb",
	textures = {{"goodluck_end_enderman.png^goodluck_end_enderman_eyes.png"}},
	makes_footstep_sound = true,
	stepheight = 1.1,
	sounds = {damage = "goodluck_end_enderman_hurt", death = "goodluck_end_enderman_death", distance = 16},
	walk_velocity = 1.3, run_velocity = 3.5,
	view_range = 64,
	jump = true,
	floats = 0,
	fear_height = 4,
	water_damage = 0, lava_damage = 4, light_damage = 0,
	drops = {{name = N .. "ender_pearl", chance = 1, min = 0, max = 1}},
	animation = {speed_normal = 1, speed_run = 1, stand_start = 0, stand_end = 1, walk_start = 1, walk_end = 2,
		run_start = 3, run_end = 3.5, punch_start = 6, punch_end = 6.5, die_start = 4, die_end = 5, die_loop = false},
	after_activate = function(self)
		self._carry_obj = nil
		if self._carried then
			show_carried(self)
		end
		if self._angry then
			calm(self)
		end
	end,
	-- whatever is shot or thrown at it misses: it teleports first; anyone else's hit makes it go after them
	do_punch = function(self, hitter, _, tool_caps)
		local ent = hitter and hitter:get_luaentity()
		local shot = tool_caps and tool_caps.damage_groups and tool_caps.damage_groups.knockback ~= nil
		if shot or ent and not ent._cmi_is_mob then
			keep_teleporting(self)
			return false
		end
		if hitter and (hitter:is_player() or ent) then
			anger(self, hitter)
			if math.random(10) == 1 and not hitter:is_player() then
				teleport(self)
			end
		end
	end,
	do_custom = enderman_step,
	on_die = function(self, pos)
		if self._carried then
			core.add_item(pos, self._carried)
		end
		if self._carry_obj then
			self._carry_obj:remove()
		end
	end,
})
AMBIENT[N .. "enderman"] = function(self)
	return self._angry and "goodluck_end_enderman_scream" or "goodluck_end_enderman"
end

-- The silverfish: 8 of health, bites for 1, quick, a quarter of a node high
mobs:register_mob(N .. "silverfish", {
	type = "monster",
	description = S("Silverfish"),
	passive = false,
	attack_type = "dogfight",
	pathfinding = 1,
	reach = 1,
	damage = 1,
	hp_min = 8, hp_max = 8,
	armor = 100,
	collisionbox = {-0.2, 0, -0.2, 0.2, 0.3, 0.2},
	visual = "mesh",
	mesh = "goodluck_models_silverfish.glb",
	textures = {{"goodluck_end_silverfish.png"}},
	sounds = {damage = "goodluck_end_silverfish_hurt", death = "goodluck_end_silverfish_death", distance = 16},
	walk_velocity = 1.2, run_velocity = 2.5,
	view_range = 16,
	jump = true,
	floats = 1,
	fear_height = 3,
	water_damage = 0, lava_damage = 4, light_damage = 0,
	animation = {speed_normal = 1, stand_start = 0, stand_end = 1, walk_start = 1, walk_end = 2, run_start = 1,
		run_end = 2, punch_start = 1, punch_end = 2, die_start = 4, die_end = 5, die_loop = false},
	do_custom = ambient,
})
AMBIENT[N .. "silverfish"] = "goodluck_end_silverfish"

for name, xp in pairs({enderman = 5, silverfish = 5}) do
	local def = core.registered_entities[N .. name]
	def._goodluck_xp = xp
	mobs:register_egg(N .. name, def.description, "goodluck_end_" .. name .. "_egg.png", 0)
end

-- out at night in the Overworld, on its ground in the dark as the other monsters, a tenth as often as each of them,
-- 1 to 4 together (Minecraft's weight 10 to their 100)
local GROUND = {"group:soil", "group:sand", "group:stone", "default:gravel", "default:snow", "default:snowblock",
	"default:dry_dirt", "default:dry_dirt_with_dry_grass"}
local function group(self, pos)
	for _ = 1, math.random(0, 3) do
		local p = vector.offset(vector.round(pos), math.random(-2, 2), 0, math.random(-2, 2))
		if landing(p) and vector.equals(landing(p), p) then
			core.add_entity(p, self.name)
		end
	end
end
mobs:spawn({name = N .. "enderman", nodes = GROUND, neighbors = {"air"}, max_light = 7, interval = 30,
	chance = 60000, active_object_count = 2, min_height = -31000, max_height = 31000, on_spawn = group})

E.anger, E.teleport, E.show_carried = anger, teleport, show_carried
