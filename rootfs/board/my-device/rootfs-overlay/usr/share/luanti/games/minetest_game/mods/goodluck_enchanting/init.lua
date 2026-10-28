-- x_enchanting as in Minecraft: lapis lazuli (not mese) and 1 to 3 levels per enchantment, a slot only with its level
-- or more; Fortune only on ores, 1 to level + 1 times (x_enchanting multiplies stone and dirt too, by the tool's
-- material). Creative pays nothing, as in Minecraft.
local TABLE = "x_enchanting:table"
local def = core.registered_nodes[TABLE]

local function creative(player)
	return core.is_creative_enabled(player:get_player_name())
end

local function can_afford(player, slot, i)
	return creative(player) or goodluck_xp.get_level(player) >= math.max(slot.level, i)
end

local allow_put = def.allow_metadata_inventory_put
local receive_fields = def.on_receive_fields
core.override_item(TABLE, {
	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		if listname == "trade" and stack:get_name() ~= "goodluck_lapis:lapis" then
			return 0
		end
		return allow_put(pos, listname, index, stack, player)
	end,
	on_receive_fields = function(pos, formname, fields, sender)
		local i
		for n = 1, 3 do
			if fields["slot_" .. n] and fields["slot_" .. n] ~= "" then
				i = n
			end
		end
		local context = XEnchanting.form_context[sender:get_player_name()]
		local slot = i and context and context.data and context.data.slots[i]
		if not slot then
			return receive_fields(pos, formname, fields, sender)
		elseif not can_afford(sender, slot, i) then
			return
		end
		local inv = core.get_meta(pos):get_inventory()
		local before = inv:get_stack("item", 1):get_meta():get_int("is_enchanted")
		receive_fields(pos, formname, fields, sender)
		if before == 0 and inv:get_stack("item", 1):get_meta():get_int("is_enchanted") == 1 and
				not creative(sender) then
			goodluck_xp.take_levels(sender, i)
		end
	end,
})

-- a slot the player's level can't pay is shown disabled, its text greyed as in Minecraft
local get_formspec = XEnchanting.get_formspec
function XEnchanting.get_formspec(self, pos, player_name, data)
	local formspec = get_formspec(self, pos, player_name, data)
	local player = core.get_player_by_name(player_name)
	if data and player then
		for i, slot in ipairs(data.slots) do
			if not can_afford(player, slot, i) then
				formspec = formspec:gsub("(image_button%[[^%]]-x_enchanting_image_button)[_disabled]*%.png;slot_" ..
					i .. ";", "style[slot_" .. i .. ";textcolor=#8A7A70]%1_disabled.png;slot_" .. i .. ";")
			end
		end
	end
	return formspec
end

