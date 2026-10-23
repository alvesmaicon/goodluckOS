-- The files come from the player's own game (luanti-mc-import.sh); nothing of Minecraft ships with goodluckOS
if not core.settings:get_bool("goodluck_mc_assets", false) then return end

local map, length = {}, {}
for line in io.lines(core.get_modpath("goodluck_mcassets") .. "/textures.txt") do
	local from, to, rest = line:match("^([^#%s]%S*)%s+(%S+)%s*(.*)$")
	if from and not rest:find("file") then
		map[from] = to:gsub("{([^}]+)}", function(p) return "mc_" .. p:gsub("/", "_") .. ".png" end)
		length[from] = tonumber(rest:match("length=([%d.]+)"))
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
