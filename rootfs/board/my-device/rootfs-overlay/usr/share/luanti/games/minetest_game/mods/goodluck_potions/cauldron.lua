-- The cauldron (seven iron ingots), as Minecraft's: a bucket of water fills it and an empty bucket takes a full one
-- back; as on Bedrock it also keeps potions, three bottles' worth of one kind: a bottle, of water or of a potion, goes
-- in, an empty bottle comes out with one, and another kind spoils what is in it. Broken, it keeps nothing
local S = core.get_translator("goodluck_potions")
local N = "goodluck_potions:"
local P = goodluck_potions
local EMPTY, BOTTLE = N .. "cauldron", "vessels:glass_bottle"
local WATER = {["bucket:bucket_water"] = true, ["bucket:bucket_river_water"] = true}
local T = "goodluck_potions_cauldron_"
local TILES = {T .. "side.png", T .. "top.png", T .. "bottom.png", T .. "inner.png"}

-- walls 2 high around a floor 4 up, as Minecraft's: you can stand in it
local BOX = {type = "fixed", fixed = {{-0.5, -0.5, -0.5, 0.5, -0.25, 0.5}, {-0.5, -0.25, -0.5, -0.375, 0.5, 0.5},
	{0.375, -0.25, -0.5, 0.5, 0.5, 0.5}, {-0.375, -0.25, -0.5, 0.375, 0.5, -0.375},
	{-0.375, -0.25, 0.375, 0.375, 0.5, 0.5}}}

local function creative(user)
	return user and core.is_creative_enabled(user:get_player_name())
end

-- the node of a content and level, or the empty cauldron
function P.cauldron(id, level)
	return level and level > 0 and N .. "cauldron_" .. id .. "_" .. level or EMPTY
end

local function give(user, itemstack, item)
	if creative(user) then
		return itemstack
	end
	itemstack:take_item()
	if itemstack:is_empty() then
		return ItemStack(item)
	end
	local left = user:get_inventory():add_item("main", item)
	if not left:is_empty() then
		core.add_item(user:get_pos(), left)
	end
	return itemstack
end

local function rightclick(pos, node, user, itemstack)
	if not user or not user:is_player() or core.is_protected(pos, user:get_player_name()) then
		return itemstack
	end
	local def = core.registered_nodes[node.name]
	local id, level = def._cauldron, def._level or 0
	local name = itemstack:get_name()
	local item = core.registered_items[name] or {}
	local function set(to_id, to_level, sound)
		core.swap_node(pos, {name = P.cauldron(to_id, to_level)})
		core.sound_play(sound, {pos = pos, gain = 0.5, max_hear_distance = 16}, true)
	end
	if WATER[name] and (level == 0 or id == "water") then
		set("water", 3, "goodluck_potions_fill")
		return give(user, itemstack, "bucket:bucket_empty")
	elseif name == "bucket:bucket_empty" and id == "water" and level == 3 then
		set(nil, 0, "goodluck_potions_fill")
		return give(user, itemstack, "bucket:bucket_water")
	elseif name == BOTTLE and level > 0 then
		set(id, level - 1, "goodluck_potions_fill")
		return give(user, itemstack, N .. id)
	elseif item._potion and not item._splash then
		if level == 0 or id == item._potion and level < 3 then
			set(item._potion, level + 1, "goodluck_potions_fill")
			return give(user, itemstack, BOTTLE)
		elseif id ~= item._potion then
			-- as on Bedrock: another kind spoils it all
			set(nil, 0, "fire_extinguish_flame")
			core.add_particlespawner({amount = 12, time = 0.3, pos = {min = vector.offset(pos, -0.3, 0.3, -0.3),
				max = vector.offset(pos, 0.3, 0.5, 0.3)}, vel = {min = vector.new(-0.2, 0.5, -0.2),
				max = vector.new(0.2, 1, 0.2)}, exptime = {min = 0.5, max = 1}, size = {min = 2, max = 4},
				texture = "tnt_smoke.png"})
			return give(user, itemstack, BOTTLE)
		end
	end
	return itemstack
end

local base = {
	drawtype = "mesh",
	paramtype = "light",
	sunlight_propagates = false,
	selection_box = {type = "regular"},
	collision_box = BOX,
	groups = {cracky = 2},
	drop = EMPTY,
	sounds = default.node_sound_metal_defaults(),
	on_rightclick = rightclick,
}

local empty = table.copy(base)
empty.description = S("Cauldron")
empty.mesh, empty.tiles = "goodluck_models_cauldron.obj", TILES
empty.inventory_image, empty.wield_image = T .. "item.png", T .. "item.png"
core.register_node(EMPTY, empty)

for _, id in ipairs(P.order) do
	for level = 1, 3 do
		local def = table.copy(base)
		def.description = S("Cauldron")
		def.mesh = "goodluck_models_cauldron_" .. level .. ".obj"
		def.tiles = table.copy(TILES)
		def.tiles[5] = T .. "content.png^[multiply:" .. P.potions[id].color
		def.groups = {cracky = 2, not_in_creative_inventory = 1}
		def._cauldron, def._level = id, level
		core.register_node(P.cauldron(id, level), def)
	end
end

local I = "default:steel_ingot"
core.register_craft({output = EMPTY, recipe = {{I, "", I}, {I, "", I}, {I, I, I}}})
