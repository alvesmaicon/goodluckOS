-- The nether portal as in Minecraft: an obsidian frame from 4x5 to 23x23 (corners optional) lit with flint and steel;
-- standing in it 4 s (at once in creative) takes the player to the other side, x and z divided by 8 into the Nether
-- and multiplied by 8 back, to the nearest lit portal within 16 nodes there (128 in the Overworld), or to one built
-- for them on the nearest floor with room, or on an obsidian ledge. Breaking the frame puts the portal out
local S = core.get_translator("goodluck_nether")
local R = goodluck_nether
local PORTAL, OBSIDIAN = "goodluck_nether:portal", "default:obsidian"
local MAX, WAIT = 21, 4
-- the obsidian block looks the same as obsidian with Minecraft's textures
local FRAME = {[OBSIDIAN] = true, ["default:obsidian_block"] = true}
local AXES = {x = {x = 1, y = 0, z = 0}, z = {x = 0, y = 0, z = 1}}
local storage = core.get_mod_storage()

core.register_node(PORTAL, {
	description = S("Nether Portal"),
	drawtype = "nodebox",
	node_box = {type = "fixed", fixed = {-0.5, -0.5, -2 / 16, 0.5, 0.5, 2 / 16}},
	tiles = {{name = "goodluck_nether_portal.png",
		animation = {type = "vertical_frames", aspect_w = 16, aspect_h = 16, length = 0.8}}},
	use_texture_alpha = "blend",
	backface_culling = false,
	paramtype = "light",
	paramtype2 = "facedir",
	light_source = 11,
	sunlight_propagates = true,
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = false,
	floodable = false,
	is_ground_content = false,
	drop = "",
	groups = {not_in_creative_inventory = 1},
	post_effect_color = {a = 140, r = 90, g = 10, b = 150},
	on_blast = function(pos)
		goodluck_nether.put_out(pos)
	end,
})

-- the lit portals, by the bottom left of their inside: "w,h,axis"
local portals = {}
for key, value in pairs(storage:to_table().fields) do
	local w, h, axis = value:match("^(%d+),(%d+),(%a)$")
	if w then
		portals[key] = {pos = core.string_to_pos(key), w = tonumber(w), h = tonumber(h), axis = axis}
	end
end
local function remember(p)
	local key = core.pos_to_string(p.pos)
	portals[key] = p
	storage:set_string(key, p.w .. "," .. p.h .. "," .. p.axis)
end
local function forget(pos)
	local key = core.pos_to_string(pos)
	portals[key] = nil
	storage:set_string(key, "")
end

local function open(name)
	return name == "air" or name == "fire:basic_flame" or name == PORTAL
end

-- the frame around pos along an axis: the bottom left of its inside, its width and height
local function frame(pos, axis)
	local d = AXES[axis]
	local function at(a, b, p)
		p = p or pos
		return core.get_node({x = p.x + d.x * a, y = p.y + b, z = p.z + d.z * a}).name
	end
	if not open(at(0, 0)) then
		return
	end
	local p = vector.copy(pos)
	for _ = 1, MAX do
		if not open(at(0, -1, p)) then
			break
		end
		p.y = p.y - 1
	end
	if not FRAME[at(0, -1, p)] then
		return
	end
	for _ = 1, MAX do
		if not open(at(-1, 0, p)) then
			break
		end
		p = {x = p.x - d.x, y = p.y, z = p.z - d.z}
	end
	if not FRAME[at(-1, 0, p)] then
		return
	end
	local w, h = 0, 0
	while w <= MAX and open(at(w, 0, p)) and FRAME[at(w, -1, p)] do
		w = w + 1
	end
	while h <= MAX and open(at(0, h, p)) and FRAME[at(-1, h, p)] do
		h = h + 1
	end
	if w < 2 or w > MAX or h < 3 or h > MAX or not FRAME[at(w, 0, p)] or not FRAME[at(0, h, p)] then
		return
	end
	for a = 0, w - 1 do
		if not FRAME[at(a, -1, p)] or not FRAME[at(a, h, p)] then
			return
		end
		for b = 0, h - 1 do
			if not open(at(a, b, p)) then
				return
			end
		end
	end
	for b = 0, h - 1 do
		if not FRAME[at(-1, b, p)] or not FRAME[at(w, b, p)] then
			return
		end
	end
	return {pos = p, w = w, h = h, axis = axis}
end

local function fill(p, name)
	local d = AXES[p.axis]
	for a = 0, p.w - 1 do
		for b = 0, p.h - 1 do
			core.swap_node({x = p.pos.x + d.x * a, y = p.pos.y + b, z = p.pos.z + d.z * a},
				{name = name, param2 = p.axis == "x" and 0 or 1})
		end
	end
end

local function light(p)
	fill(p, PORTAL)
	remember(p)
end

