-- Dev tool, not shipped: shot.sh takes a screenshot at each "showcase:" log line
local W = 24

local function list(t, skip)
	local out = {}
	for name, def in pairs(t) do
		if name ~= "" and not skip[name] and not (def.groups or {}).not_in_creative_inventory then out[#out + 1] = name end
	end
	table.sort(out)
	return out
end

local function look(player, pos, yaw, pitch, mark)
	player:set_pos(pos)
	player:set_look_horizontal(yaw)
	player:set_look_vertical(pitch)
	core.after(3, core.log, "action", "showcase: " .. mark)
end

core.register_on_joinplayer(function(player)
	player:set_physics_override({gravity = 0, speed = 0})
	player:hud_set_flags({crosshair = false, hotbar = false, healthbar = false, breathbar = false, wielditem = false})
	core.set_timeofday(0.5)
	local nodes = list(core.registered_nodes, {air = true, ignore = true})
	local items = list(core.registered_items, {})
	local rows = math.ceil(#nodes / W)
	core.emerge_area({x = -4, y = -4, z = -4}, {x = W + 4, y = rows + 4, z = rows + 8}, function(_, _, left)
		if left > 0 then return end
		for i, n in ipairs(nodes) do
			local x, r = (i - 1) % W, math.floor((i - 1) / W)
			core.set_node({x = x, y = 0, z = r}, {name = n})
			core.set_node({x = x, y = rows - r, z = rows + 4}, {name = n})
		end
		look(player, {x = W / 2, y = rows + 8, z = -6}, 0, 0.9, "floor")
		core.after(8, look, player, {x = W / 2, y = rows / 2, z = rows - 16}, 0, 0, "wall")
		core.after(16, function()
			local fs = {"formspec_version[6]size[24,13]bgcolor[#202020;true]"}
			for i, n in ipairs(items) do
				local x, y = (i - 1) % 24, math.floor((i - 1) / 24)
				fs[#fs + 1] = ("item_image[%d,%d;1,1;%s]"):format(x, y, n)
			end
			core.show_formspec(player:get_player_name(), "showcase", table.concat(fs))
			core.after(3, core.log, "action", "showcase: items")
		end)
	end)
end)
