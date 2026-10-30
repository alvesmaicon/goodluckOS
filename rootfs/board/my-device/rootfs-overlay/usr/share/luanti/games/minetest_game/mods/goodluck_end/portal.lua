-- The strongholds' blocks and the end portal. Cracked, mossy and chiseled stone bricks; the end portal frame, which
-- can't be broken and takes an eye of ender (either button); twelve eyes in a ring of frames about a 3x3 hole light
-- the portal in it, as Minecraft's pattern does. The chests and the silverfish spawner of the strongholds are set once
-- their mapchunk is made
local S = core.get_translator("goodluck_end")
local E = goodluck_end
local F = E.stronghold
local FRAME, EYE, PORTAL = "goodluck_end:frame", "goodluck_end:frame_eye", "goodluck_end:portal"

core.register_node("goodluck_end:stonebrick_cracked", {
	description = S("Cracked Stone Bricks"),
	tiles = {"goodluck_end_stonebrick_cracked.png"},
	groups = {cracky = 2, stone = 1},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
})
core.register_node("goodluck_end:stonebrick_mossy", {
	description = S("Mossy Stone Bricks"),
	tiles = {"goodluck_end_stonebrick_mossy.png"},
	groups = {cracky = 2, stone = 1},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
})
core.register_node("goodluck_end:stonebrick_chiseled", {
	description = S("Chiseled Stone Bricks"),
	tiles = {"goodluck_end_stonebrick_chiseled.png"},
	groups = {cracky = 2, stone = 1},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
})
core.register_craft({type = "cooking", output = "goodluck_end:stonebrick_cracked", recipe = "default:stonebrick"})
core.register_craft({output = "goodluck_end:stonebrick_chiseled",
	recipe = {{"stairs:slab_stonebrick"}, {"stairs:slab_stonebrick"}}})
core.register_craft({type = "shapeless", output = "goodluck_end:stonebrick_mossy",
	recipe = {"default:stonebrick", "default:mossycobble"}})

