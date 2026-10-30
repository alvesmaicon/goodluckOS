-- Minecraft's swamp, in ground not generated yet (where old ground meets it, a seam): low wet land in the humid and
-- warm, its grass and leaves in Minecraft's swamp colours, water standing in its hollows, swamp oaks hung with vines
-- (mapgen.lua), lily pads, blue orchids, mushrooms and papyrus. Now and then a witch's hut on stilts (mapgen.lua, as
-- Minecraft's SwampHutPiece) with a witch and a black cat that stay; when the witch is killed, another comes some
-- minutes later, as on Bedrock
local S = core.get_translator("goodluck_swamp")
local N = "goodluck_swamp:"
-- Minecraft's swamp grass and foliage, #6a7039, over this game's grass (#91bd59 with Minecraft's textures) and leaves
-- (#77ab2f)
local GRASS_TINT, LEAVES_TINT = "^[multiply:#ba97a3", "^[multiply:#e3a7ff"
local RESPAWN = 300

core.register_node(N .. "dirt_with_grass", {
	description = S("Swamp Grass Block"),
	tiles = {"default_grass.png" .. GRASS_TINT, "default_dirt.png",
		{name = "default_dirt.png^(default_grass_side.png" .. GRASS_TINT .. ")", tileable_vertical = false}},
	groups = {crumbly = 3, soil = 1, spreading_dirt_type = 1},
	drop = "default:dirt",
	soil = {base = N .. "dirt_with_grass", dry = "farming:soil", wet = "farming:soil_wet"},
	sounds = default.node_sound_dirt_defaults({footstep = {name = "default_grass_footstep", gain = 0.25}}),
})

core.register_node(N .. "leaves", {
	description = S("Swamp Oak Leaves"),
	drawtype = "allfaces_optional",
	waving = 1,
	tiles = {"default_leaves.png" .. LEAVES_TINT},
	special_tiles = {"default_leaves_simple.png" .. LEAVES_TINT},
	paramtype = "light",
	is_ground_content = false,
	groups = {snappy = 3, leafdecay = 3, flammable = 2, leaves = 1},
	drop = {max_items = 1, items = {{items = {"default:sapling"}, rarity = 20}, {items = {N .. "leaves"}}}},
	sounds = default.node_sound_leaves_defaults(),
	after_place_node = default.after_place_leaves,
})
default.register_leafdecay({trunks = {"default:tree"}, leaves = {N .. "leaves"}, radius = 3})

-- climbed like a ladder, flat on the side of what holds it
core.register_node(N .. "vine", {
	description = S("Vines"),
	drawtype = "signlike",
	tiles = {"goodluck_swamp_vine.png"},
	inventory_image = "goodluck_swamp_vine.png",
	wield_image = "goodluck_swamp_vine.png",
	use_texture_alpha = "clip",
	paramtype = "light",
	paramtype2 = "wallmounted",
	sunlight_propagates = true,
	walkable = false,
	climbable = true,
	buildable_to = true,
	is_ground_content = false,
	selection_box = {type = "wallmounted"},
	groups = {snappy = 3, flammable = 2, vine = 1},
	sounds = default.node_sound_leaves_defaults(),
})

core.register_node(N .. "potted_red_mushroom", {
	description = S("Potted Red Mushroom"),
	drawtype = "mesh",
	mesh = "goodluck_models_potted_plant.obj",
	tiles = {"goodluck_swamp_flower_pot.png", "default_dirt.png", "flowers_mushroom_red.png"},
	use_texture_alpha = "clip",
	paramtype = "light",
	sunlight_propagates = true,
	selection_box = {type = "fixed", fixed = {-3 / 16, -0.5, -3 / 16, 3 / 16, 0.5, 3 / 16}},
	collision_box = {type = "fixed", fixed = {-3 / 16, -0.5, -3 / 16, 3 / 16, -2 / 16, 3 / 16}},
	groups = {dig_immediate = 3, attached_node = 1, not_in_creative_inventory = 1},
	drop = "flowers:mushroom_red",
	sounds = default.node_sound_stone_defaults(),
})

-- the land between 1 and 6 nodes over the sea where it is humid and warm; its shore and its shallows with dirt
-- under the water, as the swamps of Minetest Game's rainforest
local HEAT, HUMIDITY, TOP = 65, 90, 6
local function biome(name, def)
	def.name = name
	def.heat_point, def.humidity_point = HEAT, HUMIDITY
	def.node_dungeon, def.node_dungeon_alt = "default:cobble", "default:mossycobble"
	def.node_dungeon_stair = "stairs:stair_cobble"
	core.register_biome(def)
end
biome("swamp", {node_top = N .. "dirt_with_grass", depth_top = 1, node_filler = "default:dirt", depth_filler = 3,
	node_riverbed = "default:sand", depth_riverbed = 2, y_max = TOP, y_min = 1, vertical_blend = 1})
biome("swamp_shore", {node_top = "default:dirt", depth_top = 1, node_filler = "default:dirt", depth_filler = 3,
	node_riverbed = "default:sand", depth_riverbed = 2, y_max = 0, y_min = -1})
biome("swamp_ocean", {node_top = "default:dirt", depth_top = 1, node_filler = "default:sand", depth_filler = 3,
	node_riverbed = "default:sand", depth_riverbed = 2, node_cave_liquid = "default:water_source", y_max = -2,
	y_min = -255})
biome("swamp_under", {node_cave_liquid = {"default:water_source", "default:lava_source"}, y_max = -256,
	y_min = -31000})

local SWAMP, WET = {"swamp"}, {"swamp", "swamp_shore", "swamp_ocean"}
local function deco(def)
	def.deco_type = def.deco_type or "simple"
	def.sidelen = def.sidelen or 16
	core.register_decoration(def)
end

-- Minecraft's swamp oak: a trunk of 5 to 8 and BlobFoliagePlacer's leaves of radius 3 and 3 high (rows of 2, 2, 3
-- and 3 from the top, the top row's corners left out and the others' half the time); it may stand in water 2 deep
local AIR, LOG, LEAF = {name = "air", prob = 0}, {name = "default:tree", force_place = true},
	{name = N .. "leaves"}
local CORNER = {name = N .. "leaves", prob = 127}
local OAKS = {}
for h = 5, 8 do
	local data = {}
	for z = 0, 6 do
		for y = 0, h do
			for x = 0, 6 do
				local dx, dz, i = math.abs(x - 3), math.abs(z - 3), z * (h + 1) * 7 + y * 7 + x + 1
				local row = h - y
				local r = row <= 1 and 2 or 3
				local node = AIR
				if dx == 0 and dz == 0 and y < h then
					node = LOG
				elseif row <= 3 and dx <= r and dz <= r then
					node = (dx == r and dz == r) and (row == 0 and AIR or CORNER) or LEAF
				end
				data[i] = node
			end
		end
	end
	OAKS[h] = {size = {x = 7, y = h + 1, z = 7}, data = data}
	deco({name = N .. "oak_" .. h, deco_type = "schematic", place_on = {N .. "dirt_with_grass", "default:dirt"},
		fill_ratio = 0.002, biomes = WET, y_min = -1, y_max = TOP, schematic = OAKS[h],
		flags = "place_center_x, place_center_z"})
end

-- water standing in the lowest ground, as Minecraft's swamp surface noise
deco({name = N .. "puddle", place_on = {N .. "dirt_with_grass"}, biomes = SWAMP, y_min = 1, y_max = 1,
	noise_params = {offset = 0.15, scale = 0.6, spread = {x = 8, y = 8, z = 8}, seed = 4207, octaves = 2,
		persist = 0.5},
	decoration = "default:water_source", place_offset_y = -1, flags = "force_placement"})
deco({name = N .. "lily", place_on = {"default:water_source"}, biomes = WET, y_min = -2, y_max = 1,
	fill_ratio = 0.05, decoration = "flowers:waterlily_waving", param2 = 0, param2_max = 3,
	flags = "liquid_surface"})
deco({name = N .. "grass", place_on = {N .. "dirt_with_grass"}, biomes = SWAMP, y_min = 1, y_max = TOP,
	fill_ratio = 0.08, decoration = {"default:grass_2", "default:grass_3", "default:grass_4"}})
deco({name = N .. "orchid", place_on = {N .. "dirt_with_grass"}, biomes = SWAMP, y_min = 1, y_max = TOP,
	fill_ratio = 0.006, decoration = "flowers:geranium"})
deco({name = N .. "mushrooms", place_on = {N .. "dirt_with_grass"}, biomes = SWAMP, y_min = 1, y_max = TOP,
	fill_ratio = 0.008, decoration = {"flowers:mushroom_brown", "flowers:mushroom_red"}})
deco({name = N .. "dead_bush", place_on = {N .. "dirt_with_grass"}, biomes = SWAMP, y_min = 1, y_max = TOP,
	fill_ratio = 0.002, decoration = "default:dry_shrub"})
deco({name = N .. "papyrus", place_on = {N .. "dirt_with_grass", "default:dirt"}, biomes = WET, y_min = 1,
	y_max = 2, fill_ratio = 0.15, decoration = "default:papyrus", height = 2, height_max = 4,
	spawn_by = "default:water_source", num_spawn_by = 1})

-- the trees' places go to mapgen.lua, which hangs their vines
core.register_on_mods_loaded(function()
	local ids = {}
	for h = 5, 8 do
		ids[#ids + 1] = core.get_decoration_id(N .. "oak_" .. h)
	end
	core.set_gen_notify({decoration = true}, ids)
end)
core.set_gen_notify({custom = true}, nil, {N .. "hut"})
core.register_mapgen_script(core.get_modpath("goodluck_swamp") .. "/mapgen.lua")

-- The huts, in mod storage: where the witch stands, and since when she is missing
local storage = core.get_mod_storage()
local huts = core.deserialize(storage:get_string("huts")) or {}
goodluck_swamp = {huts = huts}

local function save()
	storage:set_string("huts", core.serialize(huts))
end

local function spawn(name, pos, key)
	local obj = core.add_entity(pos, name)
	local ent = obj and obj:get_luaentity()
	if not ent then
		return
	end
	ent._hut = key
	if name == "goodluck_monsters:witch" then
		ent.lifetimer = 20000
		obj:set_properties({static_save = true})
	else
		ent.base_texture = {"mobs_kitten_black.png"}
		obj:set_properties({textures = ent.base_texture})
	end
	return obj
end

core.register_on_generated(function(minp, maxp)
	local notes = core.get_mapgen_object("gennotify")
	local hut = notes and notes.custom and notes.custom[N .. "hut"]
	if not hut then
		return
	end
	local key = core.pos_to_string(hut.witch)
	huts[key] = {dir = hut.dir}
	save()
	local at = vector.offset(hut.witch, 0, -0.5, 0)
	if core.registered_entities["goodluck_monsters:witch"] then
		spawn("goodluck_monsters:witch", at, key)
	end
	if core.registered_entities["mobs_animal:kitten"] then
		spawn("mobs_animal:kitten", at, key)
	end
	core.log("action", ("[goodluck_swamp] witch hut at %s"):format(key))
end)

-- every 10 s, for each hut near a player in an active block: a witch of its own around it, or the time since there
-- was none; after RESPAWN seconds, with nobody inside, a new one in it
local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 10 then
		return
	end
	timer = 0
	local players = core.get_connected_players()
	if #players == 0 or not core.registered_entities["goodluck_monsters:witch"] then
		return
	end
	local now, changed = core.get_gametime(), false
	for key, hut in pairs(huts) do
		local pos = core.string_to_pos(key)
		local near, inside = false, false
		for _, player in ipairs(players) do
			local d = vector.distance(pos, player:get_pos())
			near, inside = near or d < 40, inside or d < 6
		end
		if near and core.compare_block_status(pos, "active") then
			local found = false
			for _, obj in ipairs(core.get_objects_inside_radius(pos, 24)) do
				local ent = obj:get_luaentity()
				if ent and ent._hut == key and ent.name == "goodluck_monsters:witch" then
					found = true
					break
				end
			end
			if found then
				changed = changed or hut.gone ~= nil
				hut.gone = nil
			elseif not hut.gone then
				hut.gone, changed = now, true
			elseif now - hut.gone >= RESPAWN and not inside then
				spawn("goodluck_monsters:witch", vector.offset(pos, 0, -0.5, 0), key)
				hut.gone, changed = nil, true
			end
		end
	end
	if changed then
		save()
	end
end)
