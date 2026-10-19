-- Two chests side by side make one big chest, as in Minecraft: a chest placed beside another that faces the same way
-- joins it (placed against its side it takes its way first, as since 1.13), and so do pairs that stood so before;
-- the big chest holds 64, all in the left half's meta, shown 32 a page with tabs as the inventory's; a half breaks
-- only when its own 32 are empty, and the other half is a chest again with what was in it
local S = core.get_translator("default")
local CHEST, FORM = "default:chest", "goodluck_chest:big"
local HALF = {}
local viewers = {}

local function right_of(param2)
	local back = core.facedir_to_dir(param2)
	return vector.new(back.z, 0, -back.x)
end

local function partner(pos, node)
	local r = right_of(node.param2)
	return HALF[node.name] == "left" and vector.add(pos, r) or vector.subtract(pos, r)
end

-- the left half holds all 64: 1-32 its own, 33-64 the right's
local function storage(pos, node)
	return HALF[node.name] == "left" and pos or partner(pos, node)
end

local function single(pos, param2)
	local node = core.get_node(pos)
	return node.name == CHEST and node.param2 == param2
end

local function join(lp, rp, param2)
	local linv, rinv = core.get_meta(lp):get_inventory(), core.get_meta(rp):get_inventory()
	local items = {}
	for i, list in ipairs({linv:get_list("main") or {}, rinv:get_list("main") or {}}) do
		for k = 1, 32 do
			items[(i - 1) * 32 + k] = list[k] or ItemStack()
		end
	end
	core.swap_node(lp, {name = "goodluck_chest:left", param2 = param2})
	core.swap_node(rp, {name = "goodluck_chest:right", param2 = param2})
	linv:set_size("main", 64)
	linv:set_list("main", items)
	rinv:set_size("main", 0)
end

local function try_join(pos)
	local node = core.get_node(pos)
	local r = right_of(node.param2)
	if single(vector.add(pos, r), node.param2) then
		join(pos, vector.add(pos, r), node.param2)
	elseif single(vector.subtract(pos, r), node.param2) then
		join(vector.subtract(pos, r), pos, node.param2)
	end
end

local function lids(lp, open)
	for _, p in ipairs({lp, partner(lp, core.get_node(lp))}) do
		local n = core.get_node(p)
		if HALF[n.name] and not (open and default.chest.chest_lid_obstructed(p)) then
			core.swap_node(p, {name = "goodluck_chest:" .. HALF[n.name] .. (open and "_open" or ""), param2 = n.param2})
		end
	end
end

