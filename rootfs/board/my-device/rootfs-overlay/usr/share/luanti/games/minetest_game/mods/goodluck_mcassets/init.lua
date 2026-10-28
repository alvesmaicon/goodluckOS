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
	-- inside [combine, a name with modifiers goes in with its ":" and "^" escaped
	local plain = s:find("[combine", 1, true)
	return (s:gsub("[%w_%-%.]+%.png", function(t)
		local m = map[t]
		if m and m:find("[%^:]") then return plain and m:gsub("[%^:]", "\\%0") or "(" .. m .. ")" end
		return m
	end))
end

-- the inventory's window as a 9-slice in a 32x32 image: Minecraft's chest window, whose title band is flat beyond
-- the border, gives the upper corners, the top and side edges and the centre; the lower pieces are the upper ones
-- upside down
local function window(img)
	local function piece(w, h, x, y, flip)
		return ("[combine\\:%dx%d\\:%d,%d=%s%s"):format(w, h, -x, -y, img, flip and "\\^[transformFY" or "")
	end
	return ("[combine:32x32:0,0=%s:22,0=%s:0,22=%s:22,22=%s:10,0=%s:10,22=%s:0,10=%s:22,10=%s:10,10=%s"):format(
		piece(10, 10, 0, 0), piece(10, 10, 166, 0), piece(10, 10, 0, 0, true), piece(10, 10, 166, 0, true),
		piece(12, 10, 60, 0), piece(12, 10, 60, 0, true), piece(10, 12, 0, 4), piece(10, 12, 166, 4),
		piece(12, 12, 60, 4))
end

-- Minecraft's hotbar holds 9 slots of 20 px in 182: cut to the slots the player has, the right edge kept
local function hotbar(img, slots)
	if slots >= 9 then return img end
	local w = 2 + 20 * slots
	return ("[combine:%dx22:%d,0=%s:0,0=[combine\\:%dx22\\:0,0=%s"):format(w, w - 182, img, w - 1, img)
end

-- every image a formspec names, the window and the slot colours with it; the window's labels dark, as Minecraft's
local LISTCOLORS = "listcolors[#00000069;#5A5A5A;#141318;#30434C;#FFF]"
local HEADER = {formspec_version = true, size = true, position = true, anchor = true, padding = true, no_prepend = true}
local WINDOWS = {["gui_formbg.png"] = true, ["x_enchanting_gui_formbg.png"] = true}
local function formspec(fs)
	if type(fs) ~= "string" then return fs end
	local windowed = false
	-- a name with modifiers goes in as a group, whole in what surrounds it, and escaped as the formspec's own text,
	-- so that the escaping inside [combine survives
	fs = fs:gsub("[%w_%-%.]+%.png", function(t)
		local m = map[t]
		if WINDOWS[t] and m then
			m = window(m)
			windowed = true
		end
		return m and m:find("[%^%[]") and core.formspec_escape("(" .. m .. ")") or m
	end)
	if windowed then
		-- slot, hover, border and tooltip colours of our own, near the window's greys
		fs = fs:gsub(LISTCOLORS:gsub("%p", "%%%0"), "listcolors[#919191;#d4d4d4;#3e3e3e;#1c1430f0;#fff]")
		-- after the leading elements: no_prepend[] only counts right after them
		local at = 0
		for first, element in fs:gmatch("()([%w_]+)%[") do
			if first ~= at or not HEADER[element] then break end
			at = fs:find("]", first, true) + 1
		end
		fs = fs:sub(1, at - 1) .. "style_type[label;textcolor=#404040]" .. fs:sub(at)
		-- the selected tab's bottom rows are the window's top border: 2 px less into the window than the game's own
		-- tab; its top reaches over the formspec's edge, where the console's engine clips an image
		fs = fs:gsub("image%[([%d%.%-]+),([%d%.%-]+);([%d%.]+),([%d%.]+);([^;]*tab_top_selected[^;]*);4%]", function(x, y, w, h, img)
			local flipped = img:find("transformFY", 1, true)
			return ("style_type[image;noclip=true]image[%s,%g;%s,%g;%s;4]style_type[image;noclip=false]"):format(
				x, tonumber(y) + (flipped and 0.04 or 0), w, tonumber(h) - 0.04, img)
		end)
	end
	return fs
end

local hud_replace_builtin = core.hud_replace_builtin
core.hud_replace_builtin = function(name, def)
	if type(def) == "table" then
		def = table.copy(def)
		def.text, def.text2 = swap(def.text), swap(def.text2)
	end
	return hud_replace_builtin(name, def)
end

local show_formspec = core.show_formspec
core.show_formspec = function(player, name, fs) return show_formspec(player, name, formspec(fs)) end

for _, f in ipairs({"add_particle", "add_particlespawner"}) do
	local add = core[f]
	core[f] = function(def, ...)
		if type(def) == "table" and def.texture then
			def = table.copy(def)
			if type(def.texture) == "table" then
				def.texture = table.copy(def.texture)
				def.texture.name = swap(def.texture.name)
			else
				def.texture = swap(def.texture)
			end
		end
		return add(def, ...)
	end
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

-- Minecraft breaks and places a block with its dig/* files at pitch 0.8, where the game's dug and place sounds are
-- its footsteps, or one sound for all; the material is read from the dug sound (wool from its group)
local MATERIAL = {
	default_hard_footstep = "stone", default_dug_node = "stone", default_dug_metal = "stone",
	default_dirt_footstep = "gravel", default_gravel_dug = "gravel", default_sand_footstep = "sand",
	default_grass_footstep = "grass", default_wood_footstep = "wood", default_snow_footstep = "snow",
}

local function sounds(def)
	local s = def.sounds
	if type(s) ~= "table" then return end
	local m = def.groups and def.groups.wool and "cloth" or type(s.dug) == "table" and MATERIAL[s.dug.name]
	if not m or not have["goodluck_mc_break_" .. m .. ".1.ogg"] then return end
	local out = table.copy(s)
	out.dug = {name = "goodluck_mc_break_" .. m, gain = 1.0, pitch = 0.8}
	out.place = {name = "goodluck_mc_break_" .. m, gain = 1.0, pitch = 0.8}
	if m == "cloth" and have["goodluck_mc_step_cloth.1.ogg"] then
		out.footstep = {name = "goodluck_mc_step_cloth", gain = 0.2}
	end
	return out
end

core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_items) do
		local o = {}
		for _, f in ipairs({"tiles", "overlay_tiles", "special_tiles"}) do o[f] = tiles(def[f]) end
		for _, f in ipairs({"inventory_image", "wield_image"}) do
			if swap(def[f]) ~= def[f] then o[f] = swap(def[f]) end
		end
		o.sounds = sounds(def)
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
	-- HUD elements, the hotbar and the inventory, from any mod, whenever they are set
	local hud_add, hud_change = methods.hud_add, methods.hud_change
	methods.hud_add = function(self, def)
		if type(def) == "table" then
			def = table.copy(def)
			def.text, def.text2 = swap(def.text), swap(def.text2)
		end
		return hud_add(self, def)
	end
	methods.hud_change = function(self, id, stat, value)
		if stat == "text" or stat == "text2" then value = swap(value) end
		return hud_change(self, id, stat, value)
	end
	local set_hotbar, set_selected = methods.hud_set_hotbar_image, methods.hud_set_hotbar_selected_image
	methods.hud_set_hotbar_image = function(self, img)
		local m = swap(img)
		if m ~= img then m = hotbar(m, self:hud_get_hotbar_itemcount()) end
		return set_hotbar(self, m)
	end
	methods.hud_set_hotbar_selected_image = function(self, img) return set_selected(self, swap(img)) end
	local set_inventory_formspec = methods.set_inventory_formspec
	methods.set_inventory_formspec = function(self, fs) return set_inventory_formspec(self, formspec(fs)) end
	local set_formspec_prepend = methods.set_formspec_prepend
	methods.set_formspec_prepend = function(self, fs) return set_formspec_prepend(self, formspec(fs)) end
	methods.goodluck_mcassets = true
end)

-- 3d_armor paints the pieces worn in their slots' order, the leggings over the chestplate's lower rows; Minecraft
-- draws them under it, and the layers above come with its belt
if armor then
	local update_player_visuals = armor.update_player_visuals
	armor.update_player_visuals = function(self, player)
		local t = self.textures[player:get_player_name()]
		if t and t.armor then
			local parts = t.armor:split("^")
			-- a piece in a group ("(...)") over its 1x1 blank.png stays 1x1: the base gets the skin's size
			if parts[1] == "blank.png" then
				parts[1] = "[fill:64x32:0,0:#00000000"
			end
			for i = 3, #parts do
				if parts[i]:find("^3d_armor_leggings_") then
					table.insert(parts, 2, table.remove(parts, i))
					break
				end
			end
			t.armor = table.concat(parts, "^")
		end
		return update_player_visuals(self, player)
	end
end

-- what the other mods set as the player joined, through the methods above once every join callback ran: the
-- hotbar's images, the inventory and the HUD elements (the first player's were set before the methods were in place)
core.register_on_joinplayer(function(player)
	core.after(0, function()
		if not player:is_valid() then return end
		player:hud_set_hotbar_image(player:hud_get_hotbar_image())
		player:hud_set_hotbar_selected_image(player:hud_get_hotbar_selected_image())
		player:set_inventory_formspec(player:get_inventory_formspec())
		player:set_formspec_prepend(player:get_formspec_prepend())
		for id, def in pairs(player:hud_get_all() or {}) do
			for _, f in ipairs({"text", "text2"}) do
				if type(def[f]) == "string" and swap(def[f]) ~= def[f] then player:hud_change(id, f, def[f]) end
			end
		end
	end)
end)
