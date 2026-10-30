-- The End's ground, in the map generator's threads: Minecraft's density (its main island 100 - d about the middle,
-- clamped to -100..80, less 8, over 128; its 3D noise on top; pulled down below 32 and above 56 up), sampled every 8
-- nodes across and 4 up and blended in between as Minecraft does, end stone where it is over 0. Then the ten obsidian
-- pillars with bedrock on top (two caged in iron bars) and the exit portal's podium, inactive, on the ground at the
-- middle. The crystals go on the pillars in the game (portal.lua's end_realm), told by gen_notify
local R = core.ipc_get("goodluck_end:realm")
local YMIN, YMAX = R.ymin, R.ymax
local GX, GY = 8, 4
local NOISE = {offset = 0, scale = 0.25, spread = {x = 96 / GX, y = 48 / GY, z = 96 / GX}, seed = 7480, octaves = 4,
	persistence = 0.5, lacunarity = 2}
-- the island's reach, past which a mapchunk stays empty (the main island ends near 100)
local REACH = 140

local c_air = core.CONTENT_AIR
local c_stone = core.get_content_id("goodluck_end:end_stone")
local c_obsidian = core.get_content_id("default:obsidian")
local c_bedrock = core.get_content_id("goodluck_nether:bedrock")
local c_bars = core.get_content_id("xpanes:bar")
local c_fire = core.get_content_id("fire:permanent_flame")
local c_torch = core.get_content_id("default:torch_wall")

-- Minecraft's density at a grid point, before its squeeze
local function density(x, jy, z, n)
	local d = math.sqrt(x * x + z * z)
	local island = (math.max(-100, math.min(80, 100 - d)) - 8) / 128
	local v = island + n
	local top = math.max(0, math.min(1, 1 - (jy - 56) / 256))
	v = -23.4375 + top * (v + 23.4375)
	local low = math.max(0, math.min(1, (jy - 4) / 28))
	return (-0.234375 + low * (v + 0.234375)) * 0.64
end

local data, nvals, grid, plane, row, maps = {}, {}, {}, {}, {}, {}

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
				grid[i] = density(minp.x + gx * GX, minp.y + gy * GY - YMIN, minp.z + gz * GX, nvals[i])
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

core.register_on_generated(function(vm, minp, maxp)
	if maxp.y < YMIN or minp.y > YMAX then
		return
	end
	-- only where the island or a pillar is
	local nearest = math.sqrt(math.max(0, minp.x, -maxp.x) ^ 2 + math.max(0, minp.z, -maxp.z) ^ 2)
	local island = nearest <= REACH and minp.y <= YMIN + 100
	local pillar = false
	for _, sp in ipairs(R.spikes) do
		pillar = pillar or sp.x + sp.radius + 2 >= minp.x and sp.x - sp.radius - 2 <= maxp.x and
			sp.z + sp.radius + 2 >= minp.z and sp.z - sp.radius - 2 <= maxp.z and minp.y <= YMIN + sp.height + 10
	end
	if not island and not pillar then
		return
	end
	local t0 = core.get_us_time()
	local emin, emax = vm:get_emerged_area()
	local area = VoxelArea(emin, emax)
	vm:get_data(data)
	local t1 = core.get_us_time()
	local made = shape(vm, minp, maxp, area)
	local t2 = core.get_us_time()
	local out = {crystals = {}, nodes = {}}
	spikes(vm, minp, maxp, area, out)
	-- the podium where the middle column's ground is (the mapchunk with the middle holds the whole island's height)
	if minp.x <= 0 and maxp.x >= 0 and minp.z <= 0 and maxp.z >= 0 and minp.y <= YMIN + 60 and maxp.y >= YMIN + 60 then
		local y = math.min(maxp.y, YMIN + 100)
		while y > minp.y and data[area:index(0, y, 0)] ~= c_stone do
			y = y - 1
		end
		podium(minp, maxp, area, {x = 0, y = y + 1, z = 0}, out)
	end
	local t3 = core.get_us_time()
	if made == 0 and #out.crystals == 0 and not out.podium and not pillar then
		return
	end
	vm:set_data(data)
	for _, n in ipairs(out.nodes) do
		vm:set_node_at(n, n)
	end
	vm:calc_lighting()
	local t4 = core.get_us_time()
	core.save_gen_notify("goodluck_end:realm", {crystals = out.crystals, podium = out.podium, stone = made,
		read = t1 - t0, shape = t2 - t1, features = t3 - t2, write = t4 - t3})
end)
