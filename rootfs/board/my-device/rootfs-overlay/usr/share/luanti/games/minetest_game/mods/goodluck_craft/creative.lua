-- Minecraft's creative tabs (Java Edition since 1.19.3, without Redstone Blocks: no circuits yet) in place of
-- minetest_game's All/Nodes/Tools/Items. An item shows in every tab whose test it passes, as in Minecraft; one that
-- passes none goes to Building Blocks (nodes), Tools & Utilities (tools) or Ingredients (the rest)
local S = core.get_translator("goodluck_craft")
local COLS, ROWS = 9, 6
-- the grid ends a third of a slot above the hotbar (at 7.3, as on the inventory page); the search field above it
local GRID_Y = 1.13
local players = {}

local function any_group(g, ...)
	for _, group in ipairs({...}) do
		if (g[group] or 0) > 0 then
			return true
		end
	end
	return false
end

local function matches(name, ...)
	for _, pattern in ipairs({...}) do
		if name:find(pattern) then
			return true
		end
	end
	return false
end

local function natural(name, def, g)
	return matches(name, "^goodluck_food:[%a_]*seeds$", "^goodluck_food:pumpkin$", "^goodluck_food:melon$",
		"^goodluck_food:cocoa_beans$") or
		def.type == "node" and (any_group(g, "soil", "sand", "leaves", "sapling", "flora", "flower", "grass",
		"mushroom", "tree", "seed", "snowy", "catchable") or matches(name, "^default:ice$", ":stone_with_",
		"^default:[%a_]*stone$", "^default:gravel$", "^default:clay$", "^default:obsidian$", "^default:cactus$",
		"^default:large_cactus_seedling$", "^default:papyrus$", "^default:dry_shrub$", "^default:coral_",
		"^default:sand_with_kelp$", "^default:permafrost", "bush_stem$", "^default:[%a_]*_source$",
		"^farming:cotton_wild$", "^flowers:", "^mobs:cobweb$", "^mobs:beehive$", "^mobs:hearing_vines$",
		"^goodluck_amethyst:", "^goodluck_nether:netherrack$", "^goodluck_nether:bedrock$", "^goodluck_nether:glowstone$",
		"^goodluck_nether:soul_sand$", "^goodluck_nether:magma$", "^goodluck_nether:%a+_ore$",
		"^goodluck_nether:blackstone$", "^goodluck_nether:crying_obsidian$"))
end

local function functional(name)
	return matches(name, "^goodluck_craft:crafting_table$", "^default:furnace$", "^default:chest", "^default:bookshelf$",
		"^default:torch$", "^goodluck_redstone:lamp$", "^default:ladder_", "^default:sign_wall_",
		"^beds:", "^bones:", "^vessels:", "^fireflies:firefly_bottle$", "^mobs:spawner$", "^goodluck_potions:brewing_stand$", "^mobs:mob_repellent$",
		"^fire:permanent_flame$", "^goodluck_food:jack_o_lantern$", "^goodluck_nether:wither_skeleton_skull$",
		"^goodluck_end:frame$") and
		name ~= "vessels:glass_fragments"
end

local function building(name, def, g)
	return def.type == "node" and (any_group(g, "stone", "wood", "tree", "stair", "slab", "wall", "fence", "pane",
		"door") or matches(name, "brick$", "_block$", "^default:%a+block$", "^default:[%a_]*sandstone$",
		"^default:[%a_]*cobble$", "^default:obsidian", "^default:glass$", "^goodluck_redstone:block$", "^mobs:cheeseblock$",
		"^mobs:honey_block$", "^farming:straw$") and name ~= "default:snowblock") or
		matches(name, "^doors:door_", "^xpanes:door_")
end

local function combat(name, def, g)
	return name:find(":sword_") ~= nil or name == "tnt:tnt" or any_group(g, "armor_head", "armor_torso", "armor_legs",
		"armor_feet", "armor_shield")
end

local function tools(name, def, g)
	return not combat(name, def, g) and (def.type == "tool" or any_group(g, "tool", "rail") or
		matches(name, "^boats:", "^carts:", "^mobs:saddle$", "^mobs:nametag$", "^mobs:protector",
		"^goodluck_nether:fire_charge$", "^goodluck_end:ender_pearl$", "^goodluck_end:ender_eye$"))
end

local function food(name, def, g)
	return any_group(g, "food", "eatable", "food_apple", "food_berry", "food_bread", "potion")
end

local function ingredients(name, def, g)
	return def.type == "craft" and not (any_group(g, "spawn_egg") or food(name, def, g) or tools(name, def, g) or
		building(name, def, g)) or matches(name, "^dye:", "^tnt:gunpowder$", "^mobs:egg$")
