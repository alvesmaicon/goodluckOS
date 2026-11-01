-- The End cities as Minecraft builds them (EndCityPieces), in both the map generator's threads and the game: from the
-- start (cities.lua) a house of three floors, then Minecraft's recursive walk of towers, bridges, houses and fat
-- towers up to 8 deep, each batch of pieces kept only when it overlaps nothing but its own parent's batch, and one
-- ship at most at a bridge's end. Every mapchunk draws its own share, the pieces in the walk's order, those that
-- Minecraft places with their air clearing what they cover. Each piece is drawn here after its template, in its size:
-- purpur floors and roofs edged with stairs, end stone brick walls on pillars with magenta windows, end rods, towers of
-- pillars with a spiral of slabs; what the game must finish (chests, shulkers, the ship's brewing stand and its item
-- frame) goes out by gen_notify
local T = {}
local C = rawget(_G, "goodluck_end_cities") or goodluck_end.cities
local DEPTH = 8

-- the templates' sizes, x, y, z
local SIZE = {
	base_floor = {10, 4, 10}, base_roof = {12, 2, 12}, second_floor_1 = {12, 8, 12}, second_floor_2 = {12, 8, 12},
	second_roof = {14, 2, 14}, third_floor_1 = {14, 8, 14}, third_floor_2 = {14, 8, 14}, third_roof = {16, 2, 16},
	tower_base = {7, 7, 7}, tower_piece = {7, 4, 7}, tower_top = {9, 5, 9}, bridge_end = {5, 6, 2},
	bridge_piece = {5, 6, 4}, bridge_steep_stairs = {5, 7, 4}, bridge_gentle_stairs = {5, 7, 8},
	fat_tower_base = {13, 4, 13}, fat_tower_middle = {13, 8, 13}, fat_tower_top = {17, 6, 17}, ship = {13, 24, 29},
}

-- Minecraft's turns about a piece's corner: none, a quarter clockwise, a half, a quarter back
local function turn(x, y, z, rot)
	if rot == 1 then
		return -z, y, x
	elseif rot == 2 then
		return -x, y, -z
	elseif rot == 3 then
		return z, y, -x
	end
	return x, y, z
end

local function make(name, x, y, z, rot, overwrite)
	local s = SIZE[name]
	local bx, by, bz = turn(s[1] - 1, s[2] - 1, s[3] - 1, rot)
	return {name = name, x = x, y = y, z = z, rot = rot, overwrite = overwrite, depth = 0,
		box = {x + math.min(0, bx), y + math.min(0, by), z + math.min(0, bz), x + math.max(0, bx), y + math.max(0, by),
			z + math.max(0, bz)}}
end

-- a piece joined to its parent at the parent's offset (in the parent's turn)
local function add(parent, ox, oy, oz, name, rot, overwrite)
	local dx, dy, dz = turn(ox, oy, oz, parent.rot)
	return make(name, parent.x + dx, parent.y + dy, parent.z + dz, rot, overwrite)
end

local function overlap(a, b)
	return a[1] <= b[4] and a[4] >= b[1] and a[2] <= b[5] and a[5] >= b[2] and a[3] <= b[6] and a[6] >= b[3]
end

