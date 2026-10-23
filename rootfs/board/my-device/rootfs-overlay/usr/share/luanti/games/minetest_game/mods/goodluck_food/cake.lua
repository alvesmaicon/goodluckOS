-- The cake as in Minecraft: placed, it is eaten in 7 bites of 2 points from its west side, only when not full;
-- broken, it gives nothing
local S = core.get_translator("goodluck_food")

local function bite(pos, node, clicker)
	if not clicker or not clicker:is_player() then
		return
	end
	-- do_item_eat takes the item only when it eats (stamina refuses when the bar is full)
	local stack = core.do_item_eat(2, nil, ItemStack("goodluck_food:cake"), clicker, {type = "node", under = pos})
	if stack and stack:is_empty() then
		local bites = core.get_item_group(node.name, "cake_bites") + 1
		if bites < 7 then
			core.swap_node(pos, {name = "goodluck_food:cake_" .. bites})
		else
			core.remove_node(pos)
		end
	end
end

for bites = 0, 6 do
	local west = -7 / 16 + bites * 2 / 16
	local cut = bites > 0 and "goodluck_food_cake_inner.png" or "goodluck_food_cake_side.png"
	core.register_node(bites == 0 and "goodluck_food:cake" or "goodluck_food:cake_" .. bites, {
		description = S("Cake"),
		inventory_image = "goodluck_food_cake.png",
		wield_image = "goodluck_food_cake.png",
		drawtype = "nodebox",
		tiles = {"goodluck_food_cake_top.png", "goodluck_food_cake_bottom.png", "goodluck_food_cake_side.png", cut,
			"goodluck_food_cake_side.png", "goodluck_food_cake_side.png"},
		use_texture_alpha = "clip",
		paramtype = "light",
		node_box = {type = "fixed", fixed = {west, -0.5, -7 / 16, 7 / 16, 0, 7 / 16}},
		stack_max = 1,
		drop = "",
		is_ground_content = false,
		groups = {food = 1, oddly_breakable_by_hand = 3, attached_node = 1, cake_bites = bites,
			not_in_creative_inventory = bites > 0 and 1 or nil},
		sounds = default.node_sound_wood_defaults(),
		on_rightclick = bite,
	})
end

if core.registered_items["mobs:bucket_milk"] and core.registered_items["mobs:egg"] then
	local milk, sugar, wheat = "mobs:bucket_milk", "goodluck_food:sugar", "farming:wheat"
	core.register_craft({
		output = "goodluck_food:cake",
		recipe = {
			{milk, milk, milk},
			{sugar, "mobs:egg", sugar},
			{wheat, wheat, wheat},
		},
		replacements = {{milk, "bucket:bucket_empty"}, {milk, "bucket:bucket_empty"}, {milk, "bucket:bucket_empty"}},
	})
end
