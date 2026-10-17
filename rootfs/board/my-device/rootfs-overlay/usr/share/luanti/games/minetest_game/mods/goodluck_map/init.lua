-- Minecraft's maps (minecraft.wiki/w/Map). An empty map (eight papers around a compass), used with R1, becomes the map
-- of the 128 x 128 nodes around you, one node a pixel, on Minecraft's grid so that maps sit side by side; eight papers
-- around a map zoom it out, 1:2 up to 1:16 (2048 nodes), drawn anew as in Minecraft. Held, it draws the surface within
-- REACH nodes of you, nearest first, north up, each node in the colour of its top texture, shaded as Minecraft's (lighter
-- than the pixel to the north when higher, darker when lower, water by depth), and shows you as an arrow.
-- The engine keeps every image it is sent, so the map goes as 16 tiles and only a changed tile is sent again
local S = core.get_translator("goodluck_map")
local EMPTY, MAP = "goodluck_map:empty_map", "goodluck_map:map"
local PIXELS, TILE, MAX_ZOOM = 128, 32, 4
local TILES = PIXELS / TILE
local REACH = 64
local TICK, BUDGET = 0.2, 6000 -- s, µs of drawing a tick
local NEW, OLD, SCAN = 600, 50, 2500 -- columns a tick for new pixels and for drawn ones again, pixels looked at
local WALK = 96 -- nodes up or down from a guess to the ground
local LOADS = 3 -- map blocks read from disk a tick, where the server has let go of them
local REDRAW = {1e6, 1e6, 2e6, 4e6, 8e6} -- µs between two images of a tile, by zoom
local SCALE, MARKER = 2, 2
local PAPER = string.char(226, 212, 168, 255)
local floor = math.floor
local get_raw, IGNORE = core.get_node_raw, core.CONTENT_IGNORE
local storage = core.get_mod_storage()
local maps, held = {}, {}
local timer, clock, loads, loaded, busy = 0, 0, 0, {}, false

goodluck_map = {}
dofile(core.get_modpath("goodluck_map") .. "/colors.lua")

-- by content id: what the map sees through, water
local clear, water = {}, {}
local THROUGH = {airlike = true, torchlike = true, signlike = true, firelike = true}
core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_nodes) do
		local id = core.get_content_id(name)
		clear[id] = THROUGH[def.drawtype or "normal"]
		water[id] = (def.groups and def.groups.water or 0) > 0
	end
	clear[core.CONTENT_AIR] = true
end)

