-- The inventory as in Minecraft: armor and the player on the left, a 2x2 grid on the right, the hotbar at the bottom;
-- the 3x3 grid only at a crafting table, which opens this same inventory (so the Recipes tab works there too)
local S = core.get_translator("goodluck_craft")
local MODPATH = core.get_modpath("goodluck_craft")
goodluck_craft = {}
dofile(MODPATH .. "/tabs.lua")
local TABLE = "goodluck_craft:crafting_table"
local at_table = {}
local has_armor = core.get_modpath("3d_armor") and armor
local mode = core.get_modpath("goodluck_creative") and goodluck_creative
-- one fixed slot per piece, in this order (3d_armor alone takes any free slot)
local SLOTS = {"head", "torso", "legs", "feet", "shield"}
local SLOT_OF = {}
for i, element in ipairs(SLOTS) do
	SLOT_OF[element] = i
end

-- what is left in the grid goes back to the inventory, or to the ground when it is full
local function give_back(player, stack)
	local left = player:get_inventory():add_item("main", stack)
	if not left:is_empty() then
		core.add_item(player:get_pos(), left)
	end
end

local function set_grid(player, size)
	local inv = player:get_inventory()
	for _, stack in ipairs(inv:get_list("craft") or {}) do
		give_back(player, stack)
	end
	inv:set_list("craft", {})
	inv:set_size("craft", size * size)
	inv:set_width("craft", size)
end

local function armor_slot(stack)
	return SLOT_OF[armor:get_element(stack:get_name()) or ""]
end

local function armor_inv(name)
	return core.get_inventory({type = "detached", name = name .. "_armor"})
end

