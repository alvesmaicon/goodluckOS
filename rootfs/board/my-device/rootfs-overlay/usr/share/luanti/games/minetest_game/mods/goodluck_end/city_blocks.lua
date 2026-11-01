-- The End cities' other blocks: magenta stained glass (eight glass about a magenta dye), the dragon head (on a floor,
-- or on a wall as on the ship's prow; worn on the head, as the carved pumpkin, with no armor points) and the item frame,
-- which shows the item put in it (use; used again, it turns it an eighth), gives it back to a punch and breaks on the
-- next; the ship's holds the elytra
local S = core.get_translator("goodluck_end")
local E = goodluck_end

core.register_node("goodluck_end:magenta_stained_glass", {
	description = S("Magenta Stained Glass"),
	drawtype = "glasslike",
	tiles = {"goodluck_end_magenta_stained_glass.png"},
	use_texture_alpha = "blend",
	paramtype = "light",
	sunlight_propagates = true,
	is_ground_content = false,
	groups = {cracky = 3, oddly_breakable_by_hand = 3},
	-- glass breaks to nothing, as in Minecraft without silk touch
	drop = "",
	sounds = default.node_sound_glass_defaults(),
})
core.register_craft({output = "goodluck_end:magenta_stained_glass 8", recipe = {
	{"default:glass", "default:glass", "default:glass"}, {"default:glass", "dye:magenta", "default:glass"},
	{"default:glass", "default:glass", "default:glass"}}})

-- The dragon head: Minecraft's DragonHeadModel on the dragon's texture, turned four ways; its box as a skull's
local HEAD = "goodluck_end:dragon_head"
local head = {
	description = S("Dragon Head"),
	drawtype = "mesh",
	mesh = "goodluck_models_dragon_head.obj",
	tiles = {"goodluck_end_dragon.png"},
	use_texture_alpha = "clip",
	paramtype = "light",
	paramtype2 = "facedir",
	selection_box = {type = "fixed", fixed = {-4 / 16, -0.5, -4 / 16, 4 / 16, 0, 4 / 16}},
	collision_box = {type = "fixed", fixed = {-4 / 16, -0.5, -4 / 16, 4 / 16, 0, 4 / 16}},
	groups = {cracky = 3, oddly_breakable_by_hand = 2},
	is_ground_content = false,
	drop = HEAD,
	sounds = default.node_sound_stone_defaults(),
	on_place = function(itemstack, placer, pointed)
		if pointed.type ~= "node" then
			return itemstack
		end
		local d = vector.subtract(pointed.above, pointed.under)
		if d.y == 0 then
			local wall = ItemStack(itemstack)
			wall:set_name(HEAD .. "_wall")
			local left = core.item_place_node(wall, placer, pointed, core.dir_to_facedir(d))
			itemstack:set_count(left:get_count())
			return itemstack
		end
		local look = placer and placer:get_look_dir() or vector.new(0, 0, 1)
		return core.item_place_node(itemstack, placer, pointed, core.dir_to_facedir(vector.multiply(look, -1)))
	end,
}
if core.global_exists("armor") then
	head.groups.armor_head = 1
	head.armor_groups = {fleshy = 0}
	head.texture = "goodluck_end_dragon_head_worn.png"
	head.preview = ""
end
core.register_node(HEAD, head)
local wall = table.copy(head)
wall.description = S("Dragon Wall Head")
wall.mesh = "goodluck_models_dragon_wall_head.obj"
wall.selection_box = {type = "fixed", fixed = {-4 / 16, -4 / 16, -0.5, 4 / 16, 4 / 16, 0}}
wall.collision_box = wall.selection_box
wall.groups = {cracky = 3, oddly_breakable_by_hand = 2, not_in_creative_inventory = 1}
wall.on_place = nil
core.register_node(HEAD .. "_wall", wall)

-- The item frame: its block on the face it was put on, the item an entity a pixel off its back
local FRAME, ITEM = "goodluck_end:item_frame", "goodluck_end:frame_item"
local function back(param2)
	return core.wallmounted_to_dir(param2 % 8)
end
local function find(pos)
	for _, obj in ipairs(core.get_objects_inside_radius(pos, 0.6)) do
		local ent = obj:get_luaentity()
		if ent and ent.name == ITEM then
			return obj
		end
	end
end
local function show(pos)
	local old = find(pos)
	if old then
		old:remove()
	end
	local meta = core.get_meta(pos)
	local item = meta:get_string("item")
	if item == "" then
		return
	end
	local d = back(core.get_node(pos).param2)
	local obj = core.add_entity(vector.add(pos, vector.multiply(d, 0.5 - 1.5 / 16)), ITEM, ItemStack(item):get_name())
	if obj then
		local roll = meta:get_int("rot") * math.pi / 4
		if d.y ~= 0 then
			obj:set_rotation(vector.new(d.y * math.pi / 2, 0, roll))
		else
			obj:set_rotation(vector.new(0, core.dir_to_yaw(vector.multiply(d, -1)), roll))
		end
	end
