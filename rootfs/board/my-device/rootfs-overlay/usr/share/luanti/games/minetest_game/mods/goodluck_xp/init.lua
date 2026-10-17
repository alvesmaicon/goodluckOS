-- Experience as in Minecraft (Java): orbs from ores, mobs and the furnace fly to the player and fill the green bar
-- above the hotbar; dying leaves 7 points a level (100 at most) in the bones, on the ground without bones
goodluck_xp = {}

local LEVEL, POINTS = "goodluck_xp:level", "goodluck_xp:points"
local BAR_W, BAR_Y = 454, -74
local REACH = 7.25
local PICKUP = 1
local ORB_LIFE = 300
-- Minecraft's orb values, largest first: a drop is split into as few orbs as it can
local SIZES = {2477, 1237, 617, 307, 149, 73, 37, 17, 7, 3, 1}

-- points from a level to the next
local function need(level)
	if level >= 31 then
		return 9 * level - 158
	elseif level >= 16 then
		return 5 * level - 38
	end
	return 2 * level + 7
end

-- 0.35 becomes 1 a third of the time
local function roll(x)
	local n = math.floor(x)
	return math.random() < x - n and n + 1 or n
end

local function creative(player)
	return core.is_creative_enabled(player:get_player_name())
end

local huds = {}
-- players whose bar something else takes for now (the horse's jump bar)
local hidden = {}

local function update_hud(player)
	local ids = huds[player:get_player_name()]
	if not ids then
		return
	end
	local meta = player:get_meta()
	local level, points = meta:get_int(LEVEL), meta:get_int(POINTS)
	local hide = creative(player) or hidden[player:get_player_name()]
	local w = math.floor(points / need(level) * (BAR_W - 2) + 0.5)
	player:hud_change(ids.bg, "text", hide and "blank.png" or "goodluck_xp_bar_bg.png")
	player:hud_change(ids.fill, "text", (hide or w == 0) and "blank.png" or
		("[combine:%dx10:0,0=goodluck_xp_bar.png"):format(w + 1))
	local text = (hide or level == 0) and "" or tostring(level)
	for _, id in ipairs(ids.level) do
		player:hud_change(id, "text", text)
	end
end

function goodluck_xp.hide(player, on)
	hidden[player:get_player_name()] = on or nil
	update_hud(player)
end

function goodluck_xp.get_level(player)
	return player:get_meta():get_int(LEVEL)
end

function goodluck_xp.add(player, amount)
	if amount <= 0 or creative(player) then
		return
	end
	local meta = player:get_meta()
	local level, points = meta:get_int(LEVEL), meta:get_int(POINTS) + amount
	local before = level
	while points >= need(level) do
		points = points - need(level)
		level = level + 1
	end
	meta:set_int(LEVEL, level)
	meta:set_int(POINTS, points)
	if math.floor(level / 5) > math.floor(before / 5) then
		core.sound_play("goodluck_xp_levelup", {to_player = player:get_player_name(), gain = 0.6}, true)
	end
	update_hud(player)
end

-- as enchanting does: the levels go, the bar keeps how full it was
function goodluck_xp.take_levels(player, n)
	local meta = player:get_meta()
	local level = meta:get_int(LEVEL)
	local after = math.max(0, level - n)
	meta:set_int(LEVEL, after)
	meta:set_int(POINTS, math.floor(meta:get_int(POINTS) / need(level) * need(after)))
	update_hud(player)
end

function goodluck_xp.drop(pos, amount)
	while amount > 0 do
		local value = 1
		for _, size in ipairs(SIZES) do
			if amount >= size then
				value = size
				break
			end
		end
		amount = amount - value
		local obj = core.add_entity(vector.offset(pos, 0, 0.3, 0), "goodluck_xp:orb", tostring(value))
		if obj then
			obj:set_velocity({x = math.random() - 0.5, y = 2 + math.random() * 2, z = math.random() - 0.5})
		end
	end
end

local last_pickup = {}

core.register_entity("goodluck_xp:orb", {
	initial_properties = {
		physical = true,
		collide_with_objects = false,
		collisionbox = {-0.1, -0.1, -0.1, 0.1, 0.1, 0.1},
		visual = "sprite",
		textures = {"goodluck_xp_orb.png"},
		spritediv = {x = 1, y = 4},
		visual_size = {x = 0.25, y = 0.25},
		glow = 12,
		pointable = false,
	},
	_value = 1,
	_age = 0,
	_timer = 0,

	on_activate = function(self, staticdata)
		self._value = tonumber(staticdata) or 1
		-- bigger orbs for bigger values, as in Minecraft
		local size = 0.15 + math.min(self._value, 149) ^ 0.25 * 0.06
		self.object:set_properties({visual_size = {x = size, y = size}})
		self.object:set_sprite({x = 0, y = 0}, 4, 0.15, false)
		self.object:set_acceleration({x = 0, y = -9.81, z = 0})
	end,

	get_staticdata = function(self)
		return tostring(self._value)
	end,

	on_step = function(self, dtime)
		self._age = self._age + dtime
		if self._age > ORB_LIFE then
			self.object:remove()
			return
		end
		self._timer = self._timer + dtime
		if self._timer < 0.1 then
			return
		end
		self._timer = 0
		local pos = self.object:get_pos()
		local target, dist
		for _, player in ipairs(core.get_connected_players()) do
			if player:get_hp() > 0 and not creative(player) then
				local p = vector.offset(player:get_pos(), 0, 0.5, 0)
				local d = vector.distance(pos, p)
				if d < REACH and (not dist or d < dist) then
					target, dist = player, d
				end
			end
		end
		if not target then
			self.object:set_acceleration({x = 0, y = -9.81, z = 0})
			local v = self.object:get_velocity()
			self.object:set_velocity({x = v.x * 0.8, y = v.y, z = v.z * 0.8})
			return
		end
		local name = target:get_player_name()
		local now = core.get_us_time()
		if dist < PICKUP and now - (last_pickup[name] or 0) > 100000 then
			last_pickup[name] = now
			core.sound_play("goodluck_xp_orb", {to_player = name, gain = 0.25,
				pitch = 0.55 + math.random() * 0.7}, true)
			goodluck_xp.add(target, self._value)
			self.object:remove()
			return
		end
		-- to the waist, below the camera; faster the closer it gets, a little gravity left so it rolls on the ground
		local dir = vector.direction(pos, vector.offset(target:get_pos(), 0, 0.5, 0))
		self.object:set_acceleration({x = 0, y = -2, z = 0})
		self.object:set_velocity(vector.multiply(dir, 2 + (REACH - dist) * 1.2))
	end,
})

core.register_on_joinplayer(function(player)
	local function bar()
		return player:hud_add({type = "image", position = {x = 0.5, y = 1}, alignment = {x = 1, y = 1},
			scale = {x = 1, y = 1}, offset = {x = -BAR_W / 2, y = BAR_Y}, text = "blank.png"})
	end
	local ids = {bg = bar(), level = {}}
	ids.fill = bar()
	-- the level in green with a black outline, on the bar's top edge between the hearts and the hunger
	for _, o in ipairs({{-2, 0}, {2, 0}, {0, -2}, {0, 2}, {0, 0}}) do
		ids.level[#ids.level + 1] = player:hud_add({
			type = "text",
			position = {x = 0.5, y = 1},
			offset = {x = o[1], y = BAR_Y - 8 + o[2]},
			alignment = {x = 0, y = 0},
			size = {x = 2, y = 0},
			number = (o[1] == 0 and o[2] == 0) and 0x80FF20 or 0x000000,
			text = "",
		})
	end
	huds[player:get_player_name()] = ids
	update_hud(player)
end)

