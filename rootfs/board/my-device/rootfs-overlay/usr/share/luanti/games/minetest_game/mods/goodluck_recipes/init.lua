-- Recipes learnt as in Minecraft: a recipe enters the Recipes book once every item it takes has been in the inventory
-- (Minecraft's key item is mostly the last of them to come), a notice in the top right says so. Players from before
-- this mod know them all, and creative shows them all
local S = core.get_translator("goodluck_recipes")
local KEY = "goodluck_recipes"
-- what Minecraft unlocks them by instead: nothing (the crafting table), ten slots taken, being in water
local SPECIAL = {
	["goodluck_craft:crafting_table"] = {},
	["default:chest"] = {"@slots"},
	["boats:boat"] = {"@water"},
}
local SLOTS, TOAST_TIME = 10, 5

goodluck_recipes = {}
local recipes = {}
-- recipe indexes by output, by the key that unlocks them and by the ingredient they take
local by_output, needed_by, used_in = {}, {}, {}
-- "group:a,b" -> {"a", "b"}, and the items of each group
local group_keys, members = {}, {}
local all_items, ready = {}, false
local players, toasts, welcome = {}, {}, {}

local function show(def)
	return def and def.groups.not_in_craft_guide ~= 1 and def.description ~= ""
end

local function resolve(name)
	for _ = 1, 10 do
		local to = core.registered_aliases[name]
		if not to then
			break
		end
		name = to
	end
	return name
end

local function in_groups(def, groups)
	for _, group in ipairs(groups) do
		if (def.groups[group] or 0) == 0 then
			return false
		end
	end
	return true
end

-- mtg_craftguide's stand-in for a group in a recipe
local STEREOTYPES = {dye = "dye:white", wool = "wool:white", coal = "default:coal_lump",
	vessel = "vessels:glass_bottle", flower = "flowers:dandelion_yellow"}
local stereotype = {}
function goodluck_recipes.group_item(key)
	if stereotype[key] then
		return stereotype[key]
	end
	local groups = group_keys[key] or key:sub(7):split(",")
	local item = #groups == 1 and (STEREOTYPES[groups[1]] or core.registered_items["default:" .. groups[1]] and
		"default:" .. groups[1])
	if not item then
		item = ":unknown"
		for name, def in pairs(core.registered_items) do
			if in_groups(def, groups) then
				item = name
				break
			end
		end
	end
	stereotype[key] = item
	return item
end

local function key_of(item)
	if item:sub(1, 6) == "group:" then
		group_keys[item] = group_keys[item] or item:sub(7):split(",")
		return item
	end
	return resolve(item)
end

local function add(index, key, i)
	index[key] = index[key] or {}
	table.insert(index[key], i)
end

