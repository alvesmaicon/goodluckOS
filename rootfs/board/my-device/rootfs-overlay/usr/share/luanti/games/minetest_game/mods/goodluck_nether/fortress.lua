-- Nether fortresses as Minecraft builds them, in both the map generator's threads and the game: one in each region of
-- 27x27 Minecraft chunks (432 nodes), its start in the first 23 of them each way; from a bridge crossing at 64, a random
-- walk of Minecraft's pieces by their weights and limits (bridges, crossings, the blaze throne, the castle and its
-- corridors, stairs, balconies and the wart room), up to 30 deep and 112 from the start, then the whole lifted so
-- that it starts between 48 and 70 above the floor. Every mapchunk draws its own share of the same walk; the game
-- asks it where the pieces are (its monsters come out only inside them)
local F = {}
local R = core.ipc_get("goodluck_nether:realm")
local SEED = (tonumber(core.get_mapgen_setting("seed")) or 0) % 2147483647
local REGION, SPREAD, REACH = 27 * 16, 23, 112

local BRIDGE = {
	{kind = "bridge_straight", weight = 30, max = 0, in_row = true},
	{kind = "bridge_crossing", weight = 10, max = 4},
	{kind = "room_crossing", weight = 10, max = 4},
	{kind = "stairs_room", weight = 10, max = 3},
	{kind = "monster_throne", weight = 5, max = 2},
	{kind = "castle_entrance", weight = 5, max = 1},
}
local CASTLE = {
	{kind = "corridor", weight = 25, max = 0, in_row = true},
	{kind = "corridor_crossing", weight = 15, max = 5},
	{kind = "corridor_right", weight = 5, max = 10},
	{kind = "corridor_left", weight = 5, max = 10},
	{kind = "corridor_stairs", weight = 10, max = 3, in_row = true},
	{kind = "balcony", weight = 7, max = 2},
	{kind = "stalk_room", weight = 5, max = 2},
}
-- where each piece starts from the door it is reached by, and its size across, up and along
local SHAPE = {
	bridge_straight = {-1, -3, 0, 5, 10, 19}, bridge_crossing = {-8, -3, 0, 19, 10, 19},
	room_crossing = {-2, 0, 0, 7, 9, 7}, stairs_room = {-2, 0, 0, 7, 11, 7}, monster_throne = {-2, 0, 0, 7, 8, 9},
	castle_entrance = {-5, -3, 0, 13, 14, 13}, corridor = {-1, 0, 0, 5, 7, 5}, corridor_crossing = {-1, 0, 0, 5, 7, 5},
	corridor_right = {-1, 0, 0, 5, 7, 5}, corridor_left = {-1, 0, 0, 5, 7, 5}, corridor_stairs = {-1, -7, 0, 5, 14, 10},
	balcony = {-3, 0, 0, 9, 7, 9}, stalk_room = {-5, -3, 0, 13, 14, 13}, end_filler = {-1, -3, 0, 5, 10, 8},
}

-- the box of a piece reached at x, y, z going dir ("N", "S", "W" or "E")
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

