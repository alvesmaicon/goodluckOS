-- Ruined portals as in Minecraft (1.16): an obsidian frame with blocks missing, some crying obsidian, on a rough base
-- of stone bricks (polished blackstone in the Nether) with netherrack and magma spread on the ground around, now and
-- then a block of gold or lava, and a chest of mostly golden loot. At most one in each region of 6x6 mapchunks in the
-- Overworld (480 nodes; Minecraft's are 640 apart) and 5x5 in the Nether (400, as Minecraft's): on the land, partly
-- buried, deep underground in a pocket of air, on the sea floor, half in the desert's sand, mossy in the jungle, some
-- lying fallen, a few giant. Each is built after its mapchunk, in a small box read around it
local R = goodluck_nether
local CHUNK = 16 * (tonumber(core.get_mapgen_setting("chunksize")) or 5)
local OFFSET = -16 * math.floor(CHUNK / 32)
local SEED = (tonumber(core.get_mapgen_setting("seed")) or 0) % 2147483647
local RAD = 7
local OBSIDIAN, CRYING = "default:obsidian", "goodluck_nether:crying_obsidian"

-- Minecraft's chests/ruined_portal: 4 to 8 draws by weight, the golden gear enchanted at random; what the game lacks
-- (iron nuggets, fire charge, clock, bell, glistering melon, the pressure plate) stays out
local LOOT = {
	{"default:obsidian", 1, 2, 40}, {"default:flint", 1, 4, 40}, {"fire:flint_and_steel", 1, 1, 40},
	{"goodluck_horse:golden_apple", 1, 1, 15}, {"goodluck_food:gold_nugget", 4, 24, 15},
	{"default:sword_gold", 1, 1, 15, true}, {"default:axe_gold", 1, 1, 15, true}, {"farming:hoe_gold", 1, 1, 15, true},
	{"default:shovel_gold", 1, 1, 15, true}, {"default:pick_gold", 1, 1, 15, true},
	{"3d_armor:boots_gold", 1, 1, 15, true}, {"3d_armor:chestplate_gold", 1, 1, 15, true},
	{"3d_armor:helmet_gold", 1, 1, 15, true}, {"3d_armor:leggings_gold", 1, 1, 15, true},
	{"goodluck_horse:armor_gold", 1, 1, 5}, {"goodluck_food:golden_carrot", 4, 12, 5}, {"default:gold_ingot", 2, 8, 5},
	{"default:goldblock", 1, 2, 1},
}
core.register_on_mods_loaded(function()
	for i = #LOOT, 1, -1 do
		if not core.registered_items[LOOT[i][1]] then
			table.remove(LOOT, i)
		end
	end
end)

