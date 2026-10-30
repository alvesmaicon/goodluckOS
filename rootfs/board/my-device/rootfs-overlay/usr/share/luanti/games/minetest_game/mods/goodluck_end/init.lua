-- Minecraft's End. Its way in first: the enderman and its pearl, the eye of ender made of a pearl and blaze powder,
-- which leads to the nearest stronghold, and the silverfish of the strongholds' spawners (items.lua, mobs.lua); where
-- the strongholds are and how they are laid out (strongholds.lua, stronghold.lua, drawn in the map generator's
-- threads), their blocks, the end portal frame and the portal (portal.lua)
goodluck_end = {}
local E = goodluck_end
local path = core.get_modpath("goodluck_end")

-- the Overworld: neither the Nether nor the End
function E.overworld(pos)
	return not goodluck_nether.inside(pos) and not (E.inside and E.inside(pos))
end

E.strongholds = dofile(path .. "/strongholds.lua")
core.ipc_set("goodluck_end:rings", E.strongholds.rings)
core.register_mapgen_script(path .. "/stronghold.lua")
E.stronghold = dofile(path .. "/stronghold.lua")
E.strongholds.locator = E.stronghold.locator
dofile(path .. "/items.lua")
dofile(path .. "/mobs.lua")
dofile(path .. "/portal.lua")
