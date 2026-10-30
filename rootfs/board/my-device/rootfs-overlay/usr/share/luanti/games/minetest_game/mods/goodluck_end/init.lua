-- Minecraft's End. Its way in first: the enderman and its pearl, the eye of ender made of a pearl and blaze powder,
-- which leads to the nearest stronghold, and the silverfish of the strongholds' spawners (items.lua, mobs.lua); where
-- the strongholds are (strongholds.lua)
goodluck_end = {}
local path = core.get_modpath("goodluck_end")

-- the Overworld: neither the Nether nor the End
function goodluck_end.overworld(pos)
	return not goodluck_nether.inside(pos) and not (goodluck_end.inside and goodluck_end.inside(pos))
end

goodluck_end.strongholds = dofile(path .. "/strongholds.lua")
dofile(path .. "/items.lua")
dofile(path .. "/mobs.lua")