local function fill(pos, pr)
	local inv = core.get_meta(pos):get_inventory()
	local size, total = inv:get_size("main"), 0
	for _, e in ipairs(LOOT) do
		total = total + e[4]
	end
	local free = {}
	for s = 1, size do
		free[s] = s
	end
	for _ = 1, pr:next(4, 8) do
		local roll = pr:next(1, total)
		for _, e in ipairs(LOOT) do
			roll = roll - e[4]
			if roll <= 0 then
				local stack = ItemStack(e[1] .. " " .. pr:next(e[2], e[3]))
				if e[5] and goodluck_enchanting then
					stack = goodluck_enchanting.enchant(e[1], pr:next(0, 15))
				end
				if #free > 0 then
					inv:set_stack("main", table.remove(free, pr:next(1, #free)), stack)
				end
				break
			end
		end
	end
end

local function solid(name)
	local def = core.registered_nodes[name]
	return def and def.walkable and def.liquidtype == "none" and not def.buildable_to
end

-- the ruin at ground (the top of the ground it stands on): kind is "land", "buried", "underground", "sea", "desert",
-- "jungle" or "nether"
local function build(ground, kind, pr)
	local nether, mossy = kind == "nether", kind == "jungle"
	local giant = pr:next(1, 100) <= 5
	local w, h = giant and pr:next(4, 6) or pr:next(2, 3), giant and pr:next(5, 8) or pr:next(3, 4)
	local fallen = not giant and pr:next(1, 100) <= 25
	local along = pr:next(0, 1) == 0 and {x = 1, z = 0} or {x = 0, z = 1}
	local across = {x = along.z, z = along.x}
	-- half of a buried frame shows
	local sink = (kind == "buried" or kind == "desert") and math.floor(h / 2) or pr:next(0, 1)
	local p1, p2 = vector.offset(ground, -RAD, -6, -RAD), vector.offset(ground, RAD, 12, RAD)
	local vm = core.get_voxel_manip()
	local e1, e2 = vm:read_from_map(p1, p2)
	local area = VoxelArea(e1, e2)
	local data = vm:get_data()
	local id = core.get_content_id
	local c_air, c_rack, c_magma = id("air"), id("goodluck_nether:netherrack"), id("goodluck_nether:magma")
	local function set(x, y, z, name)
		if area:contains(x, y, z) then
			data[area:index(x, y, z)] = id(name)
		end
	end
	local function get(x, y, z)
		return area:contains(x, y, z) and core.get_name_from_content_id(data[area:index(x, y, z)]) or "ignore"
	end
	-- the ground's top in a column, near the ruin's own (not a tree's)
	local function top(x, z)
		for y = ground.y + 4, ground.y - 5, -1 do
			local name = get(x, y, z)
			if solid(name) and not solid(get(x, y + 1, z)) and core.get_item_group(name, "leaves") == 0 and
					core.get_item_group(name, "tree") == 0 then
				return y
			end
		end
	end

	-- deep underground, a pocket of air around it
	if kind == "underground" then
		for x = -RAD + 1, RAD - 1 do
			for z = -RAD + 1, RAD - 1 do
				for y = 1, h + 3 do
					if (x / (RAD - 1)) ^ 2 + (z / (RAD - 1)) ^ 2 + ((y - 1) / (h + 3)) ^ 2 <= 1 then
						set(ground.x + x, ground.y + y, ground.z + z, "air")
					end
				end
			end
		end
	end

	-- netherrack spread on the ground around, thinning out, a magma block here and there; in the Nether magma alone
	for x = -RAD, RAD do
		for z = -RAD, RAD do
			local d = math.sqrt(x * x + z * z) / RAD
			local y = top(ground.x + x, ground.z + z)
			if y and d < 1 and pr:next(1, 100) <= (1 - d) * (nether and 15 or 100) then
				data[area:index(ground.x + x, y, ground.z + z)] = (nether or pr:next(1, 100) <= 8) and c_magma or c_rack
			end
		end
	end

	-- the base: bricks along the frame's foot, two to three wide
	local a0 = -math.floor(w / 2)
	local base = {}
	local function brick()
		if nether then
			return pr:next(1, 100) <= 60 and "goodluck_nether:polished_blackstone_bricks" or "goodluck_nether:blackstone"
		end
		return mossy and pr:next(1, 100) <= 40 and "default:mossycobble" or "default:stonebrick"
	end
	local by = ground.y - sink
	for a = a0 - 2, a0 + w + 1 do
		for c = -2, 2 do
			if (math.abs(c) <= 1 or pr:next(1, 100) <= 40) and pr:next(1, 100) <= 75 then
				local x, z = ground.x + along.x * a + across.x * c, ground.z + along.z * a + across.z * c
				set(x, by, z, brick())
				base[#base + 1] = {x = x, y = by, z = z, c = c}
			end
		end
	end

	-- the frame, upright or lying, with blocks missing (some fallen beside it) and some crying obsidian
	local frame = {}
	for a = a0 - 1, a0 + w do
		for b = -1, h do
			local edge = a == a0 - 1 or a == a0 + w or b == -1 or b == h
			local corner = (a == a0 - 1 or a == a0 + w) and (b == -1 or b == h)
			if edge and (not corner or pr:next(1, 100) <= 50) then
				local x, y, z
				if fallen then
					x, y, z = ground.x + along.x * a + across.x * (b + 1), by + 1, ground.z + along.z * a + across.z * (b + 1)
				else
					x, y, z = ground.x + along.x * a, by + 1 + b, ground.z + along.z * a
				end
				frame[#frame + 1] = {x = x, y = y, z = z}
			end
		end
	end
	local missing = 0
	for i, f in ipairs(frame) do
		local r = pr:next(1, 100)
		if r <= 22 or i == #frame and missing == 0 then
			missing = missing + 1
			local b = base[pr:next(1, #base)]
			if b and pr:next(1, 2) == 1 then
				set(b.x, b.y + 1, b.z, OBSIDIAN)
			end
		else
			set(f.x, f.y, f.z, r <= 37 and CRYING or OBSIDIAN)
		end
	end
	if mossy then
		for _ = 1, pr:next(3, 6) do
			local f = frame[pr:next(1, #frame)]
			if get(f.x, f.y + 1, f.z) == "air" then
				set(f.x, f.y + 1, f.z, "default:jungleleaves")
			end
		end
	end
	if pr:next(1, 100) <= 30 and #base > 0 then
		local b = base[pr:next(1, #base)]
		set(b.x, b.y + 1, b.z, "default:goldblock")
	end

	vm:set_data(data)
	vm:write_to_map(true)

	-- lava in the base, and the chest beside the frame, after the write so that they run as placed
	if pr:next(1, 100) <= 20 and #base > 0 then
		local b = base[pr:next(1, #base)]
		core.set_node(b, {name = "default:lava_source"})
	end
	-- a fallen frame lies on the +across side
	local side = (fallen or pr:next(0, 1) == 0) and -2 or 2
	local chest = {x = ground.x + along.x * pr:next(a0, a0 + w - 1) + across.x * side, y = by + 1,
		z = ground.z + along.z * pr:next(a0, a0 + w - 1) + across.z * side}
	if solid(core.get_node(vector.offset(chest, 0, -1, 0)).name) then
		core.set_node(chest, {name = "default:chest", param2 = pr:next(0, 3)})
		fill(chest, pr)
	end
	return {w = w, h = h, fallen = fallen, giant = giant}
end

function goodluck_nether.ruin_at(pos, kind)
	return build(vector.round(pos), kind or "land", PcgRandom(core.get_us_time() % 2147483647))
end

local function chunk_index(v)
	return math.floor((v - OFFSET) / CHUNK)
end

core.register_on_generated(function(minp, maxp)
	local nether = maxp.y >= R.ymin and minp.y <= R.ymax
	-- nor in goodluck_end's End, far over the world
	local the_end = rawget(_G, "goodluck_end") and goodluck_end.inside and goodluck_end.inside(minp)
	if not nether and (minp.y < -200 or the_end) then
		return
	end
	local n = nether and 5 or 6
	local cx, cz = chunk_index(minp.x), chunk_index(minp.z)
	local rx, rz = math.floor(cx / n), math.floor(cz / n)
	-- never negative: the engine takes the seed as an unsigned number, and every negative one as the same
	local pr = PcgRandom((SEED + rx * 7349 + rz * 21911 + (nether and 104729 or 0)) % 2147483647)
	if cx - rx * n ~= pr:next(0, n - 1) or cz - rz * n ~= pr:next(0, n - 1) then
		return
	end
	local x, z = minp.x + pr:next(RAD + 4, CHUNK - RAD - 5), minp.z + pr:next(RAD + 4, CHUNK - RAD - 5)
	local ground, kind
	if nether then
		-- one of the two realm mapchunks; a floor with room above in its column or one near it
		if chunk_index(minp.y) % 2 ~= pr:next(0, 1) then
			return
		end
		for _ = 1, 8 do
			local floors = {}
			for y = minp.y + 6, maxp.y - 14 do
				if core.get_node({x = x, y = y, z = z}).name == "goodluck_nether:netherrack" and
						core.get_node({x = x, y = y + 1, z = z}).name == "air" and
						core.get_node({x = x, y = y + 6, z = z}).name == "air" then
					floors[#floors + 1] = y
				end
			end
			if #floors > 0 then
				ground, kind = {x = x, y = floors[pr:next(1, #floors)], z = z}, "nether"
				break
			end
			x, z = minp.x + pr:next(RAD + 4, CHUNK - RAD - 5), minp.z + pr:next(RAD + 4, CHUNK - RAD - 5)
		end
	else
		local heightmap = core.get_mapgen_object("heightmap")
		local y = heightmap and heightmap[(z - minp.z) * CHUNK + (x - minp.x) + 1]
		if not y or y < minp.y + 8 or y > maxp.y - 14 then
			return
		end
		ground = {x = x, y = y, z = z}
		local biome = core.get_biome_name(core.get_biome_data(ground).biome) or ""
		local roll = pr:next(1, 100)
		if y < 0 then
			kind = "sea"
		elseif biome:find("desert") then
			kind = "desert"
		elseif roll <= 25 and y - 20 > minp.y + 8 then
			kind = "underground"
			ground.y = y - pr:next(12, math.min(20, y - minp.y - 8))
		elseif roll <= 50 then
			kind = "buried"
		else
			kind = biome:find("rainforest") and "jungle" or "land"
		end
	end
	if not ground then
		return
	end
	local r = build(ground, kind, pr)
	core.log("action", ("[goodluck_nether] ruined portal at %s: %s%s%s, %dx%d"):format(core.pos_to_string(ground), kind,
		r.fallen and ", fallen" or "", r.giant and ", giant" or "", r.w + 2, r.h + 2))
end)
