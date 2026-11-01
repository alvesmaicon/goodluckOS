-- The End's ground, in the map generator's threads: Minecraft's density (the islands of islands.lua; its 3D noise
-- on top; pulled down below 32 and above 56 up), sampled every 8 nodes across and 4 up and blended in between as
-- Minecraft does, end stone where it is over 0. Then the ten obsidian pillars with bedrock on top (two caged in iron
-- bars) and the exit portal's podium, inactive, on the ground at the middle. The crystals go on the pillars in the
-- game (realm.lua), told by gen_notify. Out past 1024, each chunk of 16 decorated as its biome is in Minecraft:
-- small islands in small_end_islands, chorus plants and, rarely, a gateway back to the middle in the highlands
local R = core.ipc_get("goodluck_end:realm")
local YMIN, YMAX = R.ymin, R.ymax
local ISL = goodluck_end_islands
local SEED = (tonumber(core.get_mapgen_setting("seed")) or 0) % 2147483647
local GX, GY = 8, 4
local NOISE = {offset = 0, scale = 0.25, spread = {x = 96 / GX, y = 48 / GY, z = 96 / GX}, seed = 7480, octaves = 4,
	persistence = 0.5, lacunarity = 2}
-- the islands' value under which the noise (0.47 at most) leaves no stone
local EMPTY = -0.5

local c_air = core.CONTENT_AIR
local c_stone = core.get_content_id("goodluck_end:end_stone")
local c_obsidian = core.get_content_id("default:obsidian")
local c_bedrock = core.get_content_id("goodluck_nether:bedrock")
local c_bars = core.get_content_id("xpanes:bar")
local c_fire = core.get_content_id("fire:permanent_flame")
local c_torch = core.get_content_id("default:torch_wall")
local c_plant = core.get_content_id("goodluck_end:chorus_plant")
local c_dead = core.get_content_id("goodluck_end:chorus_flower_dead")
local c_gateway = core.get_content_id("goodluck_end:gateway")

-- Minecraft's density at a grid point, before its squeeze, from the islands' value there (cols, by column)
local function density(island, jy, n)
	local v = island + n
	local top = math.max(0, math.min(1, 1 - (jy - 56) / 256))
	v = -23.4375 + top * (v + 23.4375)
	local low = math.max(0, math.min(1, (jy - 4) / 28))
	return (-0.234375 + low * (v + 0.234375)) * 0.64
end

local data, nvals, grid, plane, row, maps, cols = {}, {}, {}, {}, {}, {}, {}

local function shape(vm, minp, maxp, area)
	local y0, y1 = math.max(minp.y, YMIN), math.min(maxp.y, YMIN + 100)
	if y0 > y1 then
		return 0
	end
	local nx, ny, nz = (maxp.x - minp.x + 1) / GX + 1, (maxp.y - minp.y + 1) / GY + 1, (maxp.z - minp.z + 1) / GX + 1
	local size = nx .. "," .. ny .. "," .. nz
	maps[size] = maps[size] or core.get_value_noise_map(NOISE, {x = nx, y = ny, z = nz})
	maps[size]:get_3d_map_flat({x = minp.x / GX, y = minp.y / GY, z = minp.z / GX}, nvals)
	-- the density at every grid point
	local i = 0
	for gz = 0, nz - 1 do
		for gy = 0, ny - 1 do
			for gx = 0, nx - 1 do
				i = i + 1
				grid[i] = density(cols[gz * nx + gx + 1], minp.y + gy * GY - YMIN, nvals[i])
			end
		end
	end
	local nxy, made = nx * ny, 0
	for z = minp.z, maxp.z do
		local oz = z - minp.z
		local cz = math.floor(oz / GX)
		local fz = (oz - cz * GX) / GX
		local b0, b1 = cz * nxy, (cz + 1) * nxy
		for k = 1, nxy do
			local a = grid[b0 + k]
			plane[k] = a + (grid[b1 + k] - a) * fz
		end
		for y = y0, y1 do
			local oy = y - minp.y
			local cy = math.floor(oy / GY)
			local fy = (oy - cy * GY) / GY
			local p0, p1 = cy * nx, (cy + 1) * nx
			for k = 1, nx do
				local a = plane[p0 + k]
				row[k] = a + (plane[p1 + k] - a) * fy
			end
			local vi = area:index(minp.x, y, z)
			for k = 1, nx - 1 do
				local d, e = row[k], row[k + 1]
				if d > 0 or e > 0 then
					local dd = (e - d) / GX
					for o = 0, GX - 1 do
						if d > 0 then
							data[vi + o] = c_stone
							made = made + 1
						end
						d = d + dd
					end
				end
				vi = vi + GX
			end
		end
	end
	return made
