-- Survival or Creative as in Minecraft, from world.mt's creative_mode (the main menu asks when the world is made).
-- game.conf keeps the engine in survival, so creative is the player's: minetest_game's creative privilege (its
-- inventory), flying, no damage, no hunger, monsters leave you alone, blocks break at once.
-- no_hunger is stamina's (the level stays put), peaceful_player is mobs_redo's (monsters don't pick you as a target)
local PRIVS = {"creative", "fly", "no_hunger", "peaceful_player"}
local HAND = "goodluck_creative:hand"
local WORLD = core.get_worldpath() .. "/world.mt"
local hunger = core.get_modpath("stamina") and stamina
local damage = core.settings:get_bool("enable_damage")
-- the menu's "Allow changing the game mode": a button in the inventory switches it
local switchable = Settings(WORLD):get_bool("allow_mode_change", false)
local on_change = {}

goodluck_creative = {}

local function creative(player)
	return core.is_creative_enabled(player:get_player_name())
end

local function set_privs(name, on)
	local privs = core.get_player_privs(name)
	for _, priv in ipairs(PRIVS) do
		if core.registered_privileges[priv] then
			privs[priv] = on or nil
		end
	end
	core.set_player_privs(name, privs)
end

-- minetest_game's creative hand, which it only gives when the whole world is creative
local digtime = 42
local caps = {times = {digtime, digtime, digtime}, uses = 0, maxlevel = 256}
core.register_tool(HAND, {
	wield_image = "wieldhand.png",
	wield_scale = {x = 1, y = 1, z = 2.5},
	range = 10,
	groups = {not_in_creative_inventory = 1},
	tool_capabilities = {
		full_punch_interval = 0.5,
		max_drop_level = 3,
		groupcaps = {
			crumbly = caps,
			cracky = caps,
			snappy = caps,
			choppy = caps,
			oddly_breakable_by_hand = caps,
			dig_immediate = {times = {[2] = digtime, [3] = 0}, uses = 0, maxlevel = 256},
		},
		damage_groups = {fleshy = 10},
	},
})

local function apply(player, on)
	local name = player:get_player_name()
	-- immortal: the engine skips fall, drowning and node damage, Lua can't lower HP, and the hearts and breath hide
	local groups = player:get_armor_groups()
	groups.immortal = (on or not damage) and 1 or nil
	player:set_armor_groups(groups)
	-- no_hunger also keeps the level from being filled
	set_privs(name, false)
	if on then
		local props = player:get_properties()
		player:set_hp(props.hp_max)
		player:set_breath(props.breath_max)
		if hunger and hunger.players[name] then
			hunger.update_saturation(player, hunger.VISUAL_MAX)
		end
		set_privs(name, true)
	end
	-- zoom as the engine gives it in a creative world
	player:set_properties({zoom_fov = on and 15 or 0})
	local inv = player:get_inventory()
	inv:set_size("hand", on and 1 or 0)
	if on then
		inv:set_stack("hand", 1, HAND)
	end
	-- the builtin hearts and breath look at immortal again on a HUD flag change
	local flags = player:hud_get_flags()
	player:hud_set_flags({healthbar = not flags.healthbar})
	player:hud_set_flags({healthbar = flags.healthbar})
	-- the creative tabs come and go, as minetest_game does on granting its privilege
	if sfinv then
		if not on and sfinv.get_page(player):sub(1, 9) == "creative:" then
			sfinv.set_page(player, sfinv.get_homepage_name(player))
		else
			sfinv.set_player_inventory_formspec(player)
		end
	end
	for _, func in ipairs(on_change) do
		func(player, on)
	end
end

function goodluck_creative.register_on_change(func)
	on_change[#on_change + 1] = func
end

function goodluck_creative.can_switch()
	return switchable
end

-- the world keeps the mode, and the menu shows it
function goodluck_creative.switch(player)
	local on = not creative(player)
	local world = Settings(WORLD)
	world:set_bool("creative_mode", on)
	world:set_bool("enable_damage", not on)
	world:write()
	core.log("action", player:get_player_name() .. " switches to " .. (on and "creative" or "survival"))
	apply(player, on)
end

core.register_on_joinplayer(function(player)
	local on = Settings(WORLD):get_bool("creative_mode", false)
	apply(player, on)
	-- the inventory opens on the creative tabs, as minetest_game's does in a creative world
	if on and sfinv then
		sfinv.set_page(player, sfinv.get_homepage_name(player))
	end
end)

-- HP can't go down anyway, but 3d_armor would still wear the armor out on every hit
if core.get_modpath("3d_armor") then
	local punch = armor.punch
	armor.punch = function(self, player, ...)
		if not creative(player) then
			return punch(self, player, ...)
		end
	end
end
