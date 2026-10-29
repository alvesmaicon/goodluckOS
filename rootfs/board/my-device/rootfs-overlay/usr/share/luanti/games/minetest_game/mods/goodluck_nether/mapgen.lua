-- The Nether's ground, in the map generator's threads: in the realm (init.lua) the engine's stone becomes netherrack
-- carved by 3D noise, sampled every 4 nodes across and 8 up and blended in between, as Minecraft does, so that only
-- the blending runs for each node; lava fills what is open up to the sea, bedrock closes the floor and the ceiling in
-- Minecraft's 5 rough layers. Glowstone hangs from the ceilings, fire and mushrooms sit on the floors; the engine then
-- adds the ores and patches, starts the lava springs flowing and lights it all
local R = core.ipc_get("goodluck_nether:realm")
local YMIN, YMAX, SEA = R.ymin, R.ymax, R.sea
-- the grid the noise is sampled on (the row below is written out for 4 across)
local GX, GY = 4, 8
local NOISE = {offset = 0, scale = 1, spread = {x = 48 / GX, y = 32 / GY, z = 48 / GX}, seed = 7420, octaves = 3,
	persistence = 0.5, lacunarity = 2}
-- netherrack where the noise is over this: open in the middle, closing toward the floor and the ceiling
local LIMIT = {}
for h = 0, YMAX - YMIN do
	local t = 0.1
	if h < 32 then
		t = t - (32 - h) / 32 * 1.5
	elseif h > YMAX - YMIN - 32 then
		t = t - (h - (YMAX - YMIN - 32)) / 32 * 1.5
	end
	LIMIT[h] = t
end
local GLOWSTONE_CLUSTERS, GLOWSTONE_GROWTH, FIRE_PATCHES, MUSHROOM_PATCHES = 6, 800, 20, 4

local c_air, c_lava = core.get_content_id("air"), core.get_content_id("default:lava_source")
local c_rack = core.get_content_id("goodluck_nether:netherrack")
local c_bedrock = core.get_content_id("goodluck_nether:bedrock")
local c_glowstone = core.get_content_id("goodluck_nether:glowstone")
local c_fire = core.get_content_id("fire:permanent_flame")
local c_mushrooms = {core.get_content_id("flowers:mushroom_brown"), core.get_content_id("flowers:mushroom_red")}

local data, nvals, plane, row, spots, maps = {}, {}, {}, {}, {}, {}

