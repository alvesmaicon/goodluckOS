-- Minecraft's Nether as a realm deep below the world: two mapchunks of height (Minecraft's 128 and a little more, so
-- that no mapchunk is half of it), closed by bedrock, its ground made in the map generator's threads (mapgen.lua).
-- Its blocks and items, its ores and patches (placed by the engine), its red fog and what works otherwise in it
local S = core.get_translator("goodluck_nether")
local YMIN, YMAX = -5152, -4993
-- Minecraft's lava sea fills what is open up to 31 above the floor
local SEA = YMIN + 31

goodluck_nether = {ymin = YMIN, ymax = YMAX, sea = SEA}

function goodluck_nether.inside(pos)
	return pos.y >= YMIN - 0.5 and pos.y <= YMAX + 0.5
end

core.ipc_set("goodluck_nether:realm", {ymin = YMIN, ymax = YMAX, sea = SEA})

local RACK, BEDROCK = "goodluck_nether:netherrack", "goodluck_nether:bedrock"
local GLOWSTONE, DUST = "goodluck_nether:glowstone", "goodluck_nether:glowstone_dust"
local SOUL_SAND, MAGMA = "goodluck_nether:soul_sand", "goodluck_nether:magma"
local QUARTZ, QUARTZ_ORE, GOLD_ORE = "goodluck_nether:quartz", "goodluck_nether:quartz_ore", "goodluck_nether:gold_ore"
local QUARTZ_BLOCK = "goodluck_nether:quartz_block"
local BRICK, BRICKS = "goodluck_nether:nether_brick", "goodluck_nether:nether_bricks"
local WART = "goodluck_nether:nether_wart"
local NUGGET = "goodluck_food:gold_nugget"

