-- Where the End cities stand, as Minecraft places them (structure_set end_cities: random_spread, spacing 20 chunks,
-- separation 11, triangular, salt 10387313): one candidate chunk of 16 in each square of 20 by 20 of them, the city
-- starting at that chunk's 7, 7, in the highlands or midlands, turned at random, and only where the lowest of the four
-- corners of a 5 by 5 square from there (toward its turn) is 60 or more over the End's floor. For the map generator's
-- threads (city.lua) and the game alike
local C = {}
local SEED = (tonumber(core.get_mapgen_setting("seed")) or 0) % 2147483647
-- the islands (islands.lua): the threads' copy, else the game's
local ISL = rawget(_G, "goodluck_end_islands") or goodluck_end.islands
local SPACING, SEPARATION, SALT = 20, 11, 10387313
local REGION = SPACING * 16
-- how far a city's pieces reach from its start, at most (bridges eight deep, the ship 80 off its bridge)
C.REACH = 288
local YMIN

local function rng(a, b, salt)
	return PcgRandom((SEED + a * 341873128712 + b * 132897987541 + salt) % 2147483647)
end

-- the 5 by 5 square's far corner from the start, by turn (none, a quarter clockwise, a half, a quarter back)
local CORNER = {[0] = {5, 5}, {-5, 5}, {-5, -5}, {5, -5}}

-- the city of region i, j: {x, y, z, rot, seed} at its start, or false
local starts, kept = {}, 0
function C.start(i, j)
	local key = i .. "," .. j
	local s = starts[key]
	if s ~= nil then
		return s
	end
	if kept >= 256 then
		starts, kept = {}, 0
	end
	kept = kept + 1
	YMIN = YMIN or core.ipc_get("goodluck_end:realm").ymin
	local pr = rng(i, j, SALT)
	local k = SPACING - SEPARATION
	local cx = i * SPACING + math.floor((pr:next(0, k - 1) + pr:next(0, k - 1)) / 2)
	local cz = j * SPACING + math.floor((pr:next(0, k - 1) + pr:next(0, k - 1)) / 2)
	local x, z = cx * 16 + 7, cz * 16 + 7
	s = false
	local biome = ISL.biome(x, z)
	if biome == "highlands" or biome == "midlands" then
		local seed = (SEED + cx * 341873128712 + cz * 132897987541) % 2147483647
		local rot = PcgRandom(seed):next(0, 3)
		local d = CORNER[rot]
		local low = math.huge
		for _, c in ipairs({{0, 0}, {0, d[2]}, {d[1], 0}, {d[1], d[2]}}) do
			local y = ISL.ground(x + c[1], z + c[2], YMIN)
			low = math.min(low, y or -math.huge)
		end
		if low - YMIN >= 60 then
			s = {x = x, y = low, z = z, rot = rot, seed = seed, biome = biome}
		end
	end
	starts[key] = s
	return s
end

-- every city whose start is within REACH of x1..x2, z1..z2: fn(start, i, j)
function C.each_near(x1, z1, x2, z2, fn)
	-- none near the main island: its biome reaches 64 chunks out
	if math.max(math.abs(x1), math.abs(x2)) < 1024 - C.REACH - 16 and
			math.max(math.abs(z1), math.abs(z2)) < 1024 - C.REACH - 16 then
		return
	end
	for i = math.floor((x1 - C.REACH - 135) / REGION), math.floor((x2 + C.REACH - 7) / REGION) do
		for j = math.floor((z1 - C.REACH - 135) / REGION), math.floor((z2 + C.REACH - 7) / REGION) do
			local s = C.start(i, j)
			if s and s.x >= x1 - C.REACH and s.x <= x2 + C.REACH and s.z >= z1 - C.REACH and s.z <= z2 + C.REACH then
				fn(s, i, j)
			end
		end
	end
end

-- the nearest city's start to pos within r (regions searched in rings), or nil
function C.nearest(pos, r)
	local best, near
	local i0, j0 = math.floor(pos.x / REGION), math.floor(pos.z / REGION)
	local n = math.ceil((r or 2000) / REGION)
	for i = i0 - n, i0 + n do
		for j = j0 - n, j0 + n do
			local s = C.start(i, j)
			if s then
				local d = (s.x - pos.x) ^ 2 + (s.z - pos.z) ^ 2
				if not near or d < near then
					best, near = s, d
				end
			end
		end
	end
	return best
end

if core.save_gen_notify then
	goodluck_end_cities = C
end
return C
