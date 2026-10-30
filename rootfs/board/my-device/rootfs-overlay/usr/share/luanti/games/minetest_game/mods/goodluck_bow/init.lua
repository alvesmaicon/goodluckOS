-- x_bows' wooden bow as Minecraft's: L1 (place) held draws it, letting go shoots, and a draw too short to send the
-- arrow keeps it. Arrows come from the inventory (no quiver, no arrow slot, no arrow HUD); one kind, made of flint, a
-- stick and a feather, does 6 at full draw. Drawing walks as slow as sneaking and stops a run. Walking into an arrow
-- stuck in a block picks it up
local S = core.get_translator("goodluck_bow")
local BOW, ARROW = "x_bows:bow_wood", "x_bows:arrow_wood"
-- Minecraft sends nothing under a tenth of its power, (t^2 + 2t) / 3 for t in seconds of a 1 s draw
local MIN_DRAW = 0.15
local SLOW = (tonumber(core.settings:get("movement_speed_crouch")) or 1.35) /
	(tonumber(core.settings:get("movement_speed_walk")) or 4)
local PICKUP_REACH, PICKUP_EVERY = 1.5, 0.2
local sprint = core.get_modpath("goodluck_sprint") and goodluck_sprint
local pop = core.get_modpath("goodluck_item_drop") and "goodluck_item_drop_pop"
local drawing = {}
local pickup_timer = 0

-- the arrow comes from the main inventory, as without sfinv
XBows.fallback_quiver = true
XBowsQuiver.udate_or_create_hud = function() end

local hidden = {"x_bows:quiver", "x_bows:arrow_stone", "x_bows:arrow_bronze", "x_bows:arrow_steel",
	"x_bows:arrow_mese", "x_bows:arrow_diamond"}
for _, name in ipairs(hidden) do
	if core.registered_items[name] then
		core.clear_craft({output = name})
		local groups = table.copy(core.registered_items[name].groups)
		groups.not_in_creative_inventory = 1
		core.override_item(name, {groups = groups})
	end
end
if core.global_exists("sfinv") and sfinv.pages["x_bows:quiver_page"] then
	sfinv.override_page("x_bows:quiver_page", {is_in_nav = function() return false end})
end

core.override_item(ARROW, {description = S("Arrow"), short_description = S("Arrow")})
XBows.registered_arrows[ARROW].custom.tool_capabilities.damage_groups.fleshy = 6
core.clear_craft({output = ARROW})
core.register_craft({
	output = ARROW .. " 4",
	recipe = {
		{"default:flint"},
		{"group:stick"},
		{"group:feather"},
	},
})

local noop = function(itemstack) return itemstack end
for _, name in ipairs({BOW, BOW .. "_semi_charged", BOW .. "_charged"}) do
	-- in the hand as big as any tool (x_bows draws it twice as big)
	local def = {description = S("Bow") .. "\n" .. S("Hold L1 to draw it, let go to shoot"), short_description = S("Bow"),
		wield_scale = {x = 1, y = 1, z = 1}}
	-- a drawn bow keeps L1, so a worn shield stays down (goodluck_shield) and a chest pointed at stays shut
	if name ~= BOW then
		def.on_place, def.on_secondary_use = noop, noop
	end
	core.override_item(name, def)
end

local function set_drawing(player, name, on)
	if (drawing[name] or false) == on then
		return
	end
	drawing[name] = on or nil
	if sprint then
		sprint.stop(player, on, "bow")
	end
	goodluck_physics.set(player, "goodluck_bow", on and {speed = SLOW} or nil)
end

-- as in Minecraft, an arrow shot in creative or with Infinity stays until it goes away by itself
local function pick_up(player)
	local inv = player:get_inventory()
	for obj in core.objects_inside_radius(vector.offset(player:get_pos(), 0, 0.9, 0), PICKUP_REACH) do
		local ent = obj:get_luaentity()
		if ent and ent._is_arrow and ent._attached and ent._attached_to.type == "node" and not ent._dropped and
				not ent._is_creative and not (ent._x_enchanting and ent._x_enchanting.infinity and
				ent._x_enchanting.infinity.value > 0) and inv:room_for_item("main", ent._arrow_name) then
			ent._dropped = true
			inv:add_item("main", ent._arrow_name)
			obj:remove()
			if pop then
				core.sound_play(pop, {to_player = player:get_player_name(), gain = 0.3}, true)
			end
		end
	end
end

core.register_globalstep(function(dtime)
	pickup_timer = pickup_timer + dtime
	local pick = pickup_timer >= PICKUP_EVERY
	if pick then
		pickup_timer = 0
	end
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local stack = player:get_wielded_item()
		local loaded = core.get_item_group(stack:get_name(), "bow_charged") > 0
		local held = player:get_player_control().place
		if loaded and not held then
			local load = tonumber(stack:get_meta():get_string("time_load"))
			if load and (core.get_us_time() - load) / 1e6 < MIN_DRAW then
				XBows:reset_charged_bow(player, true)
			else
				player:set_wielded_item(XBows:shoot(stack, player))
			end
			loaded = false
		end
		set_drawing(player, name, loaded and held and player:get_hp() > 0)
		if pick and player:get_hp() > 0 then
			pick_up(player)
		end
	end
end)

core.register_on_joinplayer(function(player)
	-- x_bows' own arrow slot, now out of sight: what it holds goes to the inventory, and so does a returned arrow
	local inv = player:get_inventory()
	for _, stack in ipairs(inv:get_list("x_bows:arrow_inv") or {}) do
		local left = inv:add_item("main", stack)
		if not left:is_empty() then
			core.add_item(player:get_pos(), left)
		end
	end
	inv:set_size("x_bows:arrow_inv", 0)
end)

core.register_on_leaveplayer(function(player)
	drawing[player:get_player_name()] = nil
end)