-- the ring of 12 frames about c (y the frames'), its middle row on each side first
local RING = {}
for i = -1, 1 do
	RING[#RING + 1] = {x = i, z = -2}
	RING[#RING + 1] = {x = i, z = 2}
	RING[#RING + 1] = {x = -2, z = i}
	RING[#RING + 1] = {x = 2, z = i}
end

local function light(pos)
	for _, o in ipairs(RING) do
		local c = {x = pos.x - o.x, y = pos.y, z = pos.z - o.z}
		local all = true
		for _, r in ipairs(RING) do
			if core.get_node({x = c.x + r.x, y = c.y, z = c.z + r.z}).name ~= EYE then
				all = false
				break
			end
		end
		if all then
			for x = -1, 1 do
				for z = -1, 1 do
					core.set_node({x = c.x + x, y = c.y, z = c.z + z}, {name = PORTAL})
				end
			end
			core.sound_play("goodluck_end_portal_open", {pos = c, gain = 1, max_hear_distance = 64}, true)
			core.log("action", ("[goodluck_end] end portal lit at %s"):format(core.pos_to_string(c)))
			return c
		end
	end
end
E.light_portal = light

local FRAME_BOX = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, 0.3125, 0.5}}
local frame = {
	description = S("End Portal Frame"),
	drawtype = "mesh",
	mesh = "goodluck_models_end_portal_frame.obj",
	tiles = {"goodluck_end_frame_top.png", "goodluck_end_frame_side.png", "goodluck_end_frame_bottom.png"},
	paramtype = "light",
	paramtype2 = "facedir",
	selection_box = FRAME_BOX,
	collision_box = FRAME_BOX,
	diggable = false,
	groups = {},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
	on_blast = function() end,
	on_place = core.rotate_node,
	on_rightclick = function(pos, node, clicker, itemstack)
		if itemstack:get_name() ~= "goodluck_end:ender_eye" then
			return itemstack
		end
		core.swap_node(pos, {name = EYE, param2 = node.param2})
		core.sound_play("goodluck_end_eye_place", {pos = pos, gain = 1}, true)
		E.specks(vector.offset(pos, 0, 0.3, 0), 16, 0.3, 0.6)
		if not (clicker and core.is_creative_enabled(clicker:get_player_name())) then
			itemstack:take_item()
		end
		light(pos)
		return itemstack
	end,
}
core.register_node(FRAME, frame)
local with_eye = table.copy(frame)
with_eye.mesh = "goodluck_models_end_portal_frame_eye.obj"
with_eye.tiles = {"goodluck_end_frame_top.png", "goodluck_end_frame_side.png", "goodluck_end_frame_bottom.png",
	"goodluck_end_frame_eye.png"}
with_eye.light_source = 1
with_eye.groups = {not_in_creative_inventory = 1}
with_eye.drop = FRAME
with_eye.on_rightclick = nil
with_eye.selection_box = {type = "fixed", fixed = {{-0.5, -0.5, -0.5, 0.5, 0.3125, 0.5},
	{-0.25, 0.3125, -0.25, 0.25, 0.5, 0.25}}}
with_eye.collision_box = with_eye.selection_box
core.register_node(EYE, with_eye)

-- the portal: a sheet of stars three quarters up its block, which nothing stands on; its light is full
core.register_node(PORTAL, {
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
	buildable_to = false,
	is_ground_content = false,
	groups = {not_in_creative_inventory = 1},
	drop = "",
	on_blast = function() end,
})

-- In the game, once a mapchunk is made: its chests filled from Minecraft's chests/stronghold_* (that game's items
-- for its own, what this one lacks left out), its spawners set to silverfish
local LOOT = {
	corridor = {rolls = {2, 3}, {"goodluck_end:ender_pearl", 1, 1, 10}, {"default:diamond", 1, 3, 3},
		{"default:steel_ingot", 1, 5, 10}, {"default:gold_ingot", 1, 3, 5}, {"goodluck_redstone:redstone", 4, 9, 5},
		{"farming:bread", 1, 3, 15}, {"default:apple", 1, 3, 15}, {"default:pick_steel", 1, 1, 5},
		{"default:sword_steel", 1, 1, 5}, {"3d_armor:chestplate_steel", 1, 1, 5}, {"3d_armor:helmet_steel", 1, 1, 5},
		{"3d_armor:leggings_steel", 1, 1, 5}, {"3d_armor:boots_steel", 1, 1, 5}, {"goodluck_horse:golden_apple", 1, 1, 1},
		{"mobs:leather", 1, 5, 1}, {"goodluck_horse:armor_iron", 1, 1, 1}, {"goodluck_horse:armor_gold", 1, 1, 1},
		{"goodluck_horse:armor_diamond", 1, 1, 1}, {"default:book", 1, 1, 1}},
	crossing = {rolls = {1, 4}, {"default:steel_ingot", 1, 5, 10}, {"default:gold_ingot", 1, 3, 5},
		{"goodluck_redstone:redstone", 4, 9, 5}, {"default:coal_lump", 3, 8, 10}, {"farming:bread", 1, 3, 15},
		{"default:apple", 1, 3, 15}, {"default:pick_steel", 1, 1, 1}, {"default:book", 1, 1, 1}},
	library = {rolls = {2, 10}, {"default:book", 1, 3, 20}, {"default:paper", 2, 7, 20},
		{"goodluck_map:empty_map", 1, 1, 1}, {"goodluck_compass:compass", 1, 1, 1}, {"default:book", 1, 1, 10}},
}
core.register_on_mods_loaded(function()
	for _, list in pairs(LOOT) do
		for i = #list, 1, -1 do
			if not core.registered_items[list[i][1]] then
				table.remove(list, i)
			end
		end
	end
end)

local SEED = (tonumber(core.get_mapgen_setting("seed")) or 0) % 2147483647
local function fill(pos, loot)
	local inv = core.get_meta(pos):get_inventory()
	local list = LOOT[loot]
	local pr = PcgRandom((SEED + core.hash_node_position(pos)) % 2147483647)
	local total, free = 0, {}
	for _, e in ipairs(list) do
		total = total + e[4]
	end
	for i = 1, inv:get_size("main") do
		free[i] = i
	end
	for _ = 1, pr:next(list.rolls[1], list.rolls[2]) do
		local roll = pr:next(1, total)
		for _, e in ipairs(list) do
			roll = roll - e[4]
			if roll <= 0 then
				inv:set_stack("main", table.remove(free, pr:next(1, #free)), e[1] .. " " .. pr:next(e[2], e[3]))
				break
			end
		end
	end
end

-- a chest's back to its one solid side, else to the north (as goodluck_nether's fortress chests)
local AROUND = {{x = 0, z = -1}, {x = 1, z = 0}, {x = 0, z = 1}, {x = -1, z = 0}}
local function solid(pos)
	local def = core.registered_nodes[core.get_node(pos).name]
	return def and def.walkable and def.drawtype == "normal"
end
local function facing(pos)
	for _, d in ipairs(AROUND) do
		if solid(vector.offset(pos, d.x, 0, d.z)) and not solid(vector.offset(pos, -d.x, 0, -d.z)) then
			return {x = -d.x, z = -d.z}
		end
	end
	return AROUND[1]
end

local logged = {}
core.set_gen_notify({custom = true}, nil, {"goodluck_end:stronghold"})
core.register_on_generated(function(minp, maxp)
	local notes = core.get_mapgen_object("gennotify")
	local made = notes and notes.custom and notes.custom["goodluck_end:stronghold"]
	if not made then
		return
	end
	for _, c in ipairs(made.chests) do
		local d = facing(c)
		core.set_node(c, {name = "default:chest", param2 = core.dir_to_facedir({x = -d.x, y = 0, z = -d.z})})
		fill(c, c.loot)
	end
	for _, pos in ipairs(made.spawners) do
		goodluck_nether.set_spawner(pos, "goodluck_end:silverfish")
	end
	F.each_near(minp.x, minp.z, maxp.x, maxp.z, function(s, i)
		if not logged[i] then
			logged[i] = true
			local b = s.portal.box
			core.log("action", ("[goodluck_end] stronghold at %d,%d,%d: %d pieces, portal room at %d,%d,%d"):format(
				s.pieces[1].box[1], s.pieces[1].box[2], s.pieces[1].box[3], #s.pieces, b[1], b[2], b[3]))
		end
	end)
	core.log("action", ("[goodluck_end] stronghold chunk %d,%d,%d: %d pieces in %d ms"):format(minp.x, minp.y, minp.z,
		made.pieces, made.us / 1000))
end)
