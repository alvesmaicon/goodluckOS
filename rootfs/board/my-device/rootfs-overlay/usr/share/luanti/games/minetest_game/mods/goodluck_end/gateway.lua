-- End gateways as Minecraft 26.3 has them (EnderDragonFight, TheEndGatewayBlockEntity). Each dragon killed opens
-- one of twenty in a ring of 96 about the middle, 75 up, in an order shuffled by the world's seed. The first one in
-- finds its far end: 1024 out the same way, back toward the middle past chunks of 16 with something in them, then
-- out past empty ones; the end stone with room over it nearest the world's middle in that chunk (else a small island
-- made at 75), the tallest block within 16 of it, and 10 over that a gateway back. Whoever comes through lands on the
-- tallest block within 5 of the gateway on the other side. The gateways of the highlands (endgen.lua) lead exactly
-- to Minecraft's 100, 50, 0. A player or a thrown pearl goes through; a beam shows a gateway opening or used
local S = core.get_translator("goodluck_end")
local E = goodluck_end
local G = "goodluck_end:gateway"
local YMIN = E.ymin
local storage = core.get_mod_storage()

core.register_node(G, {
	description = S("End Gateway"),
	drawtype = "glasslike",
	tiles = {{name = "goodluck_end_portal.png", animation = {type = "vertical_frames", aspect_w = 16, aspect_h = 16,
		length = 6.4}}},
	use_texture_alpha = "opaque",
	paramtype = "light",
	sunlight_propagates = true,
	light_source = core.LIGHT_MAX,
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = false,
	is_ground_content = false,
	groups = {not_in_creative_inventory = 1},
	drop = "",
	on_blast = function() end,
})

-- the purple beam, up and down from the gateway
local function beam(pos, seconds)
	core.add_particlespawner({amount = 40 * seconds, time = seconds, pos = {min = vector.offset(pos, -0.15, -6, -0.15),
		max = vector.offset(pos, 0.15, 6, 0.15)}, vel = {min = vector.new(0, -0.2, 0), max = vector.new(0, 0.2, 0)},
		exptime = {min = 0.4, max = 0.8}, size = {min = 2, max = 3.5}, glow = 14,
		texture = "goodluck_nether_portal_particle.png^[multiply:#c060ff"})
end

local function put_gateway(pos, exit, exact)
	for dx = -1, 1 do
		for dz = -1, 1 do
			for dy = -2, 2 do
				local centre = dx == 0 and dz == 0
				local name = "air"
				if centre and dy == 0 then
					name = G
				elseif dy ~= 0 and (math.abs(dy) == 2 and centre or math.abs(dy) == 1 and (dx == 0 or dz == 0)) then
					name = "goodluck_nether:bedrock"
				end
				core.set_node(vector.offset(pos, dx, dy, dz), {name = name})
			end
		end
	end
	local meta = core.get_meta(pos)
	if exit then
		meta:set_string("exit", core.pos_to_string(exit))
	end
	meta:set_int("exact", exact and 1 or 0)
	core.sound_play("tnt_explode", {pos = pos, gain = 1, max_hear_distance = 64}, true)
	beam(pos, 10)
end

-- a gateway's far side: (Minecraft's) exit, and whether it is exact
local function exit_of(pos)
	local meta = core.get_meta(pos)
	local s = meta:get_string("exit")
	if s ~= "" then
		return core.string_to_pos(s), meta:get_int("exact") == 1
	end
	-- a highlands' one, made with the map
	if pos.x * pos.x + pos.z * pos.z > 512 * 512 then
		return {x = 100, y = YMIN + 50, z = 0}, true
	end
end

-- what counts as a whole block for Minecraft's isCollisionShapeFullBlock
local full = {}
core.register_on_mods_loaded(function()
	local kinds = {normal = true, glasslike = true, glasslike_framed = true, glasslike_framed_optional = true,
		allfaces = true, allfaces_optional = true}
	for name, def in pairs(core.registered_nodes) do
		if def.walkable ~= false and kinds[def.drawtype or "normal"] then
			full[core.get_content_id(name)] = true
		end
	end
end)
local c_bedrock = core.get_content_id("goodluck_nether:bedrock")
local c_stone = core.get_content_id("goodluck_end:end_stone")
local c_air = core.CONTENT_AIR
-- the End's height that can hold blocks, from the void to over the islands' structures
local TOP = YMIN + 200

