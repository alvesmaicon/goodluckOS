-- Chorus as Minecraft 26.3 has it: the plant, a stem that joins its neighbours and the end stone under it, breaks
-- (a fruit half the time) when nothing holds it any longer, and the ones it held after it; the flower, which grows on
-- end stone or a stem as ChorusFlowerBlock's random tick does, up or out to the sides, ageing a step with each branch
-- until it dies at 5; the fruit, food that takes whoever eats it up to 8 away to firm ground, and popped in a furnace
local S = core.get_translator("goodluck_end")
local PLANT, FLOWER, DEAD = "goodluck_end:chorus_plant", "goodluck_end:chorus_flower", "goodluck_end:chorus_flower_dead"
local STONE = "goodluck_end:end_stone"
local SIDES = {{x = 1, y = 0, z = 0}, {x = -1, y = 0, z = 0}, {x = 0, y = 0, z = 1}, {x = 0, y = 0, z = -1}}

local function name(pos)
	return core.get_node(pos).name
end
local function air(pos)
	return name(pos) == "air"
end
local function flower(n)
	return n == FLOWER or n == DEAD
end

-- ChorusPlantBlock.canSurvive
local function plant_holds(pos)
	local below = name(vector.offset(pos, 0, -1, 0))
	local both = not air(vector.offset(pos, 0, 1, 0)) and below ~= "air"
	for _, d in ipairs(SIDES) do
		local side = vector.add(pos, d)
		if name(side) == PLANT then
			if both then
				return false
			end
			local under = name(vector.offset(side, 0, -1, 0))
			if under == PLANT or under == STONE then
				return true
			end
		end
	end
	return below == PLANT or below == STONE
end
-- ChorusFlowerBlock.canSurvive: on a stem or end stone, or in the air beside exactly one stem
local function flower_holds(pos)
	local below = name(vector.offset(pos, 0, -1, 0))
	if below == PLANT or below == STONE then
		return true
	elseif below ~= "air" then
		return false
	end
	local stems = 0
	for _, d in ipairs(SIDES) do
		local n = name(vector.add(pos, d))
		if n == PLANT then
			stems = stems + 1
		elseif n ~= "air" then
			return false
		end
	end
	return stems == 1
end

-- what a broken stem or flower held breaks a tick later, as Minecraft's scheduled ticks pass it on
local check
local function shake(pos)
	for _, d in ipairs({{x = 0, y = 1, z = 0}, {x = 0, y = -1, z = 0}, unpack(SIDES)}) do
		local p = vector.add(pos, d)
		local n = name(p)
		if n == PLANT or flower(n) then
			core.after(0.05, check, p)
		end
	end
end
function check(pos)
	local n = name(pos)
	if n == PLANT and not plant_holds(pos) then
		core.remove_node(pos)
		if math.random(0, 1) == 1 then
			core.add_item(pos, "goodluck_end:chorus_fruit")
		end
	elseif flower(n) and not flower_holds(pos) then
		core.remove_node(pos)
	end
end

local CONNECTED = {type = "connected", fixed = {-0.25, -0.25, -0.25, 0.25, 0.25, 0.25},
	connect_top = {-0.25, 0.25, -0.25, 0.25, 0.5, 0.25}, connect_bottom = {-0.25, -0.5, -0.25, 0.25, -0.25, 0.25},
	connect_front = {-0.25, -0.25, -0.5, 0.25, 0.25, -0.25}, connect_back = {-0.25, -0.25, 0.25, 0.25, 0.25, 0.5},
	connect_left = {-0.5, -0.25, -0.25, -0.25, 0.25, 0.25}, connect_right = {0.25, -0.25, -0.25, 0.5, 0.25, 0.25}}
core.register_node(PLANT, {
	description = S("Chorus Plant"),
	drawtype = "nodebox",
	node_box = CONNECTED,
	connects_to = {PLANT, FLOWER, DEAD, STONE},
	tiles = {"goodluck_end_chorus_plant.png"},
	paramtype = "light",
	sunlight_propagates = true,
	groups = {choppy = 3, oddly_breakable_by_hand = 2, not_in_creative_inventory = 1},
	drop = {items = {{items = {"goodluck_end:chorus_fruit"}, rarity = 2}}},
	is_ground_content = false,
	sounds = default.node_sound_wood_defaults(),
	after_destruct = shake,
})
-- a stem takes the end stone under it, and only under it
core.override_item(STONE, {connect_sides = {"top"}})

-- ChorusFlowerBlock's model: a cube with its edges cut, a plate of the flower on every face
local FLOWER_BOX = {type = "fixed", fixed = {{-6 / 16, 6 / 16, -6 / 16, 6 / 16, 0.5, 6 / 16},
	{-6 / 16, -0.5, -6 / 16, 6 / 16, -6 / 16, 6 / 16}, {-0.5, -6 / 16, -6 / 16, -6 / 16, 6 / 16, 6 / 16},
	{6 / 16, -6 / 16, -6 / 16, 0.5, 6 / 16, 6 / 16}, {-6 / 16, -6 / 16, -0.5, 6 / 16, 6 / 16, -6 / 16},
	{-6 / 16, -6 / 16, 6 / 16, 6 / 16, 6 / 16, 0.5}, {-6 / 16, -6 / 16, -6 / 16, 6 / 16, 6 / 16, 6 / 16}}}
