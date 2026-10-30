-- In the map generator's threads: the swamp oaks' vines and the witch's hut
local N = "goodluck_swamp:"
local LEAVES, TREE, VINE = N .. "leaves", "default:tree", N .. "vine"
local SWAMP = core.get_biome_id("swamp")
local WET = {[SWAMP] = true, [core.get_biome_id("swamp_shore")] = true}
-- huts: the mapchunks in groups of REGION x REGION, one place per group where a hut may stand, never in a group's
-- last row or column so that two are a mapchunk apart at least, as Minecraft's random spread of one in 32 x 32 chunks
-- 8 apart
local REGION = 3
local SEED = tonumber(core.get_mapgen_setting("seed")) or 0
local W, D = 7, 9

-- Minecraft's LeaveVineDecorator: on each side of each leaf with air there, one time in four, a vine hanging from it
-- and down while there is air, 4 more at most. The leaves' rings are where the air is. A vine lets the light through,
-- so it keeps the light of the air it takes
local SIDES = {{-1, 0, 2}, {1, 0, 3}, {0, -1, 4}, {0, 1, 5}}
local function vines(vm, base, rand)
	local p = {x = base.x, y = base.y, z = base.z}
	-- the trunk's top
	local h = 0
	while h < 10 do
		p.y = base.y + h
		if vm:get_node_at(p).name ~= TREE then
			break
		end
		h = h + 1
	end
	if h < 4 then
		return 0
	end
	local placed = 0
	local q = {}
	for row = 0, 3 do
		local y = base.y + h - row
		local r = row <= 1 and 2 or 3
		for dx = -r, r do
			for dz = -r, r do
				if math.abs(dx) == r or math.abs(dz) == r then
					p.x, p.y, p.z = base.x + dx, y, base.z + dz
					if vm:get_node_at(p).name == LEAVES then
						for _, s in ipairs(SIDES) do
							if rand:next(1, 4) == 1 then
								q.x, q.y, q.z = p.x + s[1], y, p.z + s[2]
								for _ = 0, 4 do
									local air = vm:get_node_at(q)
									if air.name ~= "air" then
										break
									end
									air.name, air.param2 = VINE, s[3]
									vm:set_node_at(q, air)
									placed = placed + 1
									q.y = q.y - 1
								end
							end
						end
					end
				end
			end
		end
	end
	return placed
end

-- The hut as SwampHutPiece builds it, in its own frame (x across 7, z along 9, y up from the ground's average);
-- Minecraft's north is -z, Luanti's +z, so its z goes the other way here
local PLANKS, LOG, FENCE = "default:pine_wood", "default:tree", "default:fence_wood"
local STAIR, OUTER = "stairs:stair_pine_wood", "stairs:stair_outer_pine_wood"
local function boxes(set)
	local function fill(x1, y1, z1, x2, y2, z2, node)
		for x = x1, x2 do
			for y = y1, y2 do
				for z = z1, z2 do
					set(x, y, z, node)
				end
			end
		end
	end
	fill(1, 1, 1, 5, 1, 7, {name = PLANKS})
	fill(1, 4, 2, 5, 4, 7, {name = PLANKS})
	fill(2, 1, 0, 4, 1, 0, {name = PLANKS})
	fill(2, 2, 2, 3, 3, 2, {name = PLANKS})
	fill(1, 2, 3, 1, 3, 6, {name = PLANKS})
	fill(5, 2, 3, 5, 3, 6, {name = PLANKS})
	fill(2, 2, 7, 4, 3, 7, {name = PLANKS})
	for _, c in ipairs({{1, 2}, {5, 2}, {1, 7}, {5, 7}}) do
		fill(c[1], 0, c[2], c[1], 3, c[2], {name = LOG})
	end
	set(2, 3, 2, {name = FENCE})
	set(3, 3, 7, {name = FENCE})
	set(1, 3, 4, {name = "air"})
	set(5, 3, 4, {name = "air"})
	set(5, 3, 5, {name = "air"})
	set(1, 3, 5, {name = N .. "potted_red_mushroom"})
	set(3, 2, 6, {name = "goodluck_craft:crafting_table"})
	set(4, 2, 6, "cauldron")
	set(1, 2, 1, {name = FENCE})
	set(5, 2, 1, {name = FENCE})
	-- the roof's edge of spruce stairs (Minecraft's facing north, east, west, south), its corners outer ones
	fill(0, 4, 1, 6, 4, 1, {stair = "north"})
	fill(0, 4, 2, 0, 4, 7, {stair = "east"})
	fill(6, 4, 2, 6, 4, 7, {stair = "west"})
	fill(0, 4, 8, 6, 4, 8, {stair = "south"})
	set(0, 4, 1, {stair = "north", shape = "right"})
	set(6, 4, 1, {stair = "north", shape = "left"})
	set(0, 4, 8, {stair = "south", shape = "left"})
	set(6, 4, 8, {stair = "south", shape = "right"})
