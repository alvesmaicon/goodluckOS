-- Coal as in Minecraft: MTG's veins are 8 ores scattered over a 3x3x3 cube, so a cave wall shows 3 or 4 of them, and
-- there is none above y 64, in the mountains; here the same number of veins holds 16 (a wall shows 6 or 7, Minecraft's
-- 17-size coal ~9) up to the floatlands. Ores can't be changed once registered: all of them go again, in order (the
-- list is keyed by handle: its low 18 bits are the index, XORed with the low bits of OBJDEF_HANDLE_SALT, 0x5e6f)
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

local ores = {}
for _, key in ipairs(keys) do
	local def = table.copy(core.registered_ores[key])
	if def.ore == "default:stone_with_coal" and def.y_max == 64 then
		def.clust_num_ores = 16
		def.y_max = 1024
	end
	ores[#ores + 1] = def
end
core.clear_registered_ores()
for _, def in ipairs(ores) do
	core.register_ore(def)
end
