-- Horses as in Minecraft (Java), on mob_horse's horse: herds in grassland and savanna, seven coats and five
-- markings, health, speed and jump of their own; tamed by riding them until they stop throwing you off, steered
-- only with a saddle, horse armor, an inventory with both (sneak + place on the horse, or the inventory while
-- riding), a jump that charges while jump is held, foals from golden apples
local S = core.get_translator("goodluck_horse")
goodluck_horse = {}

local NAME = "mob_horse:horse"
local G = "goodluck_horse_"
local PAGE = "goodluck_horse:horse"
-- Minecraft's horses run 4.9 to 14.6 nodes a second; the handheld can't load terrain that fast
local MIN_SPEED = 5
local MAX_SPEED = tonumber(core.settings:get("goodluck_horse_max_speed")) or 9
local MAX_JUMP = 5.3
local GRAVITY = 10
local has_xp = core.get_modpath("goodluck_xp") and goodluck_xp

local COATS = {"white", "creamy", "chestnut", "brown", "black", "gray", "darkbrown"}
local MARKINGS = {"", "white", "whitefield", "whitedots", "blackdots"}

-- armor points as in Minecraft; each one takes 4 % off the damage
local ARMORS = {
	["goodluck_horse:armor_leather"] = 3,
	["goodluck_horse:armor_iron"] = 5,
	["goodluck_horse:armor_gold"] = 7,
	["goodluck_horse:armor_diamond"] = 11,
}
local LEATHER = "#a0653a"

-- Minecraft's horse food: health, seconds off a foal's growing, temper; a golden apple starts breeding
local FOOD = {
	["farming:wheat"] = {heal = 2, grow = 20, temper = 3},
	["default:apple"] = {heal = 3, grow = 60, temper = 3},
	["goodluck_horse:golden_apple"] = {heal = 10, grow = 240, temper = 10, love = true},
	["farming:straw"] = {heal = 20, grow = 180},
}

local function rand3()
	return (math.random() + math.random() + math.random()) / 3
end

-- Minecraft's jump height in nodes for a jump strength from 0.4 to 1.0
local function jump_height(s)
	return math.min(-0.1817584952 * s ^ 3 + 3.689713992 * s ^ 2 + 2.128599134 * s - 0.343930367, MAX_JUMP)
end

local function texture(self)
	local t = G .. (self._coat or "brown") .. ".png"
	if self._marking and self._marking ~= "" then
		t = t .. "^" .. G .. "markings_" .. self._marking .. ".png"
	end
	local armor = self._armor and ItemStack(self._armor)
	if armor and armor:get_name() == "goodluck_horse:armor_leather" then
		local color = armor:get_meta():get_string("color")
		t = t .. "^(" .. G .. "armor_leather.png^[multiply:" .. (color ~= "" and color or LEATHER) .. ")^" ..
			G .. "armor_leather_trim.png"
	elseif armor then
		t = t .. "^" .. G .. "armor_" .. armor:get_name():match("armor_(%a+)$") .. ".png"
	end
	if self._saddle then
		t = t .. "^" .. G .. "saddle.png"
	end
	return t
end

local function update_look(self)
	local t = texture(self)
	-- the model has two buffers: one texture each
	self.base_texture = {t, t}
	self.object:set_properties({textures = self.base_texture})
	local points = self._armor and ARMORS[ItemStack(self._armor):get_name()] or 0
	self.armor = 100 - 4 * points
	self.object:set_armor_groups({fleshy = self.armor})
end

