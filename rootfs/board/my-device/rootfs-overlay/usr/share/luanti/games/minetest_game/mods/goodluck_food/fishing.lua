-- Fishing as in Minecraft: the rod casts a bobber; floating on water, it gets a bite after 5 to 30 s and dips with
-- a splash for a second, and reeling in then catches fish (85 %), junk (10 %) or treasure (5 %) and 1 to 6
-- experience, a use of the rod's 64. Reeling in at any other time only brings the bobber back
local S = core.get_translator("goodluck_food")
local ROD = "goodluck_food:fishing_rod"
local BITE = 1.2
-- Minecraft's weights, without what this game lacks
local FISH = {{"goodluck_food:cod", 60}, {"goodluck_food:salmon", 25}, {"goodluck_food:pufferfish", 13}}
local JUNK = {{"flowers:waterlily", 17}, {"goodluck_food:bowl", 10}, {"mobs:leather", 10}, {"3d_armor:boots_leather", 10},
	{"goodluck_monsters:rotten_flesh", 10}, {"vessels:glass_bottle", 10}, {"goodluck_monsters:bone", 10},
	{"default:stick", 5}, {"farming:string", 5}}
local TREASURE = {{"x_bows:bow_wood", 1}, {"mobs:nametag", 1}, {"mobs:saddle", 1}, {ROD, 1}}
local bobbers = {}

local function pick(list)
	local total = 0
	for _, e in ipairs(list) do
		total = total + (core.registered_items[e[1]] and e[2] or 0)
	end
	local r = math.random() * total
	for _, e in ipairs(list) do
		r = r - (core.registered_items[e[1]] and e[2] or 0)
		if r <= 0 and core.registered_items[e[1]] then
			return e[1]
		end
	end
end

local function catch()
	local r = math.random(100)
	return pick(r <= 85 and FISH or r <= 95 and JUNK or TREASURE)
end

local function forget(self)
	if self.owner and bobbers[self.owner] == self then
		bobbers[self.owner] = nil
	end
	self.object:remove()
end

local function wait(self)
	self.biting, self.timer, self.wait = false, 0, math.random(5, 30)
end

core.register_entity("goodluck_food:bobber", {
	initial_properties = {
		physical = true,
		collide_with_objects = false,
		collisionbox = {-0.1, -0.1, -0.1, 0.1, 0.1, 0.1},
		visual = "sprite",
		visual_size = {x = 0.3, y = 0.3},
		textures = {"goodluck_food_bobber.png"},
		pointable = false,
		static_save = false,
	},
	on_step = function(self, dtime, moveresult)
		local player = self.owner and core.get_player_by_name(self.owner)
		local pos = self.object:get_pos()
		if not player or player:get_wielded_item():get_name() ~= ROD or vector.distance(pos, player:get_pos()) > 32 then
			return forget(self)
		end
		if not self.float and core.get_item_group(core.get_node(pos).name, "water") > 0 then
			-- up to the top of the water, and it floats there
			local top = vector.round(pos)
			while core.get_item_group(core.get_node(vector.offset(top, 0, 1, 0)).name, "water") > 0 do
				top.y = top.y + 1
			end
			self.float = top.y + 0.55
			self.object:set_acceleration(vector.zero())
			self.object:set_velocity(vector.zero())
			self.object:set_pos({x = pos.x, y = self.float, z = pos.z})
			wait(self)
		elseif not self.float and moveresult and moveresult.touching_ground then
			self.object:set_acceleration(vector.zero())
			self.object:set_velocity(vector.zero())
		end
		if self.float then
			self.timer = self.timer + dtime
			if not self.biting and self.timer >= self.wait then
				self.biting, self.timer = true, 0
				self.object:set_pos({x = pos.x, y = self.float - 0.2, z = pos.z})
				core.sound_play("default_water_footstep", {pos = pos, gain = 0.8}, true)
				core.add_particlespawner({amount = 12, time = 0.3, pos = pos, radius = 0.3,
					vel = {min = vector.new(-0.5, 1, -0.5), max = vector.new(0.5, 2, 0.5)}, acc = vector.new(0, -6, 0),
					exptime = 0.6, size = 1, texture = "bubble.png"})
			elseif self.biting and self.timer >= BITE then
				self.object:set_pos({x = pos.x, y = self.float, z = pos.z})
				wait(self)
			end
		end
		-- the line, a few dots from the rod to the bobber four times a second
		self.line = (self.line or 0) + dtime
		if self.line >= 0.25 then
			self.line = 0
			-- from the rod's tip, ahead of the eye and to the right
			local yaw = player:get_look_horizontal()
			local from = vector.offset(player:get_pos(), math.cos(yaw) * 0.4, player:get_properties().eye_height - 0.1,
				math.sin(yaw) * 0.4)
			from = vector.add(from, vector.multiply(player:get_look_dir(), 1.2))
			for i = 1, 7 do
				core.add_particle({pos = vector.add(from, vector.multiply(vector.subtract(pos, from), i / 8)),
					expirationtime = 0.3, size = 0.3, texture = "goodluck_food_fishing_line.png"})
			end
		end
	end,
})

