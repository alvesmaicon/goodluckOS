-- Minecraft's potions (26.x's, but Slow Falling and the Turtle Master's, whose phantom and turtle this game hasn't):
-- a glass bottle filled at any water, then brewed (brewing.lua) into the awkward potion and on into the rest, longer
-- with redstone, stronger with glowstone, splash with gunpowder. Drunk, a potion gives its effects (goodluck_effects)
-- and leaves its bottle; thrown, a splash potion breaks where it lands and gives them to whoever is within 4, less
-- the farther (Healing and Harming also on mobs). Fermented spider eyes, glistering melon slices and rabbit feet too,
-- and the cauldron (cauldron.lua)
local S = core.get_translator("goodluck_potions")
local N = "goodluck_potions:"
local E = goodluck_effects
local BOTTLE = "vessels:glass_bottle"
local WATER_COLOR = "#385dc6"
goodluck_potions = {potions = {}, order = {}}
local P = goodluck_potions

-- id, name, splash name, effects: {effect, seconds, level}
local LIST = {
	{"water", S("Water Bottle"), S("Splash Water Bottle")},
	{"mundane", S("Mundane Potion"), S("Splash Mundane Potion")},
	{"thick", S("Thick Potion"), S("Splash Thick Potion")},
	{"awkward", S("Awkward Potion"), S("Splash Awkward Potion")},
	{"night_vision", S("Potion of Night Vision"), S("Splash Potion of Night Vision"), {"night_vision", 180}},
	{"long_night_vision", S("Potion of Night Vision"), S("Splash Potion of Night Vision"), {"night_vision", 480}},
	{"invisibility", S("Potion of Invisibility"), S("Splash Potion of Invisibility"), {"invisibility", 180}},
	{"long_invisibility", S("Potion of Invisibility"), S("Splash Potion of Invisibility"), {"invisibility", 480}},
	{"leaping", S("Potion of Leaping"), S("Splash Potion of Leaping"), {"jump_boost", 180}},
	{"long_leaping", S("Potion of Leaping"), S("Splash Potion of Leaping"), {"jump_boost", 480}},
	{"strong_leaping", S("Potion of Leaping"), S("Splash Potion of Leaping"), {"jump_boost", 90, 2}},
	{"fire_resistance", S("Potion of Fire Resistance"), S("Splash Potion of Fire Resistance"), {"fire_resistance", 180}},
	{"long_fire_resistance", S("Potion of Fire Resistance"), S("Splash Potion of Fire Resistance"),
		{"fire_resistance", 480}},
	{"swiftness", S("Potion of Swiftness"), S("Splash Potion of Swiftness"), {"speed", 180}},
	{"long_swiftness", S("Potion of Swiftness"), S("Splash Potion of Swiftness"), {"speed", 480}},
	{"strong_swiftness", S("Potion of Swiftness"), S("Splash Potion of Swiftness"), {"speed", 90, 2}},
	{"slowness", S("Potion of Slowness"), S("Splash Potion of Slowness"), {"slowness", 90}},
	{"long_slowness", S("Potion of Slowness"), S("Splash Potion of Slowness"), {"slowness", 240}},
	{"strong_slowness", S("Potion of Slowness"), S("Splash Potion of Slowness"), {"slowness", 20, 4}},
	{"water_breathing", S("Potion of Water Breathing"), S("Splash Potion of Water Breathing"),
		{"water_breathing", 180}},
	{"long_water_breathing", S("Potion of Water Breathing"), S("Splash Potion of Water Breathing"),
		{"water_breathing", 480}},
	{"healing", S("Potion of Healing"), S("Splash Potion of Healing"), {"instant_health", 0, 1}},
	{"strong_healing", S("Potion of Healing"), S("Splash Potion of Healing"), {"instant_health", 0, 2}},
	{"harming", S("Potion of Harming"), S("Splash Potion of Harming"), {"instant_damage", 0, 1}},
	{"strong_harming", S("Potion of Harming"), S("Splash Potion of Harming"), {"instant_damage", 0, 2}},
	{"poison", S("Potion of Poison"), S("Splash Potion of Poison"), {"poison", 45}},
	{"long_poison", S("Potion of Poison"), S("Splash Potion of Poison"), {"poison", 90}},
	{"strong_poison", S("Potion of Poison"), S("Splash Potion of Poison"), {"poison", 21.6, 2}},
	{"regeneration", S("Potion of Regeneration"), S("Splash Potion of Regeneration"), {"regeneration", 45}},
	{"long_regeneration", S("Potion of Regeneration"), S("Splash Potion of Regeneration"), {"regeneration", 90}},
	{"strong_regeneration", S("Potion of Regeneration"), S("Splash Potion of Regeneration"),
		{"regeneration", 22.5, 2}},
	{"strength", S("Potion of Strength"), S("Splash Potion of Strength"), {"strength", 180}},
	{"long_strength", S("Potion of Strength"), S("Splash Potion of Strength"), {"strength", 480}},
	{"strong_strength", S("Potion of Strength"), S("Splash Potion of Strength"), {"strength", 90, 2}},
	{"weakness", S("Potion of Weakness"), S("Splash Potion of Weakness"), {"weakness", 90}},
	{"long_weakness", S("Potion of Weakness"), S("Splash Potion of Weakness"), {"weakness", 240}},
}

