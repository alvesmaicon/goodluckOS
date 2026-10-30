-- Strongholds where Minecraft puts them: 128 in rings about the world's middle, 3 in the first one 1280 to 2816
-- away, more in each one further out (its concentric_rings: distance 32 chunks, spread 3), each at a random angle and
-- distance in its ring; their pieces (stronghold.lua) are walked from each one's start
local F = {}
local SEED = (tonumber(core.get_mapgen_setting("seed")) or 0) % 2147483647
local COUNT, DISTANCE, SPREAD = 128, 32, 3

local function double(pr)
	return pr:next(0, 2147483646) / 2147483647
end

-- the chunk of each, in Minecraft's order
F.rings = {}
do
	local pr = PcgRandom((SEED + 7341) % 2147483647)
	local angle = double(pr) * math.pi * 2
	local spread, placed, ring = SPREAD, 0, 0
	for i = 0, COUNT - 1 do
		local d = 4 * DISTANCE + DISTANCE * ring * 6 + (double(pr) - 0.5) * DISTANCE * 2.5
		F.rings[#F.rings + 1] = {x = math.floor(math.cos(angle) * d + 0.5), z = math.floor(math.sin(angle) * d + 0.5)}
		angle = angle + math.pi * 2 / spread
		placed = placed + 1
		if placed == spread then
			ring, placed = ring + 1, 0
			spread = math.min(spread + math.floor(2 * spread / (ring + 1)), COUNT - i)
			angle = angle + double(pr) * math.pi * 2
		end
	end
end

-- where the eye of ender leads from pos: the nearest one's portal room once its pieces are known, else its start
function F.nearest(pos)
	local best, near
	for i, c in ipairs(F.rings) do
		local x, z = c.x * 16 + 8, c.z * 16 + 8
		local d = (x - pos.x) ^ 2 + (z - pos.z) ^ 2
		if not near or d < near then
			best, near = i, d
		end
	end
	local c = F.rings[best]
	local target = F.locator and F.locator(best)
	return target or {x = c.x * 16 + 8, y = 0, z = c.z * 16 + 8}, best
end

return F
