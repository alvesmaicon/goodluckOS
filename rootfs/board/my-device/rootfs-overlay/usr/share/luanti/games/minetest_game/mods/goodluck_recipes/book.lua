-- The Recipes page: mtg_craftguide's (MIT, LICENSE-mtg_craftguide.txt), its layout and its strings, on
-- goodluck_recipes' lists
local R = goodluck_recipes
local S = core.get_translator("mtg_craftguide")
local esc = core.formspec_escape
local PAGE = "mtg_craftguide:craftguide"
local player_data = {}

local group_names = {
	coal = S("Any coal"),
	sand = S("Any sand"),
	wool = S("Any wool"),
	stick = S("Any stick"),
	vessel = S("Any vessel"),
	wood = S("Any wood planks"),
	stone = S("Any kind of stone block"),

	["color_red,flower"] = S("Any red flower"),
	["color_blue,flower"] = S("Any blue flower"),
	["color_black,flower"] = S("Any black flower"),
	["color_green,flower"] = S("Any green flower"),
	["color_white,flower"] = S("Any white flower"),
	["color_orange,flower"] = S("Any orange flower"),
	["color_violet,flower"] = S("Any violet flower"),
	["color_yellow,flower"] = S("Any yellow flower"),

	["color_red,dye"] = S("Any red dye"),
	["color_blue,dye"] = S("Any blue dye"),
	["color_cyan,dye"] = S("Any cyan dye"),
	["color_grey,dye"] = S("Any grey dye"),
	["color_pink,dye"] = S("Any pink dye"),
	["color_black,dye"] = S("Any black dye"),
	["color_brown,dye"] = S("Any brown dye"),
	["color_green,dye"] = S("Any green dye"),
	["color_white,dye"] = S("Any white dye"),
	["color_orange,dye"] = S("Any orange dye"),
	["color_violet,dye"] = S("Any violet dye"),
	["color_yellow,dye"] = S("Any yellow dye"),
	["color_magenta,dye"] = S("Any magenta dye"),
	["color_dark_grey,dye"] = S("Any dark grey dye"),
	["color_dark_green,dye"] = S("Any dark green dye")
}

local function extract_groups(str)
	if str:sub(1, 6) == "group:" then
		return str:sub(7):split()
	end
	return nil
end

local function coords(i, cols)
	return i % cols, math.floor(i / cols)
end

local function is_fuel(item)
	return core.get_craft_result({method = "fuel", items = {item}}).time > 0
end

local function item_button_fs(fs, x, y, item, element_name, groups)
	table.insert(fs, ("item_image_button[%s,%s;1.05,1.05;%s;%s;%s]")
		:format(x, y, item, element_name, groups and "\n" .. esc(S("G")) or ""))

	local tooltip
	if groups then
		table.sort(groups)
		tooltip = group_names[table.concat(groups, ",")]
		if not tooltip then
			local groupstr = {}
			for _, group in ipairs(groups) do
				table.insert(groupstr, core.colorize("yellow", group))
			end
			groupstr = table.concat(groupstr, ", ")
			tooltip = S("Any item belonging to the group(s): @1", groupstr)
		end
	elseif is_fuel(item) then
		local itemdef = core.registered_items[item:match("%S*")]
		local desc = itemdef and itemdef.description or S("Unknown Item")
		tooltip = desc .. "\n" .. core.colorize("orange", S("Fuel"))
	end
	if tooltip then
		table.insert(fs, ("tooltip[%s;%s]"):format(element_name, esc(tooltip)))
	end
end

