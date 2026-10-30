-- Crops as in Minecraft: dry farmland grows them too, about half as fast (MTG: wet only, so a crop away from water
-- stops at its first stage); they need light 9 from the sky or a torch, so they grow by night too (MTG: 13 at the
-- moment); picked before they are ripe they give their seed back (MTG: 1 in 8 at the first stage)
local LIGHT = 9
-- a tick that fails retries in 40-80 s, so 1 in 4 makes a dry stage ~1.8 times as long as a wet one (226 s)
local DRY = 0.25

function farming.can_grow(pos)
	local soil = core.get_item_group(core.get_node(vector.offset(pos, 0, -1, 0)).name, "soil")
	if soil < 2 then
		return false
	end
	local light = math.max(core.get_natural_light(pos, 0.5) or 0, core.get_artificial_light(core.get_node(pos).param1))
	return light >= LIGHT and (soil >= 3 or math.random() < DRY)
end

core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_nodes) do
		if def.on_timer == farming.grow_plant and def.minlight and core.get_item_group(name, "seed") == 0 then
			-- can_grow checks the light now: MTG's own check reads the light of the moment, and its top (14) kept
			-- crops from growing in full sun (15)
			local over = {minlight = 0, maxlight = 15}
			local mod, plant = name:match("^(.-):(.-)_%d+$")
			if def.next_plant and mod and core.registered_items[mod .. ":seed_" .. plant] then
				over.drop = mod .. ":seed_" .. plant
			end
			core.override_item(name, over)
		end
	end
end)
