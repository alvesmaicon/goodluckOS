-- Minecraft's shulker box: a chest of 27 between two shulker shells (shell, chest, shell), put on any face and opening
-- away from it, its lid rising half a node and turning as Minecraft's does; it can't open with a block in its way.
-- Broken it keeps what it holds (the item lists its first five), and it takes no shulker box inside. Dyed with any of
-- this game's 15 dyes, the colour Minecraft gives that dye's name (none for light blue, which has no dye here),
-- keeping what it holds
local S = core.get_translator("goodluck_end")
local BOX = "goodluck_end:shulker_box"
local ITEMS = "goodluck_end:items"
-- this game's dyes and Minecraft's colours for them
local COLOURS = {
	{"white", "white", S("White Shulker Box")}, {"grey", "light_gray", S("Light Gray Shulker Box")},
	{"dark_grey", "gray", S("Gray Shulker Box")}, {"black", "black", S("Black Shulker Box")},
	{"violet", "purple", S("Purple Shulker Box")}, {"blue", "blue", S("Blue Shulker Box")},
	{"cyan", "cyan", S("Cyan Shulker Box")}, {"dark_green", "green", S("Green Shulker Box")},
	{"green", "lime", S("Lime Shulker Box")}, {"yellow", "yellow", S("Yellow Shulker Box")},
	{"brown", "brown", S("Brown Shulker Box")}, {"orange", "orange", S("Orange Shulker Box")},
	{"red", "red", S("Red Shulker Box")}, {"magenta", "magenta", S("Magenta Shulker Box")},
	{"pink", "pink", S("Pink Shulker Box")},
}

local viewers = {}
local function closed(name)
	return (name:gsub("_open$", ""))
end

