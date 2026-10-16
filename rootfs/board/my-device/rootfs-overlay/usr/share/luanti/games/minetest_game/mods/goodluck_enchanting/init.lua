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

-- an enchanted tool for the villages' traders: x_enchanting's draw for a table with this many bookshelves, written in
-- the item as the table writes it (XEnchanting.set_enchanted_tool, without the table)
goodluck_enchanting = {}

local function glint(image)
	return image .. "^((" .. image .. "^[contrast:127:127)^[mask:x_enchanting_glint.png^[opacity:80)"
end

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
	for _, field in ipairs({"inventory_image", "inventory_overlay", "wield_image", "wield_overlay"}) do
		if def[field] and def[field] ~= "" then
			meta:set_string(field, glint(def[field]))
		end
	end
	return stack
end
