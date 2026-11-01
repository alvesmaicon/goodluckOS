-- The End's islands as Minecraft 26.3 has them (end/islands: the main island's 100 - d, and EndIslandFunction for
-- the outer ones), for the map generator's threads and the game alike: from 1024 out, a cell of 16 whose simplex
-- noise is under -0.9 raises an island of its own reach; its value, less 8, over 128, is the density's base and the
-- erosion its biomes go by (TheEndBiomeSource)
local I = {}
local floor, sqrt, abs, max, min = math.floor, math.sqrt, math.abs, math.max, math.min

-- GradientNoise's table from the world's seed: 0..255 shuffled, twice over
local P = {}
do
	local seed = (tonumber(core.get_mapgen_setting("seed")) or 0) % 2147483647
	local pr = PcgRandom((seed + 17292) % 2147483647)
	for i = 0, 255 do
		P[i + 1] = i
	end
	for i = 0, 255 do
		local j = pr:next(0, 255 - i)
		P[i + 1], P[i + j + 1] = P[i + j + 1], P[i + 1]
	end
	for i = 1, 256 do
		P[i + 256] = P[i]
	end
end

-- SimplexNoise.get in 2D: GradientNoise's first twelve gradients, x and y of each
local GX = {1, -1, 1, -1, 1, -1, 1, -1, 0, 0, 0, 0}
local GY = {1, 1, -1, -1, 0, 0, 0, 0, 1, -1, 1, -1}
local F2 = 0.5 * (sqrt(3) - 1)
local G2 = (3 - sqrt(3)) / 6
local function corner(g, x, y)
	local t = 0.5 - x * x - y * y
	if t < 0 then
		return 0
	end
	t = t * t
	return t * t * (GX[g + 1] * x + GY[g + 1] * y)
end
local function simplex(x, y)
	local s = (x + y) * F2
	local i, j = floor(x + s), floor(y + s)
	local t = (i + j) * G2
	local x0, y0 = x - (i - t), y - (j - t)
	local i1, j1 = 0, 1
	if x0 > y0 then
		i1, j1 = 1, 0
	end
	local x1, y1 = x0 - i1 + G2, y0 - j1 + G2
	local x2, y2 = x0 - 1 + 2 * G2, y0 - 1 + 2 * G2
	local ii, jj = i % 256, j % 256
	local g0 = P[(ii + P[jj + 1]) % 256 + 1] % 12
	local g1 = P[(ii + i1 + P[(jj + j1) % 256 + 1]) % 256 + 1] % 12
	local g2 = P[(ii + 1 + P[(jj + 1) % 256 + 1]) % 256 + 1] % 12
	return 70 * (corner(g0, x0, y0) + corner(g1, x1, y1) + corner(g2, x2, y2))
end
I.simplex = simplex

-- Java's integer division and remainder, toward zero
local function tdiv(a, b)
	local q = a / b
	return q >= 0 and floor(q) or -floor(-q)
end
local function trem(a, b)
	return a - tdiv(a, b) * b
end

