-- The End cities in the game, once a mapchunk of one is made: its chests filled from Minecraft's
-- chests/end_city_treasure (2 to 6 draws by its weights; this game's items for its own, the spear, the copper horse
-- armor and the spire trim it lacks left out), the iron and diamond tools and armor enchanted as at a table with 15
-- bookshelves (Minecraft's levels 20 to 39); a shulker at each of Minecraft's sentry places; the ship's brewing stand
-- with two Instant Health II potions and its item frame with the elytra
local E = goodluck_end
local SEED = (tonumber(core.get_mapgen_setting("seed")) or 0) % 2147483647
local ELYTRA = "goodluck_elytra:elytra"

local LOOT = {
	{"default:diamond", 2, 7, 5}, {"default:steel_ingot", 4, 8, 10}, {"default:gold_ingot", 2, 7, 15},
	{"goodluck_emerald:emerald", 2, 6, 2}, {"goodluck_food:beetroot_seeds", 1, 10, 5}, {"mobs:saddle", 1, 1, 3},
	{"goodluck_horse:armor_iron", 1, 1, 1}, {"goodluck_horse:armor_gold", 1, 1, 1},
	{"goodluck_horse:armor_diamond", 1, 1, 1},
}
for _, metal in ipairs({"diamond", "steel"}) do
	for _, name in ipairs({"default:sword_", "3d_armor:boots_", "3d_armor:chestplate_", "3d_armor:leggings_",
			"3d_armor:helmet_", "default:pick_", "default:shovel_"}) do
		LOOT[#LOOT + 1] = {name .. metal, 1, 1, 3, true}
	end
end
core.register_on_mods_loaded(function()
	for i = #LOOT, 1, -1 do
		if not core.registered_items[LOOT[i][1]] then
			table.remove(LOOT, i)
		end
	end
end)

local function fill(pos)
	local inv = core.get_meta(pos):get_inventory()
	local pr = PcgRandom((SEED + core.hash_node_position(pos)) % 2147483647)
	local total, free = 0, {}
	for _, e in ipairs(LOOT) do
		total = total + e[4]
	end
	for i = 1, inv:get_size("main") do
		free[i] = i
	end
	for _ = 1, pr:next(2, 6) do
		local roll = pr:next(1, total)
		for _, e in ipairs(LOOT) do
			roll = roll - e[4]
			if roll <= 0 then
				local stack = ItemStack(e[1] .. " " .. pr:next(e[2], e[3]))
				if e[5] and goodluck_enchanting then
					stack = goodluck_enchanting.enchant(e[1], 15)
				end
				inv:set_stack("main", table.remove(free, pr:next(1, #free)), stack)
				break
			end
		end
	end
end
E.city_loot = fill

local function wallmounted(d)
	return d.x == 1 and 2 or d.x == -1 and 3 or d.z == 1 and 4 or 5
end

local logged = {}
core.set_gen_notify({custom = true}, nil, {"goodluck_end:city"})
core.register_on_generated(function(minp)
	local notes = core.get_mapgen_object("gennotify")
	local made = notes and notes.custom and notes.custom["goodluck_end:city"]
	if not made then
		return
	end
	for _, c in ipairs(made.chests) do
		core.set_node(c, {name = "default:chest", param2 = core.dir_to_facedir({x = -c.dx, y = 0, z = -c.dz})})
		fill(c)
	end
	for _, p in ipairs(made.shulkers) do
		core.add_entity(p, "goodluck_end:shulker")
	end
	for _, f in ipairs(made.frames) do
		core.set_node(f, {name = "goodluck_end:item_frame", param2 = wallmounted({x = -f.dx, z = -f.dz})})
		if core.registered_items[ELYTRA] then
			E.frame_set(f, ItemStack(ELYTRA))
		end
	end
	for _, s in ipairs(made.stands) do
		core.set_node(s, {name = "goodluck_potions:brewing_stand"})
		local inv = core.get_meta(s):get_inventory()
		inv:set_stack("bottles", 1, "goodluck_potions:strong_healing")
		inv:set_stack("bottles", 3, "goodluck_potions:strong_healing")
		core.swap_node(s, {name = "goodluck_potions:brewing_stand_5"})
	end
	for _, key in ipairs(made.cities) do
		if not logged[key] then
			logged[key] = true
			local x, z = key:match("^(-?%d+),(-?%d+)$")
			local start = E.cities.start(math.floor((tonumber(x) - 7) / 320), math.floor((tonumber(z) - 7) / 320))
			local city = start and E.city.layout(start)
			if city then
				local ship = city.ship
				core.log("action", ("[goodluck_end] End city at %d,%d,%d (%s, turn %d): %d pieces, %s"):format(start.x,
					start.y, start.z, start.biome, start.rot, #city.pieces, ship and ("a ship at %d,%d,%d"):format(
					ship.x, ship.y, ship.z) or "no ship"))
			end
		end
	end
	core.log("action", ("[goodluck_end] End city chunk %d,%d,%d: %d pieces, %d ms (walk %d, data %d, draw %d, write"
		.. " %d with %d turned, light %d), %d chests, %d shulkers"):format(minp.x, minp.y, minp.z, made.pieces,
		(made.walk + made.read + made.draw + made.write + made.light) / 1000, made.walk / 1000, made.read / 1000,
		made.draw / 1000, made.write / 1000, made.turned, made.light / 1000, #made.chests, #made.shulkers))
end)
