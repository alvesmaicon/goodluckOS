-- The colour a node shows from above: the average of its top texture, as the engine's minimap has it, read from the
-- mods' PNG files (decoded here, the server has no image loader); a few fixed colours where a texture can't be read
local floor = math.floor
local paths

local function scan(dir)
	for _, f in ipairs(core.get_dir_list(dir, false) or {}) do
		paths[f] = paths[f] or dir .. "/" .. f
	end
	for _, d in ipairs(core.get_dir_list(dir, true) or {}) do
		scan(dir .. "/" .. d)
	end
end

local function be32(s, i)
	local a, b, c, d = s:byte(i, i + 3)
	return ((a * 256 + b) * 256 + c) * 256 + d
end

local function paeth(a, b, c)
	local p = a + b - c
	local pa, pb, pc = math.abs(p - a), math.abs(p - b), math.abs(p - c)
	if pa <= pb and pa <= pc then
		return a
	end
	return pb <= pc and b or c
end

local CHANNELS = {[0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4}
local ADAM7 = {{0, 0, 8, 8}, {4, 0, 8, 8}, {0, 4, 4, 8}, {2, 0, 4, 4}, {0, 2, 2, 4}, {1, 0, 2, 2}, {0, 1, 1, 2}}

-- a PNG's colour weighted by alpha and its mean alpha (0-1)
local function average(path)
	local f = io.open(path, "rb")
	if not f then
		return
	end
	local s = f:read("*a")
	f:close()
	if s:sub(1, 8) ~= "\137PNG\r\n\26\n" then
		return
	end
	local w, h, depth, ctype, interlace, plte, trns
	local idat, pos = {}, 9
	while pos + 8 <= #s do
		local len, typ = be32(s, pos), s:sub(pos + 4, pos + 7)
		local data = s:sub(pos + 8, pos + 7 + len)
		if typ == "IHDR" then
			w, h, depth, ctype, interlace = be32(data, 1), be32(data, 5), data:byte(9), data:byte(10), data:byte(13)
		elseif typ == "PLTE" then
			plte = data
		elseif typ == "tRNS" then
			trns = data
		elseif typ == "IDAT" then
			idat[#idat + 1] = data
		elseif typ == "IEND" then
			break
		end
		pos = pos + 12 + len
	end
	local channels = w and CHANNELS[ctype]
	if not channels or (ctype == 3 and not plte) then
		return
	end
	local raw = core.decompress(table.concat(idat), "deflate")
	local bits = depth * channels
	local bpp, step, top = math.max(1, bits / 8), depth / 8, 2 ^ depth - 1
	local sr, sg, sb, sa, n = 0, 0, 0, 0, 0
	local at = 1
	local passes = interlace == 1 and ADAM7 or {{0, 0, 1, 1}}
	for _, p in ipairs(passes) do
		local pw, ph = math.ceil((w - p[1]) / p[3]), math.ceil((h - p[2]) / p[4])
		if pw > 0 and ph > 0 then
			local stride = math.ceil(pw * bits / 8)
			local prev = {}
			for i = 1, stride do
				prev[i] = 0
			end
			for _ = 1, ph do
				local ft = raw:byte(at)
				local cur = {raw:byte(at + 1, at + stride)}
				if ft == 1 then
					for i = bpp + 1, stride do
						cur[i] = (cur[i] + cur[i - bpp]) % 256
					end
				elseif ft == 2 then
					for i = 1, stride do
						cur[i] = (cur[i] + prev[i]) % 256
					end
				elseif ft == 3 then
					for i = 1, stride do
						cur[i] = (cur[i] + floor(((cur[i - bpp] or 0) + prev[i]) / 2)) % 256
					end
				elseif ft == 4 then
					for i = 1, stride do
						cur[i] = (cur[i] + paeth(cur[i - bpp] or 0, prev[i], prev[i - bpp] or 0)) % 256
					end
				end
				for x = 0, pw - 1 do
					local r, g, b, a
					if depth < 8 then
						local bit = x * depth
						local v = floor(cur[floor(bit / 8) + 1] / 2 ^ (8 - depth - bit % 8)) % (top + 1)
						if ctype == 3 then
							r, g, b = plte:byte(v * 3 + 1, v * 3 + 3)
							a = trns and trns:byte(v + 1) or 255
						else
							r = floor(v * 255 / top)
							g, b, a = r, r, 255
						end
					else
						local o = x * channels * step + 1
						if ctype == 3 then
							local v = cur[o]
							r, g, b = plte:byte(v * 3 + 1, v * 3 + 3)
							a = trns and trns:byte(v + 1) or 255
						elseif ctype == 0 then
							r, g, b, a = cur[o], cur[o], cur[o], 255
						elseif ctype == 4 then
							r, a = cur[o], cur[o + step]
							g, b = r, r
						else
							r, g, b = cur[o], cur[o + step], cur[o + 2 * step]
							a = ctype == 6 and cur[o + 3 * step] or 255
						end
					end
					if r then
						sr, sg, sb, sa = sr + r * a, sg + g * a, sb + b * a, sa + a
					end
					n = n + 1
				end
				prev = cur
				at = at + 1 + stride
			end
		end
	end
	if sa > 0 then
		return {sr / sa, sg / sa, sb / sa, sa / 255 / n}
	end
end

local files = {}
local function file(name)
	local c = files[name]
	if c == nil then
		if not paths then
			paths = {}
			for _, mod in ipairs(core.get_modnames()) do
				scan(core.get_modpath(mod) .. "/textures")
			end
		end
		local ok, avg = pcall(average, paths[name] or "")
		c = ok and avg or false
		files[name] = c
	end
	return c
end

local function rgb(spec)
	if type(spec) == "table" then
		return {spec.r or 255, spec.g or 255, spec.b or 255, spec.a or 255}
	end
	local hex = type(spec) == "string" and spec:match("^#(%x+)$")
	if hex and (#hex == 3 or #hex == 4) then
		hex = hex:gsub("%x", "%0%0")
	end
	if hex and (#hex == 6 or #hex == 8) then
		return {tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16),
			#hex == 8 and tonumber(hex:sub(7, 8), 16) or 255}
	end
end

-- a texture string: files (overlays blended by how much of them is opaque), [colorize and [multiply; other modifiers
-- don't change the average much and are left out
local function texture(str)
	local parts, depth, start = {}, 0, 1
	for i = 1, #str do
		local ch = str:sub(i, i)
		if ch == "(" then
			depth = depth + 1
		elseif ch == ")" then
			depth = depth - 1
		elseif ch == "^" and depth == 0 and str:sub(i - 1, i - 1) ~= "\\" then
			parts[#parts + 1] = str:sub(start, i - 1)
			start = i + 1
		end
	end
	parts[#parts + 1] = str:sub(start)
	local c
	for _, part in ipairs(parts) do
		local layer
		if part:sub(1, 1) == "(" and part:sub(-1) == ")" then
			local r, g, b, a = texture(part:sub(2, -2))
			layer = r and {r, g, b, a}
		elseif part:sub(1, 1) == "[" then
			local mod, arg = part:match("^%[(%a+):(.*)$")
			local col = arg and rgb(arg:match("^[^:]+"))
			if c and col and mod == "colorize" then
				local k = (tonumber(arg:match(":(%d+)$")) or col[4]) / 255
				c = {c[1] + (col[1] - c[1]) * k, c[2] + (col[2] - c[2]) * k, c[3] + (col[3] - c[3]) * k, c[4]}
			elseif c and col and mod == "multiply" then
				c = {c[1] * col[1] / 255, c[2] * col[2] / 255, c[3] * col[3] / 255, c[4]}
			end
		elseif part ~= "" then
			layer = file(part)
		end
		if layer then
			local k = c and layer[4] or 1
			c = c or {0, 0, 0, 0}
			c = {c[1] + (layer[1] - c[1]) * k, c[2] + (layer[2] - c[2]) * k, c[3] + (layer[3] - c[3]) * k,
				c[4] + (1 - c[4]) * layer[4]}
		end
	end
	if c then
		return c[1], c[2], c[3], c[4]
	end
end

local function tile(t)
	if type(t) == "table" then
		return t.name or t.image, t.color
	end
	return t
end

-- Minecraft's map colours for what has no readable texture
local FALLBACK = {{"water", 0x4040FF}, {"lava", 0xFF0000}, {"ice", 0xA0A0FF}, {"snow", 0xFFFFFF},
	{"leaves", 0x007C00}, {"sand", 0xF7E9A3}, {"tree", 0x8F7748}, {"wood", 0x8F7748}, {"stone", 0x707070},
	{"soil", 0x976D4D}, {"flora", 0x007C00}}

function goodluck_map.node_color(name)
	local def = core.registered_nodes[name] or {}
	local tiles = def.tiles or def.tile_images
	local str, color = tile(tiles and tiles[1])
	local r, g, b
	if type(str) == "string" then
		r, g, b = texture(str)
		local over = tile(def.overlay_tiles and def.overlay_tiles[1])
		local o = r and type(over) == "string" and over ~= "" and {texture(over)}
		if o and o[1] then
			r, g, b = r + (o[1] - r) * o[4], g + (o[2] - g) * o[4], b + (o[3] - b) * o[4]
		end
	end
	if not r then
		local groups = def.groups or {}
		r, g, b = 160, 160, 160
		for _, f in ipairs(FALLBACK) do
			if (groups[f[1]] or 0) > 0 or name:find(f[1], 1, true) then
				r, g, b = floor(f[2] / 65536), floor(f[2] / 256) % 256, f[2] % 256
				break
			end
		end
	end
	local tint = rgb(color or def.color)
	if tint then
		r, g, b = r * tint[1] / 255, g * tint[2] / 255, b * tint[3] / 255
	end
	return floor(r + 0.5), floor(g + 0.5), floor(b + 0.5)
end
