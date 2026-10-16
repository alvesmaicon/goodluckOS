-- Minetest Game's binoculars become Minecraft's spyglass, made of an amethyst shard and two copper ingots. With R1
-- (use, the button that eats) held it looks through its one round lens: a narrow view, no item in hand and no run.
-- The item keeps its name, so binoculars already in an inventory are a spyglass now. The engine's zoom key has no
-- button on the handheld
local S = core.get_translator("goodluck_spyglass")
local FOV, FOV_TIME = 10, 0.1
local ITEM = "binoculars:binoculars"
local sprint = core.get_modpath("goodluck_sprint") and goodluck_sprint
local looking = {}

core.override_item(ITEM, {
	description = S("Spyglass") .. "\n" .. S("Hold R1 to look through it"),
	inventory_image = "goodluck_spyglass_item.png",
})

core.clear_craft({output = ITEM})
core.register_craft({
	output = ITEM,
	recipe = {
		{"goodluck_amethyst:amethyst_shard"},
		{"default:copper_ingot"},
		{"default:copper_ingot"},
	},
})

local function set_looking(player, name, on)
	if (looking[name] ~= nil) == on then
		return
	end
	if on then
		if sprint then
			sprint.stop(player, true, "spyglass")
		end
		player:set_fov(FOV, false, FOV_TIME)
		player:hud_set_flags({wielditem = false})
		-- under the hotbar and the bars, as in Minecraft
		looking[name] = player:hud_add({type = "image", text = "goodluck_spyglass_mask.png",
			position = {x = 0.5, y = 0.5}, scale = {x = -100, y = -100}, z_index = -300})
	else
		player:hud_remove(looking[name])
		looking[name] = nil
		player:hud_set_flags({wielditem = true})
		player:set_fov(0, false, FOV_TIME)
		if sprint then
			sprint.stop(player, false, "spyglass")
		end
	end
end

core.register_globalstep(function()
	for _, player in ipairs(core.get_connected_players()) do
		set_looking(player, player:get_player_name(), player:get_player_control().dig and
			player:get_wielded_item():get_name() == ITEM and player:get_hp() > 0)
	end
end)

core.register_on_leaveplayer(function(player)
	looking[player:get_player_name()] = nil
end)
