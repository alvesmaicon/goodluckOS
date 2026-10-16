-- With a 3d_armor shield on, L1 (place) held with nothing to place in hand, or sneaking as on Bedrock, raises it after
-- 0.25 s as in Minecraft: hits and arrows from the front half do no damage and wear only the shield
local RAISE_DELAY = 0.25 * 1e6
-- raised, it walks as slow as sneaking, which already is
local SLOW = (tonumber(core.settings:get("movement_speed_crouch")) or 1.35) /
	(tonumber(core.settings:get("movement_speed_walk")) or 4)
-- a mob that hits it is pushed back as mobs_redo's own knockback does
local PUSH, PUSH_UP, PUSH_PAUSE = 5, 2, 0.25
local sprint = core.get_modpath("goodluck_sprint") and goodluck_sprint
local since, raised, slowed, huds = {}, {}, {}, {}

local function shield_slot(name)
	local inv = core.get_inventory({type = "detached", name = name .. "_armor"})
	if not inv then
		return
	end
	for i, stack in ipairs(inv:get_list("armor")) do
		if core.get_item_group(stack:get_name(), "armor_shield") > 0 then
			return i, stack
		end
	end
end

-- as Minecraft's main hand wins: a block or an item with its own place keeps L1, a sword, a tool or the hand don't
local function places(stack)
	local def = stack:get_definition()
	return def.type == "node" or rawget(def, "on_place") ~= nil or rawget(def, "on_secondary_use") ~= nil
end

-- the attacker, or the arrow touching the player, stands in the half the player looks at
local function blocks(player, hitter)
	if not raised[player:get_player_name()] or type(hitter) ~= "userdata" then
		return false
	end
	local from = hitter:get_pos()
	if not from then
		return false
	end
	local d, look = vector.subtract(from, player:get_pos()), player:get_look_dir()
	return d.x * look.x + d.z * look.z > 0
end

local function walk_speed(name)
	local def = armor.def[name]
	return def and def.speed or 1
end

local function set_slowed(player, name, on)
	if (slowed[name] or false) == on then
		return
	end
	slowed[name] = on or nil
	local walk = walk_speed(name)
	if on then
		player:set_physics_override({speed = walk * SLOW})
	-- a bed or another mod may have changed the speed meanwhile: leave theirs
	elseif math.abs(player:get_physics_override().speed - walk * SLOW) < 0.001 then
		player:set_physics_override({speed = walk})
	end
end

local function set_raised(player, name, on)
	if (raised[name] or false) == on then
		return
	end
	raised[name] = on or nil
	if sprint then
		sprint.stop(player, on)
	end
	if on then
		local _, stack = shield_slot(name)
		-- as Minecraft draws it: big, low left of the crosshair, only its top right corner on screen, under the HUD
		huds[name] = player:hud_add({
			type = "image",
			position = {x = 0.5, y = 0.5},
			alignment = {x = -1, y = 1},
			offset = {x = -30, y = 10},
			scale = {x = 24, y = 24},
			z_index = -1,
			text = stack:get_definition().inventory_image,
		})
	elseif huds[name] then
		player:hud_remove(huds[name])
		huds[name] = nil
	end
end

core.register_globalstep(function()
	local now = core.get_us_time()
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local ctrl = player:get_player_control()
		local up = (ctrl.sneak or ctrl.place and not places(player:get_wielded_item())) and player:get_hp() > 0 and
			shield_slot(name) ~= nil
		if not up then
			since[name] = nil
		elseif not since[name] then
			since[name] = now
		end
		set_raised(player, name, up and now - since[name] >= RAISE_DELAY)
		set_slowed(player, name, raised[name] and not ctrl.sneak or false)
	end
end)

-- 3d_armor wears every piece on a punch: a blocked one wears only the shield, below
local armor_punch = armor.punch
armor.punch = function(self, player, hitter, ...)
	if blocks(player, hitter) then
		return
	end
	return armor_punch(self, player, hitter, ...)
end

local knockback = core.calculate_knockback
function core.calculate_knockback(player, hitter, ...)
	if blocks(player, hitter) then
		return 0
	end
	return knockback(player, hitter, ...)
end

core.register_on_punchplayer(function(player, hitter)
	if not blocks(player, hitter) then
		return
	end
	local name = player:get_player_name()
	local i, stack = shield_slot(name)
	local use = stack and core.get_item_group(stack:get_name(), "armor_use") or 0
	-- the shield's on_damage plays its material's sound
	if use > 0 and not core.is_creative_enabled(name) then
		armor:damage(player, i, stack, use)
	end
	local mob = hitter:get_luaentity()
	if mob and mob._cmi_is_mob then
		local dir = vector.direction(player:get_pos(), hitter:get_pos())
		hitter:set_velocity(vector.new(dir.x * PUSH, PUSH_UP, dir.z * PUSH))
		mob.pause_timer = PUSH_PAUSE
	end
	return true
end)

armor:register_on_update(function(player)
	local name = player:get_player_name()
	if slowed[name] then
		player:set_physics_override({speed = walk_speed(name) * SLOW})
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	since[name], raised[name], slowed[name], huds[name] = nil, nil, nil, nil
end)