-- Fortune here, before x_enchanting's: the inner handlers see the tool without it
local handle_node_drops = core.handle_node_drops
function core.handle_node_drops(pos, drops, digger)
	local wielded = digger and digger:is_player() and digger:get_wielded_item()
	local fortune = wielded and wielded:get_meta():get_float("is_fortune") or 0
	if fortune <= 0 then
		return handle_node_drops(pos, drops, digger)
	end
	if core.get_node(pos).name:find(":stone_with_") then
		-- Minecraft: nextInt(level + 2) - 1 extra times, never below none (III: 1 to 4 times, 2.2 on average)
		local times = 1 + math.max(0, math.random(0, fortune + 1) - 1)
		local more = {}
		for _, drop in ipairs(drops) do
			local stack = ItemStack(drop)
			stack:set_count(stack:get_count() * times)
			more[#more + 1] = stack
		end
		drops = more
	end
	wielded:get_meta():set_string("is_fortune", "")
	local plain = setmetatable({get_wielded_item = function()
		return wielded
	end}, {__index = function(_, key)
		return function(_, ...)
			return digger[key](digger, ...)
		end
	end})
	return handle_node_drops(pos, drops, plain)
end

-- Minecraft's glint: a purple sheen drifting over an enchanted item. The engine takes an overlay's animation from the
-- item's definition and only its texture from the meta, so every tool gets an animated overlay with no texture, and an
-- enchanted one 16 frames of its image cut by goodluck_enchanting_glint.png (x_enchanting's was still, a lilac tint)
goodluck_enchanting = {}

local FRAMES = 16
local ANIMATION = {type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = 2.4}

local function escape(s)
	return (s:gsub("[\\%^:]", "\\%0"))
end

-- the item tinted purple, 16 times, cut by the sheen: in the hand, where an overlay is drawn or not by its
-- alpha, the streak still shows the item's pixels
local function sheen(image)
	local tinted = escape(image .. "^[resize:16x16^[colorize:#A86CFF:180")
	local parts = {}
	for i = 0, FRAMES - 1 do
		parts[#parts + 1] = "0," .. i * 16 .. "=" .. tinted
	end
	return "[combine:16x" .. FRAMES * 16 .. ":" .. table.concat(parts, ":") .. "^[mask:goodluck_enchanting_glint.png"
end

local function image_of(def, field)
	return type(def[field]) == "string" and def[field] or ""
end

-- the glint of an enchanted stack, for the image its item has now (a bow's changes as it is drawn)
function goodluck_enchanting.glint(stack)
	local def = stack:get_definition()
	local meta = stack:get_meta()
	for _, field in ipairs({"inventory_image", "wield_image"}) do
		if meta:get_string(field):find("x_enchanting_glint.png", 1, true) then
			meta:set_string(field, "")
		end
	end
	local image, wield = image_of(def, "inventory_image"), image_of(def, "wield_image")
	meta:set_string("inventory_overlay", image ~= "" and sheen(image) or "")
	meta:set_string("wield_overlay", wield ~= "" and sheen(wield) or "")
	meta:set_string("goodluck_glint", stack:get_name())
	return stack
end

-- an enchanted stack whose glint is x_enchanting's or was made for another item gets it anew
function goodluck_enchanting.update(stack)
	local meta = stack:get_meta()
	if meta:get_int("is_enchanted") == 1 and meta:get_string("goodluck_glint") ~= stack:get_name() then
		goodluck_enchanting.glint(stack)
		return true
	end
	return false
end

-- one frame of it over the item's image, for a button
function goodluck_enchanting.preview(stack)
	local overlay = stack:get_meta():get_string("inventory_overlay")
	local image = image_of(stack:get_definition(), "inventory_image")
	if stack:get_meta():get_int("is_enchanted") ~= 1 or overlay == "" or image == "" then
		return ""
	end
	return image .. "^(" .. overlay .. "^[verticalframe:" .. FRAMES .. ":3)"
end

core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_tools) do
		local animated = {}
		for _, field in ipairs({"inventory_overlay", "wield_overlay"}) do
			if def[field] == nil or type(def[field]) == "string" then
				animated[field] = {name = def[field] or "", animation = ANIMATION}
			end
		end
		core.override_item(name, animated)
	end
	-- wieldview joins a tool's image and its overlay as text: it gets the animation's still image
	if armor and armor.get_wield_image then
		local get_wield_image = armor.get_wield_image
		armor.get_wield_image = function(item)
			local def = core.registered_tools[ItemStack(item):get_name()]
			if not def or type(def.inventory_overlay) ~= "table" then
				return get_wield_image(item)
			end
			local image, overlay = def.wield_image, def.wield_overlay
			if image == nil or image == "" then
				image, overlay = def.inventory_image, def.inventory_overlay
			end
			if image == nil or image == "" then
				return "blank.png"
			end
			if type(overlay) == "table" then
				overlay = overlay.name
			end
			return overlay and overlay ~= "" and image .. "^" .. overlay or image
		end
	end
end)

-- x_enchanting writes its own glint over the item's images: it is shown none, and ours goes on after
local set_enchanted_tool = XEnchanting.set_enchanted_tool
function XEnchanting.set_enchanted_tool(self, pos, itemstack, level, player_name)
	local name = itemstack:get_name()
	local def = core.registered_tools[name]
	if def then
		core.registered_tools[name] = setmetatable({inventory_image = "", inventory_overlay = "", wield_image = "",
			wield_overlay = ""}, {__index = def})
	end
	local ok, err = pcall(set_enchanted_tool, self, pos, itemstack, level, player_name)
	core.registered_tools[name] = def
	if not ok then
		error(err, 0)
	end
	local inv = core.get_meta(pos):get_inventory()
	local stack = inv:get_stack("item", 1)
	if stack:get_meta():get_int("is_enchanted") == 1 then
		inv:set_stack("item", 1, goodluck_enchanting.glint(stack))
	end
end

-- items enchanted before: in the player's inventory when joining, in the hand (and a bow as it is drawn), in chests
local function update_inventory(inv)
	for listname, list in pairs(inv:get_lists()) do
		local changed = false
		for _, stack in ipairs(list) do
			changed = goodluck_enchanting.update(stack) or changed
		end
		if changed then
			inv:set_list(listname, list)
		end
	end
end

core.register_on_joinplayer(function(player)
	update_inventory(player:get_inventory())
end)

local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 0.2 then
		return
	end
	timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		local stack = player:get_wielded_item()
		if goodluck_enchanting.update(stack) then
			player:set_wielded_item(stack)
		end
	end
end)

core.register_lbm({
	label = "Enchanted items in chests get the moving glint",
	name = "goodluck_enchanting:glint",
	nodenames = {"default:chest", "default:chest_open", "default:chest_locked", "default:chest_locked_open",
		"bones:bones", "x_enchanting:table", "x_enchanting:grindstone", "goodluck_anvil:anvil"},
	run_at_every_load = false,
	action = function(pos)
		update_inventory(core.get_meta(pos):get_inventory())
	end,
})

-- an enchanted tool for the villages' traders: x_enchanting's draw for a table with this many bookshelves, written in
-- the item as the table writes it (XEnchanting.set_enchanted_tool, without the table)
function goodluck_enchanting.enchant(name, bookshelves)
	local stack = ItemStack(name)
	local def = core.registered_tools[stack:get_name()]
	if not def then
		return stack
	end
	-- x_enchanting seeds its draw by the second (os.time): a seed of our own, or every tool of a trader gets the same
	XEnchanting.player_seeds.goodluck_trader = core.get_us_time() % 2147483647
	local data = XEnchanting:get_enchantment_data({get_player_name = function() return "goodluck_trader" end},
		bookshelves, def)
	XEnchanting.player_seeds.goodluck_trader = nil
	math.randomseed(core.get_us_time())
	local slot = data.slots[math.random(1, #data.slots)]
	if not slot or #slot.final_enchantments == 0 then
		return stack
	end
	local meta = stack:get_meta()
	local saved = {}
	for _, e in ipairs(slot.final_enchantments) do
		meta:set_float("is_" .. e.id, e.value)
		saved[e.id] = {value = e.value}
	end
	meta:set_tool_capabilities(slot.tool_cap_data)
	meta:set_string("description", stack:get_description() .. "\n" .. slot.descriptions.enchantments_desc)
	meta:set_string("short_description", core.translate("x_enchanting", "Enchanted") .. " " ..
		stack:get_short_description())
	meta:set_int("is_enchanted", 1)
	meta:set_string("x_enchanting", core.serialize(saved))
	return goodluck_enchanting.glint(stack)
end