-- one of n amounts from lo to hi, each as likely
local function some(item, lo, hi)
	local items = {}
	for n = hi, lo, -1 do
		items[#items + 1] = {items = {item .. " " .. n}, rarity = n - lo + 1}
	end
	return {max_items = 1, items = items}
end

-- a fire lit on top burns for ever, and goes out with the block, as on minetest_game's coal block
local function eternal(pos)
	local above = vector.offset(pos, 0, 1, 0)
	if core.get_node(above).name == "air" then
		core.set_node(above, {name = "fire:permanent_flame"})
	end
end
local function put_out(pos)
	local above = vector.offset(pos, 0, 1, 0)
	if core.get_node(above).name == "fire:permanent_flame" then
		core.remove_node(above)
	end
end

core.register_node(RACK, {
	description = S("Netherrack"),
	tiles = {"goodluck_nether_netherrack.png"},
	groups = {cracky = 3},
	-- the engine's caves from a mapchunk next door don't cut into the realm
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
	_goodluck_mc_sound = "netherrack",
	on_ignite = eternal,
	after_destruct = put_out,
})

core.register_node(BEDROCK, {
	description = S("Bedrock"),
	tiles = {"goodluck_nether_bedrock.png"},
	groups = {},
	diggable = false,
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
	on_blast = function() end,
})

core.register_craftitem(DUST, {
	description = S("Glowstone Dust"),
	inventory_image = "goodluck_nether_glowstone_dust.png",
})

core.register_node(GLOWSTONE, {
	description = S("Glowstone"),
	tiles = {"goodluck_nether_glowstone.png"},
	paramtype = "light",
	light_source = core.LIGHT_MAX,
	groups = {cracky = 3, oddly_breakable_by_hand = 3},
	is_ground_content = false,
	drop = some(DUST, 2, 4),
	sounds = default.node_sound_glass_defaults(),
})

core.register_node(SOUL_SAND, {
	description = S("Soul Sand"),
	tiles = {"goodluck_nether_soul_sand.png"},
	groups = {crumbly = 3},
	is_ground_content = false,
	sounds = default.node_sound_sand_defaults(),
	_goodluck_mc_sound = "soul_sand",
})

core.register_node(MAGMA, {
	description = S("Magma Block"),
	tiles = {{name = "goodluck_nether_magma.png",
		animation = {type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = 1.6}}},
	paramtype = "light",
	light_source = 3,
	groups = {cracky = 3},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
})

core.register_craftitem(QUARTZ, {
	description = S("Nether Quartz"),
	inventory_image = "goodluck_nether_quartz.png",
})

core.register_node(QUARTZ_ORE, {
	description = S("Nether Quartz Ore"),
	tiles = {"goodluck_nether_quartz_ore.png"},
	groups = {cracky = 3},
	is_ground_content = false,
	drop = QUARTZ,
	sounds = default.node_sound_stone_defaults(),
	_goodluck_mc_sound = "nether_ore",
})

core.register_node(GOLD_ORE, {
	description = S("Nether Gold Ore"),
	tiles = {"goodluck_nether_gold_ore.png"},
	groups = {cracky = 3},
	is_ground_content = false,
	drop = core.registered_items[NUGGET] and some(NUGGET, 2, 6) or "default:gold_lump",
	sounds = default.node_sound_stone_defaults(),
	_goodluck_mc_sound = "nether_ore",
})

core.register_node(QUARTZ_BLOCK, {
	description = S("Block of Quartz"),
	tiles = {"goodluck_nether_quartz_block_top.png", "goodluck_nether_quartz_block_bottom.png",
		"goodluck_nether_quartz_block_side.png"},
	groups = {cracky = 3},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
})

core.register_node("goodluck_nether:quartz_pillar", {
	description = S("Quartz Pillar"),
	tiles = {"goodluck_nether_quartz_pillar_top.png", "goodluck_nether_quartz_pillar_top.png",
		"goodluck_nether_quartz_pillar_side.png"},
	paramtype2 = "facedir",
	on_place = core.rotate_node,
	groups = {cracky = 3},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
})

core.register_node("goodluck_nether:chiseled_quartz", {
	description = S("Chiseled Quartz Block"),
	tiles = {"goodluck_nether_quartz_chiseled_top.png", "goodluck_nether_quartz_chiseled_top.png",
		"goodluck_nether_quartz_chiseled_side.png"},
	groups = {cracky = 3},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
})

stairs.register_stair_and_slab("quartz_block", QUARTZ_BLOCK, {cracky = 3},
	{"goodluck_nether_quartz_block_top.png", "goodluck_nether_quartz_block_bottom.png",
		"goodluck_nether_quartz_block_side.png"},
	S("Quartz Stairs"), S("Quartz Slab"), default.node_sound_stone_defaults(), true)

core.register_craftitem(BRICK, {
	description = S("Nether Brick"),
	inventory_image = "goodluck_nether_brick.png",
})

core.register_node(BRICKS, {
	description = S("Nether Bricks"),
	tiles = {"goodluck_nether_bricks.png"},
	groups = {cracky = 2},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
	_goodluck_mc_sound = "nether_bricks",
})

stairs.register_stair_and_slab("nether_bricks", BRICKS, {cracky = 2}, {"goodluck_nether_bricks.png"},
	S("Nether Brick Stairs"), S("Nether Brick Slab"), default.node_sound_stone_defaults(), true)

-- joins nether brick fences and walls only, as in Minecraft
default.register_fence("goodluck_nether:nether_brick_fence", {
	description = S("Nether Brick Fence"),
	texture = "goodluck_nether_bricks.png",
	connects_to = {"group:nether_brick_fence", "group:wall"},
	groups = {cracky = 2, nether_brick_fence = 1},
	sounds = default.node_sound_stone_defaults(),
	_goodluck_mc_sound = "nether_bricks",
})

-- nether wart: planted on soul sand, it grows in the dark, a stage every 11 minutes or so (Minecraft's random tick
-- at 1 in 10), and gives 2 to 4 when ripe
local HEIGHT = {5, 8, 11, 14}
local STAGE_TEXTURE = {0, 1, 1, 2}
for stage = 0, 3 do
	core.register_node(WART .. "_" .. stage, {
		description = S("Nether Wart"),
		drawtype = "plantlike",
		tiles = {"goodluck_nether_wart_" .. STAGE_TEXTURE[stage + 1] .. ".png"},
		paramtype = "light",
		paramtype2 = "meshoptions",
		place_param2 = 3,
		sunlight_propagates = true,
		walkable = false,
		selection_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, -0.5 + HEIGHT[stage + 1] / 16, 0.5}},
		groups = {snappy = 3, attached_node = 1, not_in_creative_inventory = 1},
		drop = stage < 3 and WART or some(WART, 2, 4),
		sounds = default.node_sound_leaves_defaults(),
	})
end

