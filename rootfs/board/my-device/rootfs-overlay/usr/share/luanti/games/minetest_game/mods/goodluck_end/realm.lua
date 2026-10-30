-- The End as a realm far over the world: Minecraft's 256 of height from 25968 up (mapchunk-aligned), its main island
-- of end stone round the middle (endgen.lua), its sky of the end_sky texture, dim and never changing, no sun, moon,
-- stars or clouds; below it the void, which hurts 4 every half second under Minecraft's -64. The end portal takes
-- whoever steps in to Minecraft's obsidian platform at 100, 49, 0 (built anew each time), the exit portal back to their
-- bed or the world's spawn. Endermen come out on its ground whatever the light, and nothing of the Overworld's; the
-- crystals on the pillars, which blow up when hit
local S = core.get_translator("goodluck_end")
local E = goodluck_end
local YMIN = 25968
local YMAX = YMIN + 239
local VOID = YMIN - 64

E.ymin, E.ymax = YMIN, YMAX
function E.inside(pos)
	return pos.y >= YMIN - 2000 and pos.y <= YMAX + 2000
end

-- Minecraft's spikes, from the world's seed: ten round a circle of 42, their sizes shuffled (radius 2 + i / 3,
-- height 76 + 3i, i = 1 and 2 caged)
local SEED = (tonumber(core.get_mapgen_setting("seed")) or 0) % 2147483647
local spikes = {}
do
	local order = {}
	for i = 0, 9 do
		order[#order + 1] = i
	end
	local pr = PcgRandom((SEED + 4207) % 2147483647)
	for i = #order, 2, -1 do
		local j = pr:next(1, i)
		order[i], order[j] = order[j], order[i]
	end
	for i = 0, 9 do
		local a = 2 * (-math.pi + math.pi / 10 * i)
		local k = order[i + 1]
		spikes[#spikes + 1] = {x = math.floor(42 * math.cos(a)), z = math.floor(42 * math.sin(a)), radius = 2 + math.floor(k / 3),
			height = 76 + 3 * k, guarded = k == 1 or k == 2}
	end
end
E.spikes = spikes
core.ipc_set("goodluck_end:realm", {ymin = YMIN, ymax = YMAX, spikes = spikes})

core.register_node("goodluck_end:end_stone", {
	description = S("End Stone"),
	tiles = {"goodluck_end_end_stone.png"},
	groups = {cracky = 2, stone = 1},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
	-- Minecraft's 9 of blast resistance: what blows up in the End leaves its ground
	on_blast = function() end,
})
core.register_node("goodluck_end:end_stone_bricks", {
	description = S("End Stone Bricks"),
	tiles = {"goodluck_end_end_stone_bricks.png"},
	groups = {cracky = 2, stone = 1},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
})
core.register_craft({output = "goodluck_end:end_stone_bricks 4", recipe = {
	{"goodluck_end:end_stone", "goodluck_end:end_stone"}, {"goodluck_end:end_stone", "goodluck_end:end_stone"}}})
if stairs then
	stairs.register_stair_and_slab("end_stone_bricks", "goodluck_end:end_stone_bricks", {cracky = 2},
		{"goodluck_end_end_stone_bricks.png"}, S("End Stone Brick Stairs"), S("End Stone Brick Slab"),
		default.node_sound_stone_defaults(), true)
end

-- the podium's place, once its mapchunk is made, kept for the dragon and the exit portal
local storage = core.get_mod_storage()
function E.podium()
	local s = storage:get_string("podium")
	return s ~= "" and core.string_to_pos(s) or nil
end

-- Travelling: the platform of obsidian under the arrival (and room over it), Minecraft's createEndPlatform
local ARRIVAL = {x = 100, y = YMIN + 50, z = 0}
local function platform(at)
	for x = -2, 2 do
		for z = -2, 2 do
			for y = -1, 2 do
				local p = {x = at.x + x, y = at.y + y, z = at.z + z}
				local want = y == -1 and "default:obsidian" or "air"
				if core.get_node(p).name ~= want then
					core.set_node(p, {name = want})
				end
			end
		end
	end
end

local travelling = {}
local function arrive(player, to, build)
	local name = player:get_player_name()
	travelling[name] = true
	core.emerge_area(vector.offset(to, -24, -24, -24), vector.offset(to, 24, 24, 24), function(_, _, left)
		if left > 0 then
			return
		end
		travelling[name] = nil
		if not player:is_valid() then
			return
		end
		if build then
			build(to)
		end
		player:set_pos({x = to.x + 0.5, y = to.y - 0.5, z = to.z + 0.5})
		player:add_velocity(vector.multiply(player:get_velocity(), -1))
		core.sound_play("goodluck_nether_portal_travel", {to_player = name, gain = 0.5}, true)
	end)
end

function E.to_end(player)
	core.log("action", ("[goodluck_end] %s goes to the End"):format(player:get_player_name()))
	arrive(player, ARRIVAL, platform)
	if E.on_enter then
		E.on_enter(player)
	end
end

-- back: their bed, else the world's spawn (the static one, else where they first came)
function E.to_overworld(player)
	local name = player:get_player_name()
	local to = beds and beds.spawn and beds.spawn[name]
	if not to then
		to = core.setting_get_pos("static_spawnpoint") or E.first_spawn(player)
	end
	core.log("action", ("[goodluck_end] %s leaves the End for %s"):format(name, core.pos_to_string(to)))
	arrive(player, vector.round(vector.offset(to, 0, 0.5, 0)), function(p)
		-- on the ground: up to the first room for a player
		for _ = 1, 64 do
			if core.get_node(p).name == "air" and core.get_node(vector.offset(p, 0, 1, 0)).name == "air" then
				break
			end
			p.y = p.y + 1
		end
	end)
end

-- where a player came into the world, else the middle (Minecraft's world spawn), kept for going back
function E.first_spawn(player)
	local s = player:get_meta():get_string("goodluck_end:spawn")
	return s ~= "" and core.string_to_pos(s) or {x = 0, y = 2, z = 0}
end
core.register_on_newplayer(function(player)
	core.after(1, function()
		if player:is_valid() then
			player:get_meta():set_string("goodluck_end:spawn", core.pos_to_string(vector.round(player:get_pos())))
		end
	end)
end)

-- the End's sky: Minecraft's end_sky on every side, dark, fog of its colour; a light that never changes
local SKY = "goodluck_end_sky.png^[multiply:#2a2a2a"
local inside, burn = {}, {}
local function set_sky(player, on)
	if on then
		player:set_sky({type = "skybox", base_color = "#000000", textures = {SKY, SKY, SKY, SKY, SKY, SKY},
			clouds = false, fog = {fog_color = "#181318"}})
		player:set_sun({visible = false, sunrise_visible = false})
		player:set_moon({visible = false})
		player:set_stars({visible = false})
		player:override_day_night_ratio(0.7)
	else
		player:set_sky()
		player:set_sun()
		player:set_moon()
		player:set_stars()
		player:override_day_night_ratio(nil)
	end
end

if weather then
	local get = weather.get
	function weather.get(player)
		if inside[player:get_player_name()] then
			return {}
		end
		return get(player)
	end
end

local PORTAL, EXIT = "goodluck_end:portal", "goodluck_end:exit_portal"
local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 0.25 then
		return
	end
	local step = timer
	timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local pos = player:get_pos()
		local here = E.inside(pos)
		if here ~= (inside[name] or false) then
			inside[name] = here or nil
			set_sky(player, here)
		end
		if not travelling[name] and player:get_hp() > 0 then
			local feet = core.get_node(vector.round(vector.offset(pos, 0, 0.3, 0))).name
			if feet == PORTAL or feet == EXIT then
				if here then
					E.to_overworld(player)
				else
					E.to_end(player)
				end
			end
		end
		-- the void
		if here and pos.y < VOID and player:get_hp() > 0 then
			burn[name] = (burn[name] or 0) + step
			if burn[name] >= 0.5 then
				burn[name] = 0
				player:set_hp(player:get_hp() - 4, {type = "set_hp", cause = "goodluck_end:void"})
			end
		else
			burn[name] = nil
		end
	end
end)
core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	inside[name], burn[name], travelling[name] = nil, nil, nil
end)