end

-- Minecraft's spikes: obsidian where the column's low corner is within r of the middle (r * r + 1), up to under the
-- top; air above it to 10 over the top (from 66 up); the cage of the two guarded ones
local function spikes(vm, minp, maxp, area, out)
	for _, s in ipairs(R.spikes) do
		local r = s.radius
		if s.x + r >= minp.x and s.x - r <= maxp.x and s.z + r >= minp.z and s.z - r <= maxp.z then
			local top = YMIN + s.height
			for z = math.max(minp.z, s.z - r), math.min(maxp.z, s.z + r) do
				for x = math.max(minp.x, s.x - r), math.min(maxp.x, s.x + r) do
					if (x - s.x) ^ 2 + (z - s.z) ^ 2 <= r * r + 1 then
						for y = math.max(minp.y, YMIN), math.min(maxp.y, top + 10) do
							if y < top then
								data[area:index(x, y, z)] = c_obsidian
							elseif y - YMIN > 65 then
								data[area:index(x, y, z)] = c_air
							end
						end
					end
				end
			end
			if s.guarded then
				for dx = -2, 2 do
					for dz = -2, 2 do
						for dy = 0, 3 do
							if math.abs(dx) == 2 or math.abs(dz) == 2 or dy == 3 then
								local p = {x = s.x + dx, y = top + dy, z = s.z + dz}
								if area:contains(p.x, p.y, p.z) and p.x >= minp.x and p.x <= maxp.x and p.y >= minp.y and
										p.y <= maxp.y and p.z >= minp.z and p.z <= maxp.z then
									data[area:index(p.x, p.y, p.z)] = c_bars
								end
							end
						end
					end
				end
			end
			local b = {x = s.x, y = top, z = s.z}
			if b.x >= minp.x and b.x <= maxp.x and b.y >= minp.y and b.y + 1 <= maxp.y and b.z >= minp.z and
					b.z <= maxp.z then
				data[area:index(b.x, b.y, b.z)] = c_bedrock
				data[area:index(b.x, b.y + 1, b.z)] = c_fire
				out.crystals[#out.crystals + 1] = {x = b.x, y = b.y + 1, z = b.z}
			end
		end
	end
end

-- the podium at origin (the ground at the middle): Minecraft's EndPodiumFeature, its portal not lit
local function podium(minp, maxp, area, origin, out)
	for y = origin.y - 1, origin.y + 32 do
		for z = origin.z - 4, origin.z + 4 do
			for x = origin.x - 4, origin.x + 4 do
				if x >= minp.x and x <= maxp.x and y >= minp.y and y <= maxp.y and z >= minp.z and z <= maxp.z then
					local d = (x - origin.x) ^ 2 + (y - origin.y) ^ 2 + (z - origin.z) ^ 2
					local near = d < 6.25
					if near or d < 12.25 then
						local vi = area:index(x, y, z)
						if y < origin.y then
							data[vi] = near and c_bedrock or c_stone
						elseif y > origin.y then
							data[vi] = c_air
						else
							data[vi] = near and c_air or c_bedrock
						end
					end
				end
			end
		end
	end
	for k = 0, 3 do
		data[area:index(origin.x, origin.y + k, origin.z)] = c_bedrock
	end
	for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
		local p = {x = origin.x + d[1], y = origin.y + 2, z = origin.z + d[2]}
		data[area:index(p.x, p.y, p.z)] = c_torch
		out.nodes[#out.nodes + 1] = {x = p.x, y = p.y, z = p.z, name = "default:torch_wall",
			param2 = core.dir_to_wallmounted({x = -d[1], y = 0, z = -d[2]})}
	end
	out.podium = origin
end

-- Decorations, each from its own chunk of 16 and spilling over into the margin of the mapchunk; what is not yet
-- generated there counts as empty
local area
local function empty(x, y, z)
	if not area:contains(x, y, z) then
		return false
	end
	local c = data[area:index(x, y, z)]
	return c == c_air or c == core.CONTENT_IGNORE
end
local function put(x, y, z, c)
	if area:contains(x, y, z) then
		data[area:index(x, y, z)] = c
	end
end
-- the ground's top at x, z between y0 and y1, the first empty node over it (Minecraft's MOTION_BLOCKING heightmap)
local function ground(x, z, y0, y1)
	for y = y1, y0, -1 do
		if not empty(x, y, z) then
			return y + 1
		end
	end