end

-- in Minecraft's places, and its order: by material, each family as Minecraft lists it (patterns on the material);
-- the icons stand for Minecraft's own (bricks, cyan wool, grass block, oak sign, diamond pickaxe, netherite sword,
-- golden apple, iron ingot, and a spawn egg)
local CATEGORIES = {
	{"building_blocks", S("Building Blocks"), "default:brick", 1, 1, building, {"^stone$", "^cobble$", "^mossycobble$",
		"^stonebrick$", "^stone_block$", "^desert_", "sandstone", "tree$", "wood$", "^brick$", "block$", "^obsidian",
		"glass"}},
	{"colored_blocks", S("Colored Blocks"), "wool:cyan", 1, 2, function(name)
		return matches(name, "^wool:", "^beds:")
	end},
	{"natural_blocks", S("Natural Blocks"), "default:dirt_with_grass", 1, 3, natural, {"^dirt_with_grass$", "dirt",
		"permafrost", "sand$", "^gravel$", "^clay$", "snow", "^ice$", "stone$", "^stone_with_", "^obsidian$", "^calcite$", "^amethyst", "tree$",
		"leaves", "needles$", "sapling$", "seedling$", "stem$", "grass", "fern", "^dry_shrub$", "^cactus$", "vines$",
		"^papyrus$", "^seed_", "^cotton_wild$", "^rose$", "^tulip", "^dandelion", "^chrysanthemum", "^geranium$",
		"^viola$", "^mushroom", "^waterlily$", "^coral", "kelp$", "^bee", "^cobweb$", "^butterfly", "^firefly$",
		"_source$"}},
	{"functional_blocks", S("Functional Blocks"), "default:sign_wall_wood", 1, 4, functional, {"^crafting_table$",
		"^furnace$", "^chest", "shelf$", "^torch$", "lamp$", "light", "^ladder", "^sign", "bed"}},
	{"tools_utilities", S("Tools & Utilities"), "default:pick_diamond", 2, 1, tools, {"^0", "^bucket",
		"^flint_and_steel$", "^fire_charge$", "^shears$", "rail$", "^cart$", "^boat$"}},
	{"combat", S("Combat"), "default:sword_diamond", 2, 2, combat},
	{"food_drinks", S("Food & Drinks"), "default:apple", 2, 3, food, {"^apple$", "^golden_apple$", "^melon_slice$",
		"^blueberries$", "^carrot$", "^golden_carrot$", "^potato$", "^baked_potato$", "^poisonous_potato$", "^beetroot$",
		"^bread$", "^cookie$", "^cake$", "^pumpkin_pie$", "^cod$", "^cooked_cod$", "^salmon$", "^cooked_salmon$",
		"^mushroom_stew$", "^beetroot_soup$"}},
	{"ingredients", S("Ingredients"), "default:steel_ingot", 2, 4, ingredients, {"^coal_lump$", "_lump$", "_ingot$", "_nugget$",
		"^emerald$", "^diamond$", "^redstone$", "^amethyst_shard$", "^flint$", "^stick$", "^clay", "^paper$", "^book$", "^string$", "^cotton$",
		"^wheat$", "^flour$", "^sugar$", "^bowl$"}},
	{"spawn_eggs", S("Spawn Eggs"), "goodluck_craft_spawn_egg.png", 2, 5, function(name, def, g)
		return any_group(g, "spawn_egg") or name == "goodluck_nether:spawner"
	end},
}

-- the block first, then its stairs and slabs, its wall, fence, gate and door; dyes, wool and sheep in Minecraft's
-- colour order
local VARIANTS = {"^stairs:stair_inner_", "^stairs:stair_outer_", "^stairs:stair_", "^stairs:slab_", "^walls:",
	"^default:fence_rail_", "^default:fence_", "^doors:gate_", "^doors:door_"}
local COLORS = {white = 1, grey = 2, dark_grey = 3, black = 4, brown = 5, red = 6, orange = 7, yellow = 8, green = 9,
	dark_green = 10, cyan = 11, blue = 12, violet = 13, magenta = 14, pink = 15}
-- tools and weapons by material, each material's set together; then shields, then armor
local GEAR = {shovel = 11, pick = 12, axe = 13, hoe = 14, sword = 15, shield = 21, helmet = 31, chestplate = 32,
	leggings = 33, boots = 34}
local MATERIALS = {wood = 1, leather = 1, enhanced_wood = 2, cactus = 3, enhanced_cactus = 4, stone = 5, copper = 6, steel = 7,
	gold = 8, diamond = 10, mithril = 11, crystal = 12, nether = 13, lava = 14}