-- what falls into the void is gone
local fall_timer = 0
core.register_globalstep(function(dtime)
	fall_timer = fall_timer + dtime
	if fall_timer < 5 then
		return
	end
	fall_timer = 0
	for _, ent in pairs(core.luaentities) do
		local p = ent.object:get_pos()
		if p and p.y < VOID - 64 and p.y > YMIN - 2000 then
			ent.object:remove()
		end
	end
end)

-- Monsters: in the End only endermen, whatever the light, in fours, up to 12 within 64 of the nearest player
local N = "goodluck_end:enderman"
local function crowded(pos)
	local all = 0
	for _, obj in ipairs(core.get_objects_inside_radius(pos, 64)) do
		local ent = obj:get_luaentity()
		if ent and ent._cmi_is_mob and ent.type == "monster" then
			all = all + 1
		end
	end
	return all >= 12
end
if mobs and mobs.spawn_abm_check then
	local spawn_abm_check = mobs.spawn_abm_check
	function mobs:spawn_abm_check(pos, node, name)
		if E.inside(pos) then
			return name ~= N or crowded(pos)
		end
		return spawn_abm_check(self, pos, node, name)
	end
end
local function group(self, pos)
	for _ = 1, 3 do
		local p = vector.offset(vector.round(pos), math.random(-3, 3), 0, math.random(-3, 3))
		if core.get_node(p).name == "air" and core.get_node(vector.offset(p, 0, 1, 0)).name == "air" and
				core.get_node(vector.offset(p, 0, 2, 0)).name == "air" and
				core.get_node(vector.offset(p, 0, -1, 0)).name == "goodluck_end:end_stone" and not crowded(p) then
			core.add_entity(p, N)
		end
	end