-- a pixel keeps one of up to 255 node names (content ids change between runs) and draws it in three shades
local names, index, by_id, shades = {}, {}, {}, {}
for name in storage:get_string("names"):gmatch("[^\n]+") do
	names[#names + 1] = name
	index[name] = #names
end

local function entry(id)
	local k = by_id[id]
	if not k then
		local name = core.get_name_from_content_id(id)
		k = index[name]
		if not k then
			k = math.min(#names + 1, 255)
			names[k], index[name] = name, k
			storage:set_string("names", table.concat(names, "\n"))
		end
		by_id[id] = k
	end
	return k
end

local function shade(k)
	local s = shades[k]
	if not s then
		local r, g, b = goodluck_map.node_color(names[k])
		s = {}
		for i, f in ipairs({180, 220, 255}) do
			s[i] = string.char(floor(r * f / 255), floor(g * f / 255), floor(b * f / 255), 255)
		end
		local def = core.registered_nodes[names[k]]
		s.water = (def and def.groups and def.groups.water or 0) > 0
		shades[k] = s
	end
	return s
end

-- a pixel: 0 not drawn yet, else the name's entry + 256 * water depth (0-31) + 8192 * (height + 32768)
local function pack(k, y, depth)
	return k + 256 * math.min(depth, 31) + 8192 * (y + 32768)
end

local function height(v)
	return floor(v / 8192) - 32768
end

local function setup(m)
	local size = PIXELS * 2 ^ m.zoom
	m.s, m.x0, m.z0 = 2 ^ m.zoom, m.cx - size / 2, m.cz + size / 2 - 1
	m.dirty, m.img, m.stamp, m.fail = {}, {}, {}, {}
	for t = 1, TILES * TILES do
		m.dirty[t], m.stamp[t] = true, 0
	end
	return m
end

local function load(id)
	if not maps[id] then
		local cx, cz, zoom = storage:get_string("m" .. id):match("^(-?%d+),(-?%d+),?(%d*)$")
		if not cx then
			return nil
		end
		local m = {id = id, cx = tonumber(cx), cz = tonumber(cz), zoom = tonumber(zoom) or 0, p = {}}
		local ok, raw = pcall(core.decompress, storage:get_string("p" .. id), "deflate")
		raw = ok and #raw == 4 * PIXELS * PIXELS and raw
		for i = 1, PIXELS * PIXELS do
			local k, d, hi, lo = 0, 0, 0, 0
			if raw then
				k, d, hi, lo = raw:byte(4 * i - 3, 4 * i)
			end
			m.p[i] = k == 0 and 0 or k + 256 * d + 8192 * (hi * 256 + lo)
		end
		-- the first maps (64 x 64 pixels of 2 x 2 nodes) are drawn anew
		if storage:get_string("c" .. id) ~= "" then
			for _, key in ipairs({"c", "h", "d"}) do
				storage:set_string(key .. id, "")
			end
		end
		maps[id] = setup(m)
	end
	return maps[id]
end

local function save(m)
	if m and m.unsaved then
		local out, char = {}, string.char
		for i = 1, PIXELS * PIXELS do
			local v = m.p[i]
			local e = floor(v / 8192)
			out[i] = char(v % 256, floor(v / 256) % 32, floor(e / 256), e % 256)
		end
		storage:set_string("p" .. m.id, core.compress(table.concat(out), "deflate"))
		m.unsaved = nil
	end
end

local function describe(id, zoom)
	local lines = {S("Map #@1", id), core.colorize("#c0c0c0", S("Scaling at 1:@1", 2 ^ zoom)),
		core.colorize("#c0c0c0", S("(Level @1/@2)", zoom, MAX_ZOOM))}
	if zoom < MAX_ZOOM then
		lines[4] = S("Eight papers around it: zoom out")
	end
	return table.concat(lines, "\n")
end

-- a map of the grid square around pos at a zoom (Minecraft's: 128 << zoom nodes, the zoom 0 squares centred on 0, 0)
function goodluck_map.new(pos, zoom)
	zoom = zoom or 0
	local id = storage:get_int("next") + 1
	storage:set_int("next", id)
	local size = PIXELS * 2 ^ zoom
	local cx = floor((pos.x + 64) / size) * size + size / 2 - 64
	local cz = floor((pos.z + 64) / size) * size + size / 2 - 64
	storage:set_string("m" .. id, cx .. "," .. cz .. "," .. zoom)
	local stack = ItemStack(MAP)
	local meta = stack:get_meta()
	meta:set_int("goodluck_map:id", id)
	meta:set_string("description", describe(id, zoom))
	return stack
end

-- where pos falls on the map, in pixels, fractional
local function locate(m, pos)
	return (pos.x + 0.5 - m.x0) / m.s, (m.z0 + 0.5 - pos.z) / m.s
end

-- a node, from disk if its block isn't in memory (the server keeps blocks 29 s after their last use; the map reaches
-- further than the active blocks): a few blocks a tick, each block at most every 30 s; busy when the tick's are used
local function fetch(x, y, z)
	local id, light, _, ok = get_raw(x, y, z)
	if ok then
		return id, light, ok
	end
	local bx, by, bz = floor(x / 16), floor(y / 16), floor(z / 16)
	local key = (bx + 2048) + 4096 * ((by + 2048) + 4096 * (bz + 2048))
	if clock - (loaded[key] or -30e6) < 30e6 then
		return id, light, ok
	end
	if loads >= LOADS then
		busy = true
		return id, light, ok
	end
	loaded[key], loads = clock, loads + 1
	core.load_area(vector.new(bx * 16, by * 16, bz * 16))
	id, light, _, ok = get_raw(x, y, z)
	return id, light, ok
end

local function surface(x, y, z, id)
	local depth = 0
	if water[id] then
		repeat
			depth = depth + 1
			local below, _, ok = fetch(x, y - depth, z)
		until not ok or not water[below] or depth >= 31
	end
	return id, y, depth
end

-- the top of a column as Minecraft's heightmap has it, the highest node under the open sky: from a guessed height
-- down through air, or up through ground and roofs to the first air the sun reaches; nil where it isn't loaded
local function column(x, z, y)
	local id, light, ok = fetch(x, y, z)
	if not ok or id == IGNORE then
		return nil
	end
	if clear[id] then
		for _ = 1, WALK do
			local below, l, ok2 = fetch(x, y - 1, z)
			if not ok2 or below == IGNORE then
				return nil
			end
			y = y - 1
			if not clear[below] then
				if light % 16 == 15 then
					return surface(x, y, z, below)
				end
				id = below
				break
			end
			light = l
		end
		if clear[id] then
			return nil
		end
	end
	for _ = 1, WALK do
		local above, l, ok2 = fetch(x, y + 1, z)
		if not ok2 or above == IGNORE then
			return nil
		end
		if clear[above] and l % 16 == 15 and not clear[id] then
			return surface(x, y, z, id)
		end
		y, id = y + 1, above
	end
end

-- a guess at a pixel's height: a drawn neighbour's
local function guess(m, px, py, fallback)
	local p, i = m.p, py * PIXELS + px + 1
	local v = px > 0 and p[i - 1] or 0
	if v == 0 and px < PIXELS - 1 then
		v = p[i + 1]
	end
	if v == 0 and py > 0 then
		v = p[i - PIXELS]
	end
	if v == 0 and py < PIXELS - 1 then
		v = p[i + PIXELS]
	end
	return v > 0 and height(v) or fallback
end

-- a pixel from its column, or zoomed out from four spread over it, the most common node as in Minecraft's
local function draw(m, px, py, y)
	local s = m.s
	local x, z = m.x0 + px * s, m.z0 - py * s
	local id, depth
	if s == 1 then
		id, y, depth = column(x, z, y)
		if not id then
			return false
		end
	else
		local half, count, most, n, sum, wet, wn = s / 2, {}, 0, 0, 0, 0, 0
		for j = 0, 1 do
			for i = 0, 1 do
				local c, cy, d = column(x + i * half, z - j * half, y)
				if c then
					y, n, sum = cy, n + 1, sum + cy
					count[c] = (count[c] or 0) + 1
					if count[c] > most then
						id, most = c, count[c]
					end
					if d > 0 then
						wet, wn = wet + d, wn + 1
					end
				end
			end
		end
		if n == 0 then
			return false
		end
		y, depth = floor(sum / n + 0.5), wn > 0 and floor(wet / wn + 0.5) or 0
	end
	local v, i = pack(entry(id), y, depth), py * PIXELS + px + 1
	if m.p[i] ~= v then
		m.p[i], m.unsaved = v, true
		local t = floor(py / TILE) * TILES + floor(px / TILE) + 1
		m.dirty[t] = true
		if py % TILE == TILE - 1 and py < PIXELS - 1 then
			m.dirty[t + TILES] = true
		end
	end
	return true
end

-- the offsets within reach at each zoom, nearest first
local rings = {}
local function ring(zoom)
	local r = rings[zoom]
	if not r then
		local rp = REACH / 2 ^ zoom
		r = {}
		for dy = -rp, rp do
			for dx = -rp, rp do
				local d = dx * dx + dy * dy
				if d <= rp * rp then
					r[#r + 1] = d * 1048576 + (dx + 512) * 1024 + dy + 512
				end
			end
		end
		table.sort(r)
		rings[zoom] = r
	end
	return r
end

-- the first offset at a distance of at least d
local function from(r, d)
	local lo, hi, key = 1, #r + 1, d * d * 1048576
	while lo < hi do
		local mid = floor((lo + hi) / 2)
		if r[mid] < key then
			lo = mid + 1
		else
			hi = mid
		end
	end
	return lo
end

-- new pixels nearest first; after a step only the ring that the step uncovers (what was done around the old spot is
-- done around the new one too, less the step); pixels that failed again after a while; with nothing new, a few drawn
-- pixels again (the world changes). The outer ring of the reach only on every other pixel, Minecraft's checkered edge
local function survey(m, st, pos, t0)
	local r = ring(m.zoom)
	local fx, fy = locate(m, pos)
	local cx, cy = floor(fx), floor(fy)
	local rp = REACH / m.s
	local edge = (rp - math.max(1, rp / 32)) ^ 2 * 1048576
	local feet = floor(pos.y + 0.5)
	local cost = m.s == 1 and 1 or 4
	if cx ~= st.cx or cy ~= st.cy then
		local done = math.sqrt(math.min(edge, st.new > 0 and r[math.min(st.new, #r)] or 0) / 1048576)
		local keep = st.cx and done - math.sqrt((cx - st.cx) ^ 2 + (cy - st.cy) ^ 2) - 1 or 0
		st.new = from(r, math.max(0, keep)) - 1
		st.cx, st.cy = cx, cy
	elseif st.new >= #r and st.failed and t0 >= st.retry then
		st.new, st.failed = 0, false
	end
	local spent, n, open = 0, 0, st.new < #r
	while st.new < #r and spent < NEW and n < SCAN do
		n = n + 1
		if n % 64 == 0 and core.get_us_time() - t0 > BUDGET then
			break
		end
		st.new = st.new + 1
		local e = r[st.new]
		local k = e % 1048576
		local px, py = cx + floor(k / 1024) - 512, cy + k % 1024 - 512
		if px >= 0 and py >= 0 and px < PIXELS and py < PIXELS and (e <= edge or (px + py) % 2 == 1) then
			local i = py * PIXELS + px + 1
			if m.p[i] == 0 then
				if (m.fail[i] or 0) > t0 then
					st.failed = true
				elseif draw(m, px, py, guess(m, px, py, feet)) then
					st.drew = true
					spent = spent + cost
				elseif busy then
					st.new = st.new - 1
					break
				else
					m.fail[i], st.failed = t0 + 5e6, true
					spent = spent + cost
				end
			end
		end
	end
	if st.new < #r then
		return
	end
	if open and st.failed then
		st.retry, st.drew = t0 + (st.drew and 5e6 or 20e6), false
	end
	spent = 0
	for _ = 1, SCAN do
		if spent >= OLD or core.get_us_time() - t0 > BUDGET then
			break
		end
		st.old = st.old % #r + 1
		local k = r[st.old] % 1048576
		local px, py = cx + floor(k / 1024) - 512, cy + k % 1024 - 512
		local v = px >= 0 and py >= 0 and px < PIXELS and py < PIXELS and m.p[py * PIXELS + px + 1] or 0
		if v > 0 then
			if not draw(m, px, py, height(v)) and busy then
				break
			end
			spent = spent + cost
		end
	end
end

local function image(m, t)
	local p, s = m.p, m.s
	local x0, y0 = (t - 1) % TILES * TILE, floor((t - 1) / TILES) * TILE
	local out, n = {}, 0
	for py = y0, y0 + TILE - 1 do
		local row = py * PIXELS + 1
		for px = x0, x0 + TILE - 1 do
			local v = p[row + px]
			n = n + 1
			if v == 0 then
				out[n] = PAPER
			else
				local sh, odd, k = shade(v % 256), (px + py) % 2
				if sh.water then
					local f = floor(v / 256) % 32 * 0.1 + odd * 0.2
					k = f < 0.5 and 3 or f > 0.9 and 1 or 2
				else
					local north = py > 0 and p[row + px - PIXELS] or 0
					local e = (north > 0 and (height(v) - height(north)) * 4 / (s + 4) or 0) + (odd - 0.5) * 0.4
					k = e > 0.6 and 3 or e < -0.6 and 1 or 2
				end
				out[n] = sh[k]
			end
		end
	end
	return "[png:" .. core.encode_base64(core.encode_png(TILE, TILE, table.concat(out)))
end

local function redraw(m, now)
	for t = 1, TILES * TILES do
		if m.dirty[t] and now - m.stamp[t] >= REDRAW[m.zoom + 1] then
			m.dirty[t], m.stamp[t] = false, now
			m.img[t] = image(m, t)
		end
	end
end

-- the arrow: where the player is on the map and which way they look (north up), or a dot on the edge when off it
local function marker(m, player)
	local fx, fy = locate(m, player:get_pos())
	local off = fx < 0 or fy < 0 or fx > PIXELS or fy > PIXELS
	fx, fy = math.max(0, math.min(PIXELS, fx)), math.max(0, math.min(PIXELS, fy))
	local k = floor(-player:get_look_horizontal() / (2 * math.pi) * 16 + 0.5) % 16
	return off and "goodluck_map_player_off.png" or "goodluck_map_player_" .. k .. ".png",
		{x = floor((fx - PIXELS / 2) * SCALE), y = floor((fy - PIXELS / 2) * SCALE)}
end

local function hide(player)
	local st = held[player:get_player_name()]
	if st then
		for _, id in pairs(st.hud) do
			player:hud_remove(id)
		end
		held[player:get_player_name()] = nil
		player:hud_set_flags({wielditem = true})
		save(maps[st.id])
	end
end

local function show(player, m, now)
	local st = held[player:get_player_name()]
	if st and st.id ~= m.id then
		hide(player)
		st = nil
	end
	if not st then
		redraw(m, now)
		local at = {x = 0.5, y = 0.5}
		st = {id = m.id, new = 0, old = 0, saved = now, shown = {}, hud = {}}
		st.hud.frame = player:hud_add({type = "image", text = "goodluck_map_frame.png", position = at,
			alignment = {x = 0, y = 0}, scale = {x = SCALE, y = SCALE}, z_index = 20})
		for t = 1, TILES * TILES do
			local ox, oy = (t - 1) % TILES * TILE, floor((t - 1) / TILES) * TILE
			st.hud[t] = player:hud_add({type = "image", text = m.img[t], position = at, alignment = {x = 1, y = 1},
				offset = {x = (ox - PIXELS / 2) * SCALE, y = (oy - PIXELS / 2) * SCALE},
				scale = {x = SCALE, y = SCALE}, z_index = 21})
			st.shown[t] = m.img[t]
		end
		st.tex, st.off = marker(m, player)
		st.hud.marker = player:hud_add({type = "image", text = st.tex, position = at, offset = st.off,
			alignment = {x = 0, y = 0}, scale = {x = MARKER, y = MARKER}, z_index = 22})
		held[player:get_player_name()] = st
		player:hud_set_flags({wielditem = false})
	end
	return st
end

core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < TICK then
		return
	end
	timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		local stack = player:get_wielded_item()
		local m = stack:get_name() == MAP and load(stack:get_meta():get_int("goodluck_map:id"))
		if m then
			local now = core.get_us_time()
			clock, loads, busy = now, 0, false
			local st = show(player, m, now)
			survey(m, st, player:get_pos(), now)
			redraw(m, now)
			for t = 1, TILES * TILES do
				if st.shown[t] ~= m.img[t] then
					st.shown[t] = m.img[t]
					player:hud_change(st.hud[t], "text", m.img[t])
				end
			end
			local tex, off = marker(m, player)
			if tex ~= st.tex then
				st.tex = tex
				player:hud_change(st.hud.marker, "text", tex)
			end
			if off.x ~= st.off.x or off.y ~= st.off.y then
				st.off = off
				player:hud_change(st.hud.marker, "offset", off)
			end
			if now - st.saved > 60e6 then
				st.saved = now
				save(m)
			end
		else
			hide(player)
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local st = held[player:get_player_name()]
	held[player:get_player_name()] = nil
	save(st and maps[st.id])
end)

core.register_on_shutdown(function()
	for _, m in pairs(maps) do
		save(m)
	end
end)

core.register_craftitem(EMPTY, {
	description = S("Empty Map") .. "\n" .. S("R1: start the map of where you are"),
	short_description = S("Empty Map"),
	inventory_image = "goodluck_map_empty.png",
	on_use = function(itemstack, user)
		if not user then
			return
		end
		local map = goodluck_map.new(user:get_pos())
		itemstack:take_item()
		if itemstack:is_empty() then
			return map
		end
		local left = user:get_inventory():add_item("main", map)
		if not left:is_empty() then
			core.add_item(user:get_pos(), left)
		end
		return itemstack
	end,
})

core.register_craftitem(MAP, {
	description = S("Map"),
	inventory_image = "goodluck_map_map.png",
	stack_max = 1,
	groups = {not_in_creative_inventory = 1},
})

core.register_craft({
	output = EMPTY,
	recipe = {
		{"default:paper", "default:paper", "default:paper"},
		{"default:paper", "goodluck_compass:compass", "default:paper"},
		{"default:paper", "default:paper", "default:paper"},
	},
})

-- zooming out (Bedrock's crafting table recipe, Minetest Game has no cartography table): a new map one level out
-- around the old one's centre, empty
core.register_craft({
	output = MAP,
	recipe = {
		{"default:paper", "default:paper", "default:paper"},
		{"default:paper", MAP, "default:paper"},
		{"default:paper", "default:paper", "default:paper"},
	},
})

local function zooming(stack, old_grid)
	local center = old_grid[5]
	if stack:get_name() == MAP and center and center:get_name() == MAP then
		return center, load(center:get_meta():get_int("goodluck_map:id"))
	end
end

core.register_craft_predict(function(stack, _, old_grid)
	local center, m = zooming(stack, old_grid)
	if center then
		if not m or m.zoom >= MAX_ZOOM then
			return ItemStack("")
		end
		local out = ItemStack(MAP)
		out:get_meta():set_string("description", describe("?", m.zoom + 1))
		return out
	end
end)

core.register_on_craft(function(stack, _, old_grid)
	local center, m = zooming(stack, old_grid)
	if center then
		if not m or m.zoom >= MAX_ZOOM then
			return center
		end
		return goodluck_map.new({x = m.cx, z = m.cz}, m.zoom + 1)
	end
end)

-- Minetest Game's mapping kit works the minimap, which this console keeps off
if core.registered_items["map:mapping_kit"] then
	core.clear_craft({output = "map:mapping_kit"})
	local groups = table.copy(core.registered_items["map:mapping_kit"].groups)
	groups.not_in_creative_inventory = 1
	core.override_item("map:mapping_kit", {groups = groups})
end