end
local function rng(cx, cz, salt)
	return PcgRandom((SEED + cx * 341873128712 + cz * 132897987541 + salt) % 2147483647)
end

-- EndIslandFeature: discs of end stone shrinking downward from a radius of 4 to 6
local function small_island(x, y, z, pr)
	local f = pr:next(0, 2) + 4
	local i = 0
	while f > 0.5 do
		for j = math.floor(-f), math.ceil(f) do
			for k = math.floor(-f), math.ceil(f) do
				if j * j + k * k <= (f + 1) * (f + 1) then
					put(x + j, y + i, z + k, c_stone)
				end
			end
		end
		f = f - (pr:next(0, 1) + 0.5)
		i = i - 1
	end
end

-- EndGatewayFeature: the gateway between bedrock above and below, a cross of it a node off, open at its own level
local function gateway(x, y, z)
	for dx = -1, 1 do
		for dz = -1, 1 do
			for dy = -2, 2 do
				local centre = dx == 0 and dz == 0
				local c = c_air
				if centre and dy == 0 then
					c = c_gateway
				elseif dy ~= 0 and (math.abs(dy) == 2 and centre or math.abs(dy) == 1 and (dx == 0 or dz == 0)) then
					c = c_bedrock
				end
				put(x + dx, y + dy, z + dz, c)
			end
		end
	end
end

-- ChorusFlowerBlock.generatePlant: stems up 1 to 4 (one more at the root), up to four branches out at their top,
-- four levels deep and within 8 of the root, a dead flower where a stem ends unbranched
local DIRS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
local OPPOSITE = {2, 1, 4, 3}
local function open(x, y, z, except)
	for d = 1, 4 do
		if d ~= except and not empty(x + DIRS[d][1], y, z + DIRS[d][2]) then
			return false
		end
	end
	return true
end
local function grow(x, y, z, pr, rx, rz, depth)
	local height = pr:next(0, 3) + 1 + (depth == 0 and 1 or 0)
	for i = 1, height do
		if not open(x, y + i, z) then
			return
		end
		put(x, y + i, z, c_plant)
		put(x, y + i - 1, z, c_plant)
	end
	local branched = false
	if depth < 4 then
		for _ = 1, pr:next(0, 3) + (depth == 0 and 1 or 0) do
			local d = pr:next(1, 4)
			local bx, by, bz = x + DIRS[d][1], y + height, z + DIRS[d][2]
			if math.abs(bx - rx) < 8 and math.abs(bz - rz) < 8 and empty(bx, by, bz) and empty(bx, by - 1, bz) and
					open(bx, by, bz, OPPOSITE[d]) then
				branched = true
				put(bx, by, bz, c_plant)
				put(x, by, z, c_plant)
				grow(bx, by, bz, pr, rx, rz, depth + 1)
			end
		end
	end
	if not branched then
		put(x, y + height, z, c_dead)
	end
end

