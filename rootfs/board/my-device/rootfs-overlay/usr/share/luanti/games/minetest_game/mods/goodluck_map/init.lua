-- Minecraft's maps. An empty map (eight papers around a compass), used with R1, becomes the map of the 128 x 128 nodes
-- around you, on a grid so that maps sit side by side; held, it draws what lies within 64 nodes as you go, north up,
-- shaded as Minecraft's (higher than the north neighbour lighter, deep water darker), and shows you as an arrow.
-- 64 x 64 pixels of 2 x 2 nodes, drawn again at most every 2 s: the engine keeps every image it is sent, so a bigger
-- or more frequent one would eat the console's memory. One ray a pixel (core.raycast) finds the top node
local S = core.get_translator("goodluck_map")
local EMPTY, MAP = "goodluck_map:empty_map", "goodluck_map:map"
local PIXELS, NODES = 64, 2
local HALF = PIXELS * NODES / 2
local REACH = 32 -- pixels around the player that get drawn (64 nodes)
local RAYS, TICK, REDRAW = 48, 0.25, 2
local SCALE, MARKER = 3, 2
local storage = core.get_mod_storage()
local maps, held = {}, {}
local timer = 0

goodluck_map = {}

-- Minecraft's map colours, each in its three shades (180, 220 and 255 of 255)
local CATS = {
	{"water", 0x4040FF}, {"lava", 0xFF5A00}, {"ice", 0xA0A0FF}, {"snow", 0xFFFFFF}, {"leaves", 0x007C00},
	{"dry", 0xBAA55A}, {"grass", 0x7FB238}, {"desert", 0xD87F33}, {"sand", 0xF7E9A3}, {"wood", 0x8F7748},
	{"stone", 0x707070}, {"litter", 0x5A6E2E}, {"dirt", 0x976D4D}, {"clay", 0xA4A8B8}, {"brick", 0x993333},
	{"other", 0xA0A0A0},
}
local INDEX, COLOR = {}, {}
for i, cat in ipairs(CATS) do
	INDEX[cat[1]] = i
	local r, g, b = math.floor(cat[2] / 65536), math.floor(cat[2] / 256) % 256, cat[2] % 256
	COLOR[i] = {}
	for s, k in ipairs({180 / 255, 220 / 255, 1}) do
		COLOR[i][s] = string.char(math.floor(r * k), math.floor(g * k), math.floor(b * k), 255)
	end
end
local PAPER = string.char(226, 212, 168, 255)
local WATER = INDEX.water

local kinds = {}
local function kind(name)
	local k = kinds[name]
	if k then
		return k
	end
	local def = core.registered_nodes[name]
	local g = def and def.groups or {}
	local function has(s)
		return name:find(s, 1, true) ~= nil
	end
	local c = g.water and "water" or g.lava and "lava" or has("ice") and "ice" or has("snow") and "snow" or
		g.leaves and "leaves" or (has("dry_grass") or has("dry_dirt") or has("dry_shrub")) and "dry" or
		(has("dirt_with_grass") or g.grass or g.flora or has("junglegrass")) and "grass" or
		has("desert") and "desert" or (g.sand or has("sandstone")) and "sand" or (g.tree or g.wood) and "wood" or
		(g.stone or has("cobble") or has("gravel") or has("stone")) and "stone" or has("litter") and "litter" or
		(has("dirt") or has("permafrost") or g.soil) and "dirt" or has("clay") and "clay" or has("brick") and "brick" or
		"other"
	kinds[name] = INDEX[c]
	return INDEX[c]
end

-- a map's pixels: kind (0 not drawn yet), height + 128, water depth; kept as strings in mod storage
local function bytes(s)
	local t = {}
	for i = 1, PIXELS * PIXELS do
		t[i] = s ~= "" and s:byte(i) or 0
	end
	return t
end

local function chars(t)
	local out = {}
	for i = 1, #t do
		out[i] = string.char(t[i])
	end
	return table.concat(out)
end

local function load(id)
	if not maps[id] then
		local cx, cz = (storage:get_string("m" .. id)):match("^(-?%d+),(-?%d+)$")
		if not cx then
			return nil
		end
		maps[id] = {id = id, cx = tonumber(cx), cz = tonumber(cz), c = bytes(storage:get_string("c" .. id)),
			h = bytes(storage:get_string("h" .. id)), d = bytes(storage:get_string("d" .. id))}
	end
	return maps[id]
end

local function save(m)
	if m.unsaved then
		storage:set_string("c" .. m.id, chars(m.c))
		storage:set_string("h" .. m.id, chars(m.h))
		storage:set_string("d" .. m.id, chars(m.d))
		m.unsaved = nil
	end
end