-- The walk, with the city's random: nextInt(n) is next(0, n - 1), nextBoolean next(0, 1) == 1
local pr, ship_made
local GEN = {}
local function recurse(gen, depth, parent, off, list)
	if depth > DEPTH then
		return false
	end
	local batch = {}
	if not gen(depth, parent, off, batch) then
		return false
	end
	local tag = pr:next()
	for _, p in ipairs(batch) do
		p.depth = tag
		for _, other in ipairs(list) do
			if overlap(other.box, p.box) then
				if other.depth ~= parent.depth then
					return false
				end
				break
			end
		end
	end
	for _, p in ipairs(batch) do
		list[#list + 1] = p
	end
	return true
end

function GEN.house(depth, parent, off, l)
	if depth > DEPTH then
		return false
	end
	local rot = parent.rot
	local p = add(parent, off[1], off[2], off[3], "base_floor", rot, true)
	l[#l + 1] = p
	local r = pr:next(0, 2)
	if r == 0 then
		l[#l + 1] = add(p, -1, 4, -1, "base_roof", rot, true)
		return true
	end
	p = add(p, -1, 0, -1, "second_floor_2", rot, false)
	l[#l + 1] = p
	if r == 1 then
		p = add(p, -1, 8, -1, "second_roof", rot, false)
	else
		p = add(p, -1, 4, -1, "third_floor_2", rot, false)
		l[#l + 1] = p
		p = add(p, -1, 8, -1, "third_roof", rot, true)
	end
	l[#l + 1] = p
	recurse(GEN.tower, depth + 1, p, nil, l)
	return true
end

local TOWER_BRIDGES = {{0, 1, -1, 0}, {1, 6, -1, 1}, {3, 0, -1, 5}, {2, 5, -1, 6}}
function GEN.tower(depth, parent, _, l)
	local rot = parent.rot
	local ox = 3 + pr:next(0, 1)
	local p = add(parent, ox, -3, 3 + pr:next(0, 1), "tower_base", rot, true)
	l[#l + 1] = p
	p = add(p, 0, 7, 0, "tower_piece", rot, true)
	l[#l + 1] = p
	local from = pr:next(0, 2) == 0 and p or nil
	local n = 1 + pr:next(0, 2)
	for i = 0, n - 1 do
		p = add(p, 0, 4, 0, "tower_piece", rot, true)
		l[#l + 1] = p
		if i < n - 1 and pr:next(0, 1) == 1 then
			from = p
		end
	end
	if from then
		for _, b in ipairs(TOWER_BRIDGES) do
			if pr:next(0, 1) == 1 then
				local e = add(from, b[2], b[3], b[4], "bridge_end", (rot + b[1]) % 4, true)
				l[#l + 1] = e
				recurse(GEN.bridge, depth + 1, e, nil, l)
			end
		end
	elseif depth ~= 7 then
		return recurse(GEN.fat, depth + 1, p, nil, l)
	end
	l[#l + 1] = add(p, -1, 4, -1, "tower_top", rot, true)
	return true
end

function GEN.bridge(depth, parent, _, l)
	local rot = parent.rot
	local n = pr:next(0, 3) + 1
	local p = add(parent, 0, 0, -4, "bridge_piece", rot, true)
	p.depth = -1
	l[#l + 1] = p
	local k = 0
	for _ = 1, n do
		if pr:next(0, 1) == 1 then
			p = add(p, 0, k, -4, "bridge_piece", rot, true)
			k = 0
		else
			if pr:next(0, 1) == 1 then
				p = add(p, 0, k, -4, "bridge_steep_stairs", rot, true)
			else
				p = add(p, 0, k, -8, "bridge_gentle_stairs", rot, true)
			end
			k = 4
		end
		l[#l + 1] = p
	end
	if ship_made or pr:next(0, 9 - depth) ~= 0 then
		if not recurse(GEN.house, depth + 1, p, {-3, k + 1, -11}, l) then
			return false
		end
	else
		local sx = -8 + pr:next(0, 7)
		l[#l + 1] = add(p, sx, k, -70 + pr:next(0, 9), "ship", rot, true)
		ship_made = true
	end
	local e = add(p, 4, k, 0, "bridge_end", (rot + 2) % 4, true)
	e.depth = -1
	l[#l + 1] = e
	return true
end

local FAT_BRIDGES = {{0, 4, -1, 0}, {1, 12, -1, 4}, {3, 0, -1, 8}, {2, 8, -1, 12}}
function GEN.fat(depth, parent, _, l)
	local rot = parent.rot
	local p = add(parent, -3, 4, -3, "fat_tower_base", rot, true)
	l[#l + 1] = p
	p = add(p, 0, 4, 0, "fat_tower_middle", rot, true)
	l[#l + 1] = p
	for _ = 1, 2 do
		if pr:next(0, 2) == 0 then
			break
		end
		p = add(p, 0, 8, 0, "fat_tower_middle", rot, true)
		l[#l + 1] = p
		for _, b in ipairs(FAT_BRIDGES) do
			if pr:next(0, 1) == 1 then
				local e = add(p, b[2], b[3], b[4], "bridge_end", (rot + b[1]) % 4, true)
				l[#l + 1] = e
				recurse(GEN.bridge, depth + 1, e, nil, l)
			end
		end
	end
	l[#l + 1] = add(p, -2, 8, -2, "fat_tower_top", rot, true)
	return true
end

-- the city at a start (cities.lua): its pieces in Minecraft's order, the box about them all and its ship, if any
local cache, cached = {}, 0
function T.layout(s)
	local key = s.x .. "," .. s.z
	if cache[key] then
		return cache[key]
	end
	if cached >= 32 then
		cache, cached = {}, 0
	end
	cached = cached + 1
	pr, ship_made = PcgRandom(s.seed), false
	-- the turn was the random's first draw
	pr:next(0, 3)
	local p = make("base_floor", s.x, s.y, s.z, s.rot, true)
	local list = {p}
	p = add(p, -1, 0, -1, "second_floor_1", s.rot, false)
	list[#list + 1] = p
	p = add(p, -1, 4, -1, "third_floor_1", s.rot, false)
	list[#list + 1] = p
	p = add(p, -1, 8, -1, "third_roof", s.rot, true)
	list[#list + 1] = p
	recurse(GEN.tower, 1, p, nil, list)
	local box, ship = {math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge}, nil
	for _, q in ipairs(list) do
		for k = 1, 3 do
			box[k], box[k + 3] = math.min(box[k], q.box[k]), math.max(box[k + 3], q.box[k + 3])
		end
		ship = q.name == "ship" and q or ship
	end
	cache[key] = {pieces = list, box = box, ship = ship, start = s}
	return cache[key]
end

-- Drawing, into data and param2 (area) inside minp..maxp: a piece's own coordinates to the world's by its turn
local c = {}
local function ids()
	local id = core.get_content_id
	c.air, c.purpur, c.pillar = id("air"), id("goodluck_end:purpur_block"), id("goodluck_end:purpur_pillar")
	c.bricks, c.glass, c.rod = id("goodluck_end:end_stone_bricks"), id("goodluck_end:magenta_stained_glass"),
		id("goodluck_end:end_rod")
	c.stair, c.outer = id("stairs:stair_purpur_block"), id("stairs:stair_outer_purpur_block")
	c.slab, c.ladder, c.obsidian = id("stairs:slab_purpur_block"), id("default:ladder_wood"), id("default:obsidian")
	c.head, c.ender = id("goodluck_end:dragon_head_wall"), id("goodluck_end:ender_chest")
	c.name = {}
	for _, v in pairs(c) do
		if type(v) == "number" then
			c.name[v] = core.get_name_from_content_id(v)
		end
	end
end

local data, p2, area, minp, maxp, out
local px, py, pz, prot
local function inside(x, y, z)
	return x >= minp.x and x <= maxp.x and y >= minp.y and y <= maxp.y and z >= minp.z and z <= maxp.z
end
local function at(x, y, z)
	local dx, dy, dz = turn(x, y, z, prot)
	return px + dx, py + dy, pz + dz
end
-- p2: the param2 of what is drawn, where not 0, by index (written with set_node_at after the data)
local function P(x, y, z, id, param2)
	x, y, z = at(x, y, z)
	if inside(x, y, z) then
		local vi = area:index(x, y, z)
		data[vi], p2[vi] = id, param2 ~= 0 and param2 or nil
	end
end
local function F(x1, y1, z1, x2, y2, z2, id, param2)
	for y = y1, y2 do
		for z = z1, z2 do
			for x = x1, x2 do
				P(x, y, z, id, param2)
			end
		end
	end
end
local function A(x1, y1, z1, x2, y2, z2)
	F(x1, y1, z1, x2, y2, z2, c.air)
end

-- directions as Minecraft names them in a template: north -z, south +z, east +x, west -x
local FACE = {N = {0, -1}, S = {0, 1}, E = {1, 0}, W = {-1, 0}}
local function world_dir(dx, dz)
	local x, _, z = turn(dx, 0, dz, prot)
	return x, z
end
local function facedir(x, z)
	return z == 1 and 0 or x == 1 and 1 or z == -1 and 2 or 3
end
local UPSIDE = {[0] = 20, 23, 22, 21}
-- a stair whose tall side is toward f; top: upside down
local function ST(x, y, z, f, top)
	local d = facedir(world_dir(FACE[f][1], FACE[f][2]))
	P(x, y, z, c.stair, top and UPSIDE[d] or d)
end
-- an outer corner stair, its tall quarter toward the piece's sx, sz
local BOTTOM_QUARTER = {["-1,1"] = 0, ["1,1"] = 1, ["1,-1"] = 2, ["-1,-1"] = 3}
local TOP_QUARTER = {["1,1"] = 20, ["1,-1"] = 23, ["-1,-1"] = 22, ["-1,1"] = 21}
local function CO(x, y, z, sx, sz, top)
	local wx, wz = world_dir(sx, sz)
	P(x, y, z, c.outer, (top and TOP_QUARTER or BOTTOM_QUARTER)[wx .. "," .. wz])
end
local function SL(x, y, z, top)
	P(x, y, z, c.slab, top and 20 or 0)
end
-- a pillar along the piece's x, y or z
local function PL(x, y, z, axis)
	if axis ~= "y" and prot % 2 == 1 then
		axis = axis == "x" and "z" or "x"
	end
	P(x, y, z, c.pillar, axis == "x" and 12 or axis == "z" and 4 or 0)
end
local function wallmounted(x, y, z)
	return y == 1 and 0 or y == -1 and 1 or x == 1 and 2 or x == -1 and 3 or z == 1 and 4 or 5
end
-- an end rod or a ladder facing f ("U" up), on the face behind it
local function mounted(x, y, z, id, f)
	if f == "U" then
		P(x, y, z, id, 1)
	else
		local wx, wz = world_dir(-FACE[f][1], -FACE[f][2])
		P(x, y, z, id, wallmounted(wx, 0, wz))
	end
end
local function ROD(x, y, z, f)
	mounted(x, y, z, c.rod, f or "U")
end
local function LAD(x, y, z, f)
	mounted(x, y, z, c.ladder, f)
end
-- what the game finishes: a chest facing f, a shulker, the ship's item frame facing f and its brewing stand
local function mark(list, x, y, z, f)
	local wx, wy, wz = at(x, y, z)
	if inside(wx, wy, wz) then
		data[area:index(wx, wy, wz)] = c.air
		local e = {x = wx, y = wy, z = wz}
		if f then
			e.dx, e.dz = world_dir(FACE[f][1], FACE[f][2])
		end
		out[list][#out[list] + 1] = e
	end
end

-- walls of end stone bricks about x1..x2, z1..z2 from y1 to y2, purpur pillars at the corners
local function walls(x1, y1, z1, x2, y2, z2)
	for y = y1, y2 do
		for x = x1 + 1, x2 - 1 do
			P(x, y, z1, c.bricks)
			P(x, y, z2, c.bricks)
		end
		for z = z1 + 1, z2 - 1 do
			P(x1, y, z, c.bricks)
			P(x2, y, z, c.bricks)
		end
		for _, q in ipairs({{x1, z1}, {x2, z1}, {x1, z2}, {x2, z2}}) do
			PL(q[1], y, q[2], "y")
		end
	end
end
-- windows at the walls' places along them, at y1..y2
local function windows(x1, z1, x2, z2, y1, y2, along_x, along_z)
	for y = y1, y2 do
		for _, x in ipairs(along_x) do
			P(x, y, z1, c.glass)
			P(x, y, z2, c.glass)
		end
		for _, z in ipairs(along_z or along_x) do
			P(x1, y, z, c.glass)
			P(x2, y, z, c.glass)
		end
	end
end
-- an edge of stairs about x1..x2, z1..z2 at y, their tall sides in, each third one upside down; outer corners
local function rim(x1, z1, x2, z2, y)
	for x = x1 + 1, x2 - 1 do
		local top = (x - x1 - 1) % 3 == 0
		ST(x, y, z1, "S", top)
		ST(x, y, z2, "N", top)
	end
	for z = z1 + 1, z2 - 1 do
		local top = (z - z1 - 1) % 3 == 0
		ST(x1, y, z, "E", top)
		ST(x2, y, z, "W", top)
	end
	CO(x1, y, z1, 1, 1, true)
	CO(x2, y, z1, -1, 1, true)
	CO(x1, y, z2, 1, -1, true)
	CO(x2, y, z2, -1, -1, true)
end
local function rods(x1, z1, x2, z2, y)
	for _, q in ipairs({{x1, z1}, {x2, z1}, {x1, z2}, {x2, z2}}) do
		ROD(q[1], y, q[2])
	end
end
-- a floor of purpur over x1..x2, z1..z2 at y, but where hole(x, z)
local function floor(x1, z1, x2, z2, y, hole)
	for z = z1, z2 do
		for x = x1, x2 do
			if not (hole and hole(x, z)) then
				P(x, y, z, c.purpur)
			end
		end
	end
end
-- a stair of slabs and blocks along path ({x, z} each) from y0, half a node up each
local function steps(path, y0)
	for i, q in ipairs(path) do
		local k = i - 1
		if k % 2 == 1 then
			P(q[1], y0 + (k - 1) / 2, q[2], c.purpur)
		else
			SL(q[1], y0 + k / 2, q[2])
			if k > 0 then
				SL(q[1], y0 + k / 2 - 1, q[2], true)
			end
		end
	end
end

-- the towers: a ring about a 3 by 3 middle, the ring's middles stuck out on its spoke level, a spiral of slabs inside
local function octagon(y, id, param2)
	for i = 2, 4 do
		P(i, y, 1, id, param2)
		P(i, y, 5, id, param2)
		P(1, y, i, id, param2)
		P(5, y, i, id, param2)
	end
end
local function ring_pillars(y)
	for i = 2, 4 do
		PL(i, y, 1, "y")
		PL(i, y, 5, "y")
		PL(1, y, i, "y")
		PL(5, y, i, "y")
	end
end
local function spokes(y, m, near, far)
	PL(m, y, near, "z")
	PL(m, y, far, "z")
	PL(near, y, m, "x")
	PL(far, y, m, "x")
	ST(m, y, near - 1, "S", true)
	ST(m, y, far + 1, "N", true)
	ST(near - 1, y, m, "E", true)
	ST(far + 1, y, m, "W", true)
end
local SPIRAL = {{2, 3}, {3, 2}, {4, 3}, {3, 4}}
local function spiral(y, level)
	local q = SPIRAL[level % 4 + 1]
	SL(q[1], y, q[2])
end

-- the fat towers: a round wall about 6, 6 (5 to 5.1 out), a round floor, the slabs in pairs a quarter apart
local function round(y, inner, outer, fn)
	for z = 0, 12 do
		for x = 0, 12 do
			local d = (x - 6) ^ 2 + (z - 6) ^ 2
			if d >= inner and d <= outer then
				fn(x, y, z)
			end
		end
	end
end
local function fat_ring(y, purpur)
	round(y, 20, 26, function(x, yy, z)
		if purpur then
			P(x, yy, z, c.purpur)
		else
			PL(x, yy, z, "y")
		end
	end)
end
local FAT_SLABS = {{{5, 2}, {7, 10}}, {{7, 2}, {5, 10}}}
local function fat_slabs(y, level)
	local pair = FAT_SLABS[level % 4 + 1]
	if not pair then
		return
	end
	for _, q in ipairs(pair) do
		local x, z = q[1], q[2]
		for _ = 1, math.floor(level / 4) % 4 do
			x, z = 12 - z, x
		end
		SL(x, y, z)
	end
end

local DRAW = {}
function DRAW.base_floor()
	A(0, 0, 0, 9, 3, 9)
	floor(1, 1, 8, 8, 0)
	floor(3, 9, 6, 9, 0)
	ST(2, 0, 9, "N")
	ST(7, 0, 9, "N")
	walls(1, 1, 1, 8, 3, 8)
	A(4, 1, 8, 5, 3, 8)
	windows(1, 1, 8, 8, 2, 3, {3, 6})
	-- no window by the door
	P(3, 2, 8, c.bricks)
	P(6, 2, 8, c.bricks)
	P(3, 3, 8, c.bricks)
	P(6, 3, 8, c.bricks)
	mark("shulkers", 3, 2, 9)
	mark("shulkers", 6, 2, 9)
end
-- a house's floor over the one below: its edge of stairs, the walls on it, end rods on the edge's corners
local function storey(w, glass)
	rim(0, 0, w - 1, w - 1, 4)
	walls(1, 5, 1, w - 2, 7, w - 2)
	windows(1, 1, w - 2, w - 2, 6, 7, glass)
	rods(0, 0, w - 1, w - 1, 5)
end
function DRAW.second_floor_1()
	floor(1, 1, 10, 10, 4, function(x, z)
		return z == 3 and x >= 4 and x <= 8 or x == 8 and z >= 4 and z <= 6
	end)
	storey(12, {3, 8})
	steps({{8, 5}, {8, 4}, {8, 3}, {7, 3}, {6, 3}, {5, 3}, {4, 3}}, 1)
	F(4, 2, 2, 4, 3, 2, c.bricks)
	F(7, 2, 2, 7, 3, 2, c.bricks)
end
function DRAW.second_floor_2()
	-- the middle open over the floor below, a walk across it
	floor(1, 1, 10, 10, 4, function(x, z)
		return x >= 3 and x <= 8 and z >= 3 and z <= 8 and (z ~= 6 or x < 5)
	end)
	ST(5, 4, 6, "E")
	for x = 6, 8 do
		SL(x, 4, 6, true)
	end
	storey(12, {3, 8})
	steps({{4, 8}, {4, 7}, {4, 6}, {4, 5}, {4, 4}, {4, 3}}, 1)
	-- up to the floor over it, along the west wall
	steps({{2, 2}, {2, 3}, {2, 4}, {2, 5}, {2, 6}, {2, 7}, {2, 8}}, 5)
	mark("shulkers", 8, 5, 6)
end
function DRAW.third_floor_1()
	floor(1, 1, 12, 12, 4, function(x, z)
		return z == 10 and x >= 3 and x <= 8
	end)
	storey(14, {3, 5, 8, 10})
	steps({{3, 10}, {4, 10}, {5, 10}, {6, 10}, {7, 10}, {8, 10}, {9, 10}}, 1)
	F(9, 2, 11, 9, 3, 11, c.bricks)
	-- a bench down the middle, back to back about a pillar
	for z = 2, 8 do
		if z == 6 then
			PL(5, 5, z, "y")
			PL(6, 5, z, "y")
			F(5, 6, z, 6, 7, z, c.pillar)
		else
			ST(5, 5, z, "E")
			ST(6, 5, z, "W")
		end
	end
end
function DRAW.third_floor_2()
	floor(1, 1, 12, 12, 4, function(x, z)
		return x >= 3 and x <= 8 and z >= 3 and z <= 9 and not (z == 8 and x >= 5)
	end)
	storey(14, {3, 5, 8, 10})
	-- the side walls hold shelves inside, no windows past their front
	for y = 6, 7 do
		for _, z in ipairs({8, 10}) do
			P(1, y, z, c.bricks)
			P(12, y, z, c.bricks)
		end
	end
	for _, z in ipairs({6, 8, 10}) do
		P(2, 5, z, c.purpur)
		P(11, 5, z, c.purpur)
		P(2, 7, z, c.purpur)
		P(11, 7, z, c.purpur)
	end
	F(2, 6, 8, 5, 6, 8, c.purpur)
	F(8, 6, 8, 11, 6, 8, c.purpur)
	ROD(6, 4, 4, "S")
	ROD(7, 4, 4, "S")
	steps({{3, 9}, {4, 9}, {5, 9}, {6, 9}, {7, 9}, {8, 9}, {9, 9}}, 1)
	mark("chests", 6, 5, 2, "S")
	local sx, sz = world_dir(FACE.S[1], FACE.S[2])
	P(7, 5, 2, c.ender, facedir(-sx, -sz))
	mark("shulkers", 2, 5, 2)
	mark("shulkers", 11, 5, 2)
end
local function roof(w)
	A(0, 0, 0, w - 1, 1, w - 1)
	floor(1, 1, w - 2, w - 2, 0)
	rim(0, 0, w - 1, w - 1, 0)
	rods(1, 1, w - 2, w - 2, 1)
end
function DRAW.base_roof()
	roof(12)
end
function DRAW.second_roof()
	floor(1, 1, 12, 12, 0)
	rim(0, 0, 13, 13, 0)
	rods(1, 1, 12, 12, 1)
end
function DRAW.third_roof()
	roof(16)
end

function DRAW.tower_base()
	for y = 0, 2 do
		PL(3, y, 5, "y")
		LAD(3, y, 4, "N")
	end
	A(0, 3, 0, 6, 6, 6)
	F(0, 3, 0, 6, 3, 6, c.purpur)
	A(2, 3, 2, 4, 3, 4)
	for y = 4, 6 do
		ring_pillars(y)
		spiral(y, y - 3)
	end
	spiral(3, 0)
	spokes(5, 3, 1, 5)
end
function DRAW.tower_piece()
	A(0, 0, 0, 6, 3, 6)
	octagon(0, c.purpur)
	for y = 1, 3 do
		ring_pillars(y)
	end
	spokes(2, 3, 1, 5)
	for y = 0, 3 do
		spiral(y, y)
	end
end
function DRAW.tower_top()
	A(0, 0, 0, 8, 4, 8)
	floor(2, 2, 6, 6, 0, function(x, z)
		return x >= 3 and x <= 5 and z >= 3 and z <= 5
	end)
	rim(1, 1, 7, 7, 0)
	SL(3, 0, 3)
	SL(4, 0, 3)
	walls(2, 1, 2, 6, 3, 6)
	windows(2, 2, 6, 6, 2, 3, {4})
	A(6, 1, 3, 6, 2, 4)
	rods(1, 1, 7, 7, 1)
	floor(1, 1, 7, 7, 4)
	rim(0, 0, 8, 8, 4)
	mark("shulkers", 4, 3, 4)
end

function DRAW.bridge_end()
	A(0, 0, 0, 4, 5, 1)
	PL(2, 0, 0, "z")
	F(1, 0, 1, 3, 0, 1, c.purpur)
	for x = 1, 3 do
		ST(x, 1, 0, "S")
	end
	F(0, 1, 1, 4, 1, 1, c.purpur)
	for _, x in ipairs({0, 4}) do
		P(x, 1, 0, c.purpur)
		F(x, 2, 0, x, 2, 1, c.purpur)
		ROD(x, 3, 0)
		F(x, 3, 1, x, 4, 1, c.purpur)
		SL(x, 5, 1)
	end
	SL(1, 4, 1, true)
	SL(3, 4, 1, true)
	F(1, 5, 1, 3, 5, 1, c.purpur)
end
-- a bridge's deck at y on row z: its stairs under the edges, purpur between, the railing over it
local function deck(z, y, rail)
	ST(0, y, z, "E", true)
	F(1, y, z, 3, y, z, c.purpur)
	ST(4, y, z, "W", true)
	if rail then
		ST(0, y + 1, z, "E")
		ST(4, y + 1, z, "W")
	end
end
function DRAW.bridge_piece()
	A(0, 0, 0, 4, 5, 3)
	ST(1, 0, 0, "E", true)
	ST(3, 0, 0, "W", true)
	for z = 0, 3 do
		PL(2, 0, z, "z")
		F(0, 1, z, 4, 1, z, c.purpur)
		if z > 0 then
			ST(0, 2, z, "E")
			ST(4, 2, z, "W")
		end
	end
	ST(0, 1, 0, "E", true)
	ST(4, 1, 0, "W", true)
	P(0, 2, 0, c.purpur)
	P(4, 2, 0, c.purpur)
end
function DRAW.bridge_steep_stairs()
	A(0, 0, 0, 4, 6, 3)
	PL(2, 0, 3, "z")
	F(1, 1, 3, 3, 1, 3, c.purpur)
	for s = 0, 3 do
		local z, y = 3 - s, 2 + s
		P(0, y, z, c.purpur)
		P(4, y, z, c.purpur)
		for x = 1, 3 do
			ST(x, y, z, "N")
		end
		if s > 0 then
			ST(1, y - 1, z, "E", true)
			ST(3, y - 1, z, "W", true)
			P(2, y - 1, z, c.purpur)
		end
		if s < 3 then
			ST(0, y + 1, z, "E")
			ST(4, y + 1, z, "W")
		end
	end
	PL(2, 4, 0, "z")
	P(0, 6, 0, c.purpur)
	P(4, 6, 0, c.purpur)
end
function DRAW.bridge_gentle_stairs()
	A(0, 0, 0, 4, 6, 7)
	PL(2, 0, 7, "z")
	for s = 0, 3 do
		local za, zb, y = 7 - 2 * s, 6 - 2 * s, 1 + s
		deck(za, y)
		P(0, y + 1, za, c.purpur)
		P(4, y + 1, za, c.purpur)
		for x = 1, 3 do
			SL(x, y + 1, za)
		end
		F(0, y + 1, zb, 4, y + 1, zb, c.purpur)
		ST(0, y + 2, za, "E")
		ST(4, y + 2, za, "W")
		if s < 3 then
			ST(0, y + 2, zb, "E")
			ST(4, y + 2, zb, "W")
		end
	end
	PL(2, 4, 0, "z")
	P(0, 6, 0, c.purpur)
	P(4, 6, 0, c.purpur)
end

function DRAW.fat_tower_base()
	A(0, 0, 0, 12, 3, 12)
	round(0, 0, 26, function(x, y, z)
		if math.abs(x - 6) > 1 or math.abs(z - 6) > 1 then
			P(x, y, z, c.purpur)
		end
	end)
	for y = 1, 3 do
		fat_ring(y)
	end
	spokes(2, 6, 1, 11)
	fat_slabs(1, 5)
	ROD(3, 2, 4, "E")
	ROD(9, 2, 8, "W")
	ROD(4, 3, 3, "S")
	ROD(8, 3, 9, "N")
end
function DRAW.fat_tower_middle()
	A(0, 0, 0, 12, 7, 12)
	for y = 0, 7 do
		fat_ring(y, y % 4 == 0)
		fat_slabs(y, y)
	end
	spokes(2, 6, 1, 11)
	spokes(6, 6, 1, 11)
	ROD(8, 2, 3, "S")
	ROD(4, 2, 9, "N")
	ROD(9, 3, 4, "W")
	ROD(3, 3, 8, "E")
	ROD(3, 6, 4, "E")
	ROD(9, 6, 8, "W")
	ROD(4, 7, 3, "S")
	ROD(8, 7, 9, "N")
	mark("shulkers", 2, 2, 6)
	mark("shulkers", 10, 2, 6)
	mark("shulkers", 6, 6, 2)
	mark("shulkers", 6, 6, 10)
end
function DRAW.fat_tower_top()
	A(0, 0, 0, 16, 5, 16)
	floor(2, 2, 14, 14, 0, function(x, z)
		return (x - 8) ^ 2 + (z - 8) ^ 2 <= 13
	end)
	rim(1, 1, 15, 15, 0)
	SL(7, 0, 4)
	SL(9, 0, 12)
	walls(2, 1, 2, 14, 3, 14)
	windows(2, 2, 14, 14, 2, 3, {4, 7, 9, 12})
	F(9, 1, 7, 9, 3, 7, c.pillar)
	F(7, 1, 9, 7, 3, 9, c.pillar)
	steps({{7, 3}, {8, 3}, {9, 3}, {10, 3}, {11, 3}, {12, 3}, {13, 3}}, 1)
	rods(1, 1, 15, 15, 1)
	floor(1, 1, 15, 15, 4, function(x, z)
		return z == 3 and x >= 8 and x <= 12
	end)
	rim(0, 0, 16, 16, 4)
	-- the hatch's frame on the roof
	for x = 8, 11 do
		ST(x, 5, 2, "S")
		ST(x, 5, 4, "N")
	end
	ST(7, 5, 3, "E")
	CO(7, 5, 2, 1, 1)
	CO(7, 5, 4, 1, -1)
	mark("chests", 3, 1, 11, "E")
	mark("chests", 5, 1, 13, "N")
end

-- The ship: a hull 13 wide, its keel of purpur with obsidian beside it, ribs of stairs every 4 along it, a deck at 7
-- with its railing; the bow narrowing to a bowsprit with the dragon's head, a spar rising over it; the mast at 14 with
-- its ladder and crow's nest; the stern raised to 9 over a cabin of end stone bricks with its brewing stand
local HULL = {[5] = 1, [6] = 2, [7] = 2, [8] = 3, [9] = 3}
function DRAW.ship()
	A(0, 0, 0, 12, 23, 28)
	for z = 5, 25 do
		local w = HULL[z] or 4
		local rib = z % 4 == 1 and z >= 13
		-- the keel
		if z >= 11 and z <= 23 then
			PL(6, 0, z, "z")
		end
		if z >= 8 then
			if z >= 12 and z <= 22 then
				F(5, 1, z, 7, 1, z, c.purpur)
			else
				PL(6, 1, z, "z")
			end
			PL(6, 2, z, "z")
			if z >= 12 then
				P(5, 2, z, c.obsidian)
				P(7, 2, z, c.obsidian)
				P(4, 2, z, c.purpur)
				P(8, 2, z, c.purpur)
				P(3, 3, z, c.purpur)
				P(9, 3, z, c.purpur)
			else
				P(5, 2, z, c.purpur)
				P(7, 2, z, c.purpur)
				F(6 - w + 1, 3, z, 6 + w - 1, 3, z, c.purpur)
				A(6 - w + 2, 3, z, 6 + w - 2, 3, z)
			end
			if rib then
				ST(4, 1, z, "E", true)
				ST(8, 1, z, "W", true)
				ST(3, 2, z, "E", true)
				ST(9, 2, z, "W", true)
				ST(2, 3, z, "E", true)
				ST(10, 3, z, "W", true)
				ST(1, 5, z, "E", true)
				ST(11, 5, z, "W", true)
			end
		end
		-- the sides and the deck
		if z <= 18 then
			local side = math.min(w, 4)
			for y = 4, 6 do
				P(6 - side, y, z, c.purpur)
				P(6 + side, y, z, c.purpur)
			end
			F(6 - w, 7, z, 6 + w, 7, z, c.purpur)
			if z >= 8 then
				if z % 3 == 1 then
					P(6 - w, 8, z, c.purpur)
					P(6 + w, 8, z, c.purpur)
				else
					ST(6 - w, 8, z, "E")
					ST(6 + w, 8, z, "W")
				end
			end
		end
	end
	-- the bow: a cabin under the deck for the chests and the item frame, the bowsprit and the dragon's head
	F(5, 4, 6, 7, 6, 6, c.purpur)
	ROD(6, 6, 6, "S")
	F(5, 3, 7, 7, 3, 7, c.purpur)
	mark("chests", 5, 4, 7, "S")
	mark("chests", 7, 4, 7, "S")
	mark("frames", 6, 5, 7, "S")
	mark("shulkers", 6, 4, 8)
	F(6, 3, 5, 6, 6, 5, c.purpur)
	for z = 1, 4 do
		PL(6, 7, z, "z")
	end
	P(6, 8, 5, c.purpur)
	ST(6, 8, 1, "N")
	P(6, 8, 0, c.head, facedir(world_dir(0, -1)))
	ROD(6, 9, 4)
	-- the spar, rising forward in steps of two
	for s = 0, 4 do
		local y, z = 8 + s, 10 - 2 * s
		PL(6, y, z, "z")
		PL(6, y, z + 1, "z")
		ST(6, y, z + 2, "N")
	end
	SL(6, 12, 1, true)
	ROD(2, 9, 10)
	ROD(10, 9, 10)
	-- the mast, its ladder and its nest
	for y = 1, 22 do
		PL(6, y, 14, "y")
	end
	P(6, 23, 14, c.purpur)
	P(6, 7, 13, c.glass)
	for y = 8, 21 do
		LAD(6, y, 15, "S")
	end
	for _, q in ipairs({{5, 13}, {7, 13}, {5, 15}, {7, 15}}) do
		SL(q[1], 20, q[2], true)
	end
	for x = 5, 7 do
		ST(x, 21, 12, "S", true)
		ST(x, 21, 16, "N", true)
	end
	for z = 13, 15 do
		ST(4, 21, z, "E", true)
		ST(8, 21, z, "W", true)
	end
	CO(4, 21, 12, 1, 1, true)
	CO(8, 21, 12, -1, 1, true)
	CO(4, 21, 16, 1, -1, true)
	CO(8, 21, 16, -1, -1, true)
	-- the stern: its floor at 5 over the hull, the cabin's walls, the deck at 9 with its railing
	for z = 19, 27 do
		F(2, 4, z, 10, 4, z, z >= 25 and c.purpur or c.air)
		P(2, 4, z, c.purpur)
		F(8, 4, z, 10, 4, z, c.purpur)
	end
	for z = 20, 27 do
		ST(1, 5, z, "E", z % 2 == 1)
		F(2, 5, z, 10, 5, z, c.purpur)
		ST(11, 5, z, "W", z % 2 == 1)
	end
	for x = 2, 11 do
		ST(x, 5, 27, "N", x % 3 ~= 2)
	end
	for y = 6, 8 do
		for z = 21, 26 do
			local id = (z == 21 or z == 26) and c.pillar or ((z == 23 or z == 24) and y == 7) and c.glass or c.bricks
			P(2, y, z, id)
			P(10, y, z, id)
		end
		for x = 3, 9 do
			P(x, y, 26, (x == 6) and c.pillar or (y == 7 and (x == 4 or x == 8)) and c.glass or c.bricks)
		end
		-- the cabin's front, a door in it
		for x = 2, 7 do
			P(x, y, 20, (x == 4 or x == 5) and y < 8 and c.air or c.bricks)
		end
	end
	PL(6, 6, 25, "y")
	mark("stands", 6, 7, 25)
	steps({{9, 19}, {9, 20}, {9, 21}}, 8)
	for z = 19, 28 do
		local edge = z == 19 or z == 28
		for x = 0, 12 do
			if x == 0 or x == 12 or edge then
				local f = x == 0 and "E" or x == 12 and "W" or z == 19 and "S" or "N"
				if not (z == 19 and x >= 4 and x <= 10) then
					ST(x, 9, z, f, x == 0 or x == 12 or z % 2 == 0)
				end
			elseif not (z == 20 and (x == 4 or x == 5)) then
				P(x, 9, z, c.purpur)
			end
		end
	end
	A(8, 9, 20, 9, 9, 20)
	for z = 21, 26 do
		ST(1, 10, z, "E")
		ST(11, 10, z, "W")
	end
	for x = 1, 11 do
		if x == 1 or x == 4 or x == 8 or x == 11 then
			P(x, 10, 27, c.purpur)
		else
			ST(x, 10, 27, "N")
		end
	end
	ROD(1, 6, 27)
	ROD(11, 6, 27)
	mark("shulkers", 8, 6, 27)
	mark("shulkers", 4, 11, 27)
end

-- the pieces of every city in minp..maxp, in their order, drawn into data (q: their param2 where not 0, by index);
-- nil when there are none
function T.draw(d, q, a, lo, hi)
	if not c.air then
		ids()
	end
	data, p2, area, minp, maxp, out = d, q, a, lo, hi, nil
	local chunk = {lo.x, lo.y, lo.z, hi.x, hi.y, hi.z}
	C.each_near(lo.x, lo.z, hi.x, hi.z, function(s)
		local city = T.layout(s)
		local b = city.box
		if b[2] > hi.y or b[5] < lo.y or b[1] > hi.x or b[4] < lo.x or b[3] > hi.z or b[6] < lo.z then
			return
		end
		for _, p in ipairs(city.pieces) do
			if overlap(p.box, chunk) then
				out = out or {chests = {}, shulkers = {}, frames = {}, stands = {}, pieces = 0, cities = {}}
				px, py, pz, prot = p.x, p.y, p.z, p.rot
				DRAW[p.name]()
				out.pieces = out.pieces + 1
				out.cities[s.x .. "," .. s.z] = true
			end
		end
	end)
	local made = out
	data, p2, out = nil, nil, nil
	return made
end

-- does any city reach into minp..maxp
function T.near(lo, hi)
	local any = false
	C.each_near(lo.x, lo.z, hi.x, hi.z, function(s)
		local b = T.layout(s).box
		any = any or not (b[2] > hi.y or b[5] < lo.y or b[1] > hi.x or b[4] < lo.x or b[3] > hi.z or b[6] < lo.z)
	end)
	return any
end

-- In the map generator's threads: the cities into the End's mapchunks they reach, if the world has structures
if core.save_gen_notify and Settings(core.get_worldpath() .. "/world.mt"):get_bool("generate_structures", true) then
	local R = core.ipc_get("goodluck_end:realm")
	local buf = {}
	core.register_on_generated(function(vm, lo, hi)
		if hi.y < R.ymin or lo.y > R.ymax then
			return
		end
		local t0 = core.get_us_time()
		if not T.near(lo, hi) then
			return
		end
		local t1 = core.get_us_time()
		local emin, emax = vm:get_emerged_area()
		local a = VoxelArea(emin, emax)
		vm:get_data(buf)
		local t2 = core.get_us_time()
		local turned = {}
		local made = T.draw(buf, turned, a, lo, hi)
		local t3 = core.get_us_time()
		if made then
			vm:set_data(buf)
			local n = 0
			for vi, param2 in pairs(turned) do
				vm:set_node_at(a:position(vi), {name = c.name[buf[vi]], param2 = param2})
				n = n + 1
			end
			local t4 = core.get_us_time()
			vm:calc_lighting()
			local cities = {}
			for k in pairs(made.cities) do
				cities[#cities + 1] = k
			end
			core.save_gen_notify("goodluck_end:city", {chests = made.chests, shulkers = made.shulkers,
				frames = made.frames, stands = made.stands, pieces = made.pieces, cities = cities, turned = n,
				walk = t1 - t0, read = t2 - t1, draw = t3 - t2, write = t4 - t3, light = core.get_us_time() - t4})
		end
	end)
end

return T