-- what it holds, written into the item, and a tooltip of its first five
local function to_item(name, list)
	local stack = ItemStack(name)
	local saved, lines, n = {}, {}, 0
	for i, s in ipairs(list or {}) do
		if not s:is_empty() then
			saved[i] = s:to_string()
			n = n + 1
			if n <= 5 then
				lines[#lines + 1] = core.colorize("#aaaaaa", ("%s x%d"):format(s:get_short_description(), s:get_count()))
			end
		end
	end
	if n > 0 then
		local meta = stack:get_meta()
		meta:set_string(ITEMS, core.serialize(saved))
		if n > 5 then
			lines[#lines + 1] = core.colorize("#aaaaaa", S("and @1 more...", n - 5))
		end
		meta:set_string("description", core.registered_items[name].description .. "\n" .. table.concat(lines, "\n"))
	end
	return stack
end
local function from_item(stack, inv)
	local saved = core.deserialize(stack:get_meta():get_string(ITEMS)) or {}
	for i, s in pairs(saved) do
		inv:set_stack("main", i, s)
	end
end

local function formspec(pos)
	local loc = ("nodemeta:%d,%d,%d"):format(pos.x, pos.y, pos.z)
	return table.concat({
		"size[9,8.4]",
		"padding[0.01,0.01]",
		"no_prepend[]",
		"bgcolor[#080808BB;true]",
		"listcolors[#00000069;#5A5A5A;#141318;#30434C;#FFF]",
		"background9[-0.2,-0.2;9.4,8.8;gui_formbg.png;false;10]",
		"label[0,-0.1;", core.formspec_escape(S("Shulker Box")), "]",
		"list[", loc, ";main;0,0.4;9,3;]",
		"list[current_player;main;0.5,4.1;8,3;8]",
		default.get_hotbar_bg(0.5, 7.3),
		"list[current_player;main;0.5,7.3;8,1;]",
		"listring[", loc, ";main]listring[current_player;main]",
	})
end

local function lid(pos, open)
	local node = core.get_node(pos)
	local name = closed(node.name) .. (open and "_open" or "")
	if node.name ~= name then
		core.swap_node(pos, {name = name, param2 = node.param2})
	end
end

-- the lid needs the place before it free
local function blocked(pos, node)
	local def = core.registered_nodes[core.get_node(vector.subtract(pos, core.wallmounted_to_dir(node.param2 % 8))).name]
	return not def or def.walkable
end

local function close(name)
	local pos = viewers[name]
	viewers[name] = nil
	if not pos then
		return
	end
	for _, other in pairs(viewers) do
		if vector.equals(other, pos) then
			return
		end
	end
	core.after(0.2, function()
		if core.get_item_group(core.get_node(pos).name, "shulker_box") > 0 then
			lid(pos, false)
			core.sound_play("goodluck_end_shulker_box_close", {pos = pos, gain = 0.5, max_hear_distance = 16}, true)
		end
	end)
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "goodluck_end:shulker_box" and fields.quit then
		close(player:get_player_name())
	end
end)
core.register_on_leaveplayer(function(player)
	close(player:get_player_name())
end)

local def = {
	drawtype = "mesh",
	mesh = "goodluck_models_shulker_box.obj",
	use_texture_alpha = "clip",
	paramtype = "light",
	paramtype2 = "wallmounted",
	groups = {cracky = 2, shulker_box = 1},
	is_ground_content = false,
	stack_max = 1,
	sounds = default.node_sound_stone_defaults(),
	on_construct = function(pos)
		core.get_meta(pos):get_inventory():set_size("main", 27)
	end,
	after_place_node = function(pos, _, itemstack)
		from_item(itemstack, core.get_meta(pos):get_inventory())
	end,
	on_rightclick = function(pos, node, clicker, itemstack)
		if not clicker or not clicker:is_player() or blocked(pos, node) then
			return itemstack
		end
		local name = clicker:get_player_name()
		close(name)
		viewers[name] = pos
		lid(pos, true)
		core.sound_play("goodluck_end_shulker_box_open", {pos = pos, gain = 0.5, max_hear_distance = 16}, true)
		core.after(0.2, function()
			if viewers[name] and core.get_player_by_name(name) then
				core.show_formspec(name, "goodluck_end:shulker_box", formspec(pos))
			end
		end)
		return itemstack
	end,
	allow_metadata_inventory_put = function(pos, _, _, stack, player)
		if core.is_protected(pos, player:get_player_name()) or core.get_item_group(stack:get_name(), "shulker_box") > 0 then
			return 0
		end
		return stack:get_count()
	end,
	allow_metadata_inventory_move = function(pos, _, _, _, _, count, player)
		return core.is_protected(pos, player:get_player_name()) and 0 or count
	end,
	allow_metadata_inventory_take = function(pos, _, _, stack, player)
		return core.is_protected(pos, player:get_player_name()) and 0 or stack:get_count()
	end,
	-- it goes as an item with all it holds
	on_dig = function(pos, node, digger)
		if core.is_protected(pos, digger and digger:get_player_name() or "") then
			return false
		end
		local stack = to_item(closed(node.name), core.get_meta(pos):get_inventory():get_list("main"))
		core.remove_node(pos)
		core.add_item(pos, stack)
		return true
	end,
	on_blast = function(pos)
		local node = core.get_node(pos)
		local stack = to_item(closed(node.name), core.get_meta(pos):get_inventory():get_list("main"))
		core.remove_node(pos)
		core.add_item(pos, stack)
	end,
}

local function register(name, description, texture)
	local d = table.copy(def)
	d.description = description
	d.tiles = {texture}
	core.register_node(name, d)
	local open = table.copy(d)
	open.mesh = "goodluck_models_shulker_box_open.obj"
	open.groups = table.copy(d.groups)
	open.groups.not_in_creative_inventory = 1
	open.drop = name
	core.register_node(name .. "_open", open)
end
register(BOX, S("Shulker Box"), "goodluck_end_shulker.png")
core.register_craft({output = BOX, recipe = {{"goodluck_end:shulker_shell"}, {"default:chest"},
	{"goodluck_end:shulker_shell"}}})
for _, c in ipairs(COLOURS) do
	local name = BOX .. "_" .. c[2]
	register(name, c[3], "goodluck_end_shulker_" .. c[2] .. ".png")
	core.register_craft({type = "shapeless", output = name, recipe = {"group:shulker_box", "dye:" .. c[1]}})
end

-- a dyed box keeps what the one it was made of held
local function dyed(itemstack, grid)
	if core.get_item_group(itemstack:get_name(), "shulker_box") == 0 then
		return
	end
	for _, s in ipairs(grid) do
		if core.get_item_group(s:get_name(), "shulker_box") > 0 then
			local saved = core.deserialize(s:get_meta():get_string(ITEMS)) or {}
			local list = {}
			for i = 1, 27 do
				list[i] = ItemStack(saved[i])
			end
			itemstack:replace(to_item(itemstack:get_name(), list))
		end
	end
	return itemstack
end
core.register_on_craft(function(itemstack, _, grid)
	return dyed(itemstack, grid)
end)
core.register_craft_predict(function(itemstack, _, grid)
	return dyed(itemstack, grid)
end)
