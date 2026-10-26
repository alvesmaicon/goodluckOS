-- The farm animals in Minecraft's models (dev/luanti-art/animals.py) and sizes; their textures keep mobs_animal's
-- names. The entity class holds the mesh, the boxes and the animations, so the animals already in a world take them
-- too. glTF frames are seconds, so every animation plays at speed 1
local S = core.get_translator("goodluck_models")
local M = "goodluck_models_"

local function anims(walk, run, extra)
	local a = {stand_start = 0, stand_end = 1, walk_start = 1, walk_end = 1 + walk, run_start = 3, run_end = 3 + run,
		die_start = 4, die_end = 5, die_loop = false, speed_normal = 1, speed_run = 1}
	for k, v in pairs(extra or {}) do a[k] = v end
	return a
end
local EAT = {replace_start = 6, replace_end = 8, replace_loop = false}

-- Minecraft's widths and heights
local ANIMALS = {
	cow = {0.9, 1.4, anims(1, 0.5, EAT)},
	pig = {0.9, 0.9, anims(0.8, 0.4)},
	sheep = {0.9, 1.3, anims(1, 0.5, EAT)},
	chicken = {0.4, 0.7, anims(0.5, 0.3, {jump_start = 9, jump_end = 9.3})},
}
local MOBS = {["mobs_animal:cow"] = "cow", ["mobs_animal:pumba"] = "pig", ["mobs_animal:chicken"] = "chicken"}
for name in pairs(core.registered_entities) do
	if name:find("^mobs_animal:sheep_") then MOBS[name] = "sheep" end
end

local function animal(def, a, model)
	local box = {-a[1] / 2, -0.01, -a[1] / 2, a[1] / 2, a[2] - 0.01, a[1] / 2}
	local p = def.initial_properties
	p.mesh, p.collisionbox, p.selectionbox, p.visual_size = M .. model .. ".glb", box, box, {x = 1, y = 1}
	def.base_mesh, def.base_colbox, def.base_selbox, def.base_size = p.mesh, box, box, p.visual_size
	def.animation, def.rotate = a[3], 0
	-- none of them fights, as in Minecraft: hit, they run (mobs_animal's cow and warthog attack, its chicken runs from
	-- whoever comes near)
	def.passive, def.runaway, def.runaway_from = true, true, nil
	-- a sheep lowers its head to eat grass, as the cow already does
	if model == "sheep" and def.on_replace then
		local on_replace = def.on_replace
		def.on_replace = function(self, ...)
			self:set_animation("replace", true)
			return on_replace(self, ...)
		end
	end
end
for name, model in pairs(MOBS) do
	if core.registered_entities[name] then animal(core.registered_entities[name], ANIMALS[model], model) end
end

-- mobs_animal's warthog is Minecraft's pig now
if core.registered_entities["mobs_animal:pumba"] then
	core.registered_entities["mobs_animal:pumba"].description = S("Pig")
end
for _, egg in ipairs({"mobs_animal:pumba", "mobs_animal:pumba_set"}) do
	if core.registered_items[egg] then core.override_item(egg, {description = S("Pig")}) end
end

-- Minecraft's wool colours (a dye's colour at 3/4, white a light grey) in place of mobs_animal's tints, in every
-- texture a sheep is given
local WOOL = {
	["#ffffffc0"] = "#e6e6e6", ["#919191b0"] = "#757571", ["#444444b0"] = "#353b3d", ["#212121b0"] = "#151518",
	["#663300a0"] = "#623f25", ["#ff0000a0"] = "#84221c", ["#ff840170"] = "#ba6015", ["#fff80070"] = "#bea22d",
	["#61ff0170"] = "#609517", ["#005b0770"] = "#465d10", ["#00b4bf70"] = "#107575", ["#015dbb70"] = "#2d337f",
	["#5c00c970"] = "#66258a", ["#ed03ad70"] = "#953a8d", ["#ff85c470"] = "#b6687f",
}
local function wool(s)
	if type(s) ~= "string" then return s end
	return (s:gsub("(wool%.png%^%[multiply:)(#%x+)", function(a, c) return a .. (WOOL[c:lower()] or c) end))
end
for name, model in pairs(MOBS) do
	local list = model == "sheep" and core.registered_entities[name] and core.registered_entities[name].texture_list
	for _, set in ipairs(list or {}) do
		for i, t in ipairs(set) do set[i] = wool(t) end
	end
end
core.register_on_joinplayer(function(player)
	local methods = getmetatable(player)
	if type(methods) ~= "table" or methods.goodluck_models then return end
	local set_properties = methods.set_properties
	methods.set_properties = function(self, props)
		if type(props) == "table" and type(props.textures) == "table" then
			props = table.copy(props)
			for i, t in ipairs(props.textures) do props.textures[i] = wool(t) end
		end
		return set_properties(self, props)
	end
	methods.goodluck_models = true
end)
