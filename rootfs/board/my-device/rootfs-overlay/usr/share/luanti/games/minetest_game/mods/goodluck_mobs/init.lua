-- Monsters chase at 2 nodes a second and walk at 1, half and a quarter of a walking player (4); mobs_monster's run at
-- 3, the sand monster at 4, close to a running player. The entity definitions are what each mob reads its speeds from
local RUN, WALK = 2, 1
-- a mob that takes damage flashes red, as in Minecraft (mobs_redo's mob_hit_effect, on in luanti.conf; its own is orange)
local HURT = "^[colorize:#ff000066"

core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_entities) do
		if name:find("^mobs_monster:") and def.run_velocity then
			def.run_velocity = math.min(def.run_velocity, RUN)
			def.walk_velocity = math.min(def.walk_velocity or WALK, WALK)
		end
		if def._cmi_is_mob and def.initial_properties then
			def.initial_properties.damage_texture_modifier = HURT
		end
	end
end)

if not core.get_modpath("mobs") then return end

-- As on Minecraft Bedrock, monsters under the open sky and in caves have their own caps around the player, so a
-- cave below can't take the surface's
local CAP = {surface = 8, cave = 6}
local RADIUS = 64

local function where(pos)
	return (core.get_natural_light(pos, 0.5) or 0) >= 15 and "surface" or "cave"
end

local function is_monster(ent)
	return ent and ent._cmi_is_mob and ent.type == "monster" and not ent.tamed
end

local function is_animal(ent)
	return ent and ent._cmi_is_mob and ent.type == "animal" and not ent.tamed
end

-- animals born later only top up a place that has fewer than this many (most come with the land, below)
local ANIMALS = 6

-- rats and penguins aren't Minecraft's: none spawn and those in a world leave (end of the file)
local GONE = {["mobs_animal:rat"] = true, ["mobs_animal:penguin"] = true}

local spawn_abm_check = mobs.spawn_abm_check
function mobs:spawn_abm_check(pos, node, name)
	if GONE[name] or spawn_abm_check(self, pos, node, name) then return true end
	local def = core.registered_entities[name]
	if def and def.type == "animal" then
		local n = 0
		for _, obj in ipairs(core.get_objects_inside_radius(pos, RADIUS)) do
			if is_animal(obj:get_luaentity()) then
				n = n + 1
				if n >= ANIMALS then return true end
			end
		end
		return
	end
	if not def or def.type ~= "monster" then return end
	-- as on Minecraft (Java 1.18 on), no monster where any block light reaches: a torch keeps its whole glow clear,
	-- not only the part brighter than 7 (mobs_redo's max_light reads the sun and the torches together)
	local above = vector.offset(pos, 0, 1, 0)
	if core.get_artificial_light(core.get_node(above).param1) > 0 then return true end
	local kind = where(above)
	local n = 0
	for _, obj in ipairs(core.get_objects_inside_radius(pos, RADIUS)) do
		local ent = obj:get_luaentity()
		if is_monster(ent) and where(obj:get_pos()) == kind then
			n = n + 1
			if n >= CAP[kind] then return true end
		end
	end
end

-- As on Minecraft Java, a monster 32 nodes or more from every player for 30 s goes away at 1 in 40 a second, and
-- at once past 128: the monsters stay where the player is, and those left far behind stop running their AI
local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 1 then return end
	timer = 0
	local players = core.get_connected_players()
	for _, ent in pairs(core.luaentities) do
		local pos = is_monster(ent) and not ent._nametag and ent.object:get_pos()
		if pos then
			local far = math.huge
			for _, player in ipairs(players) do
				far = math.min(far, vector.distance(pos, player:get_pos()))
			end
			if far > 128 then
				ent.object:remove()
			elseif far >= 32 and ent.state ~= "attack" then
				ent._goodluck_far = (ent._goodluck_far or 0) + 1
				if ent._goodluck_far > 30 and math.random(40) == 1 then ent.object:remove() end
			else
				ent._goodluck_far = 0
			end
		end
	end
end)

-- As in Minecraft, animals stay put: mobs_redo takes away every untamed one the second time its place unloads
local mob_staticdata = mobs.mob_class.mob_staticdata
function mobs.mob_class:mob_staticdata()
	if self.type == "animal" then self.remove_ok = false end
	return mob_staticdata(self)