core.register_on_leaveplayer(function(player)
	huds[player:get_player_name()] = nil
	hidden[player:get_player_name()] = nil
	last_pickup[player:get_player_name()] = nil
end)

if core.get_modpath("goodluck_creative") then
	goodluck_creative.register_on_change(update_hud)
end

-- ores: Minecraft's coal, lapis, diamond and redstone (mese here); none with silk touch
local ores = {
	["default:stone_with_coal"] = {0, 2},
	["goodluck_lapis:stone_with_lapis"] = {2, 5},
	["default:stone_with_mese"] = {1, 5},
	["default:stone_with_diamond"] = {3, 7},
}

core.register_on_dignode(function(pos, oldnode, digger)
	local range = ores[oldnode.name]
	if not range or not digger or not digger:is_player() or creative(digger) or
			digger:get_wielded_item():get_meta():get_float("is_silk_touch") > 0 then
		return
	end
	goodluck_xp.drop(pos, math.random(range[1], range[2]))
end)

-- the furnace pays when its output is taken: ingots 0.7 (gold 1), food 0.35, the rest 0.1
local function smelt_xp(name)
	if name == "default:gold_ingot" then
		return 1
	elseif name:find("_ingot$") then
		return 0.7
	elseif core.get_item_group(name, "food") > 0 or (core.registered_items[name] or {}).on_use then
		return 0.35
	end
	return 0.1