core.register_craftitem(WART, {
	description = S("Nether Wart"),
	inventory_image = "goodluck_nether_wart.png",
	on_place = function(itemstack, placer, pointed)
		if pointed.type ~= "node" then
			return itemstack
		end
		local under = core.get_node(pointed.under)
		local def = core.registered_nodes[under.name]
		if def and def.on_rightclick and not (placer and placer:get_player_control().sneak) then
			return def.on_rightclick(pointed.under, under, placer, itemstack, pointed)
		end
		local name = placer and placer:get_player_name() or ""
		local above = core.registered_nodes[core.get_node(pointed.above).name]
		if under.name ~= SOUL_SAND or pointed.above.y ~= pointed.under.y + 1 or not (above and above.buildable_to) or
				core.is_protected(pointed.above, name) then
			return itemstack
		end
		core.set_node(pointed.above, {name = WART .. "_0", param2 = 3})
		core.sound_play("default_place_node", {pos = pointed.above, gain = 1.0}, true)
		if not core.is_creative_enabled(name) then
			itemstack:take_item()
		end
		return itemstack
	end,
})

core.register_abm({
	label = "Nether wart growth",
	nodenames = {WART .. "_0", WART .. "_1", WART .. "_2"},
	neighbors = {SOUL_SAND},
	interval = 68,
	chance = 10,
	action = function(pos, node)
		if core.get_node(vector.offset(pos, 0, -1, 0)).name == SOUL_SAND then
			core.swap_node(pos, {name = WART .. "_" .. tonumber(node.name:sub(-1)) + 1, param2 = node.param2})
		end
	end,
})

core.register_craft({output = GLOWSTONE, recipe = {{DUST, DUST}, {DUST, DUST}}})
core.register_craft({output = QUARTZ_BLOCK, recipe = {{QUARTZ, QUARTZ}, {QUARTZ, QUARTZ}}})
core.register_craft({output = "goodluck_nether:quartz_pillar 2", recipe = {{QUARTZ_BLOCK}, {QUARTZ_BLOCK}}})
core.register_craft({output = "goodluck_nether:chiseled_quartz",
	recipe = {{"stairs:slab_quartz_block"}, {"stairs:slab_quartz_block"}}})
core.register_craft({output = BRICKS, recipe = {{BRICK, BRICK}, {BRICK, BRICK}}})
core.register_craft({output = "goodluck_nether:nether_brick_fence 6",
	recipe = {{BRICKS, BRICK, BRICKS}, {BRICKS, BRICK, BRICKS}}})
core.register_craft({type = "cooking", output = BRICK, recipe = RACK})
if core.get_modpath("goodluck_redstone") then
	local R = "goodluck_redstone:redstone"
	core.register_craft({output = "goodluck_redstone:lamp", recipe = {{"", R, ""}, {R, GLOWSTONE, R}, {"", R, ""}}})
end

-- ores and patches, by the engine in the realm's netherrack once mapgen.lua has carved it: veins as many and as big
-- as Minecraft's (1.16) per 16x16 column over its 108 nodes of height, matched as goodluck_ores matches them, lava
-- springs (hidden and on walls), magma about the lava sea's level, soul sand anywhere and gravel by the sea
local COLUMN = 16 * 16 * 108
local function ore(def)
	def.wherein = RACK
	def.y_min = def.y_min or YMIN + 10
	def.y_max = def.y_max or YMAX - 10
	core.register_ore(def)
end
ore({ore_type = "scatter", ore = QUARTZ_ORE, clust_scarcity = COLUMN / 16, clust_num_ores = 12, clust_size = 3})
ore({ore_type = "scatter", ore = GOLD_ORE, clust_scarcity = math.floor(COLUMN / 10), clust_num_ores = 9,
	clust_size = 3})
ore({ore_type = "scatter", ore = "default:lava_source", clust_scarcity = math.floor(COLUMN / 24), clust_num_ores = 1,
	clust_size = 1})
ore({ore_type = "scatter", ore = MAGMA, clust_scarcity = 16 * 16 * 10 / 4, clust_num_ores = 24, clust_size = 4,
	y_min = SEA - 4, y_max = SEA + 5})
ore({ore_type = "blob", ore = SOUL_SAND, clust_scarcity = 16 * 16 * 16, clust_size = 7, y_min = SEA - 4,
	noise_params = {offset = 0, scale = 1, spread = {x = 5, y = 5, z = 5}, seed = 7431, octaves = 1, persistence = 0}})
