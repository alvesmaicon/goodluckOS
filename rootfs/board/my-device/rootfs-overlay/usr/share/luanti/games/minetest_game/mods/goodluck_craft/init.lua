-- Crafting as in Minecraft: a 2x2 grid in the inventory, the 3x3 one only at a crafting table
local S = core.get_translator("goodluck_craft")
local TABLE = "goodluck_craft:crafting_table"
local at_table = {}

-- what is left in the grid goes back to the inventory, or to the ground when it is full
local function set_grid(player, size)
	local inv = player:get_inventory()
	for _, stack in ipairs(inv:get_list("craft") or {}) do
		local left = inv:add_item("main", stack)
		if not left:is_empty() then
			core.add_item(player:get_pos(), left)
		end
	end
	inv:set_list("craft", {})
	inv:set_size("craft", size * size)
	inv:set_width("craft", size)
end

local function leave_table(player)
	local name = player:get_player_name()
	if at_table[name] then
		at_table[name] = nil
		set_grid(player, 2)
	end
end

local function table_formspec()
	return "size[8,9.1]" ..
		"label[0,0;" .. core.formspec_escape(S("Crafting Table")) .. "]" ..
		"list[current_player;craft;1.75,0.5;3,3;]" ..
		"image[4.75,1.5;1,1;sfinv_crafting_arrow.png]" ..
		"list[current_player;craftpreview;5.75,1.5;1,1;]" ..
		(core.global_exists("default") and default.get_hotbar_bg(0, 5.2) or "") ..
		"list[current_player;main;0,5.2;8,1;]" ..
		"list[current_player;main;0,6.35;8,3;8]" ..
		"listring[current_player;main]" ..
		"listring[current_player;craft]"
end

core.register_node(TABLE, {
	description = S("Crafting Table"),
	tiles = {
		"default_wood.png^goodluck_craft_table_top.png",
		"default_wood.png",
		"default_wood.png^goodluck_craft_table_side.png",
	},
	paramtype2 = "facedir",
	is_ground_content = false,
	groups = {choppy = 2, oddly_breakable_by_hand = 2, flammable = 2},
	sounds = core.global_exists("default") and default.node_sound_wood_defaults() or nil,
	on_rightclick = function(pos, node, clicker)
		if not clicker or not clicker:is_player() then
			return
		end
		local name = clicker:get_player_name()
		if not at_table[name] then
			at_table[name] = true
			set_grid(clicker, 3)
		end
		core.show_formspec(name, TABLE, table_formspec())
	end,
})

core.register_craft({
	output = TABLE,
	recipe = {
		{"group:wood", "group:wood"},
		{"group:wood", "group:wood"},
	},
})

core.register_craft({type = "fuel", recipe = TABLE, burntime = 30})

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= TABLE then
		return
	end
	if fields.quit then
		leave_table(player)
	end
	return true
end)

core.register_on_joinplayer(function(player)
	local inv = player:get_inventory()
	if inv:get_size("craft") ~= 4 or inv:get_width("craft") ~= 2 then
		set_grid(player, 2)
	end
end)

core.register_on_leaveplayer(leave_table)
core.register_on_dieplayer(leave_table)

if core.global_exists("sfinv") then
	sfinv.override_page("sfinv:crafting", {
		get = function(self, player, context)
			return sfinv.make_formspec(player, context, [[
					list[current_player;craft;2.75,1;2,2;]
					image[4.75,1.5;1,1;sfinv_crafting_arrow.png]
					list[current_player;craftpreview;5.75,1.5;1,1;]
					listring[current_player;main]
					listring[current_player;craft]
				]], true)
		end,
	})
end