end
function E.frame_set(pos, stack)
	core.get_meta(pos):set_string("item", stack and not stack:is_empty() and stack:to_string() or "")
	show(pos)
end

core.register_entity(ITEM, {
	initial_properties = {
		visual = "wielditem",
		visual_size = {x = 0.3, y = 0.3},
		physical = false,
		pointable = false,
		collisionbox = {0, 0, 0, 0, 0, 0},
		static_save = false,
	},
	on_activate = function(self, staticdata)
		if staticdata == "" then
			self.object:remove()
			return
		end
		self.object:set_properties({wield_item = staticdata})
	end,
})

local function sound(pos, name)
	core.sound_play(name, {pos = pos, gain = 1, max_hear_distance = 16}, true)
end
local BOX = {type = "wallmounted", wall_bottom = {-6 / 16, -0.5, -6 / 16, 6 / 16, -7 / 16, 6 / 16},
	wall_top = {-6 / 16, 7 / 16, -6 / 16, 6 / 16, 0.5, 6 / 16}, wall_side = {-0.5, -6 / 16, -6 / 16, -7 / 16, 6 / 16, 6 / 16}}
core.register_node(FRAME, {
	description = S("Item Frame"),
	drawtype = "mesh",
	mesh = "goodluck_models_item_frame.obj",
	tiles = {"default_aspen_wood.png", "goodluck_end_item_frame.png"},
	inventory_image = "goodluck_end_item_frame_item.png",
	wield_image = "goodluck_end_item_frame_item.png",
	paramtype = "light",
	paramtype2 = "wallmounted",
	sunlight_propagates = true,
	walkable = false,
	selection_box = BOX,
	groups = {choppy = 3, oddly_breakable_by_hand = 3, attached_node = 1},
	is_ground_content = false,
	sounds = default.node_sound_wood_defaults(),
	after_place_node = function(pos)
		sound(pos, "goodluck_end_item_frame_place")
	end,
	on_rightclick = function(pos, _, clicker, itemstack)
		local name = clicker and clicker:get_player_name() or ""
		if core.is_protected(pos, name) then
			return itemstack
		end
		local meta = core.get_meta(pos)
		if meta:get_string("item") ~= "" then
			meta:set_int("rot", (meta:get_int("rot") + 1) % 8)
			show(pos)
			sound(pos, "goodluck_end_item_frame_rotate")
		elseif not itemstack:is_empty() then
			local one = ItemStack(itemstack)
			one:set_count(1)
			meta:set_int("rot", 0)
			E.frame_set(pos, one)
			sound(pos, "goodluck_end_item_frame_add")
			if not core.is_creative_enabled(name) then
				itemstack:take_item()
			end
		end
		return itemstack
	end,
	on_punch = function(pos, node, puncher, pointed)
		local meta = core.get_meta(pos)
		local item = meta:get_string("item")
		if item == "" or core.is_protected(pos, puncher and puncher:get_player_name() or "") then
			return core.node_punch(pos, node, puncher, pointed)
		end
		E.frame_set(pos, nil)
		local d = back(node.param2)
		core.add_item(vector.add(pos, vector.multiply(d, 0.2)), item)
		sound(pos, "goodluck_end_item_frame_remove")
	end,
	-- only once its item is out
	can_dig = function(pos)
		return core.get_meta(pos):get_string("item") == ""
	end,
	on_destruct = function(pos)
		local obj = find(pos)
		if obj then
			obj:remove()
		end
	end,
	after_dig_node = function(pos)
		sound(pos, "goodluck_end_item_frame_break")
	end,
	on_blast = function(pos)
		local item = core.get_meta(pos):get_string("item")
		core.remove_node(pos)
		core.add_item(pos, FRAME)
		if item ~= "" then
			core.add_item(pos, item)
		end
	end,
})
core.register_craft({output = FRAME, recipe = {{"default:stick", "default:stick", "default:stick"},
	{"default:stick", "mobs:leather", "default:stick"}, {"default:stick", "default:stick", "default:stick"}}})
core.register_lbm({
	label = "Item frames show their items",
	name = "goodluck_end:frame_items",
	nodenames = {FRAME},
	run_at_every_load = true,
	action = function(pos)
		if core.get_meta(pos):get_string("item") ~= "" and not find(pos) then
			show(pos)
		end
	end,
})
