-- Strongholds as Minecraft builds them, in both the map generator's threads and the game: from stairs down at the
-- ring's chunk (strongholds.lua), a random walk of Minecraft's pieces by their weights and limits (corridors, turns,
-- crossings, stairs, a prison, chest corridors, libraries and the portal room), up to 50 deep and 112 from the start,
-- tried again until it has its portal room, then sunk below the sea as Minecraft sinks it (its top 10 or more under
-- sea level, its bottom 64 over Minecraft's floor at the deepest). Every mapchunk draws its own share of the same walk;
-- the walls keep the caves that cross them (Minecraft's skipAir), their bricks cracked, mossy or whole by the node
local F = {}
local SEED = (tonumber(core.get_mapgen_setting("seed")) or 0) % 2147483647
local WATER = tonumber(core.get_mapgen_setting("water_level")) or 1
-- Minecraft's sea at 63 and floor at -64, here at the water level and 126 below it
local SEA, FLOOR = WATER, WATER - 126
local REACH, DEPTH = 112, 50

local RINGS = core.ipc_get("goodluck_end:rings")

local WEIGHTS = {
	{kind = "straight", weight = 40, max = 0},
	{kind = "prison", weight = 5, max = 5},
	{kind = "left_turn", weight = 20, max = 0},
	{kind = "right_turn", weight = 20, max = 0},
	{kind = "room_crossing", weight = 10, max = 6},
	{kind = "straight_stairs", weight = 5, max = 5},
	{kind = "stairs", weight = 5, max = 5},
	{kind = "five_crossing", weight = 5, max = 4},
	{kind = "chest_corridor", weight = 5, max = 4},
	{kind = "library", weight = 10, max = 2, depth = 4},
	{kind = "portal_room", weight = 20, max = 1, depth = 5},
}
-- each piece's box from the door it is reached by: across, up, along offsets and size (Minecraft's orientBox)
local SHAPE = {
	straight = {-1, -1, 0, 5, 5, 7}, prison = {-1, -1, 0, 9, 5, 11}, left_turn = {-1, -1, 0, 5, 5, 5},
	right_turn = {-1, -1, 0, 5, 5, 5}, room_crossing = {-4, -1, 0, 11, 7, 11}, straight_stairs = {-1, -7, 0, 5, 11, 8},
	stairs = {-1, -7, 0, 5, 11, 5}, five_crossing = {-4, -3, 0, 10, 9, 11}, chest_corridor = {-1, -1, 0, 5, 5, 7},
	library = {-4, -1, 0, 14, 11, 15}, library_short = {-4, -1, 0, 14, 6, 15}, portal_room = {-4, -1, 0, 11, 8, 16},
}

local function orient(x, y, z, s, dir)
	local ox, oy, oz, w, h, d = s[1], s[2], s[3], s[4], s[5], s[6]
	if dir == "N" then
		return {x + ox, y + oy, z - d + 1 + oz, x + w - 1 + ox, y + h - 1 + oy, z + oz}
	elseif dir == "W" then
		return {x - d + 1 + oz, y + oy, z + ox, x + oz, y + h - 1 + oy, z + w - 1 + ox}
	elseif dir == "E" then
		return {x + oz, y + oy, z + ox, x + d - 1 + oz, y + h - 1 + oy, z + w - 1 + ox}
	end
	return {x + ox, y + oy, z + oz, x + w - 1 + ox, y + h - 1 + oy, z + d - 1 + oz}
end

local function overlap(a, b)
	return a[1] <= b[4] and a[4] >= b[1] and a[2] <= b[5] and a[5] >= b[2] and a[3] <= b[6] and a[6] >= b[3]
end

-- a door of Minecraft's SmallDoorType: 2 in 5 an opening, else a wooden door, grates or an iron door
local DOORS = {"opening", "opening", "wood", "grates", "iron"}

-- the walk from a start at x, z (Minecraft's 64 up), pr its random; nil when it has no portal room
local function walk(x, z, pr)
	local dirs = {"N", "E", "S", "W"}
	local dir = dirs[pr:next(1, 4)]
	local start = {kind = "stairs", dir = dir, depth = 0, door = "opening", box = {x, 64, z, x + 4, 74, z + 4}}
	local pieces, pending = {start}, {}
	local list = {}
	for i, w in ipairs(WEIGHTS) do
		list[i] = {kind = w.kind, weight = w.weight, max = w.max, depth = w.depth, count = 0}
	end
	local previous, imposed, portal = nil, "five_crossing", nil

	local function collides(box)
		for _, p in ipairs(pieces) do
			if overlap(p.box, box) then
				return p
			end
		end
	end
	local function make(kind, px, py, pz, d, depth)
		local box = orient(px, py, pz, SHAPE[kind], d)
		local tall = true
		if kind == "library" and (box[2] <= 10 or collides(box)) then
			box, tall = orient(px, py, pz, SHAPE.library_short, d), false
		end
		if box[2] <= 10 or collides(box) then
			return
		end
		local piece = {kind = kind, dir = d, depth = depth, box = box, door = kind ~= "portal_room" and
			DOORS[pr:next(1, 5)] or "grates", seed = pr:next(0, 2147483646)}
		if kind == "straight" then
			piece.left, piece.right = pr:next(0, 1) == 0, pr:next(0, 1) == 0
		elseif kind == "five_crossing" then
			piece.left_low, piece.left_high, piece.right_low = pr:next(0, 1) == 1, pr:next(0, 1) == 1, pr:next(0, 1) == 1
			piece.right_high = pr:next(0, 2) > 0
		elseif kind == "room_crossing" then
			piece.type = pr:next(0, 4)
		elseif kind == "library" then
			piece.tall = tall
		elseif kind == "portal_room" then
			portal = piece
		end
		return piece
	end
	local function limited()
		local total, any = 0, false
		for _, w in ipairs(list) do
			any = any or w.max > 0 and w.count < w.max
			total = total + w.weight
		end
		return any, total
	end
	-- Minecraft's filler: when nothing fits, a stub of corridor 2 or 3 long up to the piece in the way
	local function filler(px, py, pz, d, depth)
		local box = orient(px, py, pz, {-1, -1, 0, 5, 5, 4}, d)
		local other = collides(box)
		if not other or other.box[2] ~= box[2] then
			return
		end
		for n = 2, 1, -1 do
			if not overlap(other.box, orient(px, py, pz, {-1, -1, 0, 5, 5, n}, d)) then
				box = orient(px, py, pz, {-1, -1, 0, 5, 5, n + 1}, d)
				return {kind = "filler", dir = d, depth = depth, box = box,
					steps = (d == "N" or d == "S") and box[6] - box[3] + 1 or box[4] - box[1] + 1}
			end
		end
	end
	local function pick(px, py, pz, d, depth)
		local any, total = limited()
		if not any then
			return
		end
		if imposed then
			local piece = make(imposed, px, py, pz, d, depth)
			imposed = nil
			if piece then
				return piece
			end
		end
		for _ = 1, 5 do
			local r = pr:next(0, total - 1)
			for i, w in ipairs(list) do
				r = r - w.weight
				if r < 0 then
					if (w.max > 0 and w.count >= w.max) or (w.depth and depth <= w.depth) or w == previous then
						break
					end
					local piece = make(w.kind, px, py, pz, d, depth)
					if piece then
						w.count = w.count + 1
						previous = w
						if w.max > 0 and w.count >= w.max then
							table.remove(list, i)
						end
						return piece
					end
				end
			end
		end
		return filler(px, py, pz, d, depth)
	end
	local function add(px, py, pz, d, depth)
		if depth > DEPTH or math.abs(px - start.box[1]) > REACH or math.abs(pz - start.box[3]) > REACH then
			return
		end
		local piece = pick(px, py, pz, d, depth + 1)
		if piece then
			pieces[#pieces + 1] = piece
			if piece.kind ~= "filler" and piece.kind ~= "library" and piece.kind ~= "portal_room" then
				pending[#pending + 1] = piece
			end
		end
	end
	-- the doors: ahead (across, up), to the left and to the right (up, along)
	local function forward(p, xo, yo)
		local b = p.box
		if p.dir == "N" then
			add(b[1] + xo, b[2] + yo, b[3] - 1, "N", p.depth)
		elseif p.dir == "S" then
			add(b[1] + xo, b[2] + yo, b[6] + 1, "S", p.depth)
		elseif p.dir == "W" then
			add(b[1] - 1, b[2] + yo, b[3] + xo, "W", p.depth)
		else
			add(b[4] + 1, b[2] + yo, b[3] + xo, "E", p.depth)
		end
	end
	local function left(p, yo, xzo)
		local b = p.box
		if p.dir == "N" or p.dir == "S" then
			add(b[1] - 1, b[2] + yo, b[3] + xzo, "W", p.depth)
		else
			add(b[1] + xzo, b[2] + yo, b[3] - 1, "N", p.depth)
		end
	end
	local function right(p, yo, xzo)
		local b = p.box
		if p.dir == "N" or p.dir == "S" then
			add(b[4] + 1, b[2] + yo, b[3] + xzo, "E", p.depth)
		else
			add(b[1] + xzo, b[2] + yo, b[6] + 1, "S", p.depth)
		end
	end
	local CHILDREN = {
		straight = function(p)
			forward(p, 1, 1)
			if p.left then
				left(p, 1, 2)
			end
			if p.right then
				right(p, 1, 2)
			end
		end,
		prison = function(p) forward(p, 1, 1) end,
		left_turn = function(p)
			if p.dir == "N" or p.dir == "E" then
				left(p, 1, 1)
			else
				right(p, 1, 1)
			end
		end,
		right_turn = function(p)
			if p.dir == "N" or p.dir == "E" then
				right(p, 1, 1)
			else
				left(p, 1, 1)
			end
		end,
		room_crossing = function(p)
			forward(p, 4, 1)
			left(p, 1, 4)
			right(p, 1, 4)
		end,
		straight_stairs = function(p) forward(p, 1, 1) end,
		stairs = function(p) forward(p, 1, 1) end,
		five_crossing = function(p)
			local lo, hi = 3, 5
			if p.dir == "W" or p.dir == "N" then
				lo, hi = 8 - lo, 8 - hi
			end
			forward(p, 5, 1)
			if p.left_low then
				left(p, lo, 1)
			end
			if p.left_high then
				left(p, hi, 7)
			end
			if p.right_low then
				right(p, lo, 1)
			end
			if p.right_high then
				right(p, hi, 7)
			end
		end,
		chest_corridor = function(p) forward(p, 1, 1) end,
	}

	CHILDREN.stairs(start)
	while #pending > 0 do
		local p = table.remove(pending, pr:next(1, #pending))
		CHILDREN[p.kind](p)
	end
	if not portal then
		return
	end

	-- sunk as Minecraft's moveBelowSeaLevel(sea, floor, random, 10)
	local y1, y2 = math.huge, -math.huge
	for _, p in ipairs(pieces) do
		y1, y2 = math.min(y1, p.box[2]), math.max(y2, p.box[5])
	end
	local top = SEA - 10
	local y = (y2 - y1 + 1) + FLOOR + 1
	if y < top then
		y = y + pr:next(0, top - y - 1)
	end
	local lift = y - y2
	for _, p in ipairs(pieces) do
		p.box[2], p.box[5] = p.box[2] + lift, p.box[5] + lift
	end
	return pieces, portal
end

-- the stronghold of ring i: its pieces, portal room and the box around them all (worked out once each)
local cache, cached = {}, 0
function F.pieces(i)
	if cache[i] == nil then
		if cached >= 16 then
			cache, cached = {}, 0
		end
		cached = cached + 1
		local c = RINGS[i]
		local pieces, portal
		for try = 0, 20 do
			local pr = PcgRandom((SEED + try + c.x * 341873128712 + c.z * 132897987541) % 2147483647)
			pieces, portal = walk(c.x * 16 + 2, c.z * 16 + 2, pr)
			if pieces then
				break
			end
		end
		local all = {math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge}
		for _, p in ipairs(pieces or {}) do
			for k = 1, 3 do
				all[k], all[k + 3] = math.min(all[k], p.box[k]), math.max(all[k + 3], p.box[k + 3])
			end
		end
		cache[i] = pieces and {pieces = pieces, portal = portal, box = all} or false
	end
	return cache[i] or nil
end

-- the strongholds that may reach into x1..x2, z1..z2 (every piece is within 112 and its size of its start)
local SPAN = REACH + 20
function F.each_near(x1, z1, x2, z2, fn)
	for i, c in ipairs(RINGS) do
		local sx, sz = c.x * 16 + 2, c.z * 16 + 2
		if sx >= x1 - SPAN and sx <= x2 + SPAN and sz >= z1 - SPAN and sz <= z2 + SPAN then
			local s = F.pieces(i)
			if s then
				fn(s, i)
			end
		end
	end
end

-- the portal room's middle, where the eye of ender leads (Minecraft's locator position)
function F.locator(i)
	local s = F.pieces(i)
	if s then
		local b = s.portal.box
		return {x = math.floor((b[1] + b[4]) / 2), y = math.floor((b[2] + b[5]) / 2), z = math.floor((b[3] + b[6]) / 2)}
	end
end

-- Drawing, in the map generator: a piece's own coordinates to the world's, as Minecraft turns them
local function world(p, x, y, z)
	local b = p.box
	if p.dir == "N" then
		return b[1] + x, b[2] + y, b[6] - z
	elseif p.dir == "S" then
		return b[1] + x, b[2] + y, b[3] + z
	elseif p.dir == "W" then
		return b[4] - z, b[2] + y, b[3] + x
	end
	return b[1] + z, b[2] + y, b[3] + x
end
F.world = world
-- a facing in the piece's terms ("N" its +z, "E" its +x...) as a direction in the world
local LOCAL = {N = {0, 1}, S = {0, -1}, E = {1, 0}, W = {-1, 0}}
local function facing(p, f)
	local v = LOCAL[f]
	if p.dir == "N" then
		return {x = v[1], y = 0, z = -v[2]}
	elseif p.dir == "S" then
		return {x = v[1], y = 0, z = v[2]}
	elseif p.dir == "W" then
		return {x = -v[2], y = 0, z = v[1]}
	end
	return {x = v[2], y = 0, z = v[1]}
end

local c = {}
local function ids()
	local id = core.get_content_id
	c.air, c.bricks = id("air"), id("default:stonebrick")
	c.cracked, c.mossy = id("goodluck_end:stonebrick_cracked"), id("goodluck_end:stonebrick_mossy")
	c.slab, c.double_slab = id("stairs:slab_stone_block"), id("default:stone_block")
	c.brick_slab, c.brick_stair = id("stairs:slab_stonebrick"), id("stairs:stair_stonebrick")
	c.cobble, c.cobble_stair = id("default:cobble"), id("stairs:stair_cobble")
	c.planks, c.fence, c.bookshelf = id("default:wood"), id("default:fence_wood"), id("default:bookshelf")
	c.web = core.registered_nodes["mobs:cobweb"] and id("mobs:cobweb") or c.air
	c.torch, c.wall_torch, c.ladder = id("default:torch"), id("default:torch_wall"), id("default:ladder_wood")
	c.bars, c.bars_flat = id("xpanes:bar"), id("xpanes:bar_flat")
	c.door_wood, c.door_steel, c.hidden = id("doors:door_wood_a"), id("doors:door_steel_a"), id("doors:hidden")
	c.lava, c.water = id("default:lava_source"), id("default:water_source")
	c.spawner, c.frame, c.frame_eye = id("goodluck_nether:spawner"), id("goodluck_end:frame"),
		id("goodluck_end:frame_eye")
	c.portal, c.chest = id("goodluck_end:portal"), id("default:chest")
	c.name = {}
	for k, v in pairs(c) do
		if type(v) == "number" then
			c.name[v] = core.get_name_from_content_id(v)
		end
	end
end

-- a node's own random, the same in whichever mapchunk draws it
local function hash(x, y, z, salt)
	local h = (x * 3129871 + z * 116129781 + y * 7919 + salt * 977 + SEED) % 2147483647
	h = h * 48271 % 2147483647
	h = h * 48271 % 2147483647
	return h / 2147483647
end

-- one piece into data (area) inside minp..maxp; what needs a param2 or metadata goes to out
local function draw(p, data, area, minp, maxp, out)
	local seed = p.seed or 0
	local function inside(x, y, z)
		return x >= minp.x and x <= maxp.x and y >= minp.y and y <= maxp.y and z >= minp.z and z <= maxp.z
	end
	-- Minecraft's SMOOTH_STONE_SELECTOR: on the box's faces 20 % cracked, 30 % mossy, the rest whole bricks (5 % of
	-- them infested, not here); air inside. skip: leave what is open already
	local function box(x1, y1, z1, x2, y2, z2, skip)
		for y = y1, y2 do
			for x = x1, x2 do
				for z = z1, z2 do
					local wx, wy, wz = world(p, x, y, z)
					if inside(wx, wy, wz) then
						local vi = area:index(wx, wy, wz)
						if not skip or data[vi] ~= c.air then
							local edge = y == y1 or y == y2 or x == x1 or x == x2 or z == z1 or z == z2
							if edge then
								local r = hash(wx, wy, wz, 1)
								data[vi] = r < 0.2 and c.cracked or r < 0.5 and c.mossy or c.bricks
							else
								data[vi] = c.air
							end
						end
					end
				end
			end
		end
	end
	local function fill(x1, y1, z1, x2, y2, z2, id)
		for y = y1, y2 do
			for x = x1, x2 do
				for z = z1, z2 do
					local wx, wy, wz = world(p, x, y, z)
					if inside(wx, wy, wz) then
						data[area:index(wx, wy, wz)] = id
					end
				end
			end
		end
	end
	local function put(x, y, z, id, param2)
		local wx, wy, wz = world(p, x, y, z)
		if inside(wx, wy, wz) then
			data[area:index(wx, wy, wz)] = id
			if param2 then
				out.nodes[#out.nodes + 1] = {x = wx, y = wy, z = wz, name = c.name[id], param2 = param2}
			end
		end
	end
	local function A(x1, y1, z1, x2, y2, z2) fill(x1, y1, z1, x2, y2, z2, c.air) end
	local function torch(x, y, z, f)
		put(x, y, z, c.wall_torch, core.dir_to_wallmounted(vector.multiply(facing(p, f), -1)))
	end
	local function ladder(x, y, z, f)
		put(x, y, z, c.ladder, core.dir_to_wallmounted(vector.multiply(facing(p, f), -1)))
	end
	local function stair(x, y, z, id, f)
		put(x, y, z, id, core.dir_to_facedir(facing(p, f)))
	end
	-- bars along the piece's x ("E") or z ("N")
	local function bars(x, y, z, along)
		local d = facing(p, along)
		put(x, y, z, c.bars_flat, d.x ~= 0 and 0 or 1)
	end
	local function chest(x, y, z, loot)
		local wx, wy, wz = world(p, x, y, z)
		if inside(wx, wy, wz) then
			data[area:index(wx, wy, wz)] = c.air
			out.chests[#out.chests + 1] = {x = wx, y = wy, z = wz, loot = loot}
		end
	end
	local function maybe(chance, x1, y1, z1, x2, y2, z2, id)
		for y = y1, y2 do
			for x = x1, x2 do
				for z = z1, z2 do
					local wx, wy, wz = world(p, x, y, z)
					if inside(wx, wy, wz) and hash(wx, wy, wz, 2) <= chance then
						data[area:index(wx, wy, wz)] = id
					end
				end
			end
		end
	end
	local function door(kind, x, y, z)
		if kind == "opening" then
			A(x, y, z, x + 2, y + 2, z)
		elseif kind == "wood" or kind == "iron" then
			fill(x, y, z, x, y + 2, z, c.bricks)
			fill(x + 1, y + 2, z, x + 2, y + 2, z, c.bricks)
			fill(x + 2, y, z, x + 2, y + 1, z, c.bricks)
			local fd = core.dir_to_facedir(facing(p, "N"))
			put(x + 1, y, z, kind == "wood" and c.door_wood or c.door_steel, fd)
			put(x + 1, y + 1, z, c.hidden, fd)
		elseif kind == "grates" then
			A(x + 1, y, z, x + 1, y + 1, z)
			for _, q in ipairs({{x, y}, {x, y + 1}, {x, y + 2}, {x + 1, y + 2}, {x + 2, y + 2}, {x + 2, y + 1},
					{x + 2, y}}) do
				bars(q[1], q[2], z, "E")
			end
		end
	end

	local k = p.kind
	if k == "straight" then
		box(0, 0, 0, 4, 4, 6, true)
		door(p.door, 1, 1, 0)
		door("opening", 1, 1, 6)
		for _, t in ipairs({{1, 2, 1, "E"}, {3, 2, 1, "W"}, {1, 2, 5, "E"}, {3, 2, 5, "W"}}) do
			local wx, wy, wz = world(p, t[1], t[2], t[3])
			if hash(wx, wy, wz, 3) < 0.1 then
				torch(t[1], t[2], t[3], t[4])
			end
		end
		if p.left then
			A(0, 1, 2, 0, 3, 4)
		end
		if p.right then
			A(4, 1, 2, 4, 3, 4)
		end
	elseif k == "prison" then
		box(0, 0, 0, 8, 4, 10, true)
		door(p.door, 1, 1, 0)
		A(1, 1, 10, 3, 3, 10)
		box(4, 1, 1, 4, 3, 1)
		box(4, 1, 3, 4, 3, 3)
		box(4, 1, 7, 4, 3, 7)
		box(4, 1, 9, 4, 3, 9)
		for y = 1, 3 do
			bars(4, y, 4, "N")
			bars(4, y, 5, "N")
			bars(4, y, 6, "N")
			bars(5, y, 5, "E")
			bars(6, y, 5, "E")
			bars(7, y, 5, "E")
		end
		bars(4, 3, 2, "N")
		bars(4, 3, 8, "N")
		local fd = core.dir_to_facedir(facing(p, "W"))
		for _, z in ipairs({2, 8}) do
			put(4, 1, z, c.door_steel, fd)
			put(4, 2, z, c.hidden, fd)
		end
	elseif k == "left_turn" or k == "right_turn" then
		box(0, 0, 0, 4, 4, 4, true)
		door(p.door, 1, 1, 0)
		local west = (k == "left_turn") == (p.dir == "N" or p.dir == "E")
		if west then
			A(0, 1, 1, 0, 3, 3)
		else
			A(4, 1, 1, 4, 3, 3)
		end
	elseif k == "room_crossing" then
		box(0, 0, 0, 10, 6, 10, true)
		door(p.door, 4, 1, 0)
		A(4, 1, 10, 6, 3, 10)
		A(0, 1, 4, 0, 3, 6)
		A(10, 1, 4, 10, 3, 6)
		if p.type == 0 then
			fill(5, 1, 5, 5, 3, 5, c.bricks)
			torch(4, 3, 5, "W")
			torch(6, 3, 5, "E")
			torch(5, 3, 4, "S")
			torch(5, 3, 6, "N")
			for _, q in ipairs({{4, 4}, {4, 5}, {4, 6}, {6, 4}, {6, 5}, {6, 6}, {5, 4}, {5, 6}}) do
				put(q[1], 1, q[2], c.slab)
			end
		elseif p.type == 1 then
			for i = 0, 4 do
				put(3, 1, 3 + i, c.bricks)
				put(7, 1, 3 + i, c.bricks)
				put(3 + i, 1, 3, c.bricks)
				put(3 + i, 1, 7, c.bricks)
			end
			fill(5, 1, 5, 5, 3, 5, c.bricks)
			put(5, 4, 5, c.water)
		elseif p.type == 2 then
			for i = 1, 9 do
				put(1, 3, i, c.cobble)
				put(9, 3, i, c.cobble)
				put(i, 3, 1, c.cobble)
				put(i, 3, 9, c.cobble)
			end
			for _, q in ipairs({{5, 1, 4}, {5, 1, 6}, {5, 3, 4}, {5, 3, 6}, {4, 1, 5}, {6, 1, 5}, {4, 3, 5}, {6, 3, 5}}) do
				put(q[1], q[2], q[3], c.cobble)
			end
			for y = 1, 3 do
				for _, q in ipairs({{4, 4}, {6, 4}, {4, 6}, {6, 6}}) do
					put(q[1], y, q[2], c.cobble)
				end
			end
			torch(5, 3, 5, "N")
			for z = 2, 8 do
				put(2, 3, z, c.planks)
				put(3, 3, z, c.planks)
				if z <= 3 or z >= 7 then
					for x = 4, 8 do
						put(x, 3, z, c.planks)
					end
				end
			end
			for y = 1, 3 do
				ladder(9, y, 3, "W")
			end
			chest(3, 4, 8, "crossing")
		end
	elseif k == "straight_stairs" then
		box(0, 0, 0, 4, 10, 7, true)
		door(p.door, 1, 7, 0)
		door("opening", 1, 1, 7)
		for i = 0, 5 do
			for x = 1, 3 do
				stair(x, 6 - i, 1 + i, c.cobble_stair, "S")
				if i < 5 then
					put(x, 5 - i, 1 + i, c.bricks)
				end
			end
		end
	elseif k == "stairs" then
		box(0, 0, 0, 4, 10, 4, true)
		door(p.door, 1, 7, 0)
		door("opening", 1, 1, 4)
		put(2, 6, 1, c.bricks)
		put(1, 5, 1, c.bricks)
		put(1, 6, 1, c.slab)
		put(1, 5, 2, c.bricks)
		put(1, 4, 3, c.bricks)
		put(1, 5, 3, c.slab)
		put(2, 4, 3, c.bricks)
		put(3, 3, 3, c.bricks)
		put(3, 4, 3, c.slab)
		put(3, 3, 2, c.bricks)
		put(3, 2, 1, c.bricks)
		put(3, 3, 1, c.slab)
		put(2, 2, 1, c.bricks)
		put(1, 1, 1, c.bricks)
		put(1, 2, 1, c.slab)
		put(1, 1, 2, c.bricks)
		put(1, 1, 3, c.slab)
	elseif k == "five_crossing" then
		box(0, 0, 0, 9, 8, 10, true)
		door(p.door, 4, 3, 0)
		if p.left_low then
			A(0, 3, 1, 0, 5, 3)
		end
		if p.right_low then
			A(9, 3, 1, 9, 5, 3)
		end
		if p.left_high then
			A(0, 5, 7, 0, 7, 9)
		end
		if p.right_high then
			A(9, 5, 7, 9, 7, 9)
		end
		A(5, 1, 10, 7, 3, 10)
		box(1, 2, 1, 8, 2, 6)
		box(4, 1, 5, 4, 4, 9)
		box(8, 1, 5, 8, 4, 9)
		box(1, 4, 7, 3, 4, 9)
		box(1, 3, 5, 3, 3, 6)
		fill(1, 3, 4, 3, 3, 4, c.slab)
		fill(1, 4, 6, 3, 4, 6, c.slab)
		box(5, 1, 7, 7, 1, 8)
		fill(5, 1, 9, 7, 1, 9, c.slab)
		fill(5, 2, 7, 7, 2, 7, c.slab)
		fill(4, 5, 7, 4, 5, 9, c.slab)
		fill(8, 5, 7, 8, 5, 9, c.slab)
		fill(5, 5, 7, 7, 5, 9, c.double_slab)
		torch(6, 5, 6, "S")
	elseif k == "chest_corridor" then
		box(0, 0, 0, 4, 4, 6, true)
		door(p.door, 1, 1, 0)
		door("opening", 1, 1, 6)
		fill(3, 1, 2, 3, 1, 4, c.bricks)
		put(3, 1, 1, c.brick_slab)
		put(3, 1, 5, c.brick_slab)
		put(3, 2, 2, c.brick_slab)
		put(3, 2, 4, c.brick_slab)
		for z = 2, 4 do
			put(2, 1, z, c.brick_slab)
		end
		chest(3, 2, 3, "corridor")
	elseif k == "filler" then
		for z = 0, p.steps - 1 do
			fill(0, 0, z, 4, 0, z, c.bricks)
			fill(0, 4, z, 4, 4, z, c.bricks)
			fill(0, 1, z, 0, 3, z, c.bricks)
			fill(4, 1, z, 4, 3, z, c.bricks)
			A(1, 1, z, 3, 3, z)
		end
	elseif k == "library" then
		local h = p.tall and 11 or 6
		box(0, 0, 0, 13, h - 1, 14, true)
		door(p.door, 4, 1, 0)
		maybe(0.07, 2, 1, 1, 11, 4, 13, c.web)
		for z = 1, 13 do
			local id = (z - 1) % 4 == 0 and c.planks or c.bookshelf
			fill(1, 1, z, 1, 4, z, id)
			fill(12, 1, z, 12, 4, z, id)
			if (z - 1) % 4 == 0 then
				torch(2, 3, z, "E")
				torch(11, 3, z, "W")
			end
			if p.tall then
				fill(1, 6, z, 1, 9, z, id)
				fill(12, 6, z, 12, 9, z, id)
			end
		end
		for z = 3, 11, 2 do
			fill(3, 1, z, 4, 3, z, c.bookshelf)
			fill(6, 1, z, 7, 3, z, c.bookshelf)
			fill(9, 1, z, 10, 3, z, c.bookshelf)
		end
		if p.tall then
			fill(1, 5, 1, 3, 5, 13, c.planks)
			fill(10, 5, 1, 12, 5, 13, c.planks)
			fill(4, 5, 1, 9, 5, 2, c.planks)
			fill(4, 5, 12, 9, 5, 13, c.planks)
			put(9, 5, 11, c.planks)
			put(8, 5, 11, c.planks)
			put(9, 5, 10, c.planks)
			fill(3, 6, 3, 3, 6, 11, c.fence)
			fill(10, 6, 3, 10, 6, 9, c.fence)
			fill(4, 6, 2, 9, 6, 2, c.fence)
			fill(4, 6, 12, 7, 6, 12, c.fence)
			put(3, 6, 2, c.fence)
			put(3, 6, 12, c.fence)
			put(10, 6, 2, c.fence)
			for i = 0, 2 do
				put(8 + i, 6, 12 - i, c.fence)
				if i ~= 2 then
					put(8 + i, 6, 11 - i, c.fence)
				end
			end
			for y = 1, 7 do
				ladder(10, y, 13, "S")
			end
			-- the chandelier
			for _, q in ipairs({{6, 9, 7}, {7, 9, 7}, {6, 8, 7}, {7, 8, 7}, {6, 7, 7}, {7, 7, 7}, {5, 7, 7}, {8, 7, 7},
					{6, 7, 6}, {6, 7, 8}, {7, 7, 6}, {7, 7, 8}}) do
				put(q[1], q[2], q[3], c.fence)
			end
			for _, q in ipairs({{5, 8, 7}, {8, 8, 7}, {6, 8, 6}, {6, 8, 8}, {7, 8, 6}, {7, 8, 8}}) do
				put(q[1], q[2], q[3], c.torch, 1)
			end
		end
		chest(3, 3, 5, "library")
		if p.tall then
			put(12, 9, 1, c.air)
			chest(12, 8, 1, "library")
		end
	elseif k == "portal_room" then
		box(0, 0, 0, 10, 7, 15)
		door("grates", 4, 1, 0)
		box(1, 6, 1, 1, 6, 14)
		box(9, 6, 1, 9, 6, 14)
		box(2, 6, 1, 8, 6, 2)
		box(2, 6, 14, 8, 6, 14)
		box(1, 1, 1, 2, 1, 4)
		box(8, 1, 1, 9, 1, 4)
		fill(1, 1, 1, 1, 1, 3, c.lava)
		fill(9, 1, 1, 9, 1, 3, c.lava)
		box(3, 1, 8, 7, 1, 12)
		fill(4, 1, 9, 6, 1, 11, c.lava)
		for z = 3, 13, 2 do
			for y = 3, 4 do
				bars(0, y, z, "N")
				bars(10, y, z, "N")
			end
		end
		for x = 2, 8, 2 do
			for y = 3, 4 do
				bars(x, y, 15, "E")
			end
		end
		box(4, 1, 5, 6, 1, 7)
		box(4, 2, 6, 6, 2, 7)
		box(4, 3, 7, 6, 3, 7)
		for x = 4, 6 do
			stair(x, 1, 4, c.brick_stair, "N")
			stair(x, 2, 5, c.brick_stair, "N")
			stair(x, 3, 6, c.brick_stair, "N")
		end
		-- the 12 frames, an eye in each 1 time in 10; all 12 and the portal is lit already
		local frames = {{4, 8, "N"}, {5, 8, "N"}, {6, 8, "N"}, {4, 12, "S"}, {5, 12, "S"}, {6, 12, "S"},
			{3, 9, "E"}, {3, 10, "E"}, {3, 11, "E"}, {7, 9, "W"}, {7, 10, "W"}, {7, 11, "W"}}
		local pr = PcgRandom(seed)
		local all = true
		for _, f in ipairs(frames) do
			local eye = pr:next(0, 9) == 0
			all = all and eye
			put(f[1], 3, f[2], eye and c.frame_eye or c.frame, core.dir_to_facedir(facing(p, f[3])))
		end
		if all then
			fill(4, 3, 9, 6, 3, 11, c.portal)
		end
		-- the spawner on the top step, after the stairs (which are set with their param2 once the data is written)
		local wx, wy, wz = world(p, 5, 3, 6)
		if inside(wx, wy, wz) then
			put(5, 3, 6, c.spawner, 0)
			out.spawners[#out.spawners + 1] = {x = wx, y = wy, z = wz}
		end
	end
end

-- the pieces of every stronghold in minp..maxp, drawn into data; nil when there are none
function F.draw(data, area, minp, maxp)
	if not c.air then
		ids()
	end
	local out
	F.each_near(minp.x, minp.z, maxp.x, maxp.z, function(s)
		local b = s.box
		if b[2] > maxp.y or b[5] < minp.y or b[1] > maxp.x or b[4] < minp.x or b[3] > maxp.z or b[6] < minp.z then
			return
		end
		for _, p in ipairs(s.pieces) do
			local pb = p.box
			if pb[1] <= maxp.x and pb[4] >= minp.x and pb[2] <= maxp.y and pb[5] >= minp.y and pb[3] <= maxp.z and
					pb[6] >= minp.z then
				out = out or {nodes = {}, chests = {}, spawners = {}, pieces = 0}
				draw(p, data, area, minp, maxp, out)
				out.pieces = out.pieces + 1
			end
		end
	end)
	return out
end

-- In the map generator's threads: the strongholds into the Overworld's mapchunks they reach
if core.save_gen_notify then
	local buf = {}
	core.register_on_generated(function(vm, minp, maxp)
		if maxp.y < FLOOR - 64 or minp.y > SEA + 20 then
			return
		end
		local near = false
		F.each_near(minp.x, minp.z, maxp.x, maxp.z, function(s)
			local b = s.box
			near = near or not (b[2] > maxp.y or b[5] < minp.y or b[1] > maxp.x or b[4] < minp.x or b[3] > maxp.z or
				b[6] < minp.z)
		end)
		if not near then
			return
		end
		local t0 = core.get_us_time()
		local emin, emax = vm:get_emerged_area()
		vm:get_data(buf)
		local made = F.draw(buf, VoxelArea(emin, emax), minp, maxp)
		if made then
			vm:set_data(buf)
			for _, n in ipairs(made.nodes) do
				vm:set_node_at(n, n)
			end
			vm:update_liquids()
			vm:calc_lighting()
			core.save_gen_notify("goodluck_end:stronghold", {chests = made.chests, spawners = made.spawners,
				pieces = made.pieces, us = core.get_us_time() - t0})
		end
	end)
end

return F
