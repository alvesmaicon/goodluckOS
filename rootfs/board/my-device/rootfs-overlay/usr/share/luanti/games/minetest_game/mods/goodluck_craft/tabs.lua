-- sfinv's tabs as icons, as in Minecraft: in creative, seven places above the panel and seven below it (Java Edition
-- since 1.19.3), the last two of each row at its right edge; in survival only Inventory and Recipes, side by side
-- above it
local HEIGHT, PITCH, WIDTH = 0.92, 1.25, 1.15
local icons = {}

-- icon: an item, or an image when it ends in .png; row 1 is above the panel, row 2 below it; column 1 to 7
function goodluck_craft.set_tab(page, icon, row, col)
	icons[page] = {icon = icon, row = row, col = col}
end

-- the places at 640x480 in the units of each layout's panel (survival's is the big chest's too), worked out from the
-- engine's legacy geometry: a closed tab ends on the panel's line above it and starts under its line below it, the
-- first place meets the panel's left corner and the last its right one; the open tab is an image as wide as the
-- button and 4 px taller, whose end rows lie over the panel's border (the rows: dev/luanti-art/tabs.py)
local LAYOUT = {
	creative = {top = -0.2555, bottom = 9.3415, left = -0.2768, right = 8.869, bottom_open = 9.2526, w = 1.1923,
		h = 1.0128},
	survival = {top = -0.2221, left = -0.1074, w = 1.1875, h = 1.0125},
}

local function tab(i, title, icon, selected, row, col, creative)
	local l = LAYOUT[creative and "creative" or "survival"]
	local right = l.right and col > 5
	local x = right and l.right - (7 - col) * PITCH or l.left + (col - 1) * PITCH
	local y = row == 1 and l.top or l.bottom
	local name = "goodluck_tab_" .. i
	local closed = row == 1 and "goodluck_craft_tab.png" or "goodluck_craft_tab_bottom.png"
	-- the slicing: the closed tab's empty rows, above it or below
	local middle = row == 1 and "4,6,-4,-4" or "4,4,-4,-8"
	local fs = {}
	if selected then
		local side = col == 1 and "_left" or right and col == 7 and "_right" or ""
		fs[#fs + 1] = ("style_type[image;noclip=true]image[%g,%g;%g,%g;%s;4]style_type[image;noclip=false]"):format(x,
			row == 1 and y or l.bottom_open, l.w, l.h,
			(row == 1 and "goodluck_craft_tab_selected" or "goodluck_craft_tab_bottom_selected") .. side .. ".png")
	end
	-- the slicing shrinks the icon's room, so the selected button gets an invisible background sliced the same way
	fs[#fs + 1] = ("style[%s;noclip=true;border=false;bgimg=%s;bgimg_middle=%s;padding=2]"):format(name,
		core.formspec_escape(closed .. (selected and "^[opacity:0" or "")), middle)
	if not selected then
		fs[#fs + 1] = ("style[%s:hovered;bgimg=%s]"):format(name,
			core.formspec_escape(closed .. "^[colorize:#ffffff:24"))
	end
	if not icon then
		fs[#fs + 1] = ("button[%g,%g;%g,%g;%s;%s]"):format(x, y, WIDTH, HEIGHT, name, core.formspec_escape(title:sub(1, 1)))
	elseif icon:sub(-4) == ".png" then
		fs[#fs + 1] = ("image_button[%g,%g;%g,%g;%s;%s;]"):format(x, y, WIDTH, HEIGHT, icon, name)
	else
		fs[#fs + 1] = ("item_image_button[%g,%g;%g,%g;%s;%s;]"):format(x, y, WIDTH, HEIGHT, icon, name)
	end
	fs[#fs + 1] = ("tooltip[%s;%s]"):format(name, core.formspec_escape(title))
	return table.concat(fs)
end
goodluck_craft.tab = tab

function goodluck_craft.tabs_formspec(context, creative)
	local nav, titles = context.nav or {}, context.nav_titles or {}
	local shown = {}
	for i, page in ipairs(nav) do
		if creative or page:sub(1, 9) ~= "creative:" then
			shown[#shown + 1] = i
		end
	end
	if #shown < 2 then
		return ""
	end
	-- pages without a place take the free ones, left to right, top row first
	local taken, places = {}, {}
	for _, i in ipairs(shown) do
		local def = icons[nav[i]]
		if creative and def and not taken[def.row * 10 + def.col] then
			places[i] = def.row * 10 + def.col
			taken[places[i]] = true
		end
	end
	local fs = {}
	for _, i in ipairs(shown) do
		if not places[i] then
			for p = 11, creative and 27 or 17 do
				if p % 10 >= 1 and p % 10 <= 7 and not taken[p] then
					places[i] = p
					taken[p] = true
					break
				end
			end
		end
		local def = icons[nav[i]]
		fs[#fs + 1] = tab(i, titles[i] or nav[i], def and def.icon, i == context.nav_idx, math.floor(places[i] / 10),
			places[i] % 10, creative)
	end
	return table.concat(fs)
end

-- before sfinv's, which would hand the field to the page
core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "" then
		return
	end
	for field in pairs(fields) do
		local i = tonumber(field:match("^goodluck_tab_(%d+)$"))
		if i then
			local context = sfinv.get_or_create_context(player)
			local page = context.nav and context.nav[i]
			if page and sfinv.pages[page] then
				sfinv.set_page(player, page)
			end
			return true
		end
	end
end)
local callbacks = core.registered_on_player_receive_fields
table.insert(callbacks, 1, table.remove(callbacks))