-- the whole portal a portal node belongs to goes out (its nodes, joined in its plane)
function goodluck_nether.put_out(pos)
	local node = core.get_node(pos)
	if node.name ~= PORTAL then
		return
	end
	local d = node.param2 % 2 == 0 and AXES.x or AXES.z
	local todo, seen, n, low = {pos}, {}, 0, vector.copy(pos)
	while #todo > 0 and n < (MAX + 2) ^ 2 do
		local p = table.remove(todo)
		local key = core.hash_node_position(p)
		if not seen[key] and core.get_node(p).name == PORTAL then
			seen[key], n = true, n + 1
			core.swap_node(p, {name = "air"})
			if p.y < low.y or p.y == low.y and p.x * d.x + p.z * d.z < low.x * d.x + low.z * d.z then
				low = p
			end
			for _, o in ipairs({{d.x, 0, d.z}, {-d.x, 0, -d.z}, {0, 1, 0}, {0, -1, 0}}) do
				todo[#todo + 1] = vector.offset(p, o[1], o[2], o[3])
			end
		end
	end
	forget(low)
end

-- lit by flint and steel on the frame: a fire next to the obsidian lights the frame around it, if there is one
for name in pairs(FRAME) do
	core.override_item(name, {
		on_ignite = function(pos)
			for _, o in ipairs({{0, 1, 0}, {0, -1, 0}, {1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}}) do
				local at = vector.offset(pos, o[1], o[2], o[3])
				for axis in pairs(AXES) do
					local p = frame(at, axis)
					if p then
						light(p)
						return
					end
				end
			end
		end,
		after_destruct = function(pos)
			for _, o in ipairs({{0, 1, 0}, {0, -1, 0}, {1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}}) do
				goodluck_nether.put_out(vector.offset(pos, o[1], o[2], o[3]))
			end
		end,
	})
end

-- flint and steel lights with the use button too, as in Minecraft (minetest_game's lights with the punch)
local flint = core.registered_items["fire:flint_and_steel"]
core.override_item("fire:flint_and_steel", {
	on_place = function(itemstack, user, pointed_thing)
		local node = pointed_thing.type == "node" and core.get_node(pointed_thing.under)
		local def = node and core.registered_nodes[node.name]
		if def and def.on_rightclick and not (user and user:get_player_control().sneak) then
			return def.on_rightclick(pointed_thing.under, node, user, itemstack, pointed_thing)
		end
		return flint.on_use(itemstack, user, pointed_thing)
	end,
})

-- Minecraft's y on both sides: our sea level is its 63 and the realm's floor its 0
local function to_nether_y(y)
	return R.ymin + math.max(R.sea - R.ymin + 1, math.min(120, math.floor(y) + 62))
end
local function to_overworld_y(y)
	return math.floor(y) - R.ymin - 62
end

local function nearest(target, radius, nether)
	local best, dist
	for _, p in pairs(portals) do
		if R.inside(p.pos) == nether and math.abs(p.pos.x - target.x) <= radius and
				math.abs(p.pos.z - target.z) <= radius then
			local dd = vector.distance(p.pos, target)
			if not dist or dd < dist then
				best, dist = p, dd
			end
		end
	end
	return best
end

-- where a 4x5 frame fits nearest to target: floor under its inside and frame, room for them and a step on both sides
local function spot(target, radius, ylo, yhi)
	local vm = core.get_voxel_manip()
	local e1, e2 = vm:read_from_map({x = target.x - radius - 2, y = ylo - 1, z = target.z - radius - 2},
		{x = target.x + radius + 2, y = yhi + 4, z = target.z + radius + 2})
	local area, data = VoxelArea(e1, e2), vm:get_data()
	local solid, air = {}, core.get_content_id("air")
	local function floor(i)
		local c = data[i]
		if solid[c] == nil then
			local def = core.registered_nodes[core.get_name_from_content_id(c)]
			solid[c] = def and def.walkable and def.liquidtype == "none" and not def.buildable_to or false
		end
		return solid[c]
	end
	local best, dist
	for x = target.x - radius, target.x + radius, 2 do
		for z = target.z - radius, target.z + radius, 2 do
			for y = ylo, yhi do
				local i = area:index(x, y, z)
				if data[i] == air and floor(i - area.ystride) then
					for axis, d in pairs(AXES) do
						local side = d.x == 1 and area.zstride or 1
						local step = d.x == 1 and 1 or area.zstride
						local fits = true
						for a = -1, 2 do
							local j = i + a * step
							if not floor(j - area.ystride) then
								fits = false
								break
							end
							for b = 0, 3 do
								local k = j + b * area.ystride
								if data[k] ~= air or a >= 0 and a <= 1 and b <= 2 and
										(data[k + side] ~= air or data[k - side] ~= air) then
									fits = false
									break
								end
							end
							if not fits then
								break
							end
						end
						if fits then
							local dd = vector.distance({x = x, y = y, z = z}, target)
							if not dist or dd < dist then
								best, dist = {pos = {x = x, y = y, z = z}, axis = axis}, dd
							end
						end
					end
				end
			end
		end
	end
	return best
end

-- a 4x5 frame lit at s.pos (its inside's bottom left); with no floor found, on an obsidian ledge with room cleared
local function build(s, ledge)
	local d = AXES[s.axis]
	local side = {x = d.z, y = 0, z = d.x}
	local function set(a, b, c, name)
		core.set_node({x = s.pos.x + d.x * a + side.x * c, y = s.pos.y + b, z = s.pos.z + d.z * a + side.z * c},
			{name = name})
	end
	if ledge then
		for a = -1, 2 do
			for c = -1, 1 do
				set(a, -1, c, OBSIDIAN)
				for b = 0, 3 do
					set(a, b, c, "air")
				end
			end
		end
	end
	for a = -1, 2 do
		set(a, -1, 0, OBSIDIAN)
		set(a, 3, 0, OBSIDIAN)
	end
	for b = 0, 2 do
		set(-1, b, 0, OBSIDIAN)
		set(2, b, 0, OBSIDIAN)
	end
	local p = {pos = s.pos, w = 2, h = 3, axis = s.axis}
	light(p)
	return p
end

local traveling, waited, arrived = {}, {}, {}

local function arrive(player, p)
	local d = AXES[p.axis]
	local a = math.floor((p.w - 1) / 2)
	arrived[player:get_player_name()] = true
	player:set_pos({x = p.pos.x + d.x * a, y = p.pos.y - 0.5, z = p.pos.z + d.z * a})
	core.sound_play("goodluck_nether_portal_travel", {to_player = player:get_player_name(), gain = 0.25}, true)
end

local function travel(player, from)
	local name = player:get_player_name()
	local nether = not R.inside(from)
	local target = nether and {x = math.floor(from.x / 8), y = to_nether_y(from.y), z = math.floor(from.z / 8)} or
		{x = math.floor(from.x * 8), y = to_overworld_y(from.y), z = math.floor(from.z * 8)}
	local radius = nether and 16 or 128
	local found = nearest(target, radius, nether)
	local ylo, yhi
	if found then
		target = found.pos
		ylo, yhi = target.y - 2, target.y + 4
	elseif nether then
		ylo, yhi = R.sea + 1, R.ymax - 10
	else
		target.y = core.get_spawn_level(target.x, target.z) or 2
		ylo, yhi = target.y - 16, target.y + 16
	end
	traveling[name] = true
	local r = found and 4 or 16
	core.emerge_area({x = target.x - r - 2, y = ylo - 1, z = target.z - r - 2},
		{x = target.x + r + 2, y = yhi + 4, z = target.z + r + 2}, function(_, _, left)
		if left > 0 then
			return
		end
		traveling[name] = nil
		player = core.get_player_by_name(name)
		if not player then
			return
		end
		if found and core.get_node(found.pos).name ~= PORTAL then
			forget(found.pos)
			return travel(player, from)
		end
		local p = found
		if not p then
			local s = spot(target, 16, ylo, yhi)
			p = build(s or {pos = {x = target.x, y = math.max(ylo, math.min(yhi, target.y)), z = target.z},
				axis = "x"}, not s)
		end
		arrive(player, p)
	end)
end

local function in_portal(pos)
	return core.get_node(vector.round(vector.offset(pos, 0, 0.1, 0))).name == PORTAL or
		core.get_node(vector.round(vector.offset(pos, 0, 1.2, 0))).name == PORTAL
end

local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 0.2 then
		return
	end
	local step = timer
	timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local pos = player:get_pos()
		if not in_portal(pos) then
			waited[name], arrived[name] = nil, nil
		elseif not arrived[name] and not traveling[name] then
			if not waited[name] then
				waited[name] = 0
				core.sound_play("goodluck_nether_portal_trigger", {to_player = name, gain = 0.25}, true)
			end
			waited[name] = waited[name] + step
			if waited[name] >= (core.is_creative_enabled(name) and 0 or WAIT) then
				waited[name] = nil
				travel(player, pos)
			end
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	traveling[name], waited[name], arrived[name] = nil, nil, nil
end)

-- now and then its hum and purple specks drifting out of it
core.register_abm({
	label = "Nether portal hum and specks",
	nodenames = {PORTAL},
	interval = 4,
	chance = 24,
	catch_up = false,
	action = function(pos)
		core.add_particlespawner({amount = 4, time = 4, pos = {min = vector.offset(pos, -0.5, -0.5, -0.5),
			max = vector.offset(pos, 0.5, 0.5, 0.5)}, vel = {min = vector.new(-0.6, -0.2, -0.6),
			max = vector.new(0.6, 0.6, 0.6)}, exptime = {min = 1, max = 2}, size = {min = 0.8, max = 1.6},
			glow = 11, texture = "goodluck_nether_portal_particle.png"})
		if math.random(1, 4) == 1 then
			core.sound_play("goodluck_nether_portal_ambient", {pos = pos, gain = 0.3, max_hear_distance = 16}, true)
		end
	end,
})