local function material(name)
	for i, prefix in ipairs(VARIANTS) do
		local base = name:match(prefix .. "(.*)")
		if base then
			return (base:gsub("_closed$", ""):gsub("^desertcobble$", "desert_cobble")), i
		end
	end
	local base = name:match(":(.*)") or name
	local kind, made_of = base:match("^(%a+)_(.+)$")
	if GEAR[kind] and MATERIALS[made_of] then
		local gear = GEAR[kind]
		return ("0%d%02d%d"):format(math.floor(gear / 10), MATERIALS[made_of], gear % 10), 0
	end
	local color = COLORS[base] and base or base:match("^sheep_(.+)$")
	if color and COLORS[color] then
		return base:gsub(color .. "$", ("%02d"):format(COLORS[color])), 0
	end
	return base, 0
end

local function sort(list, order)
	local keys = {}
	for _, name in ipairs(list) do
		local base, variant = material(name)
		local rank = #(order or {}) + 1
		for i, pattern in ipairs(order or {}) do
			if base:find(pattern) then
				rank = i
				break
			end
		end
		keys[name] = ("%02d%s\0%02d"):format(rank, base, variant)
	end
	table.sort(list, function(a, b)
		return keys[a] < keys[b] or keys[a] == keys[b] and a < b
	end)
end

