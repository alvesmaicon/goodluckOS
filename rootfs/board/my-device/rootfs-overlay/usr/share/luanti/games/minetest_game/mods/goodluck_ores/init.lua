-- Ores as in Minecraft before 1.18 (1.8 to 1.17): its veins' size, how many a 16x16 column has and at what height
-- (its sea level, 63, is ours at 1: y here = Minecraft's - 62), and on down below, where a Minecraft world ends at
-- bedrock (Minetest Game had iron from y -128, gold from -256, diamonds from -1024). A Minecraft vein, spheres along
-- a line, is matched by a scatter cluster of the same mean size that shows as many ores on a wall: coal (size 17,
-- ~22 ores) 22 in 3x3x3, iron and gold (9, ~7) 7 in 2x2x2, diamond (8, ~6) 6 in 2x2x2. Lapis is goodluck_lapis'.
-- The floatlands' ores stay, and so do tin, copper and mese, which Minecraft didn't have
local SEA = 62
local CLASSIC = {
	["default:stone_with_coal"] = {size = 3, ores = 22, veins = 20, top = 128},
	["default:stone_with_iron"] = {size = 2, ores = 7, veins = 20, top = 64},
	["default:stone_with_gold"] = {size = 2, ores = 7, veins = 2, top = 32},
	["default:stone_with_diamond"] = {size = 2, ores = 6, veins = 1, top = 16},
}
local FLOATLANDS = 1025

-- Ores can't be changed once registered: all of them go again, in order (the list is keyed by handle: its low 18
-- bits are the index, XORed with the low bits of OBJDEF_HANDLE_SALT, 0x5e6f)
local keys = {}
for key in pairs(core.registered_ores) do
	keys[#keys + 1] = key
end
local function index(key)
	if type(key) ~= "number" then
		return math.huge
	end
	local a, b, r, bit = key % 2 ^ 18, 0x5e6f, 0, 1
	while a > 0 or b > 0 do
		if a % 2 ~= b % 2 then
			r = r + bit
		end
		a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
	end
	return r
end
table.sort(keys, function(a, b) return index(a) < index(b) end)

-- each ore's Minetest Game bands below the floatlands make way for one, where the first of them was
local ores, done = {}, {}
for _, key in ipairs(keys) do
	local def = core.registered_ores[key]
	local c = CLASSIC[def.ore]
	if c and def.y_min < FLOATLANDS then
		if not done[def.ore] then
			done[def.ore] = true
			ores[#ores + 1] = {
				ore_type = "scatter",
				ore = def.ore,
				wherein = "default:stone",
				clust_scarcity = math.floor(16 * 16 * c.top / c.veins),
				clust_num_ores = c.ores,
				clust_size = c.size,
				y_max = c.top - SEA,
				y_min = -31000,
			}
		end
	else
		ores[#ores + 1] = table.copy(def)
	end
end
core.clear_registered_ores()
for _, def in ipairs(ores) do
	core.register_ore(def)
end
