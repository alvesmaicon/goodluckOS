-- Broken blocks fall to the ground in survival, and walking by an item picks it up, as in Minecraft: half a second
-- after it appears, two seconds after the player throws it (D-pad down). R1 still picks one up at once.
local PICKUP_DELAY = 0.5
local THROWN_DELAY = 2
-- Minecraft's reach: the player's box (0.6 wide, 1.77 high) grown by 1 node sideways and half a node up and down
local REACH_SIDE = 0.3 + 1
local REACH_DOWN = 0.5
local REACH_UP = 1.77 + 0.5
local FLIGHT = 0.15

-- no name text with the crosshair on an item, as in Minecraft (mob_infotext = false does it for mobs)
local item = core.registered_entities["__builtin:item"]
local set_item = item.set_item
function item.set_item(self, ...)
	set_item(self, ...)
	self.object:set_properties({infotext = ""})
end

-- builtin's handle_node_drops drops on the ground what the digger's inventory doesn't take: it gets the digger
-- without an inventory, through creative's, the lava pick's and the enchantments', which still run (all loaded before)
local handle_node_drops = core.handle_node_drops
function core.handle_node_drops(pos, drops, digger)
	if not digger or not digger:is_player() or core.is_creative_enabled(digger:get_player_name()) then
		return handle_node_drops(pos, drops, digger)
	end
	local no_inventory = setmetatable({get_inventory = function() end}, {__index = function(_, key)
		return function(_, ...)
			return digger[key](digger, ...)
		end
	end})
	return handle_node_drops(pos, drops, no_inventory)
end

-- the item flies into the player, and is gone
local function fly(obj, ent, target)
	ent.itemstring = ""
	ent:disable_physics()
	obj:set_velocity(vector.divide(vector.subtract(target, obj:get_pos()), FLIGHT))
	core.after(FLIGHT, function()
		obj:remove()
	end)
end

-- as punching it does: the item's on_pickup puts in the inventory what fits
local function pick_up(player, inv, obj, ent)
	local stack = ItemStack(ent.itemstring)
	if not inv:room_for_item("main", stack:peek_item()) then
		return
	end
	local on_pickup = stack:get_definition().on_pickup or core.item_pickup
	local left = on_pickup(ItemStack(stack), player, {type = "object", ref = obj})
	left = left and ItemStack(left)
	if not left or left:get_count() == stack:get_count() then
		return
	end
	core.sound_play("goodluck_item_drop_pop", {to_player = player:get_player_name(), gain = 0.3,
		pitch = 1 + (math.random() - math.random()) * 0.3}, true)
	if left:is_empty() then
		fly(obj, ent, vector.offset(player:get_pos(), 0, 0.5, 0))
	else
		ent:set_item(left)
	end
end

core.register_globalstep(function()
	for _, player in ipairs(core.get_connected_players()) do
		if player:get_hp() > 0 then
			local inv = player:get_inventory()
			local p = player:get_pos()
			for obj in core.objects_inside_radius(vector.offset(p, 0, 0.9, 0), 3) do
				local ent = obj:get_luaentity()
				if ent and ent.name == "__builtin:item" and ent.itemstring ~= "" and
						ent.age >= (ent.dropped_by and THROWN_DELAY or PICKUP_DELAY) then
					local o = obj:get_pos()
					local s = ent._collisionbox and ent._collisionbox[4] or 0.3
					if math.abs(o.x - p.x) < REACH_SIDE + s and math.abs(o.z - p.z) < REACH_SIDE + s and
							o.y + s > p.y - REACH_DOWN and o.y - s < p.y + REACH_UP then
						pick_up(player, inv, obj, ent)
					end
				end
			end
		end
	end
end)