end

-- Minecraft's facings in Luanti (north +z) as the stairs' facedir (their high side), and its turns
local FACEDIR = {north = 0, east = 1, south = 2, west = 3}
local CW = {north = "east", east = "south", south = "west", west = "north"}
local FLIP = {north = "south", south = "north", east = "east", west = "west"}

-- a piece facing dir, from its box's corner (x0, z0): StructurePiece's getWorldX/Z, with Minecraft's z the other way,
-- and its mirror and rotation of the states
local function frame(dir, x0, z0)
	local function at(x, z)
		if dir == "north" then
			return x0 + x, z0 + z
		elseif dir == "south" then
			return x0 + x, z0 + (D - 1 - z)
		elseif dir == "west" then
			return x0 + (D - 1 - z), z0 + (W - 1 - x)
		end
		return x0 + z, z0 + (W - 1 - x)
	end
	local mirror = dir == "south" or dir == "west"
	local turn = dir == "west" or dir == "east"
	local function face(f, shape)
		if mirror then
			f = FLIP[f]
			shape = shape and (shape == "left" and "right" or "left")
		end
		if turn then
			f = CW[f]
		end
		return f, shape
	end
	return at, face
end

local function width(dir)
	return (dir == "north" or dir == "south") and W or D, (dir == "north" or dir == "south") and D or W
end

local POTIONS = {"night_vision", "invisibility", "leaping", "fire_resistance", "swiftness", "slowness",
	"water_breathing", "healing", "harming", "poison", "regeneration", "strength", "weakness"}
local DIRS = {"north", "east", "south", "west"}