-- findTallestBlock: the highest whole block within r of pos (the column of pos too, if bedrock is allowed)
local function tallest(pos, r, bedrock)
	local vm = VoxelManip()
	local emin, emax = vm:read_from_map({x = pos.x - r, y = YMIN, z = pos.z - r}, {x = pos.x + r, y = TOP, z = pos.z + r})
	local area, data = VoxelArea(emin, emax), vm:get_data()
	local best
	for dx = -r, r do
		for dz = -r, r do
			if bedrock or dx ~= 0 or dz ~= 0 then
				for y = TOP, best and best.y + 1 or YMIN, -1 do
					local c = data[area:index(pos.x + dx, y, pos.z + dz)]
					if full[c] and (bedrock or c ~= c_bedrock) then
						best = {x = pos.x + dx, y = y, z = pos.z + dz}
						break
					end
				end
			end
		end
	end
	return best or pos
end

-- the chunk of 16 holding p, generated, then fn(its corner, whether it holds anything)
local function chunk(p, fn)
	local x0, z0 = math.floor(p.x / 16) * 16, math.floor(p.z / 16) * 16
	local lo, hi = {x = x0, y = YMIN, z = z0}, {x = x0 + 15, y = TOP, z = z0 + 15}
	core.emerge_area(lo, hi, function(_, _, left)
		if left > 0 then
			return
		end
		local vm = VoxelManip()
		local emin, emax = vm:read_from_map(lo, hi)
		local area, data = VoxelArea(emin, emax), vm:get_data()
		for i in area:iterp(lo, hi) do
			if data[i] ~= c_air then
				return fn(lo, true)
			end
		end
		fn(lo, false)
	end)
end

-- findValidSpawnInChunk: end stone with two nodes of room over it, from Minecraft's 30 up, nearest the middle
local function spawn_in(lo)
	local vm = VoxelManip()
	local hi = {x = lo.x + 15, y = TOP, z = lo.z + 15}
	local emin, emax = vm:read_from_map({x = lo.x, y = YMIN + 30, z = lo.z}, hi)
	local area, data = VoxelArea(emin, emax), vm:get_data()
	local best, near
	for z = lo.z, hi.z do
		for x = lo.x, hi.x do
			for y = YMIN + 30, TOP - 2 do
				if data[area:index(x, y, z)] == c_stone and not full[data[area:index(x, y + 1, z)]] and
						not full[data[area:index(x, y + 2, z)]] then
					local d = (x + 0.5) ^ 2 + (y - YMIN + 0.5) ^ 2 + (z + 0.5) ^ 2
					if not near or d < near then
						best, near = {x = x, y = y, z = z}, d
					end
				end
			end
		end
	end
	return best
end

-- EndIslandFeature, for a far end with no ground
local function small_island(pos)
	local f = math.random(0, 2) + 4
	local i = 0
	while f > 0.5 do
		for j = math.floor(-f), math.ceil(f) do
			for k = math.floor(-f), math.ceil(f) do
				if j * j + k * k <= (f + 1) * (f + 1) then
					core.set_node(vector.offset(pos, j, i, k), {name = "goodluck_end:end_stone"})
				end
			end
		end
		f = f - (math.random(0, 1) + 0.5)
		i = i - 1
	end
end

-- the far end of the ring's gateway at pos, then done(the gateway made there)
local function find_exit(pos, done)
	local dir = vector.normalize({x = pos.x, y = 0, z = pos.z})
	local p = vector.multiply(dir, 1024)
	local steps = 16
	local function forward()
		chunk(p, function(lo, full_)
			steps = steps - 1
			if not full_ and steps > 0 then
				p = vector.add(p, vector.multiply(dir, 16))
				return forward()
			end
			local at = spawn_in(lo)
			local around = at or {x = math.floor(p.x + 0.5), y = YMIN + 75, z = math.floor(p.z + 0.5)}
			core.emerge_area({x = around.x - 16, y = YMIN, z = around.z - 16},
					{x = around.x + 16, y = TOP + 12, z = around.z + 16}, function(_, _, left)
				if left > 0 then
					return
				end
				if not at then
					core.log("action", ("[goodluck_end] no ground for the gateway at %s: a small island at %s"):format(
						core.pos_to_string(pos), core.pos_to_string(around)))
					small_island(around)
					at = around
				end
				local gate = vector.offset(tallest(at, 16, true), 0, 10, 0)
				put_gateway(gate, pos, false)
				done(gate)
			end)
		end)
	end
	local function back()
		chunk(p, function(_, full_)
			steps = steps - 1
			if full_ and steps > 0 then
				p = vector.subtract(p, vector.multiply(dir, 16))
				return back()
			end
			steps = 16
			forward()
		end)
	end
	back()