-- the walk from a start at x, z (Minecraft's height), pr its random
local function walk(x, z, pr)
	local dir = ({"N", "E", "S", "W"})[pr:next(1, 4)]
	local start = {kind = "bridge_crossing", dir = dir, depth = 0, box = {x, 64, z, x + 18, 73, z + 18}}
	local pieces, pending = {start}, {}
	local lists = {bridge = {}, castle = {}}
	for name, list in pairs({bridge = BRIDGE, castle = CASTLE}) do
		for i, w in ipairs(list) do
			lists[name][i] = {kind = w.kind, weight = w.weight, max = w.max, in_row = w.in_row, count = 0}
		end
	end
	local previous

	local function free(box)
		if box[2] <= 10 then
			return false
		end
		for _, p in ipairs(pieces) do
			if overlap(p.box, box) then
				return false
			end
		end
		return true
	end
	local function make(kind, px, py, pz, d, depth)
		local box = orient(px, py, pz, SHAPE[kind], d)
		if not free(box) then
			return
		end
		local piece = {kind = kind, dir = d, depth = depth, box = box}
		if kind == "corridor_right" or kind == "corridor_left" then
			piece.chest = pr:next(0, 2) == 0
		elseif kind == "end_filler" then
			piece.seed = pr:next(0, 2147483646)
		end
		return piece
	end
	local function available(w)
		return w.max == 0 or w.count < w.max
	end
	local function pick(list, px, py, pz, d, depth)
		local total, limited = 0, false
		for _, w in ipairs(list) do
			limited = limited or w.max > 0 and w.count < w.max
			total = total + w.weight
		end
		if limited and depth <= 30 then
			for _ = 1, 5 do
				local r = pr:next(0, total - 1)
				for i, w in ipairs(list) do
					r = r - w.weight
					if r < 0 then
						if not available(w) or w == previous and not w.in_row then
							break
						end
						local piece = make(w.kind, px, py, pz, d, depth)
						if piece then
							w.count = w.count + 1
							previous = w
							if not available(w) then
								table.remove(list, i)
							end
							return piece
						end
					end
				end
			end
		end
		return make("end_filler", px, py, pz, d, depth)
	end
	local function add(px, py, pz, d, depth, castle)
		if math.abs(px - start.box[1]) > REACH or math.abs(pz - start.box[3]) > REACH then
			return
		end
		local piece = pick(castle and lists.castle or lists.bridge, px, py, pz, d, depth + 1)
		if piece then
			pieces[#pieces + 1] = piece
			pending[#pending + 1] = piece
		end
	end
	-- the doors: straight on (across, up), to the left and to the right (up, along)
	local function forward(p, xo, yo, castle)
		local b = p.box
		if p.dir == "N" then
			add(b[1] + xo, b[2] + yo, b[3] - 1, "N", p.depth, castle)
		elseif p.dir == "S" then
			add(b[1] + xo, b[2] + yo, b[6] + 1, "S", p.depth, castle)
		elseif p.dir == "W" then
			add(b[1] - 1, b[2] + yo, b[3] + xo, "W", p.depth, castle)
		else
			add(b[4] + 1, b[2] + yo, b[3] + xo, "E", p.depth, castle)
		end
	end
	local function left(p, yo, xzo, castle)
		local b = p.box
		if p.dir == "N" or p.dir == "S" then
			add(b[1] - 1, b[2] + yo, b[3] + xzo, "W", p.depth, castle)
		else
			add(b[1] + xzo, b[2] + yo, b[3] - 1, "N", p.depth, castle)
		end
	end
	local function right(p, yo, xzo, castle)
		local b = p.box
		if p.dir == "N" or p.dir == "S" then
			add(b[4] + 1, b[2] + yo, b[3] + xzo, "E", p.depth, castle)
		else
			add(b[1] + xzo, b[2] + yo, b[6] + 1, "S", p.depth, castle)
		end
	end
	local CHILDREN = {
		bridge_straight = function(p) forward(p, 1, 3, false) end,
		bridge_crossing = function(p)
			forward(p, 8, 3, false)
			left(p, 3, 8, false)
			right(p, 3, 8, false)
		end,
		room_crossing = function(p)
			forward(p, 2, 0, false)
			left(p, 0, 2, false)
			right(p, 0, 2, false)
		end,
		stairs_room = function(p) right(p, 6, 2, false) end,
		castle_entrance = function(p) forward(p, 5, 3, true) end,
		corridor = function(p) forward(p, 1, 0, true) end,
		corridor_crossing = function(p)
			forward(p, 1, 0, true)
			left(p, 0, 1, true)
			right(p, 0, 1, true)
		end,
		corridor_right = function(p) right(p, 0, 1, true) end,
		corridor_left = function(p) left(p, 0, 1, true) end,
		corridor_stairs = function(p) forward(p, 1, 0, true) end,
		balcony = function(p)
			local o = (p.dir == "W" or p.dir == "N") and 5 or 1
			left(p, 0, o, pr:next(0, 7) > 0)
			right(p, 0, o, pr:next(0, 7) > 0)
		end,
		stalk_room = function(p)
			forward(p, 5, 3, true)
			forward(p, 5, 11, true)
		end,
	}

	CHILDREN.bridge_crossing(start)
	while #pending > 0 do
		local p = table.remove(pending, pr:next(1, #pending))
		if CHILDREN[p.kind] then
			CHILDREN[p.kind](p)
		end
	end

	-- lifted between 48 and 70 if it fits, and to the realm's floor
	local y1, y2 = math.huge, -math.huge
	for _, p in ipairs(pieces) do
		y1, y2 = math.min(y1, p.box[2]), math.max(y2, p.box[5])
	end
	local room = 70 - 48 + 1 - (y2 - y1 + 1)
	local lift = (room > 1 and 48 + pr:next(0, room - 1) or 48) - y1 + R.ymin
	for _, p in ipairs(pieces) do
		p.box[2], p.box[5] = p.box[2] + lift, p.box[5] + lift
	end
	return pieces
end

-- the fortress of the region rx, rz: its start, and its pieces (worked out once)
local cache, cached = {}, 0
function F.start(rx, rz)
	local pr = PcgRandom((SEED + rx * 9161 + rz * 31337 + 30084232) % 2147483647)
	return (rx * 27 + pr:next(0, SPREAD - 1)) * 16 + 2, (rz * 27 + pr:next(0, SPREAD - 1)) * 16 + 2, pr
end
function F.pieces(rx, rz)
	local key = rx .. "," .. rz
	if not cache[key] then
		if cached >= 16 then
			cache, cached = {}, 0
		end
		local x, z, pr = F.start(rx, rz)
		cache[key], cached = walk(x, z, pr), cached + 1
	end
	return cache[key]
end

-- the fortresses that may reach into x1..x2, z1..z2: each piece is within 112 and its own size of its start
local SPAN = REACH + 20
function F.each_near(x1, z1, x2, z2, fn)
	for rx = math.floor((x1 - SPAN) / REGION), math.floor((x2 + SPAN) / REGION) do
		for rz = math.floor((z1 - SPAN) / REGION), math.floor((z2 + SPAN) / REGION) do
			local sx, sz = F.start(rx, rz)
			if sx >= x1 - SPAN and sx <= x2 + SPAN and sz >= z1 - SPAN and sz <= z2 + SPAN then
				fn(F.pieces(rx, rz), rx, rz)
			end
		end
	end
end

-- the piece pos is in, if any
function F.piece_at(pos)
	if pos.y < R.ymin or pos.y > R.ymax then
		return
	end
	local x, y, z = math.floor(pos.x + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + 0.5)
	local found
	F.each_near(x, z, x, z, function(pieces)
		for _, p in ipairs(pieces) do
			local b = p.box
			if not found and x >= b[1] and x <= b[4] and y >= b[2] and y <= b[5] and z >= b[3] and z <= b[6] then
				found = p
			end
		end
	end)
	return found
end

-- Drawing, in the map generator: a piece's own coordinates (across, up, along from its door) to the world's, as
-- Minecraft turns them; facings given in the piece's own terms ("N" ahead, "S" back, "E" right, "W" left)
local function world(p, x, y, z)
	local b = p.box
	local wx, wz
	if p.dir == "N" then
		wx, wz = b[1] + x, b[6] - z
	elseif p.dir == "S" then
		wx, wz = b[1] + x, b[3] + z
	elseif p.dir == "W" then
		wx, wz = b[4] - z, b[3] + x
	else
		wx, wz = b[1] + z, b[3] + x
	end
	return wx, b[2] + y, wz
end
F.world = world
local LOCAL = {N = {0, 1}, S = {0, -1}, E = {1, 0}, W = {-1, 0}}
local function facedir(p, facing)
	local v = LOCAL[facing]
	local dx, dz
	if p.dir == "N" then
		dx, dz = v[1], -v[2]
	elseif p.dir == "S" then
		dx, dz = v[1], v[2]
	elseif p.dir == "W" then
		dx, dz = -v[2], v[1]
	else
		dx, dz = v[2], v[1]
	end
	return core.dir_to_facedir({x = dx, y = 0, z = dz})
end

local c = {}
local function ids()
	local id = core.get_content_id
	c.air, c.bricks = id("air"), id("goodluck_nether:nether_bricks")
	c.fence, c.stairs = id("goodluck_nether:nether_brick_fence"), id("stairs:stair_nether_bricks")
	c.soul_sand, c.wart = id("goodluck_nether:soul_sand"), id("goodluck_nether:nether_wart_0")
	c.lava, c.spawner, c.chest = id("default:lava_source"), id("goodluck_nether:spawner"), id("default:chest")
	c.open = {[c.air] = true, [c.lava] = true, [id("default:lava_flowing")] = true,
		[id("default:water_source")] = true, [id("default:water_flowing")] = true}
end

-- one piece into data (area) inside minp..maxp; what needs a param2 or metadata goes to out
local function draw(p, data, area, minp, maxp, out)
	-- a box of one block, turned to the world and cut to the mapchunk
	local function fill(x1, y1, z1, x2, y2, z2, id)
		local ax, ay, az = world(p, x1, y1, z1)
		local bx, by, bz = world(p, x2, y2, z2)
		if ax > bx then
			ax, bx = bx, ax
		end
		if az > bz then
			az, bz = bz, az
		end
		ax, bx = math.max(ax, minp.x), math.min(bx, maxp.x)
		ay, by = math.max(ay, minp.y), math.min(by, maxp.y)
		az, bz = math.max(az, minp.z), math.min(bz, maxp.z)
		for wz = az, bz do
			for wy = ay, by do
				local vi = area:index(ax, wy, wz)
				for _ = ax, bx do
					data[vi] = id
					vi = vi + 1
				end
			end
		end
	end
	local function inside(x, y, z)
		return x >= minp.x and x <= maxp.x and y >= minp.y and y <= maxp.y and z >= minp.z and z <= maxp.z
	end
	local function B(x1, y1, z1, x2, y2, z2) fill(x1, y1, z1, x2, y2, z2, c.bricks) end
	local function A(x1, y1, z1, x2, y2, z2) fill(x1, y1, z1, x2, y2, z2, c.air) end
	local function F(x1, y1, z1, x2, y2, z2) fill(x1, y1, z1, x2, y2, z2, c.fence) end
	-- a block that needs its param2 (set once the mapchunk is written)
	local function put(x, y, z, id, name, param2)
		local wx, wy, wz = world(p, x, y, z)
		if inside(wx, wy, wz) then
			data[area:index(wx, wy, wz)] = id
			out.nodes[#out.nodes + 1] = {x = wx, y = wy, z = wz, name = name, param2 = param2}
		end
	end
	local function stair(x, y, z, facing)
		put(x, y, z, c.stairs, "stairs:stair_nether_bricks", facedir(p, facing))
	end
	-- the pillars under it, down through air and liquid to the ground (from the mapchunk's top when it starts above)
	local function P(x1, z1, x2, z2)
		for x = x1, x2 do
			for z = z1, z2 do
				local wx, wy, wz = world(p, x, -1, z)
				if wx >= minp.x and wx <= maxp.x and wz >= minp.z and wz <= maxp.z and wy >= minp.y then
					wy = math.min(wy, maxp.y)
					local vi = area:index(wx, wy, wz)
					while wy >= minp.y and wy > R.ymin + 1 and c.open[data[vi]] do
						data[vi] = c.bricks
						wy, vi = wy - 1, vi - area.ystride
					end
				end
			end
		end
	end

	local k = p.kind
	if k == "bridge_straight" then
		B(0, 3, 0, 4, 4, 18)
		A(1, 5, 0, 3, 7, 18)
		B(0, 5, 0, 0, 5, 18)
		B(4, 5, 0, 4, 5, 18)
		B(0, 2, 0, 4, 2, 5)
		B(0, 2, 13, 4, 2, 18)
		B(0, 0, 0, 4, 1, 3)
		B(0, 0, 15, 4, 1, 18)
		P(0, 0, 4, 2)
		P(0, 16, 4, 18)
		F(0, 1, 1, 0, 4, 1)
		F(0, 3, 4, 0, 4, 4)
		F(0, 3, 14, 0, 4, 14)
		F(0, 1, 17, 0, 4, 17)
		F(4, 1, 1, 4, 4, 1)
		F(4, 3, 4, 4, 4, 4)
		F(4, 3, 14, 4, 4, 14)
		F(4, 1, 17, 4, 4, 17)
	elseif k == "end_filler" then
		local pr = PcgRandom(p.seed)
		for x = 0, 4 do
			for y = 3, 4 do
				B(x, y, 0, x, y, pr:next(0, 7))
			end
		end
		B(0, 5, 0, 0, 5, pr:next(0, 7))
		B(4, 5, 0, 4, 5, pr:next(0, 7))
		for x = 0, 4 do
			B(x, 2, 0, x, 2, pr:next(0, 4))
		end
		for x = 0, 4 do
			for y = 0, 1 do
				B(x, y, 0, x, y, pr:next(0, 2))
			end
		end
	elseif k == "bridge_crossing" then
		B(7, 3, 0, 11, 4, 18)
		B(0, 3, 7, 18, 4, 11)
		A(8, 5, 0, 10, 7, 18)
		A(0, 5, 8, 18, 7, 10)
		B(7, 5, 0, 7, 5, 7)
		B(7, 5, 11, 7, 5, 18)
		B(11, 5, 0, 11, 5, 7)
		B(11, 5, 11, 11, 5, 18)
		B(0, 5, 7, 7, 5, 7)
		B(11, 5, 7, 18, 5, 7)
		B(0, 5, 11, 7, 5, 11)
		B(11, 5, 11, 18, 5, 11)
		B(7, 2, 0, 11, 2, 5)
		B(7, 2, 13, 11, 2, 18)
		B(7, 0, 0, 11, 1, 3)
		B(7, 0, 15, 11, 1, 18)
		P(7, 0, 11, 2)
		P(7, 16, 11, 18)
		B(0, 2, 7, 5, 2, 11)
		B(13, 2, 7, 18, 2, 11)
		B(0, 0, 7, 3, 1, 11)
		B(15, 0, 7, 18, 1, 11)
		P(0, 7, 2, 11)
		P(16, 7, 18, 11)
	elseif k == "room_crossing" or k == "stairs_room" then
		local stairs = k == "stairs_room"
		B(0, 0, 0, 6, 1, 6)
		A(0, 2, 0, 6, stairs and 10 or 7, 6)
		if stairs then
			B(0, 2, 0, 1, 8, 0)
			B(5, 2, 0, 6, 8, 0)
			B(0, 2, 1, 0, 8, 6)
			B(6, 2, 1, 6, 8, 6)
			B(1, 2, 6, 5, 8, 6)
			F(0, 3, 2, 0, 5, 4)
			F(6, 3, 2, 6, 5, 2)
			F(6, 3, 4, 6, 5, 4)
			B(5, 2, 5, 5, 2, 5)
			B(4, 2, 5, 4, 3, 5)
			B(3, 2, 5, 3, 4, 5)
			B(2, 2, 5, 2, 5, 5)
			B(1, 2, 5, 1, 6, 5)
			B(1, 7, 1, 5, 7, 4)
			A(6, 8, 2, 6, 8, 4)
			B(2, 6, 0, 4, 8, 0)
			F(2, 5, 0, 4, 5, 0)
		else
			B(0, 2, 0, 1, 6, 0)
			B(0, 2, 6, 1, 6, 6)
			B(5, 2, 0, 6, 6, 0)
			B(5, 2, 6, 6, 6, 6)
			B(0, 2, 0, 0, 6, 1)
			B(0, 2, 5, 0, 6, 6)
			B(6, 2, 0, 6, 6, 1)
			B(6, 2, 5, 6, 6, 6)
			B(2, 6, 0, 4, 6, 0)
			F(2, 5, 0, 4, 5, 0)
			B(2, 6, 6, 4, 6, 6)
			F(2, 5, 6, 4, 5, 6)
			B(0, 6, 2, 0, 6, 4)
			F(0, 5, 2, 0, 5, 4)
			B(6, 6, 2, 6, 6, 4)
			F(6, 5, 2, 6, 5, 4)
		end
		P(0, 0, 6, 6)
	elseif k == "monster_throne" then
		A(0, 2, 0, 6, 7, 7)
		B(1, 0, 0, 5, 1, 7)
		B(1, 2, 1, 5, 2, 7)
		B(1, 3, 2, 5, 3, 7)
		B(1, 4, 3, 5, 4, 7)
		B(1, 2, 0, 1, 4, 2)
		B(5, 2, 0, 5, 4, 2)
		B(1, 5, 2, 1, 5, 3)
		B(5, 5, 2, 5, 5, 3)
		B(0, 5, 3, 0, 5, 8)
		B(6, 5, 3, 6, 5, 8)
		B(1, 5, 8, 5, 5, 8)
		F(1, 6, 3, 1, 6, 3)
		F(5, 6, 3, 5, 6, 3)
		F(0, 6, 3, 0, 6, 8)
		F(6, 6, 3, 6, 6, 8)
		F(1, 6, 8, 5, 6, 8)
		F(1, 7, 8, 5, 7, 8)
		F(2, 8, 8, 4, 8, 8)
		local wx, wy, wz = world(p, 3, 5, 5)
		if inside(wx, wy, wz) then
			data[area:index(wx, wy, wz)] = c.spawner
			out.spawners[#out.spawners + 1] = {x = wx, y = wy, z = wz}
		end
		P(0, 0, 6, 6)
	elseif k == "castle_entrance" or k == "stalk_room" then
		B(0, 3, 0, 12, 4, 12)
		A(0, 5, 0, 12, 13, 12)
		B(0, 5, 0, 1, 12, 12)
		B(11, 5, 0, 12, 12, 12)
		B(2, 5, 11, 4, 12, 12)
		B(8, 5, 11, 10, 12, 12)
		B(5, 9, 11, 7, 12, 12)
		B(2, 5, 0, 4, 12, 1)
		B(8, 5, 0, 10, 12, 1)
		B(5, 9, 0, 7, 12, 1)
		B(2, 11, 2, 10, 12, 10)
		if k == "castle_entrance" then
			F(5, 8, 0, 7, 8, 0)
		end
		for i = 1, 11, 2 do
			F(i, 10, 0, i, 11, 0)
			F(i, 10, 12, i, 11, 12)
			F(0, 10, i, 0, 11, i)
			F(12, 10, i, 12, 11, i)
			B(i, 13, 0, i, 13, 0)
			B(i, 13, 12, i, 13, 12)
			B(0, 13, i, 0, 13, i)
			B(12, 13, i, 12, 13, i)
			if i ~= 11 then
				F(i + 1, 13, 0, i + 1, 13, 0)
				F(i + 1, 13, 12, i + 1, 13, 12)
				F(0, 13, i + 1, 0, 13, i + 1)
				F(12, 13, i + 1, 12, 13, i + 1)
			end
		end
		F(0, 13, 0, 0, 13, 0)
		F(0, 13, 12, 0, 13, 12)
		F(12, 13, 12, 12, 13, 12)
		F(12, 13, 0, 12, 13, 0)
		for i = 3, 9, 2 do
			F(1, 7, i, 1, 8, i)
			F(11, 7, i, 11, 8, i)
		end
		if k == "stalk_room" then
			-- the stairs up to the upper door, and the wart in two beds of soul sand
			for i = 0, 6 do
				local z = i + 4
				for x = 5, 7 do
					stair(x, 5 + i, z, "N")
				end
				if z >= 5 and z <= 8 then
					B(5, 5, z, 7, i + 4, z)
				elseif z >= 9 and z <= 10 then
					B(5, 8, z, 7, i + 4, z)
				end
				if i >= 1 then
					A(5, 6 + i, z, 7, 9 + i, z)
				end
			end
			for x = 5, 7 do
				stair(x, 12, 11, "N")
			end
			F(5, 6, 7, 5, 7, 7)
			F(7, 6, 7, 7, 7, 7)
			A(5, 13, 12, 7, 13, 12)
			B(2, 5, 2, 3, 5, 3)
			B(2, 5, 9, 3, 5, 10)
			B(2, 5, 4, 2, 5, 8)
			B(9, 5, 2, 10, 5, 3)
			B(9, 5, 9, 10, 5, 10)
			B(10, 5, 4, 10, 5, 8)
			for _, z in ipairs({2, 3, 9, 10}) do
				stair(4, 5, z, "W")
				stair(8, 5, z, "E")
			end
			fill(3, 4, 4, 4, 4, 8, c.soul_sand)
			fill(8, 4, 4, 9, 4, 8, c.soul_sand)
			for _, x in ipairs({3, 4, 8, 9}) do
				for z = 4, 8 do
					put(x, 5, z, c.wart, "goodluck_nether:nether_wart_0", 3)
				end
			end
		end
		B(4, 2, 0, 8, 2, 12)
		B(0, 2, 4, 12, 2, 8)
		B(4, 0, 0, 8, 1, 3)
		B(4, 0, 9, 8, 1, 12)
		B(0, 0, 4, 3, 1, 8)
		B(9, 0, 4, 12, 1, 8)
		P(4, 0, 8, 2)
		P(4, 10, 8, 12)
		P(0, 4, 2, 8)
		P(10, 4, 12, 8)
		if k == "castle_entrance" then
			-- the lava well
			B(5, 5, 5, 7, 5, 7)
			A(6, 1, 6, 6, 4, 6)
			B(6, 0, 6, 6, 0, 6)
			fill(6, 5, 6, 6, 5, 6, c.lava)
		end
	elseif k == "corridor" or k == "corridor_crossing" or k == "corridor_right" or k == "corridor_left" then
		B(0, 0, 0, 4, 1, 4)
		A(0, 2, 0, 4, 5, 4)
		if k == "corridor" then
			B(0, 2, 0, 0, 5, 4)
			B(4, 2, 0, 4, 5, 4)
			F(0, 3, 1, 0, 4, 1)
			F(0, 3, 3, 0, 4, 3)
			F(4, 3, 1, 4, 4, 1)
			F(4, 3, 3, 4, 4, 3)
		elseif k == "corridor_crossing" then
			B(0, 2, 0, 0, 5, 0)
			B(4, 2, 0, 4, 5, 0)
			B(0, 2, 4, 0, 5, 4)
			B(4, 2, 4, 4, 5, 4)
		else
			-- the wall on the side it doesn't turn to, and the one ahead
			local s, o = k == "corridor_right" and 0 or 4, k == "corridor_right" and 4 or 0
			B(s, 2, 0, s, 5, 4)
			F(s, 3, 1, s, 4, 1)
			F(s, 3, 3, s, 4, 3)
			B(o, 2, 0, o, 5, 0)
			if k == "corridor_right" then
				B(1, 2, 4, 4, 5, 4)
			else
				B(0, 2, 4, 3, 5, 4)
			end
			F(1, 3, 4, 1, 4, 4)
			F(3, 3, 4, 3, 4, 4)
			if p.chest then
				local wx, wy, wz = world(p, k == "corridor_right" and 1 or 3, 2, 3)
				if inside(wx, wy, wz) then
					data[area:index(wx, wy, wz)] = c.chest
					out.chests[#out.chests + 1] = {x = wx, y = wy, z = wz}
				end
			end
		end
		B(0, 6, 0, 4, 6, 4)
		P(0, 0, 4, 4)
	elseif k == "corridor_stairs" then
		for i = 0, 9 do
			local floor = math.max(1, 7 - i)
			local top = math.min(math.max(floor + 5, 14 - i), 13)
			B(0, 0, i, 4, floor, i)
			A(1, floor + 1, i, 3, top - 1, i)
			if i <= 6 then
				for x = 1, 3 do
					stair(x, floor + 1, i, "S")
				end
			end
			B(0, top, i, 4, top, i)
			B(0, floor + 1, i, 0, top - 1, i)
			B(4, floor + 1, i, 4, top - 1, i)
			if i % 2 == 0 then
				F(0, floor + 2, i, 0, floor + 3, i)
				F(4, floor + 2, i, 4, floor + 3, i)
			end
			P(0, i, 4, i)
		end
	elseif k == "balcony" then
		B(0, 0, 0, 8, 1, 8)
		A(0, 2, 0, 8, 5, 8)
		B(0, 6, 0, 8, 6, 5)
		B(0, 2, 0, 2, 5, 0)
		B(6, 2, 0, 8, 5, 0)
		F(1, 3, 0, 1, 4, 0)
		F(7, 3, 0, 7, 4, 0)
		B(0, 2, 4, 8, 2, 8)
		A(1, 1, 4, 2, 2, 4)
		A(6, 1, 4, 7, 2, 4)
		F(1, 3, 8, 7, 3, 8)
		F(0, 3, 8, 0, 3, 8)
		F(8, 3, 8, 8, 3, 8)
		F(0, 3, 6, 0, 3, 7)
		F(8, 3, 6, 8, 3, 7)
		B(0, 3, 4, 0, 5, 5)
		B(8, 3, 4, 8, 5, 5)
		B(1, 3, 5, 2, 5, 5)
		B(6, 3, 5, 7, 5, 5)
		F(1, 4, 5, 1, 5, 5)
		F(7, 4, 5, 7, 5, 5)
		P(0, 0, 8, 5)
	end
end

-- the pieces of every fortress that reach into the mapchunk, in data; out gets what the game sets up after
-- (nodes: param2s, spawners, chests)
function F.draw(data, area, minp, maxp)
	if not c.air then
		ids()
	end
	local out = {nodes = {}, spawners = {}, chests = {}}
	local drawn = 0
	F.each_near(minp.x, minp.z, maxp.x, maxp.z, function(pieces)
		for _, p in ipairs(pieces) do
			local b = p.box
			if b[1] <= maxp.x and b[4] >= minp.x and b[3] <= maxp.z and b[6] >= minp.z and b[5] >= minp.y then
				draw(p, data, area, minp, maxp, out)
				drawn = drawn + 1
			end
		end
	end)
	out.pieces = drawn
	return drawn > 0 and out
end

if core.save_gen_notify then
	goodluck_nether = {fortress = F}
	return
end

-- In the game, once a mapchunk is made: its chests filled from Minecraft's chests/nether_bridge (2 to 4 draws by
-- weight; what the game lacks, copper horse armor and the armor trim, stays out) and turned as Minecraft turns them,
-- its spawners set to blazes
local LOOT = {
	{"default:diamond", 1, 3, 5}, {"default:steel_ingot", 1, 5, 5}, {"default:gold_ingot", 1, 3, 15},
	{"default:sword_gold", 1, 1, 5}, {"3d_armor:chestplate_gold", 1, 1, 5}, {"fire:flint_and_steel", 1, 1, 5},
	{"goodluck_nether:nether_wart", 3, 7, 5}, {"mobs:saddle", 1, 1, 10}, {"goodluck_horse:armor_gold", 1, 1, 8},
	{"goodluck_horse:armor_iron", 1, 1, 5}, {"goodluck_horse:armor_diamond", 1, 1, 3}, {"default:obsidian", 2, 4, 2},
}
core.register_on_mods_loaded(function()
	for i = #LOOT, 1, -1 do
		if not core.registered_items[LOOT[i][1]] then
			table.remove(LOOT, i)
		end
	end
end)

local function fill(pos)
	local inv = core.get_meta(pos):get_inventory()
	local pr = PcgRandom((SEED + core.hash_node_position(pos)) % 2147483647)
	local total, free = 0, {}
	for _, e in ipairs(LOOT) do
		total = total + e[4]
	end
	for i = 1, inv:get_size("main") do
		free[i] = i
	end
	for _ = 1, pr:next(2, 4) do
		local roll = pr:next(1, total)
		for _, e in ipairs(LOOT) do
			roll = roll - e[4]
			if roll <= 0 then
				inv:set_stack("main", table.remove(free, pr:next(1, #free)), e[1] .. " " .. pr:next(e[2], e[3]))
				break
			end
		end
	end
end

-- away from its one solid side; else ahead (north), unless blocked, then back, then to the side
-- (Minecraft's north, east, south and west, as its pieces here are laid)
local AROUND = {{x = 0, z = -1}, {x = 1, z = 0}, {x = 0, z = 1}, {x = -1, z = 0}}
local function solid(pos)
	local def = core.registered_nodes[core.get_node(pos).name]
	return def and def.walkable and def.drawtype == "normal"
end
local function facing(pos)
	local one
	for _, d in ipairs(AROUND) do
		local p = vector.offset(pos, d.x, 0, d.z)
		if core.get_node(p).name == "default:chest" then
			return AROUND[1]
		elseif solid(p) then
			if one then
				one = nil
				break
			end
			one = d
		end
	end
	if one then
		return {x = -one.x, z = -one.z}
	end
	local d = AROUND[1]
	for _, turn in ipairs({function(v) return {x = -v.x, z = -v.z} end, function(v) return {x = -v.z, z = v.x} end,
			function(v) return {x = -v.x, z = -v.z} end}) do
		if not solid(vector.offset(pos, d.x, 0, d.z)) then
			break
		end
		d = turn(d)
	end
	return d
end

local logged = {}
core.set_gen_notify({custom = true}, nil, {"goodluck_nether:fortress"})
core.register_on_generated(function(minp, maxp)
	if maxp.y < R.ymin or minp.y > R.ymax then
		return
	end
	local notes = core.get_mapgen_object("gennotify")
	local made = notes and notes.custom and notes.custom["goodluck_nether:fortress"]
	if not made then
		return
	end
	for _, pos in ipairs(made.chests) do
		local d = facing(pos)
		core.set_node(pos, {name = "default:chest", param2 = core.dir_to_facedir({x = -d.x, y = 0, z = -d.z})})
		fill(pos)
	end
	for _, pos in ipairs(made.spawners) do
		if goodluck_nether.set_spawner then
			goodluck_nether.set_spawner(pos, core.registered_entities["goodluck_nether:blaze"] and
				"goodluck_nether:blaze" or "")
		end
	end
	F.each_near(minp.x, minp.z, maxp.x, maxp.z, function(pieces, rx, rz)
		if not logged[rx .. "," .. rz] then
			logged[rx .. "," .. rz] = true
			local b = pieces[1].box
			core.log("action", ("[goodluck_nether] nether fortress at %d,%d,%d: %d pieces"):format(b[1], b[2], b[3],
				#pieces))
		end
	end)
end)

return F
