-- The files come from the player's own game, taken into textures/server by luanti-update.sh, which lists what came
-- in mod_data; nothing of Minecraft ships with goodluckOS
if not core.settings:get_bool("goodluck_mc_assets", false) then return end

local have = {}
local list = io.open(core.get_mod_data_path() .. "/imported.txt")
if not list then return end
for name in list:lines() do have[name:match("^%s*(.-)%s*$")] = true end
list:close()

local opaque_leaves = core.settings:get("leaves_style") == "opaque"

-- Minecraft's leaf holes are black; opaque leaves get a dark shade of the leaf behind them instead
local function backed(expr)
	local r, g, b = expr:match("%[multiply:#(%x%x)(%x%x)(%x%x)")
	local dark = ("#%02x%02x%02x"):format(tonumber(r, 16) * 0.35, tonumber(g, 16) * 0.35, tonumber(b, 16) * 0.35)
	return "[fill:16x16:0,0:" .. dark .. "^(" .. expr .. ")"
end

local map, length = {}, {}
for line in io.lines(core.get_modpath("goodluck_mcassets") .. "/textures.txt") do
	local from, to, rest = line:match("^([^#%s]%S*)%s+(%S+)%s*(.*)$")
	if from and not rest:find("file") then
		to = to:gsub("{([^}]+)}", function(p) return "mc_" .. p:gsub("/", "_") .. ".png" end)
		-- a file the player's version lacks leaves the game's texture
		local all = true
		for name in to:gmatch("mc_[%w_%-%.]+%.png") do all = all and have[name] end
		if all then
			if rest:find("leaves") and (opaque_leaves or from:find("_simple%.png$")) then to = backed(to) end
			map[from] = to
			length[from] = tonumber(rest:match("length=([%d.]+)"))
		end
	end
end

local function swap(s)
	if type(s) ~= "string" or s == "" then return s end
	if map[s] then return map[s] end
	-- [combine takes its own ":" and "^" escaping: only plain names go in there
	local plain = s:find("[combine", 1, true)
	return (s:gsub("[%w_%-%.]+%.png", function(t)
		local m = map[t]
		if m and m:find("^", 1, true) then return not plain and "(" .. m .. ")" or nil end
		return m
	end))
end

local function tiles(list)
	if type(list) ~= "table" then return end
	local out, changed = {}, false
	for i, t in ipairs(list) do
		if type(t) == "table" then
			local n, key = table.copy(t), t.name and "name" or "image"
			n[key] = swap(t[key])
			if n[key] ~= t[key] then
				changed = true
				if n.animation and length[t[key]] then n.animation.length = length[t[key]] end
			end
			out[i] = n
		else
			out[i] = swap(t)
			changed = changed or out[i] ~= t
		end
	end
	return changed and out or nil
end

core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_items) do
		local o = {}
		for _, f in ipairs({"tiles", "overlay_tiles", "special_tiles"}) do o[f] = tiles(def[f]) end
		for _, f in ipairs({"inventory_image", "wield_image"}) do
			if swap(def[f]) ~= def[f] then o[f] = swap(def[f]) end
		end
		if next(o) and name ~= "" then core.override_item(name, o) end
	end
	for _, def in pairs(core.registered_entities) do
		local p = def.initial_properties
		if p and p.textures then p.textures = tiles(p.textures) or p.textures end
		-- mobs_redo picks one of these lists when a mob spawns
		if type(def.textures) == "table" then
			for i, set in ipairs(def.textures) do def.textures[i] = tiles(set) or set end
		end
	end
end)

-- entities given their textures as they run (mobs_redo's animals, from what each keeps in the world): a world saves
-- the game's names, Minecraft's are only drawn
core.register_on_joinplayer(function(player)
	local methods = getmetatable(player)
	if type(methods) ~= "table" or methods.goodluck_mcassets then return end
	local set_properties = methods.set_properties
	methods.set_properties = function(self, props)
		local t = type(props) == "table" and tiles(props.textures)
		if t then
			props = table.copy(props)
			props.textures = t
		end
		return set_properties(self, props)
	end
	methods.goodluck_mcassets = true
end)