end

for _, name in ipairs({"default:furnace", "default:furnace_active"}) do
	local take = core.registered_nodes[name].on_metadata_inventory_take
	core.override_item(name, {
		on_metadata_inventory_take = function(pos, listname, index, stack, player)
			if listname == "dst" and player and player:is_player() then
				goodluck_xp.drop(player:get_pos(), roll(stack:get_count() * smelt_xp(stack:get_name())))
			end
			if take then
				return take(pos, listname, index, stack, player)
			end
		end,
	})
end

-- mobs killed by the player: monsters 5, adult animals 1 to 3
if core.get_modpath("mobs") then
	local check_for_death = mobs.mob_class.check_for_death
	function mobs.mob_class.check_for_death(self, cause)
		-- the position first: a mob without a death animation is gone when this returns
		local alive, pos = self.state ~= "die", self.object:get_pos()
		local dead = check_for_death(self, cause)
		local killer = cause and cause.puncher
		if alive and self.state == "die" and not self.child and killer and killer:is_player() then
			local xp = self.type == "monster" and 5 or self.type == "animal" and math.random(1, 3) or 0
			if pos and xp > 0 then
				goodluck_xp.drop(pos, xp)
			end
		end
		return dead
	end
end

-- death: 7 points a level, 100 at most, kept by the bones (bones' own callback ran first) or dropped as orbs
core.register_on_dieplayer(function(player)
	if creative(player) then
		return
	end
	local name = player:get_player_name()
	local meta = player:get_meta()
	local xp = math.min(7 * meta:get_int(LEVEL), 100)
	meta:set_int(LEVEL, 0)
	meta:set_int(POINTS, 0)
	update_hud(player)
	if xp == 0 then
		return
	end
	local pos = vector.round(player:get_pos())
	for _, p in ipairs(core.find_nodes_in_area(vector.offset(pos, -1, -1, -1), vector.offset(pos, 1, 1, 1),
			{"bones:bones"})) do
		local bones = core.get_meta(p)
		if bones:get_string("owner") == name and bones:get_int("goodluck_xp") == 0 then
			bones:set_int("goodluck_xp", xp)
			return
		end
	end
	goodluck_xp.drop(player:get_pos(), xp)
end)

-- bones emptied (or dug) let their experience out where they stood
if core.registered_nodes["bones:bones"] then
	local destruct = core.registered_nodes["bones:bones"].on_destruct
	core.override_item("bones:bones", {
		on_destruct = function(pos)
			local xp = core.get_meta(pos):get_int("goodluck_xp")
			if xp > 0 then
				goodluck_xp.drop(pos, xp)
			end
			if destruct then
				destruct(pos)
			end
		end,
	})
end