local function group_members(key)
	local groups, list = group_keys[key], {}
	for _, name in ipairs(members[groups[1]] or {}) do
		if in_groups(core.registered_items[name], groups) then
			list[#list + 1] = name
		end
	end
	return list
end

-- after every mod has added and taken its recipes, as mtg_craftguide
core.after(0, function()
	local t0 = core.get_us_time()
	for name, def in pairs(core.registered_items) do
		if show(def) then
			for group, rating in pairs(def.groups) do
				if rating ~= 0 then
					members[group] = members[group] or {}
					table.insert(members[group], name)
				end
			end
		end
	end
	local listed = {}
	for name, def in pairs(core.registered_items) do
		for _, recipe in ipairs(show(def) and core.get_all_craft_recipes(name) or {}) do
			local keys, have, ok = {}, {}, true
			for _, item in pairs(recipe.items) do
				local key = key_of(item)
				if not have[key] then
					have[key] = true
					keys[#keys + 1] = key
					ok = ok and core.registered_items[group_keys[key] and goodluck_recipes.group_item(key) or key] ~= nil
				end
			end
			if ok then
				local i = #recipes + 1
				recipes[i] = {output = name, recipe = recipe, keys = keys, needs = SPECIAL[name] or keys}
				add(by_output, name, i)
				for _, key in ipairs(keys) do
					add(used_in, key, i)
				end
				for _, key in ipairs(recipes[i].needs) do
					add(needed_by, key, i)
				end
				listed[name] = true
				for _, key in ipairs(keys) do
					for _, item in ipairs(group_keys[key] and group_members(key) or {key}) do
						listed[item] = show(core.registered_items[item]) or nil
					end
				end
			end
		end
	end
	for name in pairs(listed) do
		all_items[#all_items + 1] = name
	end
	table.sort(all_items)
	core.log("action", ("[goodluck_recipes] %d recipes, %d items in %d ms"):format(#recipes, #all_items,
		(core.get_us_time() - t0) / 1000))
	ready = true
	for _, player in ipairs(core.get_connected_players()) do
		goodluck_recipes.load(player)
	end
end)

local function knows(p, r)
	for _, key in ipairs(r.needs) do
		if not p.have[key] then
			return false
		end
	end
	return true
end

-- an item (or "@slots", "@water") the player has had: the keys it brings, and the recipes they complete
local function learn(p, item, new)
	if p.have[item] then
		return
	end
	local keys, def = {item}, core.registered_items[item]
	if def then
		for key, groups in pairs(group_keys) do
			if not p.have[key] and in_groups(def, groups) then
				keys[#keys + 1] = key
			end
		end
	end
	for _, key in ipairs(keys) do
		p.have[key] = true
	end
	for _, key in ipairs(keys) do
		for _, i in ipairs(needed_by[key] or {}) do
			if not p.known[i] and knows(p, recipes[i]) then
				p.known[i] = true
				new[#new + 1] = i
			end
		end
	end
end

local function save(player, p)
	local list = {"learn"}
	for key in pairs(p.have) do
		if not group_keys[key] then
			list[#list + 1] = key
		end
	end
	player:get_meta():set_string(KEY, table.concat(list, " "))
end

-- the item's picture: its own, or a cube of its tiles
local CUBES = {normal = true, allfaces = true, allfaces_optional = true, glasslike = true,
	glasslike_framed = true, glasslike_framed_optional = true, liquid = true}
local function icon(name)
	local def = core.registered_items[name] or {}
	if (def.inventory_image or "") ~= "" then
		return def.inventory_image
	end
	local tiles = def.tiles or {}
	local function tile(i)
		local t = tiles[i] or tiles[#tiles] or "blank.png"
		return type(t) == "table" and (t.name or t.image) or t
	end
	if CUBES[def.drawtype or "normal"] and def.type == "node" then
		return core.inventorycube(tile(1), tile(6), tile(3))
	end
	return (def.wield_image or "") ~= "" and def.wield_image or tile(1)
end

-- Minecraft's toast: 280 x 48 at 640x480 (in percent of the screen, so another texture's size doesn't change it)
local W, H = 280, 48
local function pct(x, y)
	return {x = -100 * x / 640, y = -100 * y / 480}
end
local function toast(player, item)
	local name = player:get_player_name()
	local t = toasts[name]
	if t then
		player:hud_change(t.icon, "text", icon(item))
		t.left = TOAST_TIME
		return
	end
	local at = {x = 1, y = 0}
	toasts[name] = {
		left = TOAST_TIME,
		player:hud_add({type = "image", position = at, alignment = {x = -1, y = 1}, offset = {x = -4, y = 4},
			scale = pct(W, H), text = "goodluck_recipes_toast.png", z_index = 20}),
		player:hud_add({type = "text", position = at, alignment = {x = 1, y = 1}, offset = {x = -W + 48, y = 11},
			text = S("New Recipes Unlocked!"), number = 0xFFFF55, z_index = 21}),
		player:hud_add({type = "text", position = at, alignment = {x = 1, y = 1}, offset = {x = -W + 48, y = 29},
			text = S("Check your recipe book"), number = 0xE0E0E0, z_index = 21}),
	}
	toasts[name].icon = player:hud_add({type = "image", position = at, alignment = {x = 1, y = 1},
		offset = {x = -W + 4, y = 12}, scale = pct(32, 32), text = icon(item), z_index = 21})
end

local function changed(player, p, new)
	save(player, p)
	p.items = nil
	if not core.is_creative_enabled(player:get_player_name()) then
		toast(player, recipes[new[1]].output)
	end
	if sfinv.get_page(player) == "mtg_craftguide:craftguide" then
		sfinv.set_player_inventory_formspec(player)
	end
end

local function scan(player, p, extra)
	local new, taken = {}, 0
	for _, stack in ipairs(player:get_inventory():get_list("main") or {}) do
		if not stack:is_empty() then
			taken = taken + 1
			learn(p, stack:get_name(), new)
		end
	end
	for _, stack in ipairs(extra or {}) do
		if not stack:is_empty() then
			learn(p, stack:get_name(), new)
		end
	end
	if taken >= SLOTS then
		learn(p, "@slots", new)
	end
	if not p.have["@water"] and core.get_item_group(core.get_node(player:get_pos():round()).name, "water") > 0 then
		learn(p, "@water", new)
	end
	if #new > 0 then
		changed(player, p, new)
	end
end

function goodluck_recipes.load(player)
	if not ready then
		return
	end
	local name, meta = player:get_player_name(), player:get_meta()
	local saved = meta:get_string(KEY)
	if saved == "" then
		saved = "all"
		meta:set_string(KEY, saved)
	end
	local p = {have = {}, known = {}, all = saved == "all"}
	players[name] = p
	if p.all then
		return
	end
	local new = {}
	for item in saved:gmatch("%S+") do
		if item ~= "learn" then
			learn(p, item, new)
		end
	end
	for i, r in ipairs(recipes) do
		p.known[i] = p.known[i] or knows(p, r) or nil
	end
	-- told about the crafting table, as Minecraft does at once
	if welcome[name] and next(p.known) then
		welcome[name] = nil
		core.after(2, function()
			if player:is_player() and not core.is_creative_enabled(name) then
				toast(player, recipes[next(p.known)].output)
			end
		end)
	end
end

-- a world's first join learns from nothing
core.register_on_newplayer(function(player)
	player:get_meta():set_string(KEY, "learn")
	welcome[player:get_player_name()] = true
end)

core.register_on_joinplayer(goodluck_recipes.load)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	players[name], toasts[name], welcome[name] = nil, nil, nil
end)

-- a recipe crafted by hand is learnt too: the chest and the boat as if ten slots were taken, or in water
core.register_on_craft(function(itemstack, player, old_craft_grid)
	local p = player and players[player:get_player_name()]
	if p and not p.all then
		scan(player, p, {itemstack, unpack(old_craft_grid)})
		local new = {}
		for _, i in ipairs(by_output[itemstack:get_name()] or {}) do
			if not p.known[i] and knows(p, {needs = recipes[i].keys}) then
				for _, key in ipairs(recipes[i].needs) do
					learn(p, key, new)
				end
			end
		end
		if #new > 0 then
			changed(player, p, new)
		end
	end
end)

local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 1 then
		return
	end
	timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local p, t = players[name], toasts[name]
		if p and not p.all then
			scan(player, p)
		end
		if t then
			t.left = t.left - 1
			if t.left <= 0 then
				for _, id in ipairs(t) do
					player:hud_remove(id)
				end
				player:hud_remove(t.icon)
				toasts[name] = nil
			end
		end
	end
end)

-- what the Recipes book shows: every recipe in creative and to players from before, else the known ones
local function knows_all(player, p)
	return not p or p.all or core.is_creative_enabled(player:get_player_name())
end

function goodluck_recipes.items(player)
	local p = players[player:get_player_name()]
	if knows_all(player, p) then
		return all_items
	end
	if p.items then
		return p.items
	end
	local set, used = {}, {}
	for i in pairs(p.known) do
		set[recipes[i].output] = true
		for _, key in ipairs(recipes[i].keys) do
			used[key] = true
		end
	end
	for item in pairs(p.have) do
		local def = not group_keys[item] and core.registered_items[item]
		if def and show(def) then
			local yes = used[item]
			for key, groups in pairs(group_keys) do
				yes = yes or used[key] and in_groups(def, groups)
			end
			set[item] = yes or set[item]
		end
	end
	p.items = {}
	for item in pairs(set) do
		p.items[#p.items + 1] = item
	end
	table.sort(p.items)
	return p.items
end

function goodluck_recipes.recipes(player, item)
	local p, list = players[player:get_player_name()], {}
	local all = knows_all(player, p)
	for _, i in ipairs(by_output[item] or {}) do
		if all or p.known[i] then
			list[#list + 1] = recipes[i].recipe
		end
	end
	return #list > 0 and list or nil
end

-- the recipes that take the item, with it in the place of the group it is in
function goodluck_recipes.usages(player, item)
	local p, def = players[player:get_player_name()], core.registered_items[item]
	local all, list, added = knows_all(player, p), {}, {}
	local keys = {item}
	for key, groups in pairs(group_keys) do
		if def and in_groups(def, groups) then
			keys[#keys + 1] = key
		end
	end
	for _, key in ipairs(keys) do
		for _, i in ipairs(used_in[key] or {}) do
			if not added[i] and (all or p.known[i]) then
				added[i] = true
				local usage = recipes[i].recipe
				if group_keys[key] then
					usage = table.copy(usage)
					for k, v in pairs(usage.items) do
						if v == key then
							usage.items[k] = item
						end
					end
				end
				list[#list + 1] = usage
			end
		end
	end
	return #list > 0 and list or nil
end

dofile(core.get_modpath("goodluck_recipes") .. "/book.lua")