core.register_on_generated(function(vm, minp, maxp, blockseed)
	if maxp.y < YMIN or minp.y > YMAX then
		return
	end
	local t0 = core.get_us_time()
	local nx, ny, nz = (maxp.x - minp.x + 1) / GX + 1, (maxp.y - minp.y + 1) / GY + 1, (maxp.z - minp.z + 1) / GX + 1
	local size = nx .. "," .. ny .. "," .. nz
	maps[size] = maps[size] or core.get_value_noise_map(NOISE, {x = nx, y = ny, z = nz})
	maps[size]:get_3d_map_flat({x = minp.x / GX, y = minp.y / GY, z = minp.z / GX}, nvals)
	local emin, emax = vm:get_emerged_area()
	local area = VoxelArea(emin, emax)
	local ystride, zstride = area.ystride, area.zstride
	vm:get_data(data)
	local t1 = core.get_us_time()

	local y0, y1 = math.max(minp.y, YMIN), math.min(maxp.y, YMAX)
	local nxy = nx * ny
	for z = minp.z, maxp.z do
		local oz = z - minp.z
		local cz = math.floor(oz / GX)
		local fz = (oz - cz * GX) / GX
		local b0, b1 = cz * nxy, (cz + 1) * nxy
		for i = 1, nxy do
			local a = nvals[b0 + i]
			plane[i] = a + (nvals[b1 + i] - a) * fz
		end
		for y = y0, y1 do
			local oy = y - minp.y
			local cy = math.floor(oy / GY)
			local fy = (oy - cy * GY) / GY
			local t = LIMIT[y - YMIN]
			local p0, p1 = cy * nx, (cy + 1) * nx
			for i = 1, nx do
				local a = plane[p0 + i]
				row[i] = a + (plane[p1 + i] - a) * fy - t
			end
			local empty = y <= SEA and c_lava or c_air
			local vi = area:index(minp.x, y, z)
			for i = 1, nx - 1 do
				local d = row[i]
				local dd = (row[i + 1] - d) * 0.25
				data[vi] = d > 0 and c_rack or empty
				d = d + dd
				data[vi + 1] = d > 0 and c_rack or empty
				d = d + dd
				data[vi + 2] = d > 0 and c_rack or empty
				d = d + dd
				data[vi + 3] = d > 0 and c_rack or empty
				vi = vi + 4
			end
		end
	end
	local t2 = core.get_us_time()

	local rand = PcgRandom(blockseed)
	local placed = {}
	-- the bottom and the top layer whole, each next one in by a fifth less
	for k = 0, 4 do
		for _, y in ipairs({YMIN + k, YMAX - k}) do
			if y >= minp.y and y <= maxp.y then
				for z = minp.z, maxp.z do
					local vi = area:index(minp.x, y, z)
					for x = 0, maxp.x - minp.x do
						if k == 0 or rand:next(0, 4) >= k then
							data[vi + x] = c_bedrock
						end
					end
				end
			end
		end
	end

	local function inside(x, y, z)
		return x >= minp.x and x <= maxp.x and z >= minp.z and z <= maxp.z and y > y0 and y < y1
	end
	-- in a random column, one of its open places right under the netherrack (step up) or on it (step down)
	local function find(step)
		local x, z = rand:next(minp.x + 3, maxp.x - 3), rand:next(minp.z + 3, maxp.z - 3)
		local n, vi = 0, area:index(x, y0 + 1, z)
		for y = y0 + 1, y1 - 1 do
			if data[vi] == c_air and data[vi + step] == c_rack then
				n = n + 1
				spots[n] = y
			end
			vi = vi + ystride
		end
		if n > 0 then
			return x, spots[rand:next(1, n)], z
		end
	end

	-- glowstone grows down from the ceiling, a block wherever an empty one touches just one, as Minecraft grows it
	for _ = 1, GLOWSTONE_CLUSTERS do
		local x, y, z = find(ystride)
		if x then
			data[area:index(x, y, z)] = c_glowstone
			placed.glowstone = (placed.glowstone or 0) + 1
			for _ = 1, GLOWSTONE_GROWTH do
				local px, py, pz = x + rand:next(0, 6) - rand:next(0, 6), y - rand:next(0, 10),
					z + rand:next(0, 6) - rand:next(0, 6)
				if inside(px, py, pz) then
					local i = area:index(px, py, pz)
					if data[i] == c_air then
						local n = (data[i - 1] == c_glowstone and 1 or 0) + (data[i + 1] == c_glowstone and 1 or 0) +
							(data[i - ystride] == c_glowstone and 1 or 0) + (data[i + ystride] == c_glowstone and 1 or 0) +
							(data[i - zstride] == c_glowstone and 1 or 0) + (data[i + zstride] == c_glowstone and 1 or 0)
						if n == 1 then
							data[i] = c_glowstone
							placed.glowstone = placed.glowstone + 1
						end
					end
				end
			end
		end
	end

	-- fire and mushrooms in patches on the netherrack floor
	local function patch(c, tries, label)
		local x, y, z = find(-ystride)
		if not x then
			return
		end
		for _ = 1, tries do
			local px, py, pz = x + rand:next(-3, 3), y + rand:next(-1, 1), z + rand:next(-3, 3)
			if inside(px, py, pz) then
				local i = area:index(px, py, pz)
				if data[i] == c_air and data[i - ystride] == c_rack then
					data[i] = c
					placed[label] = (placed[label] or 0) + 1
				end
			end
		end
	end
	for _ = 1, FIRE_PATCHES do
		patch(c_fire, 12, "fire")
	end
	for _ = 1, MUSHROOM_PATCHES do
		patch(c_mushrooms[1], 6, "mushroom")
		patch(c_mushrooms[2], 6, "mushroom")
	end
	local t3 = core.get_us_time()

	vm:set_data(data)
	core.generate_ores(vm, {x = minp.x, y = y0, z = minp.z}, {x = maxp.x, y = y1, z = maxp.z})
	vm:update_liquids()
	vm:calc_lighting()
	local t4 = core.get_us_time()
	-- what it took and made, for a mod that asks (set_gen_notify)
	core.save_gen_notify("goodluck_nether:chunk", {y = minp.y, read = t1 - t0, shape = t2 - t1, features = t3 - t2,
		engine = t4 - t3, placed = placed})
end)
