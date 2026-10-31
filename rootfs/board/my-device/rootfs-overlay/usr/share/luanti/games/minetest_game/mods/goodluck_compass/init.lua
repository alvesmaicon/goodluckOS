-- Minecraft's compass: its needle points at the world's spawn, whatever bed you sleep in, in the inventory as in the
-- hand; held, it shows where you are. Four steel ingots around redstone dust.
-- The needle is the stack's own image (16 of them), set when it turns
local S = core.get_translator("goodluck_compass")
local ITEM = "goodluck_compass:compass"
local FRAMES, TICK = 16, 0.2
local storage = core.get_mod_storage()
local shown = {}
local timer = 0

goodluck_compass = {}

-- static_spawnpoint when set, else where the world's first player came in (worlds from before this mod: 0, 0, near
-- where the engine puts new players)
function goodluck_compass.spawn()
	local fixed = core.setting_get_pos("static_spawnpoint")
	if fixed then
		return fixed
	end
	local s = storage:get_string("spawn")
	return s ~= "" and core.string_to_pos(s) or vector.new(0, 0, 0)
end

core.register_on_newplayer(function(player)
	if storage:get_string("spawn") == "" then
		storage:set_string("spawn", core.pos_to_string(vector.round(player:get_pos())))
	end
end)

local function image(k)
	return "goodluck_compass_" .. k .. ".png"
end

core.register_craftitem(ITEM, {
	description = S("Compass") .. "\n" .. S("Points to the world's spawn; held, shows where you are"),
	short_description = S("Compass"),
	inventory_image = image(0),
	wield_image = image(0),
	groups = {tool = 1},
})

core.register_craft({
	output = ITEM,
	recipe = {
		{"", "default:steel_ingot", ""},
		{"default:steel_ingot", "goodluck_redstone:redstone", "default:steel_ingot"},
		{"", "default:steel_ingot", ""},
	},
})

-- which of the 16 needles: the spawn's direction against where the player looks, clockwise from straight ahead
local function frame(player)
	local pos, spawn = player:get_pos(), goodluck_compass.spawn()
	local dx, dz = spawn.x - pos.x, spawn.z - pos.z
	if dx * dx + dz * dz < 1 then
		return math.floor(core.get_us_time() / 100000) % FRAMES -- on the spot it spins, as in Minecraft
	end
	local rel = player:get_look_horizontal() - core.dir_to_yaw(vector.new(dx, 0, dz))
	return math.floor(rel / (2 * math.pi) * FRAMES + 0.5) % FRAMES
end

local function set_needles(player, k)
	local inv = player:get_inventory()
	local list = inv:get_list("main")
	for i, stack in ipairs(list) do
		if stack:get_name() == ITEM then
			local meta = stack:get_meta()
			if meta:get_string("inventory_image") ~= image(k) then
				meta:set_string("inventory_image", image(k))
				meta:set_string("wield_image", image(k))
				inv:set_stack("main", i, stack)
			end
		end
	end
end

local function where(player)
	local p = vector.round(player:get_pos())
	return S("Position: @1, @2, @3", p.x, p.y, p.z)
end

local function show_position(player, on)
	local name = player:get_player_name()
	local hud = shown[name]
	if on and not hud then
		-- at the top right, under the system's status bar
		shown[name] = {
			back = player:hud_add({type = "image", text = "goodluck_compass_back.png", position = {x = 1, y = 0},
				offset = {x = -10, y = 50}, alignment = {x = -1, y = 1}, scale = {x = 230, y = 24}, z_index = 10}),
			text = player:hud_add({type = "text", text = where(player), number = 0xFFFFFF,
				position = {x = 1, y = 0}, offset = {x = -125, y = 62}, alignment = {x = 0, y = 0}, z_index = 11}),
		}
	elseif on then
		local text = where(player)
		if text ~= hud.last then
			hud.last = text
			player:hud_change(hud.text, "text", text)
		end
	elseif hud then
		player:hud_remove(hud.back)
		player:hud_remove(hud.text)
		shown[name] = nil
	end
end

core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < TICK then
		return
	end
	timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		if player:get_inventory():contains_item("main", ITEM) then
			set_needles(player, frame(player))
		end
		show_position(player, player:get_wielded_item():get_name() == ITEM)
	end
end)

core.register_on_leaveplayer(function(player)
	shown[player:get_player_name()] = nil
end)