-- the outer islands' centres among cells o0..o1, p0..p1: {o, p, reach}
local function centres(o0, o1, p0, p1)
	local out = {}
	for o = o0, o1 do
		for p = p0, p1 do
			if o * o + p * p > 4096 and simplex(o, p) < -0.9 then
				out[#out + 1] = {o, p, (abs(o) * 3439 + abs(p) * 147) % 13 + 9}
			end
		end
	end
	return out
end

-- getHeightValue at X, Z (blocks over 8) from the centres about it
local function height(X, Z, list)
	local i, j, k, l = tdiv(X, 2), tdiv(Z, 2), trem(X, 2), trem(Z, 2)
	local f = -100
	for n = 1, #list do
		local c = list[n]
		local m, q = c[1] - i, c[2] - j
		if m >= -12 and m <= 12 and q >= -12 and q <= 12 then
			local h, v = k - m * 2, l - q * 2
			f = max(f, max(-100, min(80, 100 - sqrt(h * h + v * v) * c[3])))
		end
	end
	return f
end

local function main(x, z)
	return (max(-100, min(80, 100 - sqrt(x * x + z * z))) - 8) / 128
end

-- the islands' value at the columns x0 + a * step, z0 + b * step (a < nx, b < nz), into out (x fastest); returns
-- its highest
function I.columns(x0, z0, nx, nz, step, out)
	local x1, z1 = x0 + (nx - 1) * step, z0 + (nz - 1) * step
	local X0, X1, Z0, Z1 = tdiv(x0, 8), tdiv(x1, 8), tdiv(z0, 8), tdiv(z1, 8)
	local o0, o1 = tdiv(min(X0, X1), 2) - 12, tdiv(max(X0, X1), 2) + 12
	local p0, p1 = tdiv(min(Z0, Z1), 2) - 12, tdiv(max(Z0, Z1), 2) + 12
	-- the outer islands begin past 64 cells
	local far = max(o0 * o0, o1 * o1) + max(p0 * p0, p1 * p1) > 4096
	local list = far and centres(o0, o1, p0, p1) or {}
	local top, n = -math.huge, 0
	for b = 0, nz - 1 do
		local z = z0 + b * step
		for a = 0, nx - 1 do
			local x = x0 + a * step
			local v = main(x, z)
			if #list > 0 then
				v = max(v, (height(tdiv(x, 8), tdiv(z, 8), list) - 8) / 128)
			end
			n = n + 1
			out[n] = v
			top = max(top, v)
		end
	end
	return top
end

local one = {}
function I.at(x, z)
	I.columns(x, z, 1, 1, 1, one)
	return one[1]
end

-- the biome of the chunk of 16 holding x, z: the main island's within 64 chunks of the middle, else by the islands'
-- value at the chunk's middle
function I.biome(x, z)
	local sx, sz = floor(x / 16), floor(z / 16)
	if sx * sx + sz * sz <= 4096 then
		return "the_end"
	end
	local e = I.at(sx * 16 + 8, sz * 16 + 8)
	if e > 0.25 then
		return "highlands"
	elseif e >= -0.0625 then
		return "midlands"
	elseif e < -0.21875 then
		return "small_islands"
	end
	return "barrens"
end

-- The ground's top at x, z, as endgen.lua makes it: Minecraft's density from the islands' value and the noise at the
-- grid's corners about the column (every 8 across and 4 up from the End's floor), blended along z, then y, then x the
-- way endgen.lua adds it up; nil where the column has no end stone. For the End cities in any thread; its noise and
-- density are endgen.lua's own, and kept in I for it
local NOISE = {offset = 0, scale = 0.25, spread = {x = 96 / 8, y = 48 / 4, z = 96 / 8}, seed = 7480, octaves = 4,
	persistence = 0.5, lacunarity = 2}
local function density(island, jy, n)
	local v = island + n
	local top = max(0, min(1, 1 - (jy - 56) / 256))
	v = -23.4375 + top * (v + 23.4375)
	local low = max(0, min(1, (jy - 4) / 28))
	return (-0.234375 + low * (v + 0.234375)) * 0.64
end
I.NOISE, I.density = NOISE, density
local noise, corner = nil, {}
function I.ground(x, z, ymin)
	local x0, z0 = floor(x / 8) * 8, floor(z / 8) * 8
	if I.columns(x0, z0, 2, 2, 8, corner) <= -0.5 then
		return nil
	end
	noise = noise or core.get_value_noise(NOISE)
	local fz, ox = (z - z0) / 8, x - x0
	local function level(jy)
		local d = {}
		for k = 1, 4 do
			local cx, cz = x0 + (k - 1) % 2 * 8, z0 + floor((k - 1) / 2) * 8
			d[k] = density(corner[k], jy, noise:get_3d({x = cx / 8, y = (ymin + jy) / 4, z = cz / 8}))
		end
		return d[1] + (d[3] - d[1]) * fz, d[2] + (d[4] - d[2]) * fz
	end
	local function stone(a, b)
		if a <= 0 and b <= 0 then
			return false
		end
		local d, dd = a, (b - a) / 8
		for _ = 1, ox do
			d = d + dd
		end
		return d > 0
	end
	local a1, b1 = level(100)
	if stone(a1, b1) then
		return ymin + 100
	end
	for g = 24, 0, -1 do
		local a0, b0 = level(g * 4)
		for y = g * 4 + 3, g * 4, -1 do
			local fy = (y - g * 4) / 4
			if stone(a0 + (a1 - a0) * fy, b0 + (b1 - b0) * fy) then
				return ymin + y
			end
		end
		a1, b1 = a0, b0
	end
end

-- the map generator's threads share it with endgen.lua
if core.save_gen_notify then
	goodluck_end_islands = I
end
return I
