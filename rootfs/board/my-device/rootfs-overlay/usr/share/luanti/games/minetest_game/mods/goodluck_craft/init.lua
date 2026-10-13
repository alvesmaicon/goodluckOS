-- The inventory as in Minecraft: armor and the player on the left, a 2x2 grid on the right, the hotbar at the bottom;
-- the 3x3 grid only at a crafting table, which opens this same inventory (so the Recipes tab works there too)
local S = core.get_translator("goodluck_craft")
local TABLE = "goodluck_craft:crafting_table"
local at_table = {}
local has_armor = core.get_modpath("3d_armor") and armor
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
	local fs = {
		"box[1,0.3;1.9,3.85;#000000]",
		"model[1,0.3;2,3.85;goodluck_player;3d_armor_character.b3d;" ..
			core.formspec_escape(tex.skin) .. "," .. core.formspec_escape(tex.armor) ..
			",blank.png;0,180;false;true;0,79;30]",
	}
	for i, element in ipairs(SLOTS) do
		if inv:get_stack("armor", i):is_empty() then
			local x, y = 0, 0.3 + i - 1
			if element == "shield" then
				x, y = 3.1, 3.3
			end
			fs[#fs + 1] = ("image[%g,%g;1,1;goodluck_craft_slot_%s.png]"):format(x, y, element)
		end
	end
	fs[#fs + 1] = ("list[detached:%s_armor;armor;0,0.3;1,4;0]"):format(name)
	fs[#fs + 1] = ("list[detached:%s_armor;armor;3.1,3.3;1,1;4]"):format(name)
	fs[#fs + 1] = ("listring[detached:%s_armor;armor]listring[current_player;main]"):format(name)
	return table.concat(fs)
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
		"label[4.2,0.1;" .. core.formspec_escape(S("Crafting")) .. "]" ..
		"list[current_player;craft;4.2,0.7;2,2;]" ..
		"image[6.2,1.2;1,1;sfinv_crafting_arrow.png]" ..
		"list[current_player;craftpreview;7,1.2;1,1;]" ..
		"listring[current_player;main]listring[current_player;craft]"
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

-- rows first and the hotbar at the bottom, on every page that shows the inventory
local inventory = default.get_hotbar_bg(0, 8.1) ..
	"list[current_player;main;0,4.95;8,3;8]" ..
	"list[current_player;main;0,8.1;8,1;]"
function sfinv.make_formspec(player, context, content, show_inv, size)
	return table.concat({
		size or "size[8,9.1]",
		sfinv.get_nav_fs(player, context, context.nav_titles, context.nav_idx),
		show_inv and inventory or "",
		content,
	})
end

sfinv.override_page("sfinv:crafting", {
	title = S("Inventory"),
	get = function(self, player, context)
		return sfinv.make_formspec(player, context, crafting_formspec(player), true)
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
