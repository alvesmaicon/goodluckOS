-- Villages as in Minecraft, from Drix03's villages_mtg 1.0.3 (MIT, LICENSE-villages_mtg.md) and its eight buildings: a
-- cross of gravel roads with houses, a blacksmith, a church, a library and fields, chests with loot, and villagers
-- (villagers.lua). Each village is built in the middle of the mapchunk being generated, so all of it fits there; one
-- chance in 2x2 chunks.
goodluck_villages = {}

local modpath = core.get_modpath("goodluck_villages")
dofile(modpath .. "/sleep.lua")
dofile(modpath .. "/villagers.lua")

local CHUNKSIZE = tonumber(core.get_mapgen_setting("chunksize")) or 5
local CHUNK = 16 * CHUNKSIZE
local OFFSET = -16 * math.floor(CHUNKSIZE / 2)
local RADIUS = CHUNK / 2 - 2
local CHANCE = 75
-- the most the ground may rise across the middle, and the room above it the buildings need
local MAX_SLOPE = 20
local HEADROOM = 16
-- how far around a building the ground is sloped to it
local SLOPE = 4

local c_air, c_gravel, c_dirt, c_sand, c_desert_sand
local clear_cids, dirt_cids, sand_cids = {}, {}, {}
-- the voxels being built on: 1.4 million entries for a chunk of 5, let go after each village
local data

local function create_prng(seed)
	local s = math.abs(seed) % 2147483647
	if s == 0 then
		s = 1
	end
	return function(min, max)
		s = (s * 16807) % 2147483647
		if not min then
			return (s - 1) / 2147483646
		end
		if not max then
			max, min = min, 1
		end
		if min > max then
			min, max = max, min
		end
		return min + (s % (max - min + 1))
	end
end

local function overlapping(x1, z1, x2, z2, boxes, margin)
	for _, box in ipairs(boxes) do
		if not (x2 + margin < box.x1 or x1 - margin > box.x2 or z2 + margin < box.z1 or z1 - margin > box.z2) then
			return true
		end
	end
	return false
end

local function surface_y(a, x, z, min_y, max_y)
	for y = max_y, min_y, -1 do
		local cid = data[a:index(x, y, z)]
		if cid ~= c_air and not clear_cids[cid] then
			return y
		end
	end
end

local function terrain_suitable(a, vx, vz, minp, maxp)
	local lo, hi, samples = nil, nil, 0
	for x = math.max(minp.x, vx - 32), math.min(maxp.x, vx + 32), 6 do
		for z = math.max(minp.z, vz - 32), math.min(maxp.z, vz + 32), 6 do
			local sy = surface_y(a, x, z, minp.y, maxp.y)
			if sy then
				if sy < 2 then
					return false
				end
				lo, hi = math.min(lo or sy, sy), math.max(hi or sy, sy)
				if hi - lo > MAX_SLOPE then
					return false
				end
				samples = samples + 1
			end
		end
	end
	return samples > 8
end

local function footprint(a, x1, z1, x2, z2, min_y, max_y)
	local lo, hi, sum, count = nil, nil, 0, 0
	for x = x1, x2 do
		for z = z1, z2 do
			local sy = surface_y(a, x, z, min_y, max_y)
			if sy then
				lo, hi = math.min(lo or sy, sy), math.max(hi or sy, sy)
				sum, count = sum + sy, count + 1
			end
		end
	end
	if count > 0 then
		return {avg_y = math.floor(sum / count), diff = hi - lo}
	end
end

-- Minecraft's village chests: food, tools and iron, a little gold and lapis, diamonds only now and then at the smith,
-- saddles and horse armor
local blacksmith_loot = {
	{name = "default:diamond", min = 1, max = 2, chance = 8},
	{name = "default:mese_crystal", min = 1, max = 2, chance = 10},
	{name = "default:gold_ingot", min = 1, max = 4, chance = 40},
	{name = "default:pick_steel", min = 1, max = 1, chance = 50},
	{name = "default:sword_steel", min = 1, max = 1, chance = 45},
	{name = "default:axe_steel", min = 1, max = 1, chance = 45},
	{name = "default:shovel_steel", min = 1, max = 1, chance = 50},
	{name = "default:steel_ingot", min = 3, max = 8, chance = 80},
	{name = "default:coal_lump", min = 8, max = 16, chance = 85},
	{name = "default:copper_ingot", min = 3, max = 6, chance = 60},
	{name = "default:bronze_ingot", min = 2, max = 5, chance = 50},
	{name = "default:obsidian", min = 1, max = 3, chance = 30},
	{name = "bucket:bucket_empty", min = 1, max = 1, chance = 50},
	{name = "bucket:bucket_water", min = 1, max = 1, chance = 35},
	{name = "farming:bread", min = 4, max = 8, chance = 75},
	{name = "default:torch", min = 8, max = 16, chance = 80},
	-- horse gear, as in the armorer's and toolsmith's chests
	{name = "mobs:saddle", min = 1, max = 1, chance = 30},
	{name = "goodluck_horse:armor_iron", min = 1, max = 1, chance = 15},
	{name = "goodluck_horse:armor_gold", min = 1, max = 1, chance = 10},
	{name = "goodluck_horse:armor_diamond", min = 1, max = 1, chance = 6},
}