local function recipe_fs(fs, data)
	local recipe = data.recipes[data.rnum]
	local width = recipe.width
	local cooktime, shapeless

	if recipe.method == "cooking" then
		cooktime, width = width, 1
	elseif width == 0 then
		shapeless = true
		if #recipe.items == 1 then
			width = 1
		elseif #recipe.items <= 4 then
			width = 2
		else
			width = 3
		end
	end

	table.insert(fs, ("label[5.5,1;%s]"):format(esc(data.show_usages
		and S("Usage @1 of @2", data.rnum, #data.recipes)
		or S("Recipe @1 of @2", data.rnum, #data.recipes))))

	if #data.recipes > 1 then
		table.insert(fs,
			"image_button[5.5,1.6;0.8,0.8;craftguide_prev_icon.png;recipe_prev;]" ..
			"image_button[6.2,1.6;0.8,0.8;craftguide_next_icon.png;recipe_next;]" ..
			"tooltip[recipe_prev;" .. esc(S("Previous recipe")) .. "]" ..
			"tooltip[recipe_next;" .. esc(S("Next recipe")) .. "]")
	end

	local rows = math.ceil(table.maxn(recipe.items) / width)
	if width > 3 or rows > 3 then
		table.insert(fs, ("label[0,1;%s]")
			:format(esc(S("Recipe is too big to be displayed."))))
		return
	end

	local base_x = 3 - width
	local base_y = rows == 1 and 1 or 0

	for i, item in pairs(recipe.items) do
		local x, y = coords(i - 1, width)

		local elem_name = item
		local groups = extract_groups(item)
		if groups then
			item = R.group_item(item)
			elem_name = esc(item .. "." .. table.concat(groups, "+"))
		end
		item_button_fs(fs, base_x + x, base_y + y, item, elem_name, groups)
	end

	if shapeless or recipe.method == "cooking" then
		table.insert(fs, ("image[3.2,0.5;0.5,0.5;craftguide_%s.png]")
			:format(shapeless and "shapeless" or "furnace"))
		local tooltip = shapeless and S("Shapeless") or
			S("Cooking time: @1", core.colorize("yellow", cooktime))
		table.insert(fs, "tooltip[3.2,0.5;0.5,0.5;" .. esc(tooltip) .. "]")
	end
	table.insert(fs, "image[3,1;1,1;sfinv_crafting_arrow.png]")

	item_button_fs(fs, 4, 1, recipe.output, recipe.output:match("%S*"))
end

local function imatch(str, filter)
	return str:lower():find(filter, 1, true) ~= nil
end

local function execute_search(data)
	local filter = data.filter
	if filter == "" then
		data.items = data.base
		return
	end
	data.items = {}

	for _, item in ipairs(data.base) do
		local def = core.registered_items[item]
		local desc = def and core.get_translated_string(data.lang_code, def.description)

		if imatch(item, filter) or desc and imatch(desc, filter) then
			table.insert(data.items, item)
		end
	end
end

local function select_item(player, data)
	local item = data.prev_item
	if item then
		if data.show_usages then
			data.recipes = R.usages(player, item)
		else
			data.recipes = R.recipes(player, item)
		end
		data.rnum = data.recipes and math.min(data.rnum or 1, #data.recipes) or 1
	end
end

-- the lists change as the player learns, or switches the game mode
local function get_data(player)
	local name = player:get_player_name()
	local data = player_data[name]
	if not data then
		data = {filter = "", pagenum = 1, lang_code = core.get_player_information(name).lang_code}
		player_data[name] = data
	end
	local base = R.items(player)
	if data.base ~= base then
		data.base = base
		execute_search(data)
		select_item(player, data)
	end
	return data
end

local function get_formspec(player)
	local data = get_data(player)
	data.pagemax = math.max(1, math.ceil(#data.items / 32))
	data.pagenum = math.min(data.pagenum, data.pagemax)

	local fs = {}
	table.insert(fs,
		"style_type[item_image_button;padding=2]" ..
		"field[0.3,4.2;2.8,1.2;filter;;" .. esc(data.filter) .. "]" ..
		"label[5.8,4.15;" .. core.colorize("yellow", data.pagenum) .. " / " ..
			data.pagemax .. "]" ..
		"image_button[2.63,4.05;0.8,0.8;craftguide_search_icon.png;search;]" ..
		"image_button[3.25,4.05;0.8,0.8;craftguide_clear_icon.png;clear;]" ..
		"image_button[5,4.05;0.8,0.8;craftguide_prev_icon.png;prev;]" ..
		"image_button[7.25,4.05;0.8,0.8;craftguide_next_icon.png;next;]" ..
		"tooltip[search;" .. esc(S("Search")) .. "]" ..
		"tooltip[clear;" .. esc(S("Reset")) .. "]" ..
		"tooltip[prev;" .. esc(S("Previous page")) .. "]" ..
		"tooltip[next;" .. esc(S("Next page")) .. "]" ..
		"field_enter_after_edit[filter;true]" ..
		"field_close_on_enter[filter;false]")

	if #data.items == 0 then
		table.insert(fs, "label[3,2;" .. esc(S("No items to show.")) .. "]")
	else
		local first_item = (data.pagenum - 1) * 32
		for i = first_item, first_item + 31 do
			local item = data.items[i + 1]
			if not item then
				break
			end
			local x, y = coords(i % 32, 8)
			item_button_fs(fs, x, y, item, item)
		end
	end

	table.insert(fs, "container[0,5.6]")
	if data.recipes then
		recipe_fs(fs, data)
	elseif data.prev_item then
		table.insert(fs, ("label[2,1;%s]"):format(esc(data.show_usages
			and S("No usages.") .. "\n" .. S("Click again to show recipes.")
			or S("No recipes.") .. "\n" .. S("Click again to show usages."))))
	end
	table.insert(fs, "container_end[]")

	return table.concat(fs)
end

local function on_receive_fields(player, fields)
	local data = get_data(player)

	if fields.clear then
		data.filter = ""
		data.pagenum = 1
		data.prev_item = nil
		data.recipes = nil
		data.items = data.base
		return true

	elseif (fields.key_enter_field == "filter" or fields.search)
			and fields.filter then
		local new = fields.filter:sub(1, 128) -- truncate to a sane length
				:gsub("[%z\1-\8\11-\31\127]", "") -- strip naughty control characters (keeps \t and \n)
				:lower() -- search is case insensitive
		if data.filter == new then
			return
		end
		data.filter = new
		data.pagenum = 1
		execute_search(data)
		return true

	elseif fields.prev or fields.next then
		if data.pagemax == 1 then
			return
		end
		data.pagenum = data.pagenum + (fields.next and 1 or -1)
		if data.pagenum > data.pagemax then
			data.pagenum = 1
		elseif data.pagenum == 0 then
			data.pagenum = data.pagemax
		end
		return true

	elseif fields.recipe_next or fields.recipe_prev then
		data.rnum = data.rnum + (fields.recipe_next and 1 or -1)
		if data.rnum > #data.recipes then
			data.rnum = 1
		elseif data.rnum == 0 then
			data.rnum = #data.recipes
		end
		return true

	else
		local item
		for field in pairs(fields) do
			if field:find(":") then
				item = field:match("[%w_:]+")
				break
			end
		end
		if not item then
			return
		end

		if item == data.prev_item then
			data.show_usages = not data.show_usages
		else
			data.show_usages = nil
		end
		data.prev_item = item
		data.rnum = 1
		select_item(player, data)
		return true
	end
end

core.register_on_leaveplayer(function(player)
	player_data[player:get_player_name()] = nil
end)

sfinv.override_page(PAGE, {
	get = function(self, player, context)
		return sfinv.make_formspec(player, context, get_formspec(player))
	end,
	on_player_receive_fields = function(self, player, context, fields)
		if on_receive_fields(player, fields) then
			sfinv.set_player_inventory_formspec(player)
		end
	end
})