-- a new horse: Minecraft's random stats
local function roll(self, coat)
	self._coat = coat or COATS[math.random(#COATS)]
	self._marking = MARKINGS[math.random(#MARKINGS)]
	self._speed = MIN_SPEED + (MAX_SPEED - MIN_SPEED) * rand3()
	self._jump = 0.4 + 0.6 * rand3()
	self._hp = 15 + math.random(0, 8) + math.random(0, 7)
	self._temper = 0
end

local function set_health(self, hp)
	self.hp_max = self._hp
	self.health = math.min(hp, self._hp)
	self.object:set_properties({hp_max = self._hp})
	self.object:set_hp(self.health)
end

-- ---- the inventory: one detached inventory per horse while it is loaded -----------------------------------------
local horses = {}
local next_id = 0

local function inv_name(self)
	return "goodluck_horse_" .. self._id
end

local function by_id(id)
	local self = horses[id]
	if self and self.object and self.object:get_pos() then
		return self
	end
end

local function near(self, player)
	local p = self.object:get_pos()
	return p and vector.distance(p, player:get_pos()) < 6
end

local function sync_from_inv(self, inv)
	local saddle, armor = inv:get_stack("saddle", 1), inv:get_stack("armor", 1)
	self._saddle = not saddle:is_empty() or nil
	self._armor = not armor:is_empty() and armor:to_string() or nil
	update_look(self)
	self.object:set_properties({stepheight = self._saddle and 1.1 or 0.6})
	if self.driver and self.tamed then
		goodluck_horse.show_bar(self.driver, self._saddle)
	end
end

local function get_inv(self)
	local name = inv_name(self)
	local inv = core.get_inventory({type = "detached", name = name})
	if not inv then
		local id = self._id
		inv = core.create_detached_inventory(name, {
			allow_put = function(_, listname, _, stack, player)
				local h = by_id(id)
				if not h or h.child or not near(h, player) or h.owner ~= player:get_player_name() then
					return 0
				end
				if listname == "saddle" and stack:get_name() == "mobs:saddle" then
					return 1
				end
				if listname == "armor" and ARMORS[stack:get_name()] then
					return 1
				end
				return 0
			end,
			allow_take = function(_, _, _, stack, player)
				local h = by_id(id)
				return h and near(h, player) and h.owner == player:get_player_name() and stack:get_count() or 0
			end,
			allow_move = function() return 0 end,
			on_put = function(inv2)
				local h = by_id(id)
				if h then
					sync_from_inv(h, inv2)
					core.sound_play("goodluck_horse_equip", {object = h.object, gain = 0.6}, true)
				end
			end,
			on_take = function(inv2)
				local h = by_id(id)
				if h then sync_from_inv(h, inv2) end
			end,
		})
		inv:set_size("saddle", 1)
		inv:set_size("armor", 1)
	end
	inv:set_stack("saddle", 1, self._saddle and "mobs:saddle" or "")
	inv:set_stack("armor", 1, self._armor or "")
	return inv
end

-- who looks at which horse's page
local viewing = {}

local function horse_formspec(self, player)
	local inv = "detached:" .. inv_name(self)
	local esc = core.formspec_escape
	local title = self._nametag and self._nametag ~= "" and self._nametag or S("Horse")
	local t = texture(self)
	return "label[0,0;" .. esc(title) .. "]" ..
		"model[2.1,0.4;5.6,3.4;horse;mobs_horse.x;" .. esc(t) .. "," .. esc(t) .. ";-8,150;false;true;25,25]" ..
		"image[0.1,0.6;1,1;" .. G .. "slot_saddle.png]" ..
		"list[" .. inv .. ";saddle;0.1,0.6;1,1;]" ..
		"image[0.1,1.7;1,1;" .. G .. "slot_armor.png]" ..
		"list[" .. inv .. ";armor;0.1,1.7;1,1;]" ..
		"listring[" .. inv .. ";saddle]listring[current_player;main]" ..
		"listring[" .. inv .. ";armor]listring[current_player;main]"
end

sfinv.register_page(PAGE, {
	title = S("Horse"),
	is_in_nav = function() return false end,
	get = function(_, player, context)
		local self = by_id(viewing[player:get_player_name()] or -1)
		if not self then
			return sfinv.pages["sfinv:crafting"]:get(player, context)
		end
		get_inv(self)
		-- the rows and the hotbar where the inventory page has them
		local rows = "list[current_player;main;0,4.15;8,3;8]" .. (goodluck_craft and goodluck_craft.hotbar(7.3) or
			"list[current_player;main;0,7.3;8,1;]")
		return sfinv.make_formspec(player, context, rows .. horse_formspec(self, player))
	end,
})

local function show_inventory(self, player, open)
	local name = player:get_player_name()
	viewing[name] = self._id
	sfinv.set_page(player, PAGE)
	if open then
		core.show_formspec(name, "", player:get_inventory_formspec())
	end
end

local function hide_inventory(player)
	local name = player:get_player_name()
	if viewing[name] then
		viewing[name] = nil
		if sfinv.get_page(player) == PAGE then
			sfinv.set_page(player, "sfinv:crafting")
		end
	end
end

-- closing the page opened beside the horse goes back to the inventory; while riding it stays the horse's
core.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "" and fields.quit and sfinv.get_page(player) == PAGE then
		local self = by_id(viewing[player:get_player_name()] or -1)
		if not self or self.driver ~= player then
			hide_inventory(player)
		end
	end
end)

-- ---- riding: the jump bar where the XP bar is ---------------------------------------------------------------------
local BAR_W, BAR_Y = 454, -74
local bars = {}

local function show_bar(player, on)
	if not player:is_player() then return end
	local name = player:get_player_name()
	if on and not bars[name] then
		local function bar(text)
			return player:hud_add({type = "image", position = {x = 0.5, y = 1}, alignment = {x = 1, y = 1},
				scale = {x = 1, y = 1}, offset = {x = -BAR_W / 2, y = BAR_Y}, text = text})
		end
		bars[name] = {bg = bar(G .. "jump_bg.png"), fill = bar("blank.png")}
		if has_xp then goodluck_xp.hide(player, true) end
	elseif not on and bars[name] then
		player:hud_remove(bars[name].bg)
		player:hud_remove(bars[name].fill)
		bars[name] = nil
		if has_xp then goodluck_xp.hide(player, false) end
	end
end

goodluck_horse.show_bar = show_bar

local function set_bar(player, charge)
	local ids = bars[player:get_player_name()]
	if ids then
		local w = math.floor(charge * (BAR_W - 2) + 0.5)
		player:hud_change(ids.fill, "text", w == 0 and "blank.png" or ("[combine:%dx10:0,0=%sjump.png"):format(w + 1, G))
	end
end

local function hearts(self)
	local p = self.object:get_pos()
	core.add_particlespawner({
		amount = 7, time = 0.2,
		minpos = vector.offset(p, -0.5, 1, -0.5), maxpos = vector.offset(p, 0.5, 1.8, 0.5),
		minvel = {x = 0, y = 0.5, z = 0}, maxvel = {x = 0, y = 1, z = 0},
		minexptime = 1, maxexptime = 1.5, minsize = 2, maxsize = 3, texture = "heart.png",
	})
end

local function mount(self, player)
	self.driver_attach_at = {x = 0, y = 10, z = -2}
	self.driver_eye_offset = {x = 0, y = 13, z = 0}
	self.driver_scale = {x = 0.8, y = 0.8}
	mobs.attach(self, player)
	self._charge = nil
	if not self.tamed then
		-- Minecraft: a few seconds on its back, then it either takes you or throws you off
		self._taming = 1.5 + math.random() * 2
	else
		show_inventory(self, player)
		show_bar(player, self._saddle)
	end
	self:set_animation("stand")
end

local function dismount(self, player, buck)
	show_bar(player, false)
	if viewing[player:get_player_name()] == self._id then
		hide_inventory(player)
	end
	mobs.detach(player)
	self.driver = nil
	self._charge = nil
	if buck then
		self:set_animation("punch")
		core.sound_play("mob_horse_whinny", {object = self.object}, true)
	end
end

-- the taming roll: Minecraft keeps a temper from 0 to 100, five more for each throw
local function try_tame(self)
	local player = self.driver
	if not player then return end
	if math.random(0, 99) < self._temper then
		self.tamed = true
		self.owner = player:get_player_name()
		show_inventory(self, player)
		hearts(self)
		core.sound_play("mob_horse_whinny", {object = self.object, gain = 0.5}, true)
	else
		self._temper = math.min(self._temper + 5, 100)
		dismount(self, player, true)
		player:add_velocity({x = 0, y = 4, z = 0})
	end
end

local function ride(self, dtime)
	local player = self.driver
	local ctrl = player:get_player_control()
	if ctrl.sneak then
		dismount(self, player)
		return
	end
	if self._taming then
		self._taming = self._taming - dtime
		self.object:set_velocity({x = 0, y = self.object:get_velocity().y, z = 0})
		if self._taming <= 0 then
			self._taming = nil
			try_tame(self)
		end
		return
	end
	if not self.tamed or not self._saddle then
		-- on its back without a saddle it won't be steered
		self.object:set_velocity({x = 0, y = self.object:get_velocity().y, z = 0})
		self:set_animation("stand")
		return
	end
	self.max_speed_forward = self._speed
	self.max_speed_reverse = 2
	self.accel = self._speed
	self.jump_height = 0
	-- held jump charges the bar; letting go jumps, higher the longer it was held (full in 0.9 s)
	local v = self.object:get_velocity()
	local grounded = v.y == 0 and self.standing_on ~= "air"
	if ctrl.jump and grounded then
		self._charge = math.min((self._charge or 0) + dtime / 0.9, 1)
		set_bar(player, self._charge)
	elseif self._charge then
		if grounded then
			local power = 0.4 + 0.6 * self._charge
			local h = jump_height(self._jump) * power * power
			self.object:set_velocity({x = v.x, y = math.sqrt(2 * GRAVITY * math.max(h, 1.15)), z = v.z})
		end
		self._charge = nil
		set_bar(player, 0)
	end
	mobs.drive(self, math.abs(self.v or 0) > 6 and "run" or "walk", "stand", false, dtime)
end

-- ---- feeding and breeding -------------------------------------------------------------------------------------------
local function feed(self, player, food, stack)
	local used = false
	if food.heal and self.health < self._hp then
		set_health(self, self.health + food.heal)
		used = true
	end
	if self.child and food.grow then
		self.hornytimer = (self.hornytimer or 0) + food.grow
		used = true
	end
	if not self.tamed and food.temper and self._temper < 100 then
		self._temper = math.min(self._temper + food.temper, 100)
		used = true
	end
	if food.love and self.tamed and not self.child and not self.horny and (self.hornytimer or 0) == 0 then
		self.horny = true
		self.hornytimer = 0
		hearts(self)
		used = true
	end
	if used then
		if not core.is_creative_enabled(player:get_player_name()) then
			stack:take_item()
			player:set_wielded_item(stack)
		end
		core.sound_play("stamina_eat", {object = self.object, gain = 0.6}, true)
	end
	return used
end

-- Minecraft's inheritance: around the parents' mean, spread by how far apart they are
local function inherit(x, y, lo, hi)
	local d = math.abs(x - y) + (hi - lo) * 0.3
	local v = (x + y) / 2 + d * (rand3() - 0.5)
	if v > hi then v = 2 * hi - v elseif v < lo then v = 2 * lo - v end
	return math.max(lo, math.min(hi, v))
end

local function on_breed(self, other)
	local pos = self.object:get_pos()
	local ent = mobs:add_mob(pos, {name = NAME, child = true, owner = self.owner, ignore_count = true})
	if ent then
		local r = math.random(9)
		ent._coat = r <= 4 and self._coat or r <= 8 and other._coat or COATS[math.random(#COATS)]
		r = math.random(5)
		ent._marking = r <= 2 and self._marking or r <= 4 and other._marking or MARKINGS[math.random(#MARKINGS)]
		ent._speed = inherit(self._speed, other._speed, MIN_SPEED, MAX_SPEED)
		ent._jump = inherit(self._jump, other._jump, 0.4, 1)
		ent._hp = math.floor(inherit(self._hp, other._hp, 15, 30) + 0.5)
		ent._temper = 0
		ent.tamed = true
		set_health(ent, ent._hp)
		update_look(ent)
	end
	if has_xp then
		goodluck_xp.drop(pos, math.random(1, 7))
	end
	return false
end

-- ---- the horse: mob_horse's model, sounds and animations with this behaviour ---------------------------------------
local def = core.registered_entities[NAME]
def.passive = true
def.attack_monsters = false
def.attack_type = nil
def.runaway = false
def.fall_damage = false
def.replace_what = nil
def.follow = {"goodluck_horse:golden_apple"}
def.drops = {{name = "mobs:leather", chance = 1, min = 0, max = 2}}
def.texture_list = {{G .. "brown.png", G .. "brown.png"}}

-- mobs_redo runs after_activate from mob_horse's own table: wrap the activation instead
local activate = def.on_activate
def.on_activate = function(self, staticdata, dtime)
	local r = activate(self, staticdata, dtime)
	if self.object:get_pos() then
		goodluck_horse.after_activate(self)
	end
	return r
end

function goodluck_horse.after_activate(self)
	if not self._coat then
		roll(self)
		set_health(self, self._hp)
	end
	if not self._id then
		next_id = next_id + 1
		self._id = ("%x%04x"):format(os.time(), next_id)
	end
	horses[self._id] = self
	self.hp_max = self._hp
	self.object:set_properties({hp_max = self._hp})
	update_look(self)
	self.object:set_properties({stepheight = self._saddle and 1.1 or 0.6})
end

def.on_deactivate = function(self)
	if self.driver then
		dismount(self, self.driver)
	end
	horses[self._id or ""] = nil
	core.remove_detached_inventory("goodluck_horse_" .. (self._id or ""))
end

def.do_custom = function(self, dtime)
	if self.driver then
		if not self.driver:is_player() then
			self.driver = nil
		else
			ride(self, dtime)
			return false
		end
	end
end

def.on_rightclick = function(self, clicker)
	if not clicker or not clicker:is_player() or self.driver then
		return
	end
	local name = clicker:get_player_name()
	local stack = clicker:get_wielded_item()
	local item = stack:get_name()
	local mine = self.tamed and self.owner == name
	if item == "mobs:nametag" then
		mobs:feed_tame(self, clicker, 1, false, false)
		return
	end
	if (item == "mobs:lasso" or item == "mobs:net") and mobs:capture_mob(self, clicker, nil, nil, 100, false, nil) then
		return
	end
	if FOOD[item] and feed(self, clicker, FOOD[item], stack) then
		return
	end
	if mine and clicker:get_player_control().sneak then
		get_inv(self)
		show_inventory(self, clicker, true)
		return
	end
	if mine and not self.child then
		local inv = get_inv(self)
		if item == "mobs:saddle" and not self._saddle then
			inv:set_stack("saddle", 1, stack:take_item())
			clicker:set_wielded_item(stack)
			sync_from_inv(self, inv)
			core.sound_play("goodluck_horse_equip", {object = self.object, gain = 0.6}, true)
			return
		end
		if ARMORS[item] and not self._armor then
			inv:set_stack("armor", 1, stack:take_item())
			clicker:set_wielded_item(stack)
			sync_from_inv(self, inv)
			core.sound_play("goodluck_horse_equip", {object = self.object, gain = 0.6}, true)
			return
		end
	end
	if not self.child and (not self.tamed or mine) then
		mount(self, clicker)
	end
end

def.on_die = function(self, pos)
	if self.driver then
		dismount(self, self.driver)
	end
	if not self.child then
		if self._saddle then core.add_item(pos, "mobs:saddle") end
		if self._armor then core.add_item(pos, self._armor) end
	end
	horses[self._id or ""] = nil
	core.remove_detached_inventory("goodluck_horse_" .. (self._id or ""))
end

def.on_breed = on_breed

core.register_on_leaveplayer(function(player)
	viewing[player:get_player_name()] = nil
	bars[player:get_player_name()] = nil
end)

-- herds of 2 to 6 in grassland and savanna, a foal now and then, one coat each herd
local BIOMES = {grassland = true, savanna = true}

function goodluck_horse.spawn_herd(self, pos)
	local biome = core.get_biome_data(pos)
	if not biome or not BIOMES[core.get_biome_name(biome.biome)] then
		self.object:remove()
		return
	end
	roll(self)
	set_health(self, self._hp)
	update_look(self)
	local grass = core.find_nodes_in_area_under_air(vector.offset(pos, -6, -2, -6), vector.offset(pos, 6, 2, 6),
		{"default:dirt_with_grass", "default:dry_dirt_with_dry_grass"})
	for _ = 1, math.random(1, 5) do
		if #grass == 0 then break end
		local p = vector.offset(table.remove(grass, math.random(#grass)), 0, 1, 0)
		local ent = mobs:add_mob(p, {name = NAME, child = math.random(5) == 1, ignore_count = true})
		if ent then
			roll(ent, self._coat)
			set_health(ent, ent._hp)
			update_look(ent)
		end
	end
end

mobs:spawn({
	name = NAME,
	nodes = {"default:dirt_with_grass", "default:dry_dirt_with_dry_grass"},
	neighbors = {"air"},
	min_light = 10,
	interval = 30,
	chance = 12000,
	active_object_count = 2,
	min_height = 1,
	max_height = 200,
	day_toggle = true,
	on_spawn = function(self, pos) goodluck_horse.spawn_herd(self, pos) end,
})

core.override_item(NAME, {
	description = S("Horse"),
	inventory_image = G .. "egg.png",
})

-- ---- items -----------------------------------------------------------------------------------------------------------
-- mob_horse's horseshoes aren't Minecraft's
for _, metal in ipairs({"steel", "bronze", "mese", "diamond", "crystal"}) do
	local item = "mobs:horseshoe_" .. metal
	if core.registered_items[item] then
		core.clear_craft({output = item})
		core.unregister_item(item)
	end
end

-- Minecraft's saddle (since 1.21.6): three leather over an iron ingot
core.override_item("mobs:saddle", {inventory_image = G .. "saddle_item.png"})
core.clear_craft({output = "mobs:saddle"})
core.register_craft({
	output = "mobs:saddle",
	recipe = {
		{"mobs:leather", "mobs:leather", "mobs:leather"},
		{"", "default:steel_ingot", ""},
	},
})

local armor_names = {
	leather = S("Leather Horse Armor"),
	iron = S("Iron Horse Armor"),
	gold = S("Golden Horse Armor"),
	diamond = S("Diamond Horse Armor"),
}
for _, material in ipairs({"leather", "iron", "gold", "diamond"}) do
	local leather = material == "leather"
	core.register_craftitem("goodluck_horse:armor_" .. material, {
		description = armor_names[material],
		inventory_image = G .. "armor_" .. material .. "_item.png",
		inventory_overlay = leather and G .. "armor_leather_item_overlay.png" or nil,
		color = leather and LEATHER or nil,
		stack_max = 1,
		groups = {horse_armor = ARMORS["goodluck_horse:armor_" .. material]},
	})
end

core.register_craft({
	output = "goodluck_horse:armor_leather",
	recipe = {
		{"mobs:leather", "", "mobs:leather"},
		{"mobs:leather", "mobs:leather", "mobs:leather"},
		{"mobs:leather", "", "mobs:leather"},
	},
})

-- leather horse armor takes a dye's colour, as in Minecraft
local DYES = {
	white = "#f0f0f0", grey = "#9a9a9a", dark_grey = "#545454", black = "#2a2a2a", violet = "#7e3fc0",
	blue = "#3050c8", cyan = "#2aa0aa", dark_green = "#2e6e2c", green = "#5cbc3c", yellow = "#e8d030",
	brown = "#6e4628", orange = "#e4842c", red = "#bc3232", magenta = "#c840bc", pink = "#f094b4",
}
core.register_craft({
	type = "shapeless",
	output = "goodluck_horse:armor_leather",
	recipe = {"goodluck_horse:armor_leather", "group:dye"},
})

local function dyed(itemstack, craft_grid)
	if itemstack:get_name() ~= "goodluck_horse:armor_leather" then
		return
	end
	local color
	for _, s in ipairs(craft_grid) do
		for dye, hex in pairs(DYES) do
			if core.get_item_group(s:get_name(), "color_" .. dye) > 0 then
				color = hex
			end
		end
	end
	if color then
		itemstack:get_meta():set_string("color", color)
	end
	return itemstack
end
core.register_on_craft(function(itemstack, _, craft_grid) return dyed(itemstack, craft_grid) end)
core.register_craft_predict(function(itemstack, _, craft_grid) return dyed(itemstack, craft_grid) end)

-- the golden apple: food for breeding horses, and for the player: four of hunger, then four of health over 5 s
core.register_craftitem("goodluck_horse:golden_apple", {
	description = S("Golden Apple"),
	inventory_image = G .. "golden_apple.png",
	on_use = function(itemstack, user, pointed_thing)
		local result = core.item_eat(4)(itemstack, user, pointed_thing)
		local name = user:get_player_name()
		for i = 1, 4 do
			core.after(i * 1.25, function()
				local p = core.get_player_by_name(name)
				if p and p:get_hp() > 0 then
					p:set_hp(p:get_hp() + 1)
				end
			end)
		end
		return result
	end,
})

core.register_craft({
	output = "goodluck_horse:golden_apple",
	recipe = {
		{"default:gold_ingot", "default:gold_ingot", "default:gold_ingot"},
		{"default:gold_ingot", "default:apple", "default:gold_ingot"},
		{"default:gold_ingot", "default:gold_ingot", "default:gold_ingot"},
	},
})

-- Minecraft's monster rooms: saddles and horse armor
if core.get_modpath("dungeon_loot") then
	dungeon_loot.register({
		{name = "mobs:saddle", chance = 0.28},
		{name = "goodluck_horse:armor_iron", chance = 0.19},
		{name = "goodluck_horse:armor_gold", chance = 0.13},
		{name = "goodluck_horse:armor_diamond", chance = 0.07},
	})
end

function goodluck_horse.is_horse(obj)
	local e = obj and obj:get_luaentity()
	return e and e.name == NAME
end
