-- The anvil as in Minecraft (Java): it renames an item (1 level) and repairs a tool or armor, with its material (a
-- quarter of the durability and 1 level a unit) or with another of its kind (both durabilities and 12 % more, 2
-- levels), joining their enchantments (x_enchanting's); each use makes the next one dearer, and past 39 levels it is
-- too expensive in Survival. One use in eight chips it, then damages it, then breaks it; it falls like sand
local S = core.get_translator("goodluck_anvil")
local F = core.formspec_escape
goodluck_anvil = {}

local FORM = "goodluck_anvil:anvil"
local WEAR = 65535
local MAX_COST = 39
local MAX_NAME = 50
local USES = "goodluck_anvil:uses"
local NAME = "goodluck_anvil:name"
local STATES = {"goodluck_anvil:anvil", "goodluck_anvil:anvil_chipped", "goodluck_anvil:anvil_damaged"}
local NEXT = {[STATES[1]] = STATES[2], [STATES[2]] = STATES[3]}
local IS_ANVIL = {[STATES[1]] = true, [STATES[2]] = true, [STATES[3]] = true}
local has_xp = core.get_modpath("goodluck_xp") and goodluck_xp
local has_ench = core.get_modpath("x_enchanting") and XEnchanting

-- ---- what repairs what --------------------------------------------------------------------------------------------
-- Minecraft repairs a tool or armor with the material of its tier: here the last word of its name
local MATERIALS = {
	wood = "group:wood", stone = "group:stone", steel = "default:steel_ingot", bronze = "default:bronze_ingot",
	mese = "default:mese_crystal", diamond = "default:diamond", gold = "default:gold_ingot", cactus = "default:cactus",
}
local REPAIRABLE = {default = true, farming = true, ["3d_armor"] = true, shields = true}

local function material_of(name)
	local mod, item = name:match("^([^:]+):(.+)$")
	if not mod or not REPAIRABLE[mod] then
		return
	end
	local key = item:match("_([a-z]+)$")
	return key and MATERIALS[key]
end

local function is_material(stack, mat)
	if mat:sub(1, 6) == "group:" then
		return core.get_item_group(stack:get_name(), mat:sub(7)) > 0
	end
	return stack:get_name() == mat
end

-- ---- enchantments: x_enchanting keeps {id = {value = v}}; the level is the value's place in its level_def --------
-- Minecraft's anvil multipliers for an enchantment coming from an item
local MULT = {sharpness = 1, efficiency = 1, unbreaking = 2, knockback = 2, looting = 4, fortune = 4, silk_touch = 8,
	curse_of_vanishing = 8}

local function enchantments(stack)
	local levels = {}
	if not has_ench then
		return levels
	end
	local saved = core.deserialize(stack:get_meta():get_string("x_enchanting")) or {}
	for id, e in pairs(saved) do
		local def = XEnchanting.enchantment_defs[id]
		if def and type(e) == "table" then
			local level = 1
			for l, v in ipairs(def.level_def) do
				if math.abs(v - (e.value or 0)) < 1e-4 then
					level = l
				end
			end
			levels[id] = level
		end
	end
	return levels
end

local function clashes(id, other)
	local a, b = XEnchanting.enchantment_defs[id], XEnchanting.enchantment_defs[other]
	return (a.incompatible and table.indexof(a.incompatible, other) > 0) or
		(b.incompatible and table.indexof(b.incompatible, id) > 0)
end

-- Minecraft's rules: equal levels go one up (to the most there is), else the higher stays; one that can't go with
-- what the item has costs 1 and is left out
local function merge(a, b)
	local out, cost = table.copy(a), 0
	for id, lb in pairs(b) do
		local clash = false
		for other in pairs(a) do
			if other ~= id and clashes(id, other) then
				clash = true
			end
		end
		if clash then
			cost = cost + 1
		else
			local max = #XEnchanting.enchantment_defs[id].level_def
			local la = out[id]
			out[id] = la and (la == lb and math.min(la + 1, max) or math.max(la, lb)) or lb
			cost = cost + out[id] * (MULT[id] or 2)
		end
	end
	return out, cost
end

local function glint(image)
	return image .. "^((" .. image .. "^[contrast:127:127)^[mask:x_enchanting_glint.png^[opacity:80)"
end

-- the item's name (its own or the one given here) and its enchantments, written as x_enchanting writes them
local function rewrite(stack, levels)
	local def = core.registered_items[stack:get_name()]
	local meta = stack:get_meta()
	local custom = meta:get_string(NAME)
	local list = {}
	if has_ench and next(levels) then
		local ids = {}
		for id in pairs(levels) do
			ids[#ids + 1] = id
		end
		table.sort(ids)
		local saved = {}
		for _, id in ipairs(ids) do
			local value = XEnchanting.enchantment_defs[id].level_def[levels[id]]
			list[#list + 1] = {id = id, level = levels[id], value = value}
			meta:set_float("is_" .. id, value)
			saved[id] = {value = value}
		end
		meta:set_tool_capabilities(XEnchanting:get_enchanted_tool_capabilities(def, list))
		meta:set_string("x_enchanting", core.serialize(saved))
		meta:set_int("is_enchanted", 1)
		for _, field in ipairs({"inventory_image", "inventory_overlay", "wield_image", "wield_overlay"}) do
			if def[field] and def[field] ~= "" then
				meta:set_string(field, glint(def[field]))
			end
		end
	end
	local base = custom ~= "" and custom or def.description
	if #list > 0 then
		meta:set_string("description", base .. "\n" .. XEnchanting:get_enchanted_descriptions(list).enchantments_desc)
		meta:set_string("short_description", custom ~= "" and custom or
			core.translate("x_enchanting", "Enchanted") .. " " .. (def.short_description or def.description))
	else
		meta:set_string("description", custom)
		meta:set_string("short_description", custom)
	end
end

-- ---- the cost -------------------------------------------------------------------------------------------------------
local function uses(stack)
	return stack:get_meta():get_int(USES)
end

local function trim(text)
	text = (text or ""):gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	local out, n = {}, 0
	for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		n = n + 1
		if n > MAX_NAME then break end
		out[n] = ch
	end
	return table.concat(out)
end

local function lang(player)
	local info = core.get_player_information(player:get_player_name())
	return info and info.lang_code or ""
end

-- what the name field shows: the item's own name, or its name in the player's language
local function shown_name(stack, player)
	local custom = stack:get_meta():get_string(NAME)
	if custom ~= "" then
		return custom
	end
	return core.get_translated_string(lang(player), stack:get_definition().description or ""):match("^[^\n]*")
end

-- the result of left + right named text: {out, cost, used} or {invalid = true}; nil when there is nothing to do
function goodluck_anvil.calc(player, left, right, text)
	if left:is_empty() then
		return
	end
	local out = ItemStack(left)
	local cost, used, work, levels = 0, 0, false, nil
	local tool = core.registered_tools[left:get_name()] ~= nil
	if not right:is_empty() then
		local mat = material_of(left:get_name())
		if mat and is_material(right, mat) and tool then
			if left:get_wear() == 0 or left:get_count() ~= 1 then
				return {invalid = true}
			end
			local wear = left:get_wear()
			while wear > 0 and used < right:get_count() do
				wear = math.max(0, wear - math.floor(WEAR / 4))
				used = used + 1
			end
			out:set_wear(wear)
			cost = cost + used
		elseif tool and right:get_name() == left:get_name() and left:get_count() == 1 then
			used = 1
			if left:get_wear() > 0 then
				local left_dur = WEAR - left:get_wear()
				local right_dur = WEAR - right:get_wear()
				out:set_wear(math.max(0, WEAR - (left_dur + right_dur + math.floor(WEAR * 0.12))))
				cost = cost + 2
			end
			local merged, ecost = merge(enchantments(left), enchantments(right))
			if ecost > 0 then
				levels = merged
				cost = cost + ecost
			end
			if cost == 0 then
				return {invalid = true}
			end
		else
			return {invalid = true}
		end
		work = true
	end
	local renamed = false
	if text then
		local name = trim(text)
		-- an empty field renames only an item that has a name of its own (back to its default)
		local custom = left:get_meta():get_string(NAME)
		if name ~= shown_name(left, player) and (name ~= "" or custom ~= "") then
			local default = shown_name(ItemStack(left:get_name()), player)
			out:get_meta():set_string(NAME, (name == "" or name == default) and "" or name)
			renamed = true
			cost = cost + 1
		end
	end
	if cost == 0 then
		return
	end
	rewrite(out, levels or enchantments(out))
	local total = cost + 2 ^ uses(left) - 1 + (right:is_empty() and 0 or 2 ^ uses(right) - 1)
	if work then
		out:get_meta():set_int(USES, math.max(uses(left), right:is_empty() and 0 or uses(right)) + 1)
	elseif renamed then
		-- Java: a rename alone is never too expensive
		total = math.min(total, MAX_COST)
	end
	return {out = out, cost = total, used = used}
end

-- ---- the window -----------------------------------------------------------------------------------------------------
-- one per player: the anvil it is at, what the name field holds, the result shown
local open = {}

local function creative(player)
	return core.is_creative_enabled(player:get_player_name())
end

local function level(player)
	return has_xp and goodluck_xp.get_level(player) or math.huge
end

local function affordable(player, r)
	return r and r.out and (creative(player) or (r.cost <= MAX_COST and level(player) >= r.cost))
end

local function inv_of(name)
	return core.get_inventory({type = "detached", name = "goodluck_anvil_" .. name})
end

local function formspec(player)
	local name = player:get_player_name()
	local st = open[name]
	local r = st.result
	local inv = "detached:goodluck_anvil_" .. name
	local cost = ""
	if r and r.out then
		if r.cost > MAX_COST and not creative(player) then
			cost = core.colorize("#FF6060", S("Too Expensive!"))
		elseif not creative(player) then
			cost = core.colorize(affordable(player, r) and "#80FF20" or "#FF6060", S("Enchantment Cost: @1", r.cost))
		end
	end
	return table.concat({
		"size[8.5,7.95]",
		"padding[0.01,0.01]",
		"no_prepend[]",
		"bgcolor[#080808BB;true]",
		"listcolors[#00000069;#5A5A5A;#141318;#30434C;#FFF]",
		"background9[-0.2,-0.3;8.9,8.55;gui_formbg.png;false;10]",
		"container[0.25,0]",
		"label[0,-0.15;", F(S("Repair & Name")), "]",
		-- Minecraft's dark name box, not the engine's bright one
		"box[2.1,0.32;5.6,0.62;#000000C0]",
		"style[name;border=false;textcolor=#FFFFFF]",
		"field[2.4,0.6;5.6,0.8;name;;", F(st.text or ""), "]",
		"field_close_on_enter[name;false]",
		"list[", inv, ";left;0.6,1.4;1,1;]",
		"image[1.85,1.4;1,1;goodluck_anvil_plus.png]",
		"list[", inv, ";right;3.1,1.4;1,1;]",
		"image[4.5,1.4;1,1;sfinv_crafting_arrow.png]",
		r and r.invalid and "image[4.5,1.4;1,1;goodluck_anvil_cross.png]" or "",
		"list[", inv, ";result;5.9,1.4;1,1;]",
		"label[2.4,2.45;", F(cost), "]",
		"list[current_player;main;0,3.3;8,3;8]",
		goodluck_craft and goodluck_craft.hotbar(6.45) or "list[current_player;main;0,6.45;8,1;]",
		"listring[", inv, ";result]listring[current_player;main]",
		"listring[", inv, ";left]listring[current_player;main]",
		"listring[", inv, ";right]listring[current_player;main]",
		"container_end[]",
	})
end

local function refresh(player, show)
	local name = player:get_player_name()
	local st = open[name]
	local inv = inv_of(name)
	if not st or not inv then
		return
	end
	st.result = goodluck_anvil.calc(player, inv:get_stack("left", 1), inv:get_stack("right", 1), st.text)
	inv:set_stack("result", 1, st.result and st.result.out or "")
	if show ~= false then
		core.show_formspec(name, FORM, formspec(player))
	end
end

goodluck_anvil.refresh = refresh

-- what is left in the window goes back to the inventory, or to the ground when it is full
local function give_back(player)
	local inv = inv_of(player:get_player_name())
	if not inv then
		return
	end
	local pinv = player:get_inventory()
	for _, list in ipairs({"left", "right"}) do
		local left = pinv:add_item("main", inv:get_stack(list, 1))
		if not left:is_empty() then
			core.add_item(player:get_pos(), left)
		end
		inv:set_stack(list, 1, "")
	end
	inv:set_stack("result", 1, "")
end

local function close(player)
	local name = player:get_player_name()
	if open[name] then
		give_back(player)
		open[name] = nil
	end
end

local function at_anvil(player)
	local st = open[player:get_player_name()]
	return st and IS_ANVIL[core.get_node(st.pos).name] and vector.distance(st.pos, player:get_pos()) < 6
end

-- one use in eight (Minecraft's 12 %) takes the anvil one step: chipped, damaged, gone
local function wear_anvil(pos, player)
	local node = core.get_node(pos)
	if NEXT[node.name] then
		core.swap_node(pos, {name = NEXT[node.name], param2 = node.param2})
		return
	end
	core.remove_node(pos)
	core.sound_play("goodluck_anvil_destroy", {pos = pos, gain = 0.8}, true)
	for name, st in pairs(open) do
		if vector.equals(st.pos, pos) then
			local p = core.get_player_by_name(name)
			if p then
				close(p)
				core.close_formspec(name, FORM)
			end
		end
	end
end

-- the result taken: the inputs spent, the levels paid, the anvil worn
local function use(player)
	local name = player:get_player_name()
	local st = open[name]
	local inv = inv_of(name)
	local r = st and st.result
	if not r or not r.out then
		return
	end
	inv:set_stack("left", 1, "")
	local right = inv:get_stack("right", 1)
	right:take_item(r.used)
	inv:set_stack("right", 1, right)
	if not creative(player) and has_xp then
		goodluck_xp.take_levels(player, r.cost)
	end
	core.sound_play("goodluck_anvil_use", {pos = st.pos, gain = 0.6}, true)
	st.text = ""
	if not creative(player) and math.random() < 0.12 then
		wear_anvil(st.pos, player)
	end
end
goodluck_anvil.use = use

local function make_inv(name)
	local inv = core.create_detached_inventory("goodluck_anvil_" .. name, {
		allow_put = function(_, listname, _, stack, player)
			return listname ~= "result" and at_anvil(player) and stack:get_count() or 0
		end,
		allow_move = function(_, from, _, to, _, count, player)
			return from ~= "result" and to ~= "result" and at_anvil(player) and count or 0
		end,
		allow_take = function(_, listname, _, stack, player)
			if listname ~= "result" then
				return stack:get_count()
			end
			local r = open[name] and open[name].result
			return at_anvil(player) and affordable(player, r) and stack:get_count() == r.out:get_count() and
				stack:get_count() or 0
		end,
		on_put = function(inv, listname, _, _, player)
			if listname == "left" then
				open[name].text = shown_name(inv:get_stack("left", 1), player)
			end
			refresh(player)
		end,
		on_move = function(inv, _, _, to, _, _, player)
			if to == "left" and open[name] then
				open[name].text = shown_name(inv:get_stack("left", 1), player)
			end
			refresh(player)
		end,
		on_take = function(inv, listname, _, _, player)
			if listname == "result" then
				use(player)
			elseif listname == "left" and open[name] then
				open[name].text = ""
			end
			if open[name] then
				refresh(player)
			end
		end,
	})
	inv:set_size("left", 1)
	inv:set_size("right", 1)
	inv:set_size("result", 1)
end

core.register_on_joinplayer(function(player)
	make_inv(player:get_player_name())
end)

core.register_on_leaveplayer(function(player)
	close(player)
	core.remove_detached_inventory("goodluck_anvil_" .. player:get_player_name())
end)
core.register_on_dieplayer(close)

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then
		return
	end
	local st = open[player:get_player_name()]
	if not st then
		return true
	end
	if fields.quit then
		close(player)
		return true
	end
	if fields.name then
		st.text = fields.name
		refresh(player)
	end
	return true
end)

local function open_anvil(pos, player)
	local name = player:get_player_name()
	if open[name] then
		give_back(player)
	end
	open[name] = {pos = vector.copy(pos), text = ""}
	refresh(player)
end

-- ---- the block ----------------------------------------------------------------------------------------------------
-- Minecraft's anvil shape (in sixteenths): a foot, a step, the waist and the long top; the top runs along z
local BOXES = {
	{2, 0, 2, 14, 4, 14},
	{4, 4, 3, 12, 5, 13},
	{6, 5, 4, 10, 10, 12},
	{3, 10, 0, 13, 16, 16},
}
for _, b in ipairs(BOXES) do
	for i = 1, 6 do
		b[i] = b[i] / 16 - 0.5
	end
end

local descriptions = {S("Anvil"), S("Chipped Anvil"), S("Damaged Anvil")}
local tops = {"goodluck_anvil_top.png", "goodluck_anvil_top_chipped.png", "goodluck_anvil_top_damaged.png"}
for i, nodename in ipairs(STATES) do
	core.register_node(nodename, {
		description = descriptions[i],
		drawtype = "nodebox",
		paramtype = "light",
		paramtype2 = "facedir",
		node_box = {type = "fixed", fixed = BOXES},
		tiles = {tops[i], "goodluck_anvil_base.png", "goodluck_anvil_side.png"},
		is_ground_content = false,
		groups = {cracky = 1, level = 2, falling_node = 1},
		sounds = default.node_sound_metal_defaults({place = {name = "goodluck_anvil_land", gain = 0.6}}),
		-- as in Minecraft, its long side across the way the player looks
		after_place_node = function(pos, placer)
			if placer and placer:is_player() then
				local node = core.get_node(pos)
				node.param2 = (core.dir_to_facedir(placer:get_look_dir()) + 1) % 4
				core.swap_node(pos, node)
			end
		end,
		on_rightclick = function(pos, _, clicker)
			if clicker and clicker:is_player() then
				open_anvil(pos, clicker)
			end
		end,
	})
end

-- Minecraft's recipe: three blocks of iron over an ingot over three ingots
core.register_craft({
	output = STATES[1],
	recipe = {
		{"default:steelblock", "default:steelblock", "default:steelblock"},
		{"", "default:steel_ingot", ""},
		{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
	},
})
