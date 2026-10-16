-- Geodes, in the map generator's threads: in half the chunks between YMIN and YMAX, a hollow ball in the stone with
-- calcite outside, a shell of amethyst blocks and clusters on the shell's inside. Only stone is replaced, so a cave
-- running through one leaves it open, as Minecraft's cracked geodes. Node by node: get_data() would copy the whole
-- emerged area (1.4 million nodes) into Lua for a ball of a few thousand
local YMIN, YMAX = -160, -16
local CHANCE = 50          -- percent of the chunks reaching that depth
local CLUSTER_CHANCE = 25  -- percent of the shell's inner faces

local AIR, BLOCK = {name = "air"}, {name = "goodluck_amethyst:amethyst_block"}
local CALCITE = {name = "goodluck_amethyst:calcite"}
local stone = {}
for name, def in pairs(core.registered_nodes) do
	if (def.groups and def.groups.stone or 0) > 0 or name:find("^default:stone_with_") then
		stone[name] = true
	end
end
-- a cluster's wallmounted param2 points at the block it grows from
local MOUNTS = {{0, 1, 0, 0}, {0, -1, 0, 1}, {1, 0, 0, 2}, {-1, 0, 0, 3}, {0, 0, 1, 4}, {0, 0, -1, 5}}

core.register_on_generated(function(vm, minp, maxp, blockseed)
	if maxp.y < YMIN or minp.y > YMAX then
		return
	end
	local rand = PcgRandom(blockseed + 51)
	if rand:next(1, 100) > CHANCE then
		return
	end
	local t0 = core.get_us_time()
	-- outer radius 5 to 6.2, each axis stretched or squeezed up to 15 %
	local r = rand:next(50, 62) / 10
	local sx, sy, sz = rand:next(85, 115) / 100, rand:next(85, 115) / 100, rand:next(85, 115) / 100
	local m = math.ceil(r * 1.15) + 1
	local ylo, yhi = math.max(minp.y, YMIN) + m, math.min(maxp.y, YMAX) - m
	if ylo > yhi then
		return
	end
	local c = {x = rand:next(minp.x + m, maxp.x - m), y = rand:next(ylo, yhi), z = rand:next(minp.z + m, maxp.z - m)}
	if not stone[vm:get_node_at(c).name] then
		return
	end
	local p, inner = {}, {}
	for z = c.z - m, c.z + m do
		for y = c.y - m, c.y + m do
			for x = c.x - m, c.x + m do
				local d = math.sqrt(((x - c.x) / sx) ^ 2 + ((y - c.y) / sy) ^ 2 + ((z - c.z) / sz) ^ 2)
				if d < r then
					p.x, p.y, p.z = x, y, z
					local name = vm:get_node_at(p).name
					if stone[name] then
						vm:set_node_at(p, d < r - 2 and AIR or d < r - 1 and BLOCK or CALCITE)
						name = d < r - 2 and "air" or ""
					end
					if d < r - 2 and name == "air" then
						inner[#inner + 1] = {x = x, y = y, z = z}
					end
				end
			end
		end
	end
	for _, q in ipairs(inner) do
		local first = rand:next(0, 5)
		for k = 0, 5 do
			local mount = MOUNTS[(first + k) % 6 + 1]
			p.x, p.y, p.z = q.x + mount[1], q.y + mount[2], q.z + mount[3]
			if vm:get_node_at(p).name == BLOCK.name then
				if rand:next(1, 100) <= CLUSTER_CHANCE then
					vm:set_node_at(q, {name = "goodluck_amethyst:amethyst_cluster", param2 = mount[4]})
				end
				break
			end
		end
	end
	vm:calc_lighting()
	core.save_gen_notify("goodluck_amethyst:geode", {x = c.x, y = c.y, z = c.z, r = r, us = core.get_us_time() - t0})
end)