end
-- (once the enderman is registered)
function E.spawn_endermen()
	mobs:spawn({name = N, nodes = {"goodluck_end:end_stone"}, neighbors = {"air"}, min_light = 0, max_light = 15,
		interval = 30, chance = 3000, active_object_count = 6, min_height = YMIN, max_height = YMAX, on_spawn = group})
end

-- The exit portal: lit by the dragon's death (dragon.lua), it takes whoever steps in back
core.register_node(EXIT, {
	description = S("End Portal"),
	drawtype = "nodebox",
	node_box = {type = "fixed", fixed = {-0.5, 0.25, -0.5, 0.5, 0.25, 0.5}},
	tiles = {{name = "goodluck_end_portal.png", animation = {type = "vertical_frames", aspect_w = 16, aspect_h = 16,
		length = 6.4}}},
	use_texture_alpha = "opaque",
	paramtype = "light",
	sunlight_propagates = true,
	light_source = core.LIGHT_MAX,
	walkable = false,
	pointable = false,
	diggable = false,
	is_ground_content = false,
	groups = {not_in_creative_inventory = 1},
	drop = "",
	on_blast = function() end,
})

-- the podium's portal lit (on) or put out, where the podium is
function E.exit_portal(on)
	local o = E.podium()
	if not o then
		return
	end
	for x = -4, 4 do
		for z = -4, 4 do
			if x * x + z * z < 6.25 and not (x == 0 and z == 0) then
				local p = {x = o.x + x, y = o.y, z = o.z + z}
				core.set_node(p, {name = on and EXIT or "air"})
			end
		end
	end
end

