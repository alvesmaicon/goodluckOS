-- Minecraft's End. Its way in: the enderman and its pearl, the eye of ender made of a pearl and blaze powder, which
-- leads to the nearest stronghold, and the silverfish of the strongholds' spawners (items.lua, mobs.lua); where the
-- strongholds are and how they are laid out (strongholds.lua, stronghold.lua, drawn in the map generator's threads),
-- their blocks, the end portal frame and the portal (portal.lua). The End itself, its island, pillars and crystals,
-- far over the world (realm.lua, endgen.lua in the map generator's threads), and its dragon (dragon.lua)
goodluck_end = {}
local E = goodluck_end
local path = core.get_modpath("goodluck_end")

-- the Overworld: neither the Nether nor the End
function E.overworld(pos)
	return not goodluck_nether.inside(pos) and not E.inside(pos)
end

dofile(path .. "/realm.lua")
core.register_mapgen_script(path .. "/endgen.lua")
E.strongholds = dofile(path .. "/strongholds.lua")
core.ipc_set("goodluck_end:rings", E.strongholds.rings)
core.register_mapgen_script(path .. "/stronghold.lua")
E.stronghold = dofile(path .. "/stronghold.lua")
E.strongholds.locator = E.stronghold.locator
dofile(path .. "/items.lua")
dofile(path .. "/mobs.lua")
E.spawn_endermen()
dofile(path .. "/portal.lua")
dofile(path .. "/dragon.lua")