local erosion = {}
local function decorate(minp, maxp, out)
	local n = (maxp.x - minp.x + 1) / 16
	ISL.columns(minp.x + 8, minp.z + 8, n, n, 16, erosion)
	local y0, y1 = YMIN, math.min(maxp.y, YMIN + 100)
	for b = 0, n - 1 do
		for a = 0, n - 1 do
			local cx, cz = minp.x / 16 + a, minp.z / 16 + b
			local e = erosion[b * n + a + 1]
			if cx * cx + cz * cz > 4096 then
				local x0, z0 = cx * 16, cz * 16
				if e < -0.21875 then
					local pr = rng(cx, cz, 1)
					if pr:next(1, 14) == 1 then
						for _ = 1, pr:next(1, 4) == 4 and 2 or 1 do
							small_island(x0 + pr:next(0, 15), YMIN + pr:next(55, 70), z0 + pr:next(0, 15), pr)
							out.islands = out.islands + 1
						end
					end
				elseif e > 0.25 then
					local pr = rng(cx, cz, 2)
					if pr:next(1, 700) == 1 then
						local x, z = x0 + pr:next(0, 15), z0 + pr:next(0, 15)
						local y = ground(x, z, y0, y1)
						if y then
							y = y + pr:next(3, 9)
							gateway(x, y, z)
							out.gateways[#out.gateways + 1] = {x = x, y = y, z = z}
						end
					end
					pr = rng(cx, cz, 3)
					for _ = 1, pr:next(0, 4) do
						local x, z = x0 + pr:next(0, 15), z0 + pr:next(0, 15)
						local y = ground(x, z, y0, y1)
						if y and data[area:index(x, y - 1, z)] == c_stone and empty(x, y, z) then
							put(x, y, z, c_plant)
							grow(x, y, z, pr, x, z, 0)
							out.plants = out.plants + 1
						end
					end
				end
			end
		end
	end
end

core.register_on_generated(function(vm, minp, maxp)
	if maxp.y < YMIN or minp.y > YMAX then
		return
	end
	-- only where an island, a pillar or a decoration (in the mapchunk holding Minecraft's 60) may be
	local low = minp.y <= YMIN + 100
	local nx, nz = (maxp.x - minp.x + 1) / GX + 1, (maxp.z - minp.z + 1) / GX + 1
	local island = low and ISL.columns(minp.x, minp.z, nx, nz, GX, cols) > EMPTY
	local decorated = minp.y <= YMIN + 60 and maxp.y >= YMIN + 60 and
		math.max(minp.x ^ 2, maxp.x ^ 2) + math.max(minp.z ^ 2, maxp.z ^ 2) > 1024 ^ 2
	local pillar = false
	for _, sp in ipairs(R.spikes) do
		pillar = pillar or sp.x + sp.radius + 2 >= minp.x and sp.x - sp.radius - 2 <= maxp.x and
			sp.z + sp.radius + 2 >= minp.z and sp.z - sp.radius - 2 <= maxp.z and minp.y <= YMIN + sp.height + 10
	end
	if not island and not pillar and not decorated then
		return
	end
	local t0 = core.get_us_time()
	local emin, emax = vm:get_emerged_area()
	area = VoxelArea(emin, emax)
	vm:get_data(data)
	local t1 = core.get_us_time()
	local made = island and shape(vm, minp, maxp, area) or 0
	local t2 = core.get_us_time()
	local out = {crystals = {}, nodes = {}, gateways = {}, islands = 0, plants = 0}
	spikes(vm, minp, maxp, area, out)
	-- the podium where the middle column's ground is (the mapchunk with the middle holds the whole island's height)
	if minp.x <= 0 and maxp.x >= 0 and minp.z <= 0 and maxp.z >= 0 and minp.y <= YMIN + 60 and maxp.y >= YMIN + 60 then
		local y = math.min(maxp.y, YMIN + 100)
		while y > minp.y and data[area:index(0, y, 0)] ~= c_stone do
			y = y - 1
		end
		podium(minp, maxp, area, {x = 0, y = y + 1, z = 0}, out)
	end
	if decorated then
		decorate(minp, maxp, out)
	end
	local t3 = core.get_us_time()
	if made == 0 and #out.crystals == 0 and not out.podium and not pillar and out.islands == 0 and
			#out.gateways == 0 then
		return
	end
	vm:set_data(data)
	for _, n in ipairs(out.nodes) do
		vm:set_node_at(n, n)
	end
	vm:calc_lighting()
	local t4 = core.get_us_time()
	core.save_gen_notify("goodluck_end:realm", {crystals = out.crystals, podium = out.podium, stone = made,
		gateways = out.gateways, islands = out.islands, plants = out.plants,
		read = t1 - t0, shape = t2 - t1, features = t3 - t2, write = t4 - t3})
end)