-- a map of the grid square around pos (Minecraft's: centres every 128 nodes)
function goodluck_map.new(pos)
	local id = storage:get_int("next") + 1
	storage:set_int("next", id)
	local cx = math.floor((pos.x + HALF) / (2 * HALF)) * 2 * HALF
	local cz = math.floor((pos.z + HALF) / (2 * HALF)) * 2 * HALF
	storage:set_string("m" .. id, cx .. "," .. cz)
	local stack = ItemStack(MAP)
	local meta = stack:get_meta()
	meta:set_int("goodluck_map:id", id)
	meta:set_string("description", S("Map #@1", id))
	return stack
end

-- the pixel a node falls in, fractional, and back
local function to_pixel(m, x, z)
	return (x - (m.cx - HALF)) / NODES, ((m.cz + HALF) - z) / NODES
end

local function draw(m, px, py, y0)
	local x, z = m.cx - HALF + px * NODES, m.cz + HALF - 1 - py * NODES
	local ray = core.raycast(vector.new(x, y0 + 48, z), vector.new(x, y0 - 64, z), false, true)
	local hit = ray:next()
	while hit and hit.type ~= "node" do
		hit = ray:next()
	end
	if not hit then
		return
	end
	local c = kind(core.get_node(hit.under).name)
	local depth = 0
	if c == WATER then
		local floor = core.raycast(hit.under, vector.offset(hit.under, 0, -24, 0), false, false):next()
		depth = floor and floor.type == "node" and hit.under.y - floor.under.y or 24
	end
	local i = py * PIXELS + px + 1
	local h = math.max(0, math.min(255, hit.under.y + 128))
	if m.c[i] ~= c or m.h[i] ~= h or m.d[i] ~= depth then
		m.c[i], m.h[i], m.d[i] = c, h, depth
		m.dirty, m.unsaved = true, true
	end
end

local function image(m)
	local px = {}
	for i = 1, PIXELS * PIXELS do
		local c = m.c[i]
		if c == 0 then
			px[i] = PAPER
		else
			local shade
			if c == WATER then
				shade = m.d[i] <= 2 and 3 or m.d[i] <= 6 and 2 or 1
			else
				local n = i - PIXELS
				local hn = n >= 1 and m.c[n] ~= 0 and m.c[n] ~= WATER and m.h[n]
				shade = not hn and 2 or m.h[i] > hn and 3 or m.h[i] < hn and 1 or 2
			end
			px[i] = COLOR[c][shade]
		end
	end
	return "[png:" .. core.encode_base64(core.encode_png(PIXELS, PIXELS, table.concat(px)))
end

-- the arrow: where the player is on it and which way they look (north up), or a dot on the edge when off it
local function marker(m, player)
	local pos = player:get_pos()
	local fx, fy = to_pixel(m, pos.x, pos.z)
	local off = fx < 0 or fy < 0 or fx > PIXELS or fy > PIXELS
	fx, fy = math.max(0, math.min(PIXELS, fx)), math.max(0, math.min(PIXELS, fy))
	local k = math.floor(-player:get_look_horizontal() / (2 * math.pi) * 16 + 0.5) % 16
	return off and "goodluck_map_player_off.png" or "goodluck_map_player_" .. k .. ".png",
		{x = math.floor((fx - PIXELS / 2) * SCALE), y = math.floor((fy - PIXELS / 2) * SCALE)}
end

local function show(player, m)
	local name = player:get_player_name()
	local st = held[name]
	if st and st.id ~= m.id then
		for _, id in pairs(st.hud) do
			player:hud_remove(id)
		end
		st = nil
	end
	if not st then
		local tex, off = marker(m, player)
		local at = {x = 0.5, y = 0.5}
		st = {id = m.id, cursor = 0, drawn = 0, tex = tex, off = off, hud = {
			frame = player:hud_add({type = "image", text = "goodluck_map_frame.png", position = at,
				alignment = {x = 0, y = 0}, scale = {x = SCALE, y = SCALE}, z_index = 20}),
			map = player:hud_add({type = "image", text = image(m), position = at, alignment = {x = 0, y = 0},
				scale = {x = SCALE, y = SCALE}, z_index = 21}),
			marker = player:hud_add({type = "image", text = tex, position = at, offset = off,
				alignment = {x = 0, y = 0}, scale = {x = MARKER, y = MARKER}, z_index = 22}),
		}}
		held[name] = st
		m.dirty = false
		player:hud_set_flags({wielditem = false})
	end
	return st
end

local function hide(player)
	local st = held[player:get_player_name()]
	if st then
		for _, id in pairs(st.hud) do
			player:hud_remove(id)
		end
		held[player:get_player_name()] = nil
		player:hud_set_flags({wielditem = true})
	end
end

-- the next RAYS pixels within reach, sweeping the square around the player
local function survey(m, st, player)
	local pos = player:get_pos()
	local fx, fy = to_pixel(m, pos.x, pos.z)
	local x0, y0 = math.floor(fx) - REACH, math.floor(fy) - REACH
	local side = 2 * REACH + 1
	local y = math.floor(pos.y + 0.5)
	local rays = 0
	for _ = 1, side * side do
		if rays >= RAYS then
			break
		end
		st.cursor = (st.cursor + 1) % (side * side)
		local px, py = x0 + st.cursor % side, y0 + math.floor(st.cursor / side)
		local dx, dy = px - fx, py - fy
		if px >= 0 and py >= 0 and px < PIXELS and py < PIXELS and dx * dx + dy * dy <= REACH * REACH then
			draw(m, px, py, y)
			rays = rays + 1
		end
	end
end

core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < TICK then
		return
	end
	timer = 0
	local now = core.get_us_time() / 1e6
	for _, player in ipairs(core.get_connected_players()) do
		local stack = player:get_wielded_item()
		local m = stack:get_name() == MAP and load(stack:get_meta():get_int("goodluck_map:id"))
		if m then
			local st = show(player, m)
			survey(m, st, player)
			if m.dirty and now - st.drawn >= REDRAW then
				st.drawn, m.dirty = now, false
				player:hud_change(st.hud.map, "text", image(m))
				save(m)
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
		else
			hide(player)
		end
	end
end)

core.register_on_leaveplayer(function(player)
	held[player:get_player_name()] = nil
	for _, m in pairs(maps) do
		save(m)
	end
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

-- Minetest Game's mapping kit works the minimap, which this console keeps off
if core.registered_items["map:mapping_kit"] then
	core.clear_craft({output = "map:mapping_kit"})
	local groups = table.copy(core.registered_items["map:mapping_kit"].groups)
	groups.not_in_creative_inventory = 1
	core.override_item("map:mapping_kit", {groups = groups})
end