end

-- through a gateway: to its exit (found the first time), else nothing
local cooldown = {}
local function enter(player, pos)
	local name = player:get_player_name()
	if E.travelling[name] or (cooldown[name] or 0) > core.get_us_time() then
		return
	end
	local function go(exit, exact)
		E.travelling[name] = nil
		if not player:is_valid() then
			return
		end
		local to = exact and exit or vector.offset(tallest(vector.offset(exit, 0, 2, 0), 5, false), 0, 1, 0)
		core.log("action", ("[goodluck_end] %s goes through the gateway at %s to %s"):format(name,
			core.pos_to_string(pos), core.pos_to_string(to)))
		beam(pos, 2)
		cooldown[name] = core.get_us_time() + 2000000
		E.arrive(player, to)
	end
	E.travelling[name] = true
	local exit, exact = exit_of(pos)
	if exit then
		return core.emerge_area({x = exit.x - 5, y = YMIN, z = exit.z - 5}, {x = exit.x + 5, y = TOP, z = exit.z + 5},
				function(_, _, left)
			if left == 0 then
				go(exit, exact)
			end
		end)
	end
	find_exit(pos, function(gate)
		core.get_meta(pos):set_string("exit", core.pos_to_string(gate))
		core.log("action", ("[goodluck_end] the gateway at %s leads to %s"):format(core.pos_to_string(pos),
			core.pos_to_string(gate)))
		go(gate, false)
	end)
end
E.enter_gateway = enter

-- a player whose box touches a gateway
local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < 0.25 then
		return
	end
	timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		local pos = player:get_pos()
		if E.inside(pos) and player:get_hp() > 0 then
			local box = player:get_properties().collisionbox
			local lo = vector.round(vector.offset(pos, box[1], box[2], box[3]))
			local hi = vector.round(vector.offset(pos, box[4], box[5], box[6]))
			local found = core.find_nodes_in_area(lo, hi, G)
			if found[1] then
				enter(player, found[1])
			end
		end
	end
end)
core.register_on_leaveplayer(function(player)
	cooldown[player:get_player_name()] = nil
end)

-- now and then the beam, as Minecraft's gateways flash every two minutes
core.register_abm({
	label = "end gateway beam",
	nodenames = {G},
	interval = 120,
	chance = 1,
	catch_up = false,
	action = function(pos)
		beam(pos, 2)
	end,
})

-- the ring's gateways, in the order the world's seed shuffles them
local function ring()
	local s = storage:get_string("gateways")
	if s ~= "" then
		return s:split(",")
	end
	local order = {}
	for i = 0, 19 do
		order[#order + 1] = tostring(i)
	end
	local pr = PcgRandom(((tonumber(core.get_mapgen_setting("seed")) or 0) + 9541) % 2147483647)
	for i = #order, 2, -1 do
		local j = pr:next(1, i)
		order[i], order[j] = order[j], order[i]
	end
	return order
end
function E.spawn_gateway()
	local order = ring()
	local i = tonumber(table.remove(order))
	if not i then
		return
	end
	storage:set_string("gateways", table.concat(order, ","))
	local a = 2 * (-math.pi + 0.15707963267948966 * i)
	local pos = {x = math.floor(96 * math.cos(a)), y = YMIN + 75, z = math.floor(96 * math.sin(a))}
	core.emerge_area(vector.offset(pos, -1, -2, -1), vector.offset(pos, 1, 2, 1), function(_, _, left)
		if left == 0 then
			put_gateway(pos, nil, false)
			core.log("action", ("[goodluck_end] an end gateway opens at %s"):format(core.pos_to_string(pos)))
		end
	end)
end