local function flower_def(dead)
	return {
		description = S("Chorus Flower"),
		drawtype = "nodebox",
		node_box = FLOWER_BOX,
		tiles = {dead and "goodluck_end_chorus_flower_dead.png" or "goodluck_end_chorus_flower.png"},
		paramtype = "light",
		sunlight_propagates = true,
		groups = {choppy = 3, oddly_breakable_by_hand = 2, not_in_creative_inventory = dead and 1 or nil},
		drop = FLOWER,
		is_ground_content = false,
		sounds = default.node_sound_wood_defaults(),
		after_destruct = shake,
		on_place = function(itemstack, placer, pointed_thing)
			local at = pointed_thing.above
			if pointed_thing.type ~= "node" or not air(at) or not flower_holds(at) then
				return itemstack
			end
			return core.item_place(itemstack, placer, pointed_thing)
		end,
	}
end
core.register_node(FLOWER, flower_def(false))
core.register_node(DEAD, flower_def(true))

local function grown(pos, age)
	core.set_node(pos, {name = FLOWER, param2 = age})
	core.sound_play("goodluck_end_chorus_grow", {pos = pos, gain = 1}, true)
end
local function died(pos)
	core.set_node(pos, {name = DEAD})
	core.sound_play("goodluck_end_chorus_death", {pos = pos, gain = 1}, true)
end
local function sides_open(pos, except)
	for i, d in ipairs(SIDES) do
		if i ~= except and not air(vector.add(pos, d)) then
			return false
		end
	end
	return true
end
local OPPOSITE = {2, 1, 4, 3}

-- ChorusFlowerBlock.randomTick, about every 68 s as Minecraft's random ticks come
core.register_abm({
	label = "chorus flower grows",
	nodenames = {FLOWER},
	interval = 10,
	chance = 7,
	catch_up = false,
	action = function(pos, node)
		local above = vector.offset(pos, 0, 1, 0)
		local age = node.param2
		if not air(above) or age >= 5 then
			return
		end
		local up, ground = false, false
		local below = name(vector.offset(pos, 0, -1, 0))
		if below == STONE then
			up = true
		elseif below == PLANT then
			local height = 1
			for _ = 1, 4 do
				local n = name(vector.offset(pos, 0, -(height + 1), 0))
				if n ~= PLANT then
					ground = n == STONE
					break
				end
				height = height + 1
			end
			up = height < 2 or height <= math.random(0, ground and 4 or 3)
		elseif below == "air" then
			up = true
		end
		if up and sides_open(above) and air(vector.offset(pos, 0, 2, 0)) then
			core.swap_node(pos, {name = PLANT})
			grown(above, age)
		elseif age < 4 then
			local placed = false
			for _ = 1, math.random(0, 3) + (ground and 1 or 0) do
				local d = math.random(1, 4)
				local p = vector.add(pos, SIDES[d])
				if air(p) and air(vector.offset(p, 0, -1, 0)) and sides_open(p, OPPOSITE[d]) then
					grown(p, age + 1)
					placed = true
				end
			end
			if placed then
				core.swap_node(pos, {name = PLANT})
			else
				died(pos)
			end
		else
			died(pos)
		end
	end,
})

-- The fruit: 4 of food that can be eaten full, and up to 16 tries at a spot within 8 across and 8 up or down,
-- dropped to the ground under it, with room and no liquid; a second's wait before the next
local wait = {}
local function room(pos)
	for y = 0, 1 do
		local def = core.registered_nodes[name(vector.offset(pos, 0, y, 0))]
		if not def or def.walkable or def.liquidtype ~= "none" then
			return false
		end
	end
	return true
end
local function teleport(player)
	local from = player:get_pos()
	for _ = 1, 16 do
		local p = vector.new(from.x + (math.random() - 0.5) * 16, math.floor(from.y + 0.5) + math.random(-8, 7),
			from.z + (math.random() - 0.5) * 16)
		local cell = vector.round(p)
		for _ = 1, 64 do
			local def = core.registered_nodes[name(vector.offset(cell, 0, -1, 0))]
			if not def or def.walkable then
				break
			end
			cell.y = cell.y - 1
		end
		local floor = core.registered_nodes[name(vector.offset(cell, 0, -1, 0))]
		if floor and floor.walkable and room(cell) then
			player:set_pos({x = p.x, y = cell.y - 0.5, z = p.z})
			player:add_velocity(vector.multiply(player:get_velocity(), -1))
			core.sound_play("goodluck_end_teleport", {pos = from, gain = 1}, true)
			core.sound_play("goodluck_end_teleport", {pos = p, gain = 1}, true)
			return true
		end
	end
end
core.register_craftitem("goodluck_end:chorus_fruit", {
	description = S("Chorus Fruit"),
	inventory_image = "goodluck_end_chorus_fruit.png",
	on_use = function(itemstack, user, pointed_thing)
		if not user or not user:is_player() then
			return itemstack
		end
		local name_ = user:get_player_name()
		local now = core.get_us_time()
		if wait[name_] and now < wait[name_] then
			return itemstack
		end
		wait[name_] = now + 1000000
		local count = itemstack:get_count()
		itemstack = core.do_item_eat(4, nil, itemstack, user, pointed_thing)
		if itemstack:get_count() == count and not core.is_creative_enabled(name_) then
			itemstack:take_item()
		end
		teleport(user)
		return itemstack
	end,
})
core.register_on_leaveplayer(function(player)
	wait[player:get_player_name()] = nil
end)

core.register_craftitem("goodluck_end:chorus_fruit_popped", {
	description = S("Popped Chorus Fruit"),
	inventory_image = "goodluck_end_chorus_fruit_popped.png",
})
core.register_craft({type = "cooking", output = "goodluck_end:chorus_fruit_popped",
	recipe = "goodluck_end:chorus_fruit"})