-- the inventory's panel and tab row (goodluck_craft), the chest's 4 rows where the inventory has the player
local TAB_ROW = 1.05
local TOP = -0.16 + TAB_ROW
local function formspec(lp, page)
	local loc = ("nodemeta:%d,%d,%d"):format(lp.x, lp.y, lp.z)
	local fs = {
		"size[8.5,9.1]",
		"padding[0.01,0.01]",
		"no_prepend[]",
		"bgcolor[#080808BB;true]",
		"listcolors[#00000069;#5A5A5A;#141318;#30434C;#FFF]",
		goodluck_craft and goodluck_craft.panel(TOP) or "",
	}
	for i = 1, 2 do
		local x, y = 0.25 + (i - 1) * 1.25, TOP - TAB_ROW + 0.043
		-- the number as an item icon: a text label or a plain image goes under the selected tab's image
		fs[#fs + 1] = goodluck_craft and goodluck_craft.tab(i, tostring(i), "goodluck_chest:page_" .. i, i == page, x,
			y, 1, false) or
			("button[%g,%g;1,0.9;goodluck_tab_%d;%d]"):format(x, y, i, i)
	end
	fs[#fs + 1] = ("container[0.25,%g]"):format(TOP)
	fs[#fs + 1] = ("list[%s;main;0,0;8,4;%d]"):format(loc, (page - 1) * 32)
	fs[#fs + 1] = goodluck_craft and goodluck_craft.inventory(4.15) or "list[current_player;main;0,4.15;8,4;]"
	fs[#fs + 1] = "container_end[]"
	fs[#fs + 1] = "listring[" .. loc .. ";main]listring[current_player;main]"
	return table.concat(fs)
end

for i = 1, 2 do
	core.register_craftitem("goodluck_chest:page_" .. i, {
		description = tostring(i),
		inventory_image = "goodluck_chest_page_" .. i .. ".png",
		groups = {not_in_creative_inventory = 1},
	})
end

local function show(name, lp, page)
	viewers[name] = {pos = lp, page = page}
	core.show_formspec(name, FORM, formspec(lp, page))
end

local function close(name)
	local v = viewers[name]
	viewers[name] = nil
	if not v then
		return
	end
	for _, other in pairs(viewers) do
		if vector.equals(other.pos, v.pos) then
			return
		end
	end
	core.after(0.2, function()
		if HALF[core.get_node(v.pos).name] then
			lids(v.pos, false)
			core.sound_play("default_chest_close", {gain = 0.3, pos = v.pos, max_hear_distance = 10}, true)
		end
	end)
end

local function open(pos, node, clicker)
	local name = clicker:get_player_name()
	local lp = storage(pos, node)
	close(name)
	core.sound_play("default_chest_open", {gain = 0.3, pos = lp, max_hear_distance = 10}, true)
	lids(lp, true)
	viewers[name] = {pos = lp, page = 1}
	-- the lids open first, as MTG's chest
	core.after(0.2, function()
		if viewers[name] and core.get_player_by_name(name) then
			show(name, lp, viewers[name].page)
		end
	end)
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= FORM then
		return
	end
	local name = player:get_player_name()
	local v = viewers[name]
	if v and (fields.goodluck_tab_1 or fields.goodluck_tab_2) then
		show(name, v.pos, fields.goodluck_tab_1 and 1 or 2)
	elseif fields.quit then
		close(name)
	end
	return true
end)

core.register_on_leaveplayer(function(player)
	close(player:get_player_name())
end)

-- this half's 32 slots: 1-32 for the left, 33-64 for the right
local function own(pos, node)
	local first = HALF[node.name] == "left" and 1 or 33
	return core.get_meta(storage(pos, node)):get_inventory(), first, first + 31
end

local function can_dig(pos)
	local inv, first, last = own(pos, core.get_node(pos))
	for i = first, last do
		if not inv:get_stack("main", i):is_empty() then
			return false
		end
	end
	return true
end

-- what is left in this half falls out (a player can't dig it full, a blast can), the other is a chest again
local function on_destruct(pos)
	local node = core.get_node(pos)
	local inv, first, last = own(pos, node)
	local list = inv:get_list("main") or {}
	for i = first, last do
		if list[i] and not list[i]:is_empty() then
			core.add_item(pos, list[i])
		end
	end
	local other = partner(pos, node)
	local o = core.get_node(other)
	if not HALF[o.name] then
		return
	end
	local rest, from = {}, first == 1 and 33 or 1
	for i = from, from + 31 do
		rest[#rest + 1] = list[i] or ItemStack()
	end
	core.swap_node(other, {name = CHEST, param2 = o.param2})
	local oinv = core.get_meta(other):get_inventory()
	oinv:set_size("main", 32)
	oinv:set_list("main", rest)
end

local function on_blast(pos)
	local node = core.get_node(pos)
	local inv, first, last = own(pos, node)
	local drops = {}
	for i = first, last do
		local stack = inv:get_stack("main", i)
		if not stack:is_empty() then
			drops[#drops + 1] = stack
			inv:set_stack("main", i, "")
		end
	end
	drops[#drops + 1] = CHEST
	core.remove_node(pos)
	return drops
end

-- normal drawtype faces: +Y, -Y, +X, -X, +Z (back), -Z (front); the right half sits at the left one's +X
local function tiles(half, open)
	local other = half == "left" and "right" or "left"
	local function t(name, side)
		return "goodluck_chest_" .. name .. "_" .. (side or half) .. ".png"
	end
	if open then
		-- chest_open.obj's parts: top, bottom, sides, back, front, inside
		local list = {t("top"), t("top"), "default_chest_side.png", t("back", other), t("front"), t("inside")}
		for i, name in ipairs(list) do
			list[i] = {name = name, backface_culling = true}
		end
		return list
	end
	-- seen from behind, the left half is on the right
	return {t("top"), t("top"), "default_chest_side.png^[transformFX", "default_chest_side.png", t("back", other),
		t("front")}
end

for _, half in ipairs({"left", "right"}) do
	local name = "goodluck_chest:" .. half
	local def = {
		description = S("Chest"),
		tiles = tiles(half, false),
		paramtype = "light",
		paramtype2 = "facedir",
		is_ground_content = false,
		groups = {choppy = 2, oddly_breakable_by_hand = 2, not_in_creative_inventory = 1},
		sounds = default.node_sound_wood_defaults(),
		drop = CHEST,
		on_rotate = core.global_exists("screwdriver") and screwdriver.disallow or nil,
		can_dig = can_dig,
		on_destruct = on_destruct,
		on_blast = on_blast,
		on_rightclick = open,
	}
	default.set_inventory_action_loggers(def, "chest")
	local opened = table.copy(def)
	opened.drawtype = "mesh"
	opened.mesh = "chest_open.obj"
	opened.tiles = tiles(half, true)
	opened.selection_box = {type = "fixed", fixed = {-1/2, -1/2, -1/2, 1/2, 3/16, 1/2}}
	opened.can_dig = function() return false end
	opened.on_blast = function() end
	core.register_node(name, def)
	core.register_node(name .. "_open", opened)
	HALF[name], HALF[name .. "_open"] = half, half
end

core.register_lbm({
	name = "goodluck_chest:close_open",
	label = "Close big chests left open",
	nodenames = {"goodluck_chest:left_open", "goodluck_chest:right_open"},
	run_at_every_load = true,
	action = function(pos, node)
		core.swap_node(pos, {name = node.name:gsub("_open$", ""), param2 = node.param2})
	end,
})

local after_place_node = core.registered_nodes[CHEST].after_place_node
core.override_item(CHEST, {
	after_place_node = function(pos, placer, itemstack, pointed_thing)
		local under = pointed_thing and pointed_thing.type == "node" and pointed_thing.under
		local u = under and core.get_node(under)
		if u and u.name == CHEST and under.y == pos.y then
			local d, r = vector.subtract(pos, under), right_of(u.param2)
			if vector.equals(d, r) or vector.equals(d, vector.multiply(r, -1)) then
				core.swap_node(pos, {name = CHEST, param2 = u.param2})
			end
		end
		try_join(pos)
		return after_place_node and after_place_node(pos, placer, itemstack, pointed_thing)
	end,
})

-- chests that stood side by side before: in a row they pair from the left, as they would have been placed
core.register_lbm({
	name = "goodluck_chest:join",
	label = "Chests side by side make a big one",
	nodenames = {CHEST},
	run_at_every_load = false,
	action = function(pos, node)
		local r = right_of(node.param2)
		local k, p = 0, vector.subtract(pos, r)
		while k < 64 and single(p, node.param2) do
			k, p = k + 1, vector.subtract(p, r)
		end
		if k % 2 == 0 and single(vector.add(pos, r), node.param2) then
			join(pos, vector.add(pos, r), node.param2)
		end
	end,
})