local lists = {}
core.register_on_mods_loaded(function()
	for _, cat in ipairs(CATEGORIES) do
		lists[cat[1]] = {}
	end
	local all = {}
	for name, def in pairs(core.registered_items) do
		local g = def.groups or {}
		if (g.not_in_creative_inventory or 0) == 0 and def.description and def.description ~= "" then
			local placed = false
			for _, cat in ipairs(CATEGORIES) do
				if cat[6](name, def, g) then
					table.insert(lists[cat[1]], name)
					placed = true
				end
			end
			if not placed then
				local fallback = def.type == "node" and "building_blocks" or def.type == "tool" and "tools_utilities" or
					"ingredients"
				table.insert(lists[fallback], name)
			end
		end
	end
	-- Search lists every item, in the tabs' order
	local seen = {}
	for _, cat in ipairs(CATEGORIES) do
		sort(lists[cat[1]], cat[7])
		for _, name in ipairs(lists[cat[1]]) do
			if not seen[name] then
				seen[name] = true
				all[#all + 1] = name
			end
		end
	end
	lists.search = all
end)

local function state(player)
	local name = player:get_player_name()
	if not players[name] then
		creative.init_creative_inventory(player)
		players[name] = {filter = "", scroll = {}}
	end
	return players[name]
end
core.register_on_leaveplayer(function(player)
	players[player:get_player_name()] = nil
end)

local function description(def, lang)
	return (core.get_translated_string(lang, def.description):gsub("\n.*", "")):lower()
end

-- as minetest_game's search: the closest matches first, in the name, the description or its translation
local function search(player, filter)
	local info = core.get_player_information(player:get_player_name())
	local lang = info and info.lang_code ~= "" and info.lang_code
	local found, order = {}, {}
	for _, name in ipairs(lists.search) do
		local def = core.registered_items[name]
		local best
		for _, s in ipairs({description(def, "en"), lang and description(def, lang) or "", name}) do
			if s:find(filter, 1, true) then
				best = math.min(best or 999, #s - #filter)
			end
		end
		if best then
			found[#found + 1] = name
			order[name] = ("%03d"):format(best) .. name
		end
	end
	table.sort(found, function(a, b) return order[a] < order[b] end)
	return found
end

function goodluck_craft.trash(x, y)
	return ("image[%g,%g;0.8,0.8;creative_trash_icon.png]list[detached:trash;main;%g,%g;1,1;]"):format(x + 0.06,
		y + 0.1, x, y)
end

-- the title, the items in a scrolling grid of 9 columns as Minecraft's (the shoulder buttons scroll it, as the mouse
-- wheel does), the hotbar
local function page_formspec(player, cat, title)
	local st = state(player)
	local name = player:get_player_name()
	local items = cat == "search" and (st.filter == "" and lists.search or search(player, st.filter)) or lists[cat]
	local inv = core.get_inventory({type = "detached", name = "creative_" .. name})
	inv:set_size("main", #items)
	inv:set_list("main", items)
	local rows = math.max(ROWS, math.ceil(#items / COLS))
	local max = rows - ROWS
	local scroll = math.min(st.scroll[cat] or 0, max)
	local esc = core.formspec_escape
	local fs = {"label[0,0.05;" .. esc(title) .. "]"}
	if cat == "search" then
		fs[#fs + 1] = "field_enter_after_edit[goodluck_filter;true]field_close_on_enter[goodluck_filter;false]" ..
			"field[4.3,0.4;4.2,0.5;goodluck_filter;;" .. esc(st.filter) .. "]" ..
			"image_button[8.3,0.1;0.7,0.7;creative_clear_icon.png;goodluck_clear;]" ..
			"tooltip[goodluck_clear;" .. esc(S("Reset")) .. "]"
	end
	if #items == 0 then
		fs[#fs + 1] = "label[3.2,3.5;" .. esc(S("No items to show.")) .. "]"
	end
	fs[#fs + 1] = ("scrollbaroptions[min=0;max=%d;smallstep=%d;largestep=%d;thumbsize=%d;arrows=hide]"):format(max,
		ROWS, ROWS, math.max(1, math.floor(ROWS * ROWS / rows + 0.5)))
	fs[#fs + 1] = ("scrollbar[9.05,%g;0.45,%g;vertical;goodluck_scroll;%d]"):format(GRID_Y - 0.08, ROWS - 0.15,
		scroll)
	-- a scroll_container's place is in image sizes from the form's corner, containers included, and the elements in it
	-- get the form's padding (3/8 image) again: the grid's top-left is at 0,GRID_Y like the other elements; it scrolls by
	-- whole image sizes, which the old coordinates' row spacing isn't, so the grid's rows are spaced in image sizes too
	local top = goodluck_craft.CREATIVE_TOP
	fs[#fs + 1] = ("scroll_container[0,%g;11.45,%g;goodluck_scroll;vertical;%g]"):format(
		(top + GRID_Y) * 15 / 13 + 0.375 - top, (ROWS - 1) * 15 / 13 + 1, 15 / 13)
	fs[#fs + 1] = "style_type[list;spacing=-1,0.15385]"
	fs[#fs + 1] = ("list[detached:creative_%s;main;0,-0.325;%d,%d;]"):format(name, COLS, rows)
	fs[#fs + 1] = "style_type[list;spacing=-1,-1]"
	fs[#fs + 1] = "scroll_container_end[]"
	fs[#fs + 1] = goodluck_craft.hotbar(7.3)
	fs[#fs + 1] = ("listring[detached:creative_%s;main]listring[current_player;main]"):format(name)
	return table.concat(fs)
end

local function in_nav(self, player)
	return core.is_creative_enabled(player:get_player_name())
end

local function register(cat, title)
	sfinv.register_page("creative:" .. cat, {
		title = title,
		is_in_nav = in_nav,
		get = function(self, player, context)
			return sfinv.make_formspec(player, context, page_formspec(player, cat, title), false)
		end,
		on_player_receive_fields = function(self, player, context, fields)
			local st = state(player)
			local scroll = fields.goodluck_scroll and tonumber(fields.goodluck_scroll:match(":(%d+)"))
			if scroll then
				st.scroll[cat] = scroll
			end
			if fields.goodluck_clear then
				st.filter, st.scroll.search = "", 0
			elseif (fields.key_enter_field == "goodluck_filter" or fields.goodluck_search) and fields.goodluck_filter then
				st.filter = fields.goodluck_filter:sub(1, 128):gsub("[%z\1-\8\11-\31\127]", ""):lower()
				st.scroll.search = 0
			else
				return
			end
			sfinv.set_player_inventory_formspec(player, context)
		end,
	})
end

for _, cat in ipairs(CATEGORIES) do
	register(cat[1], cat[2])
	goodluck_craft.set_tab("creative:" .. cat[1], cat[3], cat[4], cat[5])
end
register("search", S("Search Items"))
-- an item, not an image: a selected image_button loses its picture under the open tab's style
core.register_craftitem("goodluck_craft:search_icon", {
	description = S("Search Items"),
	inventory_image = "goodluck_craft_compass.png",
	groups = {not_in_creative_inventory = 1},
})
goodluck_craft.set_tab("creative:search", "goodluck_craft:search_icon", 1, 7)

-- minetest_game's own creative tabs give way to these
for _, cat in ipairs({"all", "nodes", "tools", "craftitems"}) do
	if sfinv.pages["creative:" .. cat] then
		sfinv.override_page("creative:" .. cat, {is_in_nav = function() return false end})
	end
end
local homepage = sfinv.get_homepage_name
function sfinv.get_homepage_name(player)
	local page = homepage(player)
	return page == "creative:all" and "creative:building_blocks" or page
end