local function hut(vm, minp, maxp, rand)
	local hmap = core.get_mapgen_object("heightmap")
	local bmap = core.get_mapgen_object("biomemap")
	if not hmap or not bmap then
		return
	end
	local dir = DIRS[rand:next(1, 4)]
	local wx, wz = width(dir)
	local sx = maxp.x - minp.x + 1
	local swamp = {}
	for i = 1, #bmap do
		if bmap[i] == SWAMP then
			swamp[#swamp + 1] = i
		end
	end
	if #swamp < 64 then
		return
	end
	-- a few tries at a spot in the swamp whose footprint is mostly swamp and not too uneven, within the chunk
	for _ = 1, 12 do
		local i = swamp[rand:next(1, #swamp)] - 1
		local x0 = math.max(minp.x + 2, math.min(maxp.x - wx - 2, minp.x + i % sx - math.floor(wx / 2)))
		local z0 = math.max(minp.z + 2, math.min(maxp.z - wz - 2, minp.z + math.floor(i / sx) - math.floor(wz / 2)))
		local sum, n, wet, lo, hi = 0, 0, 0, math.huge, -math.huge
		for z = z0, z0 + wz - 1 do
			for x = x0, x0 + wx - 1 do
				local i = (z - minp.z) * sx + (x - minp.x) + 1
				-- Minecraft's MOTION_BLOCKING: water counts, so over the sea it is the water's top
				local top = math.max(hmap[i], 1)
				sum, n = sum + top + 1, n + 1
				lo, hi = math.min(lo, top), math.max(hi, top)
				if WET[bmap[i]] then
					wet = wet + 1
				end
			end
		end
		local y0 = math.floor(sum / n)
		if wet * 2 >= n and hi - lo <= 4 and y0 + 7 <= maxp.y and lo - 8 >= minp.y then
			local at, face = frame(dir, x0, z0)
			local p = {}
			local cauldron = "goodluck_potions:cauldron_" .. POTIONS[rand:next(1, #POTIONS)] .. "_" .. rand:next(1, 3)
			local function set(x, y, z, node)
				p.x, p.z = at(x, z)
				p.y = y0 + y
				if node == "cauldron" then
					node = {name = cauldron}
				elseif node.stair then
					local f, shape = face(node.stair, node.shape)
					if shape then
						-- Minecraft's outer left is the facing's corner turned anticlockwise, which is this game's
						-- outer stair at that facedir; its right one the next facing's left
						node = {name = OUTER, param2 = FACEDIR[shape == "left" and f or CW[f]]}
					else
						node = {name = STAIR, param2 = FACEDIR[f]}
					end
				end
				vm:set_node_at(p, core.registered_nodes[node.name] and node or {name = "air"})
			end
			boxes(set)
			-- the stilts: logs from under the floor down to the ground (through water and air)
			for _, c in ipairs({{1, 2}, {5, 2}, {1, 7}, {5, 7}}) do
				p.x, p.z = at(c[1], c[2])
				for y = y0 - 1, y0 - 20, -1 do
					p.y = y
					local name = vm:get_node_at(p).name
					local def = core.registered_nodes[name]
					if name ~= "air" and not (def and (def.liquidtype ~= "none" or def.buildable_to)) then
						break
					end
					vm:set_node_at(p, {name = LOG})
				end
			end
			-- its shade, down to the ground
			vm:calc_lighting({x = x0 - 1, y = math.max(minp.y, lo - 2), z = z0 - 1},
				{x = x0 + wx, y = y0 + 6, z = z0 + wz})
			local wxp, wzp = at(2, 5)
			return {x = wxp, y = y0 + 2, z = wzp}, dir
		end
	end
end

core.register_on_generated(function(vm, minp, maxp, blockseed)
	if maxp.y < -16 or minp.y > 48 then
		return
	end
	local t0 = core.get_us_time()
	local notes = core.get_mapgen_object("gennotify")
	local trees, hung = 0, 0
	local rand = PcgRandom(blockseed % 2147483647)
	for key, list in pairs(notes or {}) do
		if type(key) == "string" and key:find("^decoration#") then
			for _, pos in ipairs(list) do
				for dy = 0, 1 do
					local base = {x = pos.x, y = pos.y + dy, z = pos.z}
					if vm:get_node_at(base).name == TREE then
						trees = trees + 1
						hung = hung + vines(vm, base, rand)
						break
					end
				end
			end
		end
	end
	local t1 = core.get_us_time()
	-- the one chunk of its group where a hut may stand, if it is a swamp's chunk at the sea's height
	local size = maxp.x - minp.x + 1
	local cx, cz = math.floor(minp.x / size), math.floor(minp.z / size)
	local rx, rz = math.floor(cx / REGION), math.floor(cz / REGION)
	local pick = PcgRandom((SEED + rx * 73856093 + rz * 19349663) % 2147483647)
	local made
	if minp.y <= 1 and maxp.y >= 1 and cx == rx * REGION + pick:next(0, REGION - 2) and
			cz == rz * REGION + pick:next(0, REGION - 2) then
		local witch, dir = hut(vm, minp, maxp, rand)
		if witch then
			made = witch
			core.save_gen_notify(N .. "hut", {witch = witch, dir = dir})
		end
	end
	local t2 = core.get_us_time()
	core.save_gen_notify(N .. "chunk", {trees = trees, vines = hung, vines_us = t1 - t0, hut_us = t2 - t1,
		light_us = core.get_us_time() - t2, hut = made})
end)