end

-- and most of them come with the land: new terrain gets a herd 1 time in 10 for every 16x16 of grass (Minecraft: 1 in
-- 10 a chunk), of one kind in Minecraft's plains mix, 4 together; terrain from before this gets its turn once, when
-- a mapblock of it first loads (such an LBM never runs on new mapblocks: they are stamped with the time they are made)
local HERD = 4
local KINDS = {{"sheep", 12}, {"mobs_animal:pumba", 10}, {"mobs_animal:chicken", 10}, {"mobs_animal:cow", 8}}
-- Minecraft's wool: light grey, grey and black 5 % each, brown 3 %, pink 1 in 600, the rest white
local WOOL = {{"grey", 50}, {"dark_grey", 50}, {"black", 50}, {"brown", 30}, {"pink", 2}}
local GRASS = {"default:dirt_with_grass", "default:dirt_with_dry_grass", "default:dirt_with_coniferous_litter"}

local function pick(list)
	local total = 0
	for _, k in ipairs(list) do total = total + k[2] end
	local r = math.random() * total
	for _, k in ipairs(list) do
		r = r - k[2]
		if r < 0 then return k[1] end
	end
end

local function sheep()
	local r, wool = math.random(1000), "white"
	for _, k in ipairs(WOOL) do
		if r <= k[2] then wool = k[1] break end
		r = r - k[2]
	end
	return "mobs_animal:sheep_" .. wool
end

-- room for an animal standing on this ground, under the sky or near it
local function free(p)
	local a, b = core.get_node(vector.offset(p, 0, 1, 0)), core.get_node(vector.offset(p, 0, 2, 0))
	return a.name == "air" and b.name == "air" and (core.get_natural_light(vector.offset(p, 0, 1, 0), 0.5) or 0) >= 9
end

local function herd(list)
	if #list == 0 or math.random() >= 0.1 * #list / 256 then return end
	local leader = list[math.random(#list)]
	if not free(leader) then return end
	local kind = pick(KINDS)
	local placed = 0
	for _ = 1, HERD * 4 do
		local p = placed == 0 and leader or list[math.random(#list)]
		if vector.distance(p, leader) <= 5 and (placed == 0 or free(p)) then
			local name = kind == "sheep" and sheep() or kind
			local box = core.registered_entities[name].initial_properties.collisionbox
			core.add_entity(vector.offset(p, 0, 1 - box[2], 0), name)
			placed = placed + 1
			if placed == HERD then break end
		end
	end
end

core.register_on_generated(function(minp, maxp)
	if maxp.y < -16 then return end
	local cells = {}
	for _, p in ipairs(core.find_nodes_in_area_under_air(minp, maxp, GRASS)) do
		local key = math.floor(p.x / 16) * 65536 + math.floor(p.z / 16)
		cells[key] = cells[key] or {}
		table.insert(cells[key], p)
	end
	for _, list in pairs(cells) do
		herd(list)
	end
end)

core.register_lbm({
	name = "goodluck_mobs:herds",
	label = "Animals come with the land, as in Minecraft",
	nodenames = GRASS,
	run_at_every_load = false,
	bulk_action = herd,
})

local mob_activate = mobs.mob_class.mob_activate
function mobs.mob_class.mob_activate(self, staticdata, def, dtime)
	if GONE[self.name] then
		self.object:remove()
		return
	end
	return mob_activate(self, staticdata, def, dtime)
end

-- their items, and butter, become what is nearest (a penguin dropped raw chicken)
local ITEMS = {
	["mobs_animal:rat"] = "mobs:chicken_raw",
	["mobs_animal:rat_set"] = "mobs:chicken_raw",
	["mobs_animal:penguin"] = "mobs:chicken_raw",
	["mobs_animal:penguin_set"] = "mobs:chicken_raw",
	["mobs:rat_cooked"] = "mobs:chicken_cooked",
	["mobs:butter"] = "mobs:cheese",
}
for old, new in pairs(ITEMS) do
	if core.registered_items[old] then
		if core.get_all_craft_recipes(old) then
			core.clear_craft({output = old})
		end
		core.unregister_item(old)
	end
	core.register_alias(old, new)
end