-- moves each piece to its slot (armor put on by other means lands in the first free one)
local function sort_armor(player)
	local inv = armor_inv(player:get_player_name())
	if not inv then
		return
	end
	local list = inv:get_list("armor")
	local sorted, rest, moved = {}, {}, false
	for i, stack in ipairs(list) do
		if not stack:is_empty() then
			local slot = armor_slot(stack)
			if slot and not sorted[slot] then
				sorted[slot] = stack
				moved = moved or slot ~= i
			else
				rest[#rest + 1] = stack
				moved = moved or i <= #SLOTS
			end
		end
	end
	if not moved then
		return
	end
	for i = 1, #list do
		list[i] = sorted[i] or ItemStack()
	end
	for _, stack in ipairs(rest) do
		local free
		for i = #SLOTS + 1, #list do
			if list[i]:is_empty() then
				free = i
				break
			end
		end
		if free then
			list[free] = stack
		else
			give_back(player, stack)
		end
	end
	inv:set_list("armor", list)
	armor:save_armor_inventory(player)
end

local function lock_armor_slots(name)
	local def = core.detached_inventories[name .. "_armor"]
	if not def or def.goodluck_slots then
		return
	end
	def.goodluck_slots = true
	local allow_put, allow_move = def.allow_put, def.allow_move
	def.allow_put = function(inv, listname, index, stack, player)
		if armor_slot(stack) ~= index then
			return 0
		end
		return allow_put(inv, listname, index, stack, player)
	end
	def.allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
		if armor_slot(inv:get_stack(from_list, from_index)) ~= to_index then
			return 0
		end
		return allow_move(inv, from_list, from_index, to_list, to_index, count, player)
	end
end

local function armor_formspec(player)
	local name = player:get_player_name()
	local inv, tex = armor_inv(name), armor.textures[name]
	if not inv or not tex then
		return ""
	end
	-- the box (in slot spacings) covers two columns by four rows; the model (in slot sizes) is fitted to a view 1.2
	-- times that, a little right of centre as its bounding box is not symmetric, and leaves the mouse to the slots below
	local fs = {
		"box[1,0;1.8,3.867;#000000]",
		"model[0.97,-0.387;2.7,5.354;goodluck_player;3d_armor_character.b3d;" ..
			core.formspec_escape(tex.skin) .. "," .. core.formspec_escape(tex.armor) ..
			",blank.png;0,180;false;false;0,79;30]",
	}
	for i, element in ipairs(SLOTS) do
		if inv:get_stack("armor", i):is_empty() then
			local x, y = 0, i - 1
			if element == "shield" then
				x, y = 3, 3
			end
			fs[#fs + 1] = ("image[%g,%g;1,1;goodluck_craft_slot_%s.png]"):format(x, y, element)
		end
	end
	fs[#fs + 1] = ("list[detached:%s_armor;armor;0,0;1,4;0]"):format(name)
	fs[#fs + 1] = ("list[detached:%s_armor;armor;3,3;1,1;4]"):format(name)
	fs[#fs + 1] = ("listring[detached:%s_armor;armor]listring[current_player;main]"):format(name)
	return table.concat(fs)
end

-- when the world was made with "Allow changing the game mode": a slot-sized toggle under the crafting result, with the
-- icon Minecraft's game mode switcher gives the mode (a grass block for creative, a sword for survival); the mode and
-- what a click does are in its tooltip
local function mode_button(player)
	if not mode or not mode.can_switch() then
		return ""
	end
	local creative = core.is_creative_enabled(player:get_player_name())
	local esc = core.formspec_escape
	return "style[goodluck_mode;border=false;bgimg=goodluck_craft_toggle.png;bgimg_middle=3;padding=3]" ..
		"style[goodluck_mode:hovered;bgimg=goodluck_craft_toggle_hovered.png]" ..
		"style[goodluck_mode:pressed;bgimg=goodluck_craft_toggle_pressed.png]" ..
		("item_image_button[7,3;1,1;%s;goodluck_mode;]"):format(creative and "default:dirt_with_grass" or
			"default:sword_steel") ..
		("tooltip[goodluck_mode;%s\n%s]"):format(esc(creative and S("Game mode: Creative") or S("Game mode: Survival")),
			esc(creative and S("Click for Survival") or S("Click for Creative")))
end

local function crafting_formspec(player)
	if at_table[player:get_player_name()] then
		return "label[0,0;" .. core.formspec_escape(S("Crafting Table")) .. "]" ..
			"list[current_player;craft;1.5,0.6;3,3;]" ..
			"image[4.6,1.6;1,1;sfinv_crafting_arrow.png]" ..
			"list[current_player;craftpreview;5.8,1.6;1,1;]" ..
			"listring[current_player;main]listring[current_player;craft]"
	end
	return (has_armor and armor_formspec(player) or "") ..
		"label[4.2,0;" .. core.formspec_escape(S("Crafting")) .. "]" ..
		"list[current_player;craft;4.2,0.6;2,2;]" ..
		"image[6.2,1.1;1,1;sfinv_crafting_arrow.png]" ..
		"list[current_player;craftpreview;7,1.1;1,1;]" ..
		"listring[current_player;main]listring[current_player;craft]" ..
		mode_button(player)
end

local function leave_table(player)
	local name = player:get_player_name()
	if at_table[name] then
		at_table[name] = nil
		set_grid(player, 2)
		sfinv.set_player_inventory_formspec(player)
	end
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
	sounds = default.node_sound_wood_defaults(),
	on_rightclick = function(pos, node, clicker)
		if not clicker or not clicker:is_player() then
			return
		end
		local name = clicker:get_player_name()
		if not at_table[name] then
			at_table[name] = true
			set_grid(clicker, 3)
		end
		sfinv.set_page(clicker, "sfinv:crafting")
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

-- the table is the inventory formspec shown by the server, which the client keeps until it is shown again
local set_inventory_formspec = sfinv.set_player_inventory_formspec
function sfinv.set_player_inventory_formspec(player, context)
	set_inventory_formspec(player, context)
	local name = player:get_player_name()
	if at_table[name] then
		core.show_formspec(name, "", player:get_inventory_formspec())
	end
end

-- first, as a page (the recipes) may stop the others
core.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "" and fields.quit then
		leave_table(player)
	end
end)
local callbacks = core.registered_on_player_receive_fields
table.insert(callbacks, 1, table.remove(callbacks))

core.register_on_joinplayer(function(player)
	local inv = player:get_inventory()
	if inv:get_size("craft") ~= 4 or inv:get_width("craft") ~= 2 then
		set_grid(player, 2)
	end
	if has_armor then
		lock_armor_slots(player:get_player_name())
		sort_armor(player)
	end
end)

core.register_on_leaveplayer(function(player)
	leave_table(player)
	at_table[player:get_player_name()] = nil
end)
core.register_on_dieplayer(leave_table)

-- rows first and the hotbar at the bottom, which stays in its place on every page
local function inventory(y)
	return ("list[current_player;main;0,%g;8,3;8]"):format(y) .. goodluck_craft.hotbar(y + 3.15)
end
goodluck_craft.inventory = inventory
function goodluck_craft.hotbar(y)
	return default.get_hotbar_bg(0, y) .. ("list[current_player;main;0,%g;8,1;]"):format(y)
end

-- the panel holds a page of the old 8.2 high forms; the tabs are rows of their own above it (and below it, in creative)
-- inside the form, so that its size fits the screen with them and leaves a margin: slots of 39 px in creative and 41
-- in survival at 640x480; the prepend's background would fill the tab rows, so the form draws its own (creative's is
-- wider, for the 9th column, the scrollbar and the trash beside the hotbar); the engine leaves the HUD out under it
local TAB_ROW = 1.05
goodluck_craft.CREATIVE_TOP = -0.17 + TAB_ROW
-- survival's panel stands 12 px from the slots at the sides and the bottom at 640x480 (in its units they take
-- 8.04 x 8.4, the hotbar's bottom in the same place on every page), 11 over the first row, where the tabs sit on
-- it; goodluck_chest's big chest draws it too
local SIDE, EDGE = 0.24, 0.26
function goodluck_craft.panel(top)
	return ("background9[%g,%g;%g,%g;gui_formbg.png;false;10]"):format(0.25 - SIDE, top - EDGE, 8.04 + 2 * SIDE,
		8.4 + 2 * EDGE)
end
function sfinv.make_formspec(player, context, content, show_inv)
	local creative = core.is_creative_enabled(player:get_player_name())
	local w = creative and 9.7 or 8.5
	-- where the page ends: the hotbar's bottom
	local bottom = show_inv and 9.02 or 8.17
	local top = creative and goodluck_craft.CREATIVE_TOP or -0.16 + TAB_ROW
	-- tabs that touch the panel's edge at 640x480: survival's bigger slots round its row 2 px higher
	local tabs_top, tabs_bottom = top - TAB_ROW + (creative and 0 or 0.043), top + bottom + 0.178
	return table.concat({
		("size[%g,%g]"):format(w, creative and 9.6 or 9.1),
		"padding[0.01,0.01]",
		"no_prepend[]",
		"bgcolor[#080808BB;true]",
		"listcolors[#00000069;#5A5A5A;#141318;#30434C;#FFF]",
		-- creative's: as much panel below the hotbar as at the sides and the top
		creative and ("background9[-0.2,%g;%g,%g;gui_formbg.png;false;10]"):format(top - 0.26, w + 0.4, bottom + 0.66)
			or goodluck_craft.panel(top),
		goodluck_craft.tabs_formspec(context, creative, tabs_top, tabs_bottom, 8.65),
		("container[%g,%g]"):format(creative and 0 or 0.25, top),
		show_inv and inventory(4.15) or "",
		context.page == "mtg_craftguide:craftguide" and content:gsub("container%[0,5%.6%]", "container[0,5.2]") or content,
		creative and goodluck_craft.trash and goodluck_craft.trash(8, 7.3) or "",
		"container_end[]",
	})
end

sfinv.override_page("sfinv:crafting", {
	title = S("Inventory"),
	get = function(self, player, context)
		return sfinv.make_formspec(player, context, inventory(4.15) .. crafting_formspec(player))
	end,
	on_player_receive_fields = function(self, player, context, fields)
		if fields.goodluck_mode and mode and mode.can_switch() then
			mode.switch(player)
			return true
		end
	end,
})

if has_armor then
	-- the armor is on the inventory page now
	if sfinv.pages["3d_armor:armor"] then
		sfinv.override_page("3d_armor:armor", {is_in_nav = function() return false end})
	end
	armor:register_on_update(function(player)
		sort_armor(player)
		if sfinv.get_page(player) == "sfinv:crafting" then
			sfinv.set_player_inventory_formspec(player)
		end
	end)
end

goodluck_craft.set_tab("sfinv:crafting", "default:chest", 2, 7)
goodluck_craft.set_tab("mtg_craftguide:craftguide", "default:book", 1, 6)
if core.get_modpath("creative") then
	dofile(MODPATH .. "/creative.lua")
end
