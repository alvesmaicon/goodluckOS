-- Minecraft's shapes for the chest, the bed, the sign, the minecart, the boat, the arrow, the farm animals
-- (animals.lua), the horses, the spider, the zombie, the skeleton and the villager (meshes goodluck_horse,
-- goodluck_monsters and goodluck_villages wear), so that its textures fit them: the player's own through
-- goodluck_mcassets, else Pixel Perfection's (chest, minecart, boat, arrow, animals, horses, monsters, villager) and
-- goodluckOS' own (bed, sign). Meshes drawn by dev/luanti-art/models.py and animals.py
local M = "goodluck_models_"

-- chests: a pixel in from every side and 14 high; open, the lid stands up on its hinge at the back
local CHEST = {type = "fixed", fixed = {-7/16, -1/2, -7/16, 7/16, 6/16, 7/16}}
local OPEN = {type = "fixed", fixed = {-7/16, -1/2, -7/16, 7/16, 2/16, 7/16}}
local function chest(name, mesh, texture, open)
	if core.registered_nodes[name] then
		core.override_item(name, {drawtype = "mesh", mesh = M .. mesh .. (open and "_open" or "") .. ".obj",
			tiles = {M .. texture .. ".png"}, paramtype = "light", selection_box = open and OPEN or CHEST,
			collision_box = open and OPEN or CHEST})
	end
end
for _, base in ipairs({"default:chest", "default:chest_locked"}) do
	chest(base, "chest", "chest")
	chest(base .. "_open", "chest", "chest", true)
end
for _, half in ipairs({"left", "right"}) do
	chest("goodluck_chest:" .. half, "chest_" .. half, "chest_" .. half)
	chest("goodluck_chest:" .. half .. "_open", "chest_" .. half, "chest_" .. half, true)
end

-- beds: the mattress from 3 to 9 pixels up and a leg under each corner at the bed's ends, every face its own
-- texture as Minecraft's (+Y, -Y, +X, -X, +Z, -Z; the head is toward +Z, where the bed points); the legs' inner
-- faces take an end's texture, which has legs where they stand
local MATTRESS = {-1/2, -5/16, -1/2, 1/2, 1/16, 1/2}
local BEDS = {["beds:bed"] = "red", ["beds:fancy_bed"] = "blue"}
for bed, colour in pairs(BEDS) do
	local c = M .. "bed_" .. colour .. "_"
	if core.registered_nodes[bed .. "_bottom"] then
		core.override_item(bed .. "_bottom", {
			node_box = {type = "fixed", fixed = {MATTRESS, {-1/2, -1/2, -1/2, -5/16, -5/16, -5/16},
				{5/16, -1/2, -1/2, 1/2, -5/16, -5/16}}},
			tiles = {c .. "foot_up.png", M .. "bed_down.png", c .. "foot_east.png", c .. "foot_west.png",
				c .. "foot_south.png", c .. "foot_south.png"},
		})
		core.override_item(bed .. "_top", {
			node_box = {type = "fixed", fixed = {MATTRESS, {-1/2, -1/2, 5/16, -5/16, -5/16, 1/2},
				{5/16, -1/2, 5/16, 1/2, -5/16, 1/2}}},
			tiles = {c .. "head_up.png", M .. "bed_down.png", c .. "head_east.png", c .. "head_west.png",
				M .. "bed_head_north.png", M .. "bed_head_north.png"},
		})
	end
end

-- signs: Minecraft's board, on a wall as before, and on the floor standing on its post, turned the way the player
-- looks in sixteenths of a turn (paramtype2 degrotate: 240 steps)
for _, material in ipairs({"wood", "steel"}) do
	local wall = "default:sign_wall_" .. material
	local def = core.registered_nodes[wall]
	if def then
		local texture = M .. "sign_" .. material .. ".png"
		local standing = "goodluck_models:sign_standing_" .. material
		local sdef = table.copy(def)
		sdef.drawtype, sdef.mesh, sdef.tiles = "mesh", M .. "sign_standing.obj", {texture}
		sdef.paramtype2, sdef.node_box, sdef.legacy_wallmounted = "degrotate", nil, nil
		sdef.selection_box = {type = "fixed", fixed = {-1/2, -1/2, -1/16, 1/2, 9/16, 1/16}}
		sdef.drop = wall
		sdef.groups = table.copy(def.groups)
		sdef.groups.not_in_creative_inventory, sdef.groups.attached_node = 1, 1
		core.register_node(":" .. standing, sdef)
		local place = def.on_place or core.item_place
		core.override_item(wall, {
			drawtype = "mesh",
			mesh = M .. "sign_wall.obj",
			tiles = {texture},
			selection_box = {type = "wallmounted", wall_side = {-1/2, -1/4, -1/2, -7/16, 1/4, 1/2},
				wall_bottom = {-1/2, -1/2, -1/4, 1/2, -7/16, 1/4}, wall_top = {-1/2, 7/16, -1/4, 1/2, 1/2, 1/4}},
			on_place = function(itemstack, placer, pointed_thing)
				local under, above = pointed_thing.under, pointed_thing.above
				if pointed_thing.type ~= "node" or not placer or above.y <= under.y then
					return place(itemstack, placer, pointed_thing)
				end
				local turn = math.floor(placer:get_look_horizontal() / (2 * math.pi) * 16 + 0.5) % 16
				local _, placed = core.item_place_node(ItemStack(standing), placer, pointed_thing, turn * 15)
				if placed and not core.is_creative_enabled(placer:get_player_name()) then
					itemstack:take_item()
				end
				return itemstack
			end,
		})
	end
end

-- the minecart
local cart = core.registered_entities["carts:cart"]
if cart then
	cart.initial_properties.mesh = M .. "minecart.obj"
	cart.initial_properties.textures = {M .. "minecart.png"}
	core.override_item("carts:cart", {inventory_image = M .. "minecart_item.png", wield_image = M .. "minecart_item.png"})
end

-- the boat and the bow's arrow, at 0.9 of its pixels as Minecraft's renderer draws it
local boat = core.registered_entities["boats:boat"]
if boat then
	boat.initial_properties.mesh = M .. "boat.glb"
	boat.initial_properties.textures = {M .. "boat.png"}
end
local arrow = core.registered_entities["x_bows:arrow_entity"]
if arrow then
	arrow.initial_properties.mesh = M .. "arrow.glb"
	arrow.initial_properties.textures = {M .. "arrow.png"}
	arrow.initial_properties.visual_size = {x = 0.9, y = 0.9}
end

if core.get_modpath("mobs_animal") then
	dofile(core.get_modpath("goodluck_models") .. "/animals.lua")
end