-- The end crystal: Minecraft's (EndCrystalModel), its glass turning about a cube over a base, with fire under it;
-- anything that hits it, a player, an arrow or a blast, blows it up (power 6: hurts and throws back what is near,
-- breaks no blocks here but the fire and bars about it)
local function boom(pos, power, by)
	core.sound_play("tnt_explode", {pos = pos, gain = 2, max_hear_distance = 96}, true)
	core.add_particlespawner({amount = 32, time = 0.2, pos = {min = vector.offset(pos, -power / 2, -power / 2,
		-power / 2), max = vector.offset(pos, power / 2, power / 2, power / 2)}, vel = {min = vector.new(-1, 0, -1),
		max = vector.new(1, 2, 1)}, exptime = {min = 0.5, max = 1.2}, size = {min = 8, max = 16},
		texture = "tnt_smoke.png"})
	for _, p in ipairs(core.find_nodes_in_area(vector.offset(pos, -2, -2, -2), vector.offset(pos, 2, 2, 2),
			{"fire:permanent_flame", "fire:basic_flame", "xpanes:bar", "xpanes:bar_flat"})) do
		core.remove_node(p)
	end
	local radius = power * 2
	for _, obj in ipairs(core.get_objects_inside_radius(pos, radius)) do
		local ent = obj:get_luaentity()
		local p = obj:get_pos()
		if p and (obj:is_player() or ent and ent._cmi_is_mob) then
			local i = 1 - vector.distance(p, pos) / radius
			if i > 0 and core.line_of_sight(pos, vector.offset(p, 0, 1, 0)) then
				local dir = vector.direction(pos, vector.offset(p, 0, 1, 0))
				obj:punch(by and by:is_valid() and by or obj, 1.0, {full_punch_interval = 1.0,
					damage_groups = {fleshy = math.floor((i * i + i) / 2 * 7 * radius + 1)}}, dir)
				if obj:is_valid() then
					obj:add_velocity(vector.multiply(dir, i * 10))
				end
			end
		end
	end
end
E.boom = boom

core.register_entity("goodluck_end:end_crystal", {
	initial_properties = {
		physical = false,
		collide_with_objects = false,
		collisionbox = {-1, 0, -1, 1, 2, 1},
		selectionbox = {-1, 0, -1, 1, 2, 1},
		visual = "mesh",
		mesh = "goodluck_models_end_crystal.glb",
		textures = {"goodluck_end_end_crystal.png"},
		visual_size = {x = 2, y = 2, z = 2},
		glow = 15,
		static_save = true,
	},
	on_activate = function(self, staticdata)
		self.object:set_armor_groups({fleshy = 100, immortal = 0})
		self.object:set_animation({x = 0, y = 6}, 1, 0, true)
		self._base = staticdata ~= "nobase"
	end,
	get_staticdata = function(self)
		return self._base and "" or "nobase"
	end,
	on_punch = function(self, puncher)
		local pos = self.object:get_pos()
		self.object:remove()
		if E.on_crystal_destroyed then
			E.on_crystal_destroyed(pos, puncher)
		end
		boom(vector.offset(pos, 0, 1, 0), 6, puncher)
		return true
	end,
})

-- the crystals on the pillars, once their mapchunk is made; the podium's place
core.set_gen_notify({custom = true}, nil, {"goodluck_end:realm"})
core.register_on_generated(function(minp, maxp)
	if maxp.y < YMIN or minp.y > YMAX then
		return
	end
	local notes = core.get_mapgen_object("gennotify")
	local made = notes and notes.custom and notes.custom["goodluck_end:realm"]
	if not made then
		return
	end
	for _, p in ipairs(made.crystals) do
		core.add_entity({x = p.x, y = p.y - 0.5, z = p.z}, "goodluck_end:end_crystal")
		core.log("action", ("[goodluck_end] end crystal at %s"):format(core.pos_to_string(p)))
	end
	if made.podium then
		storage:set_string("podium", core.pos_to_string(made.podium))
		core.log("action", ("[goodluck_end] exit portal's podium at %s"):format(core.pos_to_string(made.podium)))
	end
	core.log("action", ("[goodluck_end] End chunk %d,%d,%d: %d ms (data %d, shape %d, pillars %d, write %d), %d stone")
		:format(minp.x, minp.y, minp.z, (made.read + made.shape + made.features + made.write) / 1000, made.read / 1000,
		made.shape / 1000, made.features / 1000, made.write / 1000, made.stone))
end)