local house_loot = {
	{name = "goodluck_lapis:lapis", min = 1, max = 4, chance = 30},
	{name = "default:mese_crystal_fragment", min = 1, max = 4, chance = 30},
	{name = "default:steel_ingot", min = 1, max = 5, chance = 50},
	{name = "default:gold_ingot", min = 1, max = 3, chance = 30},
	{name = "farming:bread", min = 3, max = 10, chance = 95},
	{name = "default:apple", min = 3, max = 12, chance = 90},
	{name = "farming:wheat", min = 4, max = 16, chance = 90},
	{name = "farming:seed_wheat", min = 4, max = 12, chance = 85},
	{name = "farming:seed_cotton", min = 2, max = 8, chance = 70},
	{name = "default:coal_lump", min = 4, max = 16, chance = 90},
	{name = "default:torch", min = 8, max = 24, chance = 95},
	{name = "default:wood", min = 8, max = 24, chance = 85},
	{name = "default:book", min = 1, max = 4, chance = 60},
	{name = "default:paper", min = 4, max = 16, chance = 75},
	{name = "farming:string", min = 2, max = 8, chance = 70},
	{name = "default:flint", min = 2, max = 6, chance = 70},
	{name = "mobs:saddle", min = 1, max = 1, chance = 15},
}

local function fill_chest(pos, blacksmith, pr)
	local def = core.registered_nodes[core.get_node(pos).name]
	if def and def.on_construct then
		def.on_construct(pos)
	end
	local inv = core.get_meta(pos):get_inventory()
	inv:set_size("main", 8 * 4)
	local pool = blacksmith and blacksmith_loot or house_loot
	local free = {}
	for s = 1, 32 do
		free[s] = s
	end
	for _ = 1, blacksmith and pr(12, 16) or pr(8, 14) do
		local entry = pool[pr(1, #pool)]
		if pr(1, 100) <= entry.chance and core.registered_items[entry.name] then
			local slot = table.remove(free, pr(1, #free))
			inv:set_stack("main", slot, ItemStack(entry.name .. " " .. pr(entry.min, entry.max)))
		end
	end
end

local function foundation_cid(pos, sample)
	if sample and sand_cids[sample] then
		return sample
	end
	local b = core.get_biome_data(pos)
	local name = b and core.get_biome_name(b.biome):lower() or ""
	if name:find("desert") then
		return c_desert_sand
	elseif name:find("dune") or name:find("sand") then
		return c_sand
	end
	return c_dirt
end

local function tree_path(pos)
	local b = core.get_biome_data(pos)
	local name = b and core.get_biome_name(b.biome):lower() or ""
	local file = "apple_tree.mts"
	if name:find("snow") or name:find("taiga") or name:find("pine") or name:find("cold") then
		file = "pine_tree.mts"
	elseif name:find("savanna") or name:find("dry") or name:find("desert") then
		file = "acacia_tree.mts"
	elseif name:find("aspen") or name:find("birch") then
		file = "aspen_tree.mts"
	elseif name:find("jungle") then
		file = "jungle_tree.mts"
	end
	return core.get_modpath("default") .. "/schematics/" .. file
end

-- the buildings, and who lives in each (villagers.lua): one villager a bed, traders by trade
local specials = {"herreria.mts", "iglesia.mts", "libreria_casa.mts", "cultivos.mts", "cultivos_dobles.mts"}
local houses = {"casa.mts", "small_house1.mts", "small_house2.mts"}
local residents = {
	["herreria.mts"] = {"armorer", "toolsmith"},
	["iglesia.mts"] = {"cleric"},
	["libreria_casa.mts"] = {"librarian"},
	["cultivos.mts"] = {"farmer"},
	["cultivos_dobles.mts"] = {"farmer"},
}
local schematics = {}

core.register_on_mods_loaded(function()
	c_air = core.get_content_id("air")
	c_gravel = core.get_content_id("default:gravel")
	c_dirt = core.get_content_id("default:dirt")
	c_sand = core.get_content_id("default:sand")
	c_desert_sand = core.get_content_id("default:desert_sand")
	for name, def in pairs(core.registered_nodes) do
		local id = core.get_content_id(name)
		local g = def.groups or {}
		-- what isn't the ground: plants, snow layers, leaves, trunks (by kind: a name with "grass" or "snow" was
		-- the grass block and the snowy dirt too, and villages sank a node into them)
		if def.liquidtype == "none" and (def.buildable_to or not def.walkable or g.flora or g.plant or g.leaves or
				g.tree or g.flower or g.sapling or g.attached_node or def.drawtype == "plantlike" or
				def.drawtype == "plantlike_rooted") then
			clear_cids[id] = true
		end
		if g.soil or name:find("dirt") then
			dirt_cids[id] = true
		end
		if g.sand or name:find("sand") then
			sand_cids[id] = true
		end
	end
	for _, list in ipairs({specials, houses}) do
		for _, file in ipairs(list) do
			local path = modpath .. "/schems/" .. file
			local schem = core.read_schematic(path, {})
			if schem then
				schematics[file] = {path = path, size = schem.size}
			end
		end
	end
end)

-- houses along four roads from the middle, the special buildings first, each at the height of the road before its
-- door (a node up where its ground is higher), on a foundation, with the ground around cut and filled in slopes so
-- no wall of earth shuts its door
local function layout(vx, vz, pr, minp, maxp, a, along)
	local placements, trees = {}, {}
	local boxes = {
		{x1 = vx - 1, z1 = vz - RADIUS, x2 = vx + 1, z2 = vz + RADIUS},
		{x1 = vx - RADIUS, z1 = vz - 1, x2 = vx + RADIUS, z2 = vz + 1},
	}
	local todo = {}
	for _, file in ipairs(specials) do
		todo[#todo + 1] = file
	end
	for i = #todo, 2, -1 do
		local j = pr(1, i)
		todo[i], todo[j] = todo[j], todo[i]
	end
	local placed, failed = 0, 0

	for _, arm in ipairs({{dx = 1, dz = 0}, {dx = -1, dz = 0}, {dx = 0, dz = 1}, {dx = 0, dz = -1}}) do
		local dist = 7
		while dist < RADIUS - 5 do
			local special = #todo > 0 and placed % 2 == 0
			local file = special and todo[1] or houses[pr(1, #houses)]
			local info = schematics[file]
			local step = 3
			if info then
				local side = pr(1, 2) == 1 and 1 or -1
				local rot, sx, sz, px, pz
				if arm.dx ~= 0 then
					rot = side == 1 and "0" or "180"
					sx, sz = info.size.x, info.size.z
					px = vx + arm.dx * dist - (arm.dx < 0 and sx or 0)
					pz = side == 1 and vz + 3 or vz - 3 - sz
				else
					rot = side == 1 and "90" or "270"
					sx, sz = info.size.z, info.size.x
					pz = vz + arm.dz * dist - (arm.dz < 0 and sz or 0)
					px = side == 1 and vx + 3 or vx - 3 - sx
				end
				local ok = false
				if px >= minp.x + 2 and px + sx <= maxp.x - 2 and pz >= minp.z + 2 and pz + sz <= maxp.z - 2 and
						not overlapping(px, pz, px + sx - 1, pz + sz - 1, boxes, 2) then
					local t = footprint(a, px, pz, px + sx - 1, pz + sz - 1, minp.y, maxp.y)
					local cx, cz = px + math.floor(sx / 2), pz + math.floor(sz / 2)
					local road = arm.dx ~= 0 and along.x[cx] or along.z[cz]
					if t and road and t.diff <= 6 and t.avg_y - road <= 3 and road - t.avg_y <= 4 then
						-- on ground higher than the road a node up, the step before the door climbs it
						local y = t.avg_y > road and road + 1 or road
						local base = foundation_cid({x = cx, y = y, z = cz}, data[a:index(cx, y, cz)])
						local top = math.min(maxp.y, y + info.size.y + HEADROOM / 2)
						for fx = math.max(minp.x, px - 1 - SLOPE), math.min(maxp.x, px + sx + SLOPE) do
							for fz = math.max(minp.z, pz - 1 - SLOPE), math.min(maxp.z, pz + sz + SLOPE) do
								-- d: how far out of the building and the row around it
								local d = math.max(px - 1 - fx, fx - px - sx, pz - 1 - fz, fz - pz - sz, 0)
								if d == 0 or not overlapping(fx, fz, fx, fz, boxes, 0) then
									for fy = y + 1 + d, top do
										data[a:index(fx, fy, fz)] = c_air
									end
									for fy = math.max(minp.y, surface_y(a, fx, fz, minp.y, y - d) or y - d), y - d do
										data[a:index(fx, fy, fz)] = base
									end
								end
							end
						end
						placements[#placements + 1] = {pos = {x = px, y = y + 1, z = pz}, path = info.path, rot = rot,
							file = file, sx = sx, sy = info.size.y, sz = sz}
						boxes[#boxes + 1] = {x1 = px, z1 = pz, x2 = px + sx - 1, z2 = pz + sz - 1}
						if special then
							table.remove(todo, 1)
							failed = 0
						end
						placed = placed + 1
						step = (arm.dx ~= 0 and sx or sz) + pr(2, 4)
						ok = true
					end
				end
				-- a special building that doesn't fit three times goes to the back of the queue
				if not ok and special then
					failed = failed + 1
					if failed >= 3 and #todo > 1 then
						todo[#todo + 1] = table.remove(todo, 1)
						failed = 0
					end
				end
			else
				step = 8
			end
			dist = dist + step
		end
	end

	-- a few trees of the biome between the houses
	local path = tree_path({x = vx, y = 0, z = vz})
	for _ = 1, pr(12, 20) do
		local tx, tz = vx + pr(-RADIUS + 6, RADIUS - 6), vz + pr(-RADIUS + 6, RADIUS - 6)
		if tx >= minp.x + 3 and tx <= maxp.x - 3 and tz >= minp.z + 3 and tz <= maxp.z - 3 and
				not overlapping(tx - 2, tz - 2, tx + 2, tz + 2, boxes, 1) then
			local ty = surface_y(a, tx, tz, minp.y, maxp.y)
			if ty and dirt_cids[data[a:index(tx, ty, tz)]] then
				trees[#trees + 1] = {pos = {x = tx, y = ty + 1, z = tz}, path = path, rot = tostring(pr(0, 3) * 90)}
				boxes[#boxes + 1] = {x1 = tx - 2, z1 = tz - 2, x2 = tx + 2, z2 = tz + 2}
			end
		end
	end
	return placements, trees
end

-- the roads: from the middle out, gravel at most a node up or down from the last (villagers walk them), the ground
-- under them filled and cleared over them; their height along each axis
local function roads(a, vx, vy, vz, minp, maxp)
	local along = {x = {[vx] = vy}, z = {[vz] = vy}}
	local base = foundation_cid({x = vx, y = vy, z = vz}, data[a:index(vx, vy, vz)])
	local function lay(x, z, y)
		if x < minp.x or x > maxp.x or z < minp.z or z > maxp.z then
			return
		end
		for fy = math.max(minp.y, surface_y(a, x, z, minp.y, y) or y), y - 1 do
			data[a:index(x, fy, z)] = base
		end
		data[a:index(x, y, z)] = c_gravel
		for fy = y + 1, math.min(maxp.y, y + 4) do
			data[a:index(x, fy, z)] = c_air
		end
	end
	for _, arm in ipairs({{dx = 1, dz = 0}, {dx = -1, dz = 0}, {dx = 0, dz = 1}, {dx = 0, dz = -1}}) do
		local y = vy
		for d = 0, RADIUS do
			local cx, cz = vx + arm.dx * d, vz + arm.dz * d
			local sy = d > 1 and surface_y(a, cx, cz, minp.y, maxp.y)
			if sy then
				y = math.max(y - 1, math.min(y + 1, sy))
			end
			y = math.max(minp.y + 1, math.min(maxp.y - HEADROOM, y))
			if arm.dx ~= 0 then
				along.x[cx] = y
			else
				along.z[cz] = y
			end
			for w = -1, 1 do
				lay(cx + arm.dz * w, cz + arm.dx * w, y)
			end
		end
	end
	return along
end

local function build(vm, emin, emax, minp, maxp, vx, vy, vz, seed)
	local a = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local pr = create_prng(seed)
	local along = roads(a, vx, vy, vz, minp, maxp)
	local placements, trees = layout(vx, vz, pr, minp, maxp, a, along)
	vm:set_data(data)
	for _, p in ipairs(placements) do
		core.place_schematic_on_vmanip(vm, p.pos, p.path, p.rot, {}, true)
	end
	for _, t in ipairs(trees) do
		core.place_schematic_on_vmanip(vm, t.pos, t.path, t.rot, {}, false)
	end
	vm:calc_lighting()
	vm:write_to_map()

	local spawns = {}
	for _, p in ipairs(placements) do
		local p2 = {x = p.pos.x + p.sx - 1, y = p.pos.y + p.sy - 1, z = p.pos.z + p.sz - 1}
		for _, c in ipairs(core.find_nodes_in_area(p.pos, p2, {"default:chest", "group:chest"})) do
			fill_chest(c, p.file == "herreria.mts", pr)
		end
		-- the smith's porch: an anvil where the building has a stone block, by the armorer
		if p.file == "herreria.mts" and core.registered_nodes["goodluck_anvil:anvil"] then
			for _, b in ipairs(core.find_nodes_in_area(p.pos, p2, {"default:stone_block"})) do
				core.set_node(b, {name = "goodluck_anvil:anvil", param2 = pr(0, 3)})
			end
		end
		-- traders by trade; in a house, one villager a bed
		for _, job in ipairs(residents[p.file] or {}) do
			spawns[#spawns + 1] = {p.pos, p2, job}
		end
		if not residents[p.file] then
			for _, bed in ipairs(core.find_nodes_in_area(p.pos, p2, {"beds:bed_bottom"})) do
				spawns[#spawns + 1] = {vector.offset(bed, -2, 0, -2), vector.offset(bed, 2, 1, 2), "villager", bed}
			end
		end
	end
	core.after(0, function()
		for _, s in ipairs(spawns) do
			goodluck_villages.spawn(s[1], s[2], s[3], s[4])
		end
	end)
	return #placements, #spawns
end

local function chunk_index(v)
	return math.floor((v - OFFSET) / CHUNK)
end

core.register_on_generated(function(minp, maxp, blockseed)
	if chunk_index(minp.x) % 2 ~= 0 or chunk_index(minp.z) % 2 ~= 0 then
		return
	end
	local pr = create_prng(blockseed)
	if pr(1, 100) > CHANCE then
		return
	end
	local t0 = core.get_us_time()
	local vx, vz = minp.x + CHUNK / 2, minp.z + CHUNK / 2
	-- the ground has to be in this chunk with room above it, not buried under the next one: the heightmap tells it
	-- before the voxels are read (chunks under the ground or in the sky end here)
	local heightmap = core.get_mapgen_object("heightmap")
	local h = heightmap and heightmap[(vz - minp.z) * CHUNK + (vx - minp.x) + 1]
	if h and (h < math.max(2, minp.y) or h > maxp.y - HEADROOM) then
		return
	end
	local vm, emin, emax = core.get_mapgen_object("voxelmanip")
	if not vm then
		return
	end
	local a = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	data = vm:get_data()
	local vy = surface_y(a, vx, vz, minp.y, maxp.y)
	if not vy or vy < 2 or vy > maxp.y - HEADROOM or not terrain_suitable(a, vx, vz, minp, maxp) then
		data = nil
		return
	end
	local buildings, villagers = build(vm, emin, emax, minp, maxp, vx, vy, vz, blockseed)
	data = nil
	core.log("action", ("[goodluck_villages] village at %d,%d,%d: %d buildings, %d villagers, %d ms"):format(
		vx, vy, vz, buildings, villagers, (core.get_us_time() - t0) / 1000))
end)

-- the same village where the player stands, for whoever may run /village
function goodluck_villages.build_at(pos)
	local minp = vector.offset(vector.round(pos), -CHUNK / 2, -20, -CHUNK / 2)
	local maxp = vector.offset(minp, CHUNK - 1, 60, CHUNK - 1)
	local vm = core.get_voxel_manip()
	local emin, emax = vm:read_from_map(minp, maxp)
	data = vm:get_data()
	local buildings, villagers = build(vm, emin, emax, minp, maxp, minp.x + CHUNK / 2, vector.round(pos).y - 1,
		minp.z + CHUNK / 2, math.random(1, 2147483646))
	data = nil
	return buildings, villagers
end

core.register_chatcommand("village", {
	description = core.translate("goodluck_villages", "Build a village here"),
	privs = {server = true},
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then
			return false
		end
		goodluck_villages.build_at(player:get_pos())
		return true
	end,
})
