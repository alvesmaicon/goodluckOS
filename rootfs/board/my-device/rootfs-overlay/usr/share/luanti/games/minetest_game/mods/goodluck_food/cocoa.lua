-- Cocoa as in Minecraft: pods on the side of jungle trunks grow in 3 ages and give cocoa beans (3 when ripe); a
-- bean on a jungle trunk grows a pod again, and beans make cookies and brown dye. Jungle trees come with a few
-- pods: their schematics get them, so the mapgen places them (no Lua while it generates)
local S = core.get_translator("goodluck_food")
-- Minecraft's pods by age, width and height in pixels, hanging from 4 pixels under the top
local SIZES = {{4, 5}, {6, 7}, {8, 9}}

local function grow(pos)
	local node = core.get_node(pos)
	local age = tonumber(node.name:sub(-1))
	-- one tick in two, as Minecraft's pods grow at a fifth of its random ticks
	if math.random(2) == 1 then
		age = age + 1
		core.swap_node(pos, {name = "goodluck_food:cocoa_" .. age, param2 = node.param2})
	end
	if age < 3 then
		core.get_node_timer(pos):start(math.random(166, 286))
	end
end

for age, size in ipairs(SIZES) do
	local w, h, back = size[1] / 32, size[2] / 16, 0.5 - 1 / 16
	core.register_node("goodluck_food:cocoa_" .. age, {
		drawtype = "nodebox",
		tiles = {"goodluck_food_cocoa_" .. age .. ".png"},
		paramtype = "light",
		paramtype2 = "facedir",
		sunlight_propagates = true,
		walkable = false,
		-- the back (+z, tile 5) faces the trunk; a stub of stem joins them
		node_box = {type = "fixed", fixed = {
			{-w, 0.25 - h, back - 2 * w, w, 0.25, back},
			{-1 / 32, 0.25 - 1 / 16, back, 1 / 32, 0.25, 0.5},
		}},
		groups = {choppy = 3, oddly_breakable_by_hand = 3, flammable = 2, attached_node = 2,
			not_in_creative_inventory = 1},
		drop = age < 3 and "goodluck_food:cocoa_beans" or "goodluck_food:cocoa_beans 3",
		sounds = default.node_sound_wood_defaults(),
		on_timer = age < 3 and grow or nil,
	})
end

-- pods the mapgen placed have no timer yet
core.register_lbm({
	name = "goodluck_food:cocoa_timer",
	nodenames = {"goodluck_food:cocoa_1", "goodluck_food:cocoa_2"},
	run_at_every_load = true,
	action = function(pos)
		local timer = core.get_node_timer(pos)
		if not timer:is_started() then
			timer:start(math.random(166, 286))
		end
	end,
})

core.register_craftitem("goodluck_food:cocoa_beans", {
	description = S("Cocoa Beans"),
	inventory_image = "goodluck_food_cocoa_beans.png",
	on_place = function(itemstack, placer, pointed_thing)
		if pointed_thing.type ~= "node" then
			return itemstack
		end
		local under = core.get_node(pointed_thing.under)
		local udef = core.registered_nodes[under.name]
		if udef and udef.on_rightclick and not (placer and placer:get_player_control().sneak) then
			return udef.on_rightclick(pointed_thing.under, under, placer, itemstack, pointed_thing) or itemstack
		end
		local name = placer and placer:get_player_name() or ""
		local dir = vector.subtract(pointed_thing.under, pointed_thing.above)
		local above = core.registered_nodes[core.get_node(pointed_thing.above).name]
		if under.name ~= "default:jungletree" or dir.y ~= 0 or not (above and above.buildable_to) or
				core.is_protected(pointed_thing.above, name) then
			return itemstack
		end
		core.set_node(pointed_thing.above, {name = "goodluck_food:cocoa_1", param2 = core.dir_to_facedir(dir)})
		core.get_node_timer(pointed_thing.above):start(math.random(166, 286))
		if not core.is_creative_enabled(name) then
			itemstack:take_item()
		end
		return itemstack
	end,
})

if core.registered_items["dye:brown"] then
	core.register_craft({
		type = "shapeless",
		output = "dye:brown",
		recipe = {"goodluck_food:cocoa_beans"},
	})
end

core.register_craftitem("goodluck_food:cookie", {
	description = S("Cookie"),
	inventory_image = "goodluck_food_cookie.png",
	groups = {food = 1},
	on_use = core.item_eat(2),
})

core.register_craft({
	output = "goodluck_food:cookie 8",
	recipe = {{"farming:wheat", "goodluck_food:cocoa_beans", "farming:wheat"}},
})

-- the jungle trees' schematics with pods on the air beside the lower trunk, now and then (prob 10 of 255, about one
-- in three trees), in all three ages, each facing its trunk (schematics turn facedir with the tree). That trunk is
-- placed over what is there (in the crowded rainforest another tree's leaves kept it out), and only a sure one:
-- the roots' nodes come and go
local function with_pods(path)
	local schem = core.read_schematic(path, {})
	if not schem then
		return path
	end
	local sx, sy, sz = schem.size.x, schem.size.y, schem.size.z
	local function index(x, y, z)
		return 1 + x + y * sx + z * sx * sy
	end
	local n = 0
	for z = 0, sz - 1 do
		for y = 1, math.min(5, sy - 1) do
			for x = 0, sx - 1 do
				local trunk = schem.data[index(x, y, z)]
				if trunk.name == "default:jungletree" and (trunk.prob or 255) >= 254 then
					trunk.force_place = true
					for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
						local px, pz = x + d[1], z + d[2]
						local i = px >= 0 and px < sx and pz >= 0 and pz < sz and index(px, y, pz)
						if i and schem.data[i].name == "air" and (schem.data[i].prob or 255) == 0 then
							n = n + 1
							schem.data[i] = {name = "goodluck_food:cocoa_" .. n % 3 + 1, prob = 10,
								param2 = core.dir_to_facedir({x = -d[1], y = 0, z = -d[2]})}
						end
					end
				end
			end
		end
	end
	return schem
end

-- Decorations can't be changed once registered: all of them go again in the same order, so each keeps its id
-- (fireflies and butterflies hold theirs), and the jungle trees with pods. Keyed by handle, see goodluck_ores
local function order(key)
	if type(key) ~= "number" then
		return math.huge
	end
	local a, b, r, bit = key % 2 ^ 18, 0x5e6f, 0, 1
	while a > 0 or b > 0 do
		if a % 2 ~= b % 2 then
			r = r + bit
		end
		a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
	end
	return r
end

local keys = {}
for key in pairs(core.registered_decorations) do
	keys[#keys + 1] = key
end
table.sort(keys, function(a, b) return order(a) < order(b) end)
local decorations = {}
for _, key in ipairs(keys) do
	local def = table.copy(core.registered_decorations[key])
	if def.name and def.name:find("^default:[%a_]*jungle_tree") and type(def.schematic) == "string" then
		def.schematic = with_pods(def.schematic)
	end
	decorations[#decorations + 1] = def
end
core.clear_registered_decorations()
for _, def in ipairs(decorations) do
	core.register_decoration(def)
end