local ROMAN = {"", " II", " III", " IV", " V"}
local function clock(s)
	s = math.floor(s + 0.5)
	return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

-- its effects under its name, blue the good ones, red the harmful, as Minecraft lists them
local function tooltip(effects)
	if #effects == 0 then
		return core.colorize("#aaaaaa", S("No Effects"))
	end
	local lines = {}
	for _, e in ipairs(effects) do
		local def = E.registered[e[1]]
		local text = def.description .. ROMAN[e[3] or 1]
		if not def.instant then
			text = text .. " (" .. clock(e[2]) .. ")"
		end
		lines[#lines + 1] = core.colorize(def.bad and "#ff5555" or "#5555ff", text)
	end
	return table.concat(lines, "\n")
end

-- Minecraft's blend of the effects' colours, the water's with none
local function color(effects)
	if #effects == 0 then
		return WATER_COLOR
	end
	local r, g, b = 0, 0, 0
	for _, e in ipairs(effects) do
		local c = tonumber(E.registered[e[1]].color:sub(2), 16)
		r, g, b = r + math.floor(c / 65536), g + math.floor(c / 256) % 256, b + c % 256
	end
	return ("#%02x%02x%02x"):format(r / #effects, g / #effects, b / #effects)
end

function P.image(id, splash)
	return "goodluck_potions_overlay.png^[multiply:" .. P.potions[id].color .. "^goodluck_potions_" ..
		(splash and "splash" or "potion") .. ".png"
end

-- the effects on obj, share of each (a splash's nearness): players get them all, mobs only the instant ones
function P.apply(obj, id, share)
	for _, e in ipairs(P.potions[id].effects) do
		local def = E.registered[e[1]]
		if def.instant then
			E.instant(obj, e[1], e[3] or 1, share)
		elseif obj:is_player() and e[2] * share >= 1 then
			E.apply(obj, e[1], e[2] * share, e[3] or 1)
		end
	end
end

local function creative(user)
	return user and core.is_creative_enabled(user:get_player_name())
end

-- the node's own right-click first (the brewing stand, a chest)
local function node_first(itemstack, user, pointed)
	if pointed and pointed.type == "node" and user then
		local node = core.get_node(pointed.under)
		local def = core.registered_nodes[node.name]
		if def and def.on_rightclick and not user:get_player_control().sneak then
			return def.on_rightclick(pointed.under, node, user, itemstack, pointed) or itemstack
		end
	end
end

local function drink(itemstack, user)
	if not user or not user:is_player() then
		return
	end
	P.apply(user, core.registered_items[itemstack:get_name()]._potion, 1)
	core.sound_play("goodluck_potions_drink", {pos = user:get_pos(), gain = 0.5, max_hear_distance = 16}, true)
	if creative(user) then
		return itemstack
	end
	return ItemStack(BOTTLE)
end

-- thrown 20 degrees above where they look at Minecraft's 0.5 a tick (10 a second) and falling 0.05 a tick each tick
local function throw(itemstack, user)
	if not user or not user:is_player() then
		return
	end
	local dir = user:get_look_dir()
	local pitch = math.asin(dir.y) + math.rad(20)
	local flat = vector.normalize({x = dir.x, y = 0, z = dir.z})
	local vel = vector.add(vector.multiply({x = flat.x * math.cos(pitch), y = math.sin(pitch),
		z = flat.z * math.cos(pitch)}, 10), user:get_velocity())
	local obj = core.add_entity(vector.offset(user:get_pos(), 0, user:get_properties().eye_height - 0.1, 0),
		N .. "thrown", itemstack:get_name())
	if obj then
		obj:set_velocity(vel)
		obj:set_acceleration({x = 0, y = -20, z = 0})
		obj:get_luaentity()._owner = user:get_player_name()
	end
	core.sound_play("goodluck_potions_throw", {pos = user:get_pos(), gain = 0.5, max_hear_distance = 16}, true)
	if not creative(user) then
		itemstack:take_item()
	end
	return itemstack
end

for _, p in ipairs(LIST) do
	local id, effects = p[1], {}
	for i = 4, #p do
		effects[#effects + 1] = p[i]
	end
	P.potions[id] = {name = p[2], splash_name = p[3], effects = effects, color = color(effects)}
	P.order[#P.order + 1] = id
	for _, splash in ipairs({false, true}) do
		local use = splash and throw or drink
		core.register_craftitem(N .. (splash and "splash_" or "") .. id, {
			description = (splash and p[3] or p[2]) .. "\n" .. tooltip(effects),
			short_description = splash and p[3] or p[2],
			inventory_image = P.image(id, splash),
			stack_max = 1,
			groups = {potion = 1, splash_potion = splash and 1 or nil},
			_potion = id,
			_splash = splash,
			on_use = use,
			on_secondary_use = use,
			on_place = function(itemstack, user, pointed)
				return node_first(itemstack, user, pointed) or use(itemstack, user, pointed)
			end,
		})
	end
end

-- a splash potion in flight; it breaks on the first block or creature in its way (not its thrower at first)
local function splash(self, pos, direct)
	local id = core.registered_items[self._item]._potion
	core.sound_play("goodluck_potions_break", {pos = pos, gain = 0.8, max_hear_distance = 24}, true)
	core.add_particlespawner({amount = 30, time = 0.1, pos = pos, vel = {min = vector.new(-2, 0.5, -2),
		max = vector.new(2, 2.5, 2)}, acc = vector.new(0, -6, 0), exptime = {min = 0.4, max = 0.9},
		size = {min = 1, max = 2}, glow = 8,
		texture = "goodluck_effects_particle.png^[multiply:" .. P.potions[id].color})
	-- Minecraft's 8x4x8 around it, the share 1 less the distance to each one's box over 4
	for _, obj in ipairs(core.get_objects_inside_radius(pos, 6)) do
		local ent = obj:get_luaentity()
		if obj:is_player() or ent and ent._cmi_is_mob then
			local p = obj:get_pos()
			local box = obj:get_properties().collisionbox
			local near = {x = math.max(p.x + box[1], math.min(pos.x, p.x + box[4])),
				y = math.max(p.y + box[2], math.min(pos.y, p.y + box[5])),
				z = math.max(p.z + box[3], math.min(pos.z, p.z + box[6]))}
			local d = obj == direct and 0 or vector.distance(pos, near)
			if d < 4 and math.abs(near.y - pos.y) <= 2 + (box[5] - box[2]) and obj ~= self._thrower then
				P.apply(obj, id, 1 - d / 4)
			end
		end
	end
	-- water puts fire out
	if id == "water" then
		for _, f in ipairs(core.find_nodes_in_area(vector.offset(pos, -1, -1, -1), vector.offset(pos, 1, 1, 1),
				{"group:fire"})) do
			core.remove_node(f)
		end
	end
	self.object:remove()
end

core.register_entity(N .. "thrown", {
	initial_properties = {physical = false, pointable = false, visual = "sprite", visual_size = {x = 0.4, y = 0.4},
		textures = {"blank.png"}, static_save = false},
	on_activate = function(self, staticdata)
		local def = core.registered_items[staticdata]
		if not def or not def._potion then
			self.object:remove()
			return
		end
		self._item, self._age = staticdata, 0
		self.object:set_properties({textures = {P.image(def._potion, true)}})
	end,
	on_step = function(self, dtime)
		self._age = self._age + dtime
		local pos = self.object:get_pos()
		local last = self._last or pos
		self._last = pos
		if self._age > 30 then
			self.object:remove()
			return
		end
		for hit in core.raycast(last, pos, true, false) do
			if hit.type == "node" then
				local def = core.registered_nodes[core.get_node(hit.under).name]
				if not def or def.walkable then
					splash(self, hit.intersection_point)
					return
				end
			elseif hit.type == "object" and hit.ref ~= self.object then
				local owner = hit.ref == self._thrower or hit.ref:is_player() and hit.ref:get_player_name() == self._owner
				if not (owner and self._age < 0.25) then
					splash(self, hit.intersection_point, hit.ref)
					return
				end
			end
		end
	end,
})

-- a splash potion thrown by a mob (the witch): it misses its thrower and leaves it out of its splash
function P.launch(from, item, vel, thrower)
	local obj = core.add_entity(from, N .. "thrown", item)
	if obj then
		obj:set_velocity(vel)
		obj:set_acceleration({x = 0, y = -20, z = 0})
		obj:get_luaentity()._thrower = thrower
	end
	core.sound_play("goodluck_potions_throw", {pos = from, gain = 0.5, max_hear_distance = 16}, true)
	return obj
end

-- an empty bottle fills at any water, as in Minecraft (the water stays); elsewhere it is placed as before
local bottle = core.registered_items[BOTTLE]
local function fill(itemstack, user, pointed)
	if not pointed or pointed.type ~= "node" or not user then
		return
	end
	if core.get_item_group(core.get_node(pointed.under).name, "water") == 0 then
		return
	end
	core.sound_play("goodluck_potions_fill", {pos = pointed.under, gain = 0.5, max_hear_distance = 16}, true)
	local water = ItemStack(N .. "water")
	if creative(user) then
		local inv = user:get_inventory()
		if not inv:contains_item("main", water) then
			inv:add_item("main", water)
		end
		return itemstack
	end
	itemstack:take_item()
	if itemstack:is_empty() then
		return water
	end
	local left = user:get_inventory():add_item("main", water)
	if not left:is_empty() then
		core.add_item(user:get_pos(), left)
	end
	return itemstack
end
if bottle then
	local on_place = bottle.on_place
	core.override_item(BOTTLE, {
		liquids_pointable = true,
		on_use = function(itemstack, user, pointed)
			return fill(itemstack, user, pointed)
		end,
		on_place = function(itemstack, user, pointed)
			local filled = fill(itemstack, user, pointed)
			if filled then
				return filled
			end
			return on_place(itemstack, user, pointed)
		end,
	})
end

-- the ingredients this game lacked
core.register_craftitem(N .. "fermented_spider_eye", {
	description = S("Fermented Spider Eye"),
	inventory_image = "goodluck_potions_fermented_spider_eye.png",
})
core.register_craftitem(N .. "glistering_melon_slice", {
	description = S("Glistering Melon Slice"),
	inventory_image = "goodluck_potions_glistering_melon_slice.png",
})
core.register_craftitem(N .. "rabbit_foot", {
	description = S("Rabbit's Foot"),
	inventory_image = "goodluck_potions_rabbit_foot.png",
})
if core.registered_items["goodluck_monsters:spider_eye"] then
	core.register_craft({type = "shapeless", output = N .. "fermented_spider_eye",
		recipe = {"goodluck_monsters:spider_eye", "flowers:mushroom_brown", "goodluck_food:sugar"}})
end
local NUGGET = "goodluck_food:gold_nugget"
core.register_craft({output = N .. "glistering_melon_slice",
	recipe = {{NUGGET, NUGGET, NUGGET}, {NUGGET, "goodluck_food:melon_slice", NUGGET}, {NUGGET, NUGGET, NUGGET}}})
-- one rabbit in ten drops its foot
local bunny = core.registered_entities["mobs_animal:bunny"]
if bunny and bunny.drops then
	bunny.drops[#bunny.drops + 1] = {name = N .. "rabbit_foot", chance = 10, min = 1, max = 1}
end

dofile(core.get_modpath("goodluck_potions") .. "/brewing.lua")
dofile(core.get_modpath("goodluck_potions") .. "/cauldron.lua")
