-- The ender chest as Minecraft has it: eight obsidian about an eye of ender; every one of them opens the same chest,
-- each player's own (here 32 slots, as the game's chests), kept with the player. Light 7, the portal's specks about
-- it, the chest's shape in its own texture; broken, it leaves its eight obsidian
local S = core.get_translator("goodluck_end")
local E = goodluck_end
local NAME = "goodluck_end:ender_chest"
local LIST = "goodluck_end:ender_chest"
local FORM = "goodluck_end:ender_chest"
local TOP = -0.16 + 1.05
local open = {}

local function lid_free(pos)
	return not default.chest.chest_lid_obstructed(pos)
end

local function formspec()
	return table.concat({
		"size[8.5,9.1]",
		"padding[0.01,0.01]",
		"no_prepend[]",
		"bgcolor[#080808BB;true]",
		"listcolors[#00000069;#5A5A5A;#141318;#30434C;#FFF]",
		goodluck_craft and goodluck_craft.panel(TOP) or "",
		("label[0.3,%g;%s]"):format(TOP - 0.55, core.formspec_escape(S("Ender Chest"))),
		("container[0.25,%g]"):format(TOP),
		("list[current_player;%s;0,0;8,4;]"):format(LIST),
		goodluck_craft and goodluck_craft.inventory(4.15) or "list[current_player;main;0,4.15;8,4;]",
		"container_end[]",
		"listring[current_player;" .. LIST .. "]listring[current_player;main]",
	})
end

local function close(name)
	local pos = open[name]
	open[name] = nil
	if not pos then
		return
	end
	for _, p in pairs(open) do
		if vector.equals(p, pos) then
			return
		end
	end
	core.after(0.2, function()
		local node = core.get_node(pos)
		if node.name == NAME .. "_open" then
			core.swap_node(pos, {name = NAME, param2 = node.param2})
			core.sound_play("goodluck_end_ender_chest_close", {gain = 0.5, pos = pos, max_hear_distance = 10}, true)
		end
	end)
end

local function on_rightclick(pos, node, clicker)
	if not clicker or not clicker:is_player() then
		return
	end
	local name = clicker:get_player_name()
	close(name)
	clicker:get_inventory():set_size(LIST, 32)
	core.sound_play("goodluck_end_ender_chest_open", {gain = 0.5, pos = pos, max_hear_distance = 10}, true)
	if lid_free(pos) then
		core.swap_node(pos, {name = NAME .. "_open", param2 = node.param2})
	end
	open[name] = pos
	core.after(0.2, function()
		if open[name] and core.get_player_by_name(name) then
			core.show_formspec(name, FORM, formspec())
		end
	end)
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then
		return
	end
	if fields.quit then
		close(player:get_player_name())
	end
	return true
end)
core.register_on_leaveplayer(function(player)
	close(player:get_player_name())
end)

local BOX = {type = "fixed", fixed = {-7 / 16, -1 / 2, -7 / 16, 7 / 16, 6 / 16, 7 / 16}}
local OPEN = {type = "fixed", fixed = {-7 / 16, -1 / 2, -7 / 16, 7 / 16, 2 / 16, 7 / 16}}
local def = {
	description = S("Ender Chest"),
	drawtype = "mesh",
	mesh = "goodluck_models_chest.obj",
	tiles = {"goodluck_end_ender_chest.png"},
	paramtype = "light",
	paramtype2 = "facedir",
	light_source = 7,
	selection_box = BOX,
	collision_box = BOX,
	groups = {cracky = 2},
	is_ground_content = false,
	drop = "default:obsidian 8",
	sounds = default.node_sound_stone_defaults(),
	on_rightclick = on_rightclick,
	on_blast = function() end,
}
core.register_node(NAME, def)
local opened = table.copy(def)
opened.mesh = "goodluck_models_chest_open.obj"
opened.selection_box, opened.collision_box = OPEN, OPEN
opened.groups = {cracky = 2, not_in_creative_inventory = 1}
opened.drop = "default:obsidian 8"
core.register_node(NAME .. "_open", opened)

core.register_craft({output = NAME, recipe = {{"default:obsidian", "default:obsidian", "default:obsidian"},
	{"default:obsidian", "goodluck_end:ender_eye", "default:obsidian"},
	{"default:obsidian", "default:obsidian", "default:obsidian"}}})

-- a lid left open by a player who went away closes
core.register_lbm({
	label = "Close ender chests left open",
	name = "goodluck_end:close_ender_chests",
	nodenames = {NAME .. "_open"},
	run_at_every_load = true,
	action = function(pos, node)
		core.swap_node(pos, {name = NAME, param2 = node.param2})
	end,
})

-- the specks rising about it
core.register_abm({
	label = "ender chest specks",
	nodenames = {NAME, NAME .. "_open"},
	interval = 2,
	chance = 1,
	catch_up = false,
	action = function(pos)
		E.specks(vector.offset(pos, 0, -0.3, 0), 3, 0.4, 0.6)
	end,
})
