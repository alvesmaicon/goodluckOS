-- sfinv's tabs as icons, as in Minecraft: in creative, seven places above the panel and seven below it (Java Edition
-- since 1.19.3), the last two of each row at its right edge; in survival only Inventory and Recipes, side by side
-- above it
local HEIGHT, PITCH, WIDTH = 0.92, 1.25, 1.15
local icons = {}

-- icon: an item, or an image when it ends in .png; row 1 is above the panel, row 2 below it; column 1 to 7
function goodluck_craft.set_tab(page, icon, row, col)
	icons[page] = {icon = icon, row = row, col = col}
end

-- the selected tab is taller and covers the panel's edge, so it opens into the panel
local function tab(i, title, icon, selected, x, y, row)
	local name = "goodluck_tab_" .. i
	local bg = selected and "goodluck_craft_tab_selected.png" or "goodluck_craft_tab.png"
	local h = selected and HEIGHT + 0.12 or HEIGHT
	if row == 2 then
		bg = bg .. "^[transformFY"
		y = selected and y - 0.12 or y
	end
	local fs = {
		("style[%s;noclip=true;border=false;bgimg=%s;bgimg_middle=4;padding=2]"):format(name,
			core.formspec_escape(bg)),
	}
	if not selected then
		fs[#fs + 1] = ("style[%s:hovered;bgimg=%s]"):format(name, core.formspec_escape(
			"goodluck_craft_tab.png^[colorize:#ffffff:24" .. (row == 2 and "^[transformFY" or "")))
	end
	if not icon then
		fs[#fs + 1] = ("button[%g,%g;%g,%g;%s;%s]"):format(x, y, WIDTH, h, name, core.formspec_escape(title:sub(1, 1)))
	elseif icon:sub(-4) == ".png" then
		fs[#fs + 1] = ("image_button[%g,%g;%g,%g;%s;%s;]"):format(x, y, WIDTH, h, icon, name)
	else
		fs[#fs + 1] = ("item_image_button[%g,%g;%g,%g;%s;%s;]"):format(x, y, WIDTH, h, icon, name)
	end
	fs[#fs + 1] = ("tooltip[%s;%s]"):format(name, core.formspec_escape(title))
	return table.concat(fs)
end

-- top and bottom: the rows' y, the upper one ending at the panel and the lower one starting there; right: the last
-- place's x
function goodluck_craft.tabs_formspec(context, creative, top, bottom, right)
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
		local row, col = math.floor(places[i] / 10), places[i] % 10
		local x = creative and (col <= 5 and (col - 1) * PITCH or right - (7 - col) * PITCH) or 0.25 + (col - 1) * PITCH
		local def = icons[nav[i]]
		fs[#fs + 1] = tab(i, titles[i] or nav[i], def and def.icon, i == context.nav_idx, x, row == 1 and top or bottom,
			row)
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
