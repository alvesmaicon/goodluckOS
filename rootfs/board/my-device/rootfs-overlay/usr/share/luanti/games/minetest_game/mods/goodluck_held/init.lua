-- The item in hand on the player seen from outside, as Minecraft draws it: a block as a small block, anything else
-- as its image with depth, in the right hand. One entity a player, on the right arm's bone of the character model,
-- hidden in first person (the engine draws the arm there) and told the item whenever it changes
local BONE = "Arm_Right"
-- Minecraft's third-person right hand: a block turned 75 and 45 degrees at 0.375 of its size, an item flat at 0.55
-- (a wielditem at visual_size 0.667 is a node's size); at the hand, down the arm's bone
local BLOCK = {size = 0.375 * 0.667, pos = {x = 0, y = 4.5, z = 0.5}, rot = {x = 75, y = 45, z = 0}}
local ITEM = {size = 0.55 * 0.667, pos = {x = 0, y = 5.5, z = 1}, rot = {x = 0, y = 0, z = 0}}

local held = {}

core.register_entity("goodluck_held:item", {
	initial_properties = {
		visual = "wielditem", wield_item = "", visual_size = {x = BLOCK.size, y = BLOCK.size},
		physical = false, pointable = false, static_save = false, is_visible = false,
	},
	-- an orphan (its player gone while it was saved) goes
	on_activate = function(self)
		core.after(0, function()
			if self.object:is_valid() and not self.object:get_attach() then
				self.object:remove()
			end
		end)
	end,
})

-- shown as the item is: a node as a block, else flat; nothing for an empty hand
local function show(player, name)
	local h = held[player:get_player_name()]
	if not h or not h.object:is_valid() then
		return
	end
	local def = core.registered_items[name]
	if not def or name == "" then
		h.object:set_properties({is_visible = false})
	else
		local look = def.type == "node" and (def.inventory_image or "") == "" and BLOCK or ITEM
		h.object:set_properties({wield_item = name, visual_size = {x = look.size, y = look.size}, is_visible = true})
		h.object:set_attach(player, BONE, look.pos, look.rot, false)
	end
	h.name = name
end

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	core.after(0, function()
		if not player:is_valid() then
			return
		end
		local obj = core.add_entity(player:get_pos(), "goodluck_held:item")
		if not obj then
			return
		end
		held[name] = {object = obj, name = nil}
		obj:set_attach(player, BONE, ITEM.pos, ITEM.rot, false)
		show(player, player:get_wielded_item():get_name())
	end)
end)

core.register_on_leaveplayer(function(player)
	local h = held[player:get_player_name()]
	if h and h.object:is_valid() then
		h.object:remove()
	end
	held[player:get_player_name()] = nil
end)

-- a name compared a step: the entity is touched only when the hand changes
core.register_globalstep(function()
	for _, player in ipairs(core.get_connected_players()) do
		local h = held[player:get_player_name()]
		if h then
			local name = player:get_wielded_item():get_name()
			if name ~= h.name then
				show(player, name)
			end
		end
	end
end)