local function use(itemstack, user)
	if not user or not user:is_player() then
		return
	end
	local name = user:get_player_name()
	local bobber = bobbers[name]
	if bobber then
		local caught = bobber.biting and catch()
		forget(bobber)
		if caught then
			local left = user:get_inventory():add_item("main", caught)
			if not left:is_empty() then
				core.add_item(user:get_pos(), left)
			end
			if core.global_exists("goodluck_xp") then
				goodluck_xp.drop(user:get_pos(), math.random(1, 6))
			end
			if not core.is_creative_enabled(name) then
				itemstack:add_wear_by_uses(64)
			end
		end
		return itemstack
	end
	local dir = user:get_look_dir()
	local eye = vector.offset(user:get_pos(), 0, user:get_properties().eye_height, 0)
	local obj = core.add_entity(vector.add(eye, vector.multiply(dir, 0.6)), "goodluck_food:bobber")
	if obj then
		obj:set_velocity(vector.add(vector.multiply(dir, 9), vector.new(0, 2, 0)))
		obj:set_acceleration(vector.new(0, -9.81, 0))
		obj:get_luaentity().owner = name
		bobbers[name] = obj:get_luaentity()
		core.sound_play("default_dig_snappy", {pos = eye, gain = 0.4}, true)
	end
	return itemstack
end

core.register_on_leaveplayer(function(player)
	local bobber = bobbers[player:get_player_name()]
	if bobber then
		forget(bobber)
	end
end)

core.register_tool(ROD, {
	description = S("Fishing Rod"),
	inventory_image = "goodluck_food_fishing_rod.png",
	stack_max = 1,
	on_use = use,
	on_secondary_use = use,
	on_place = function(itemstack, placer, pointed_thing)
		local under = pointed_thing.under and core.get_node(pointed_thing.under)
		local def = under and core.registered_nodes[under.name]
		if def and def.on_rightclick and not (placer and placer:get_player_control().sneak) then
			return def.on_rightclick(pointed_thing.under, under, placer, itemstack, pointed_thing) or itemstack
		end
		return use(itemstack, placer)
	end,
})

core.register_craft({
	output = ROD,
	recipe = {
		{"", "", "default:stick"},
		{"", "default:stick", "farming:string"},
		{"default:stick", "", "farming:string"},
	},
})

for _, fish in ipairs({{"cod", S("Raw Cod"), 2, S("Cooked Cod"), 5}, {"salmon", S("Raw Salmon"), 2, S("Cooked Salmon"), 6}}) do
	local raw, cooked = "goodluck_food:" .. fish[1], "goodluck_food:cooked_" .. fish[1]
	core.register_craftitem(raw, {
		description = fish[2],
		inventory_image = "goodluck_food_" .. fish[1] .. ".png",
		groups = {food = 1},
		on_use = core.item_eat(fish[3]),
	})
	core.register_craftitem(cooked, {
		description = fish[4],
		inventory_image = "goodluck_food_cooked_" .. fish[1] .. ".png",
		groups = {food = 1},
		on_use = core.item_eat(fish[5]),
	})
	core.register_craft({type = "cooking", output = cooked, recipe = raw, cooktime = 10})
end

-- the pufferfish isn't cooked: eaten, 1 of hunger, Poison II for a minute and Hunger III for 15 s (Minecraft's nausea
-- has no match here); it makes Water Breathing in the brewing stand
core.register_craftitem("goodluck_food:pufferfish", {
	description = S("Pufferfish"),
	inventory_image = "goodluck_food_pufferfish.png",
	groups = {food = 1},
	on_use = function(itemstack, user, pointed_thing)
		local before = itemstack:get_count()
		local left = core.item_eat(1)(itemstack, user, pointed_thing)
		if left and left:get_count() < before and user and core.global_exists("goodluck_effects") then
			goodluck_effects.apply(user, "poison", 60, 2)
			goodluck_effects.apply(user, "hunger", 15, 3)
		end
		return left
	end,
})