ore({ore_type = "blob", ore = "default:gravel", clust_scarcity = 12 * 12 * 12, clust_size = 6, y_min = SEA - 3,
	y_max = SEA + 6,
	noise_params = {offset = 0, scale = 1, spread = {x = 5, y = 5, z = 5}, seed = 7432, octaves = 1, persistence = 0}})

core.register_mapgen_script(core.get_modpath("goodluck_nether") .. "/mapgen.lua")
dofile(core.get_modpath("goodluck_nether") .. "/portal.lua")

-- inside: the Nether's red fog, as near as Minecraft's (it also keeps the A33 from drawing far into one big cave), no
-- sun, moon, stars or clouds; soul sand walks at 40 %, magma burns half a heart every half second unless sneaking
local FOG = tonumber(core.settings:get("goodluck_nether_fog")) or 48
local RED = "#330808"
local inside, on_soul_sand, burn = {}, {}, {}

local function set_sky(player, nether)
	if nether then
		player:set_sky({type = "plain", base_color = RED, clouds = false,
			fog = {fog_distance = FOG, fog_start = 0.3, fog_color = RED}})
		player:set_sun({visible = false, sunrise_visible = false})
		player:set_moon({visible = false})
		player:set_stars({visible = false})
	else
		player:set_sky()
		player:set_sun()
		player:set_moon()
		player:set_stars()
	end
end

-- minetest_game's weather leaves the clouds and the light alone in the Nether
if weather then
	local get = weather.get
	function weather.get(player)
		if inside[player:get_player_name()] then
			return {}
		end
		return get(player)
	end
end

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
		local nether = goodluck_nether.inside(pos)
		if nether ~= (inside[name] or false) then
			inside[name] = nether or nil
			set_sky(player, nether)
		end
		local under = core.get_node(vector.round(vector.offset(pos, 0, -0.1, 0))).name
		local soul = under == SOUL_SAND
		if soul ~= (on_soul_sand[name] or false) then
			on_soul_sand[name] = soul or nil
			player:set_physics_override({speed_walk = soul and 0.4 or 1, speed_crouch = soul and 0.4 or 1})
		end
		if under == MAGMA and not player:get_player_control().sneak and player:get_hp() > 0 and
				not core.is_creative_enabled(name) then
			burn[name] = (burn[name] or 0) + step
			if burn[name] >= 0.5 then
				burn[name] = 0
				player:set_hp(player:get_hp() - 1, {type = "set_hp", cause = "goodluck_nether:magma"})
			end
		else
			burn[name] = nil
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	inside[name], on_soul_sand[name], burn[name] = nil, nil, nil
end)

-- water poured in the Nether boils away with a hiss and a puff, as in Minecraft
for _, name in ipairs({"bucket:bucket_water", "bucket:bucket_river_water"}) do
	local def = core.registered_items[name]
	if def and def.on_place then
		local on_place = def.on_place
		core.override_item(name, {on_place = function(itemstack, user, pointed)
			local node = pointed.type == "node" and core.get_node(pointed.under)
			local ndef = node and core.registered_nodes[node.name]
			if not node or not goodluck_nether.inside(pointed.above) or
					ndef and ndef.on_rightclick and not (user and user:get_player_control().sneak) then
				return on_place(itemstack, user, pointed)
			end
			local pos = ndef and ndef.buildable_to and pointed.under or pointed.above
			core.sound_play("fire_extinguish_flame", {pos = pos, gain = 0.5}, true)
			core.add_particlespawner({amount = 8, time = 0.2, pos = {min = vector.offset(pos, -0.4, -0.4, -0.4),
				max = vector.offset(pos, 0.4, 0.2, 0.4)}, vel = {min = vector.new(-0.2, 0.8, -0.2),
				max = vector.new(0.2, 1.6, 0.2)}, exptime = {min = 0.6, max = 1.2}, size = {min = 2, max = 4},
				texture = "default_item_smoke.png"})
			if core.is_creative_enabled(user and user:get_player_name() or "") then
				return itemstack
			end
			return ItemStack("bucket:bucket_empty")
		end})
	end
end

-- none of the Overworld's monsters and animals come out in the Nether
if mobs and mobs.spawn_abm_check then
	local spawn_abm_check = mobs.spawn_abm_check
	function mobs:spawn_abm_check(pos, node, name)
		if goodluck_nether.inside(pos) then
			return true
		end
		return spawn_abm_check(self, pos, node, name)
	end
end
