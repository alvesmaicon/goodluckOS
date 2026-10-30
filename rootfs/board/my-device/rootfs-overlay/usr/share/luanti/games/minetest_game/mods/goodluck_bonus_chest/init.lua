-- Minecraft's bonus chest, asked for when the world is made (the menu's "Bonus chest", world.mt's bonus_chest): the
-- first time someone comes into the world, a chest by them with torches around it, holding a map of the place (as
-- Bedrock's starting map), a stone pickaxe and axe, apples, bread, sticks, planks and logs
local WORLD = core.get_worldpath() .. "/world.mt"
local storage = core.get_mod_storage()

-- air or a plant: what the chest or a torch takes the place of
local function free(pos)
	local def = core.registered_nodes[core.get_node(pos).name]
	return def and def.buildable_to and not def.walkable and def.liquidtype == "none"
end

-- the ground a chest stands on: a full block of the land, not leaves, a trunk or planks
local function land(pos)
	local def = core.registered_nodes[core.get_node(pos).name]
	local g = def and def.groups or {}
	return def and def.walkable and def.drawtype == "normal" and not (g.leaves or g.tree or g.wood)
end

-- the land under pos, or a snow layer on it (the chest stands on the snow, as the player does)
local function ground(pos)
	local below = vector.offset(pos, 0, -1, 0)
	if land(below) then
		return true
	end
	local def = core.registered_nodes[core.get_node(below).name]
	return def and def.walkable and def.buildable_to and land(vector.offset(below, 0, -1, 0))
end

-- nothing over it: not under a tree or a ledge
local function open_sky(pos)
	for y = 1, 24 do
		local def = core.registered_nodes[core.get_node(vector.offset(pos, 0, y, 0)).name]
		if not def or def.walkable or (def.groups and def.groups.leaves) then
			return false
		end
	end
	return true
end

local AROUND = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}

-- the open ground near pos as Minecraft's bonus chest has it: each column's top on the land (not on a tree), scored
-- by flat free ground around it (the torches and room to open it), the open sky (not under a tree or a ledge), and a
-- little by how near and how level with the player it is
local function spot(pos)
	local p0 = vector.round(pos)
	local best
	for dx = -6, 6 do
		for dz = -6, 6 do
			local r = math.max(math.abs(dx), math.abs(dz))
			local p = vector.offset(p0, dx, 8, dz)
			if r >= 2 and free(p) then
				while p.y > p0.y - 12 and free(vector.offset(p, 0, -1, 0)) do
					p.y = p.y - 1
				end
				if ground(p) and free(vector.offset(p, 0, 1, 0)) then
					local score = -0.4 * r - math.abs(p.y - p0.y) + (open_sky(p) and 0 or -8)
					local torches = 0
					for i, d in ipairs(AROUND) do
						local n = vector.offset(p, d[1], 0, d[2])
						if free(n) and free(vector.offset(n, 0, 1, 0)) and ground(n) then
							score = score + (i <= 4 and 3 or 1.5)
							torches = torches + (i <= 4 and 1 or 0)
						end
					end
					if torches < 2 then
						score = score - 10
					end
					if not best or score > best.score then
						best = {pos = p, score = score}
					end
				end
			end
		end
	end
	return best and best.pos
end

local function fill(inv, pos)
	local items = {
		"default:pick_stone", "default:axe_stone", "default:apple " .. math.random(3, 5),
		"default:stick " .. math.random(6, 12), "default:wood " .. math.random(6, 12),
		"default:tree " .. math.random(2, 4), "default:torch " .. math.random(4, 8),
	}
	if core.get_modpath("farming") then
		items[#items + 1] = "farming:bread " .. math.random(1, 3)
	end
	if core.global_exists("goodluck_map") then
		table.insert(items, 1, goodluck_map.new(pos))
	end
	for _, item in ipairs(items) do
		inv:add_item("main", item)
	end
end

local function place(near)
	local pos = spot(near)
	if not pos then
		return false
	end
	core.set_node(pos, {name = "default:chest", param2 = core.dir_to_facedir(vector.direction(pos, near))})
	fill(core.get_meta(pos):get_inventory(), near)
	for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
		local t = vector.offset(pos, d[1], 0, d[2])
		if free(t) and ground(t) then
			core.set_node(t, {name = "default:torch", param2 = 1})
		end
	end
	core.log("action", "[goodluck_bonus_chest] at " .. core.pos_to_string(pos))
	return true
end

core.register_on_joinplayer(function(player)
	if storage:get_string("done") ~= "" or not Settings(WORLD):get_bool("bonus_chest", false) then
		return
	end
	-- by where they came in, once every mapchunk around is made: when the generator finishes one it writes back a
	-- block-wide edge from the copy it started with, which took a chest placed there meanwhile (a second a chunk on
	-- the console); the chest is at most 4 nodes off and an edge reaches 16 past its chunk, so 20 around
	local name = player:get_player_name()
	local tries = 0
	local function try()
		local p = core.get_player_by_name(name)
		if not p or storage:get_string("done") ~= "" then
			return
		end
		tries = tries + 1
		local near = vector.round(p:get_pos())
		core.emerge_area(vector.subtract(near, 20), vector.add(near, 20), function(_, _, remaining)
			if remaining > 0 or storage:get_string("done") ~= "" then
				return
			end
			if place(near) or tries >= 10 then
				storage:set_string("done", "1")
			else
				core.after(1, try)
			end
		end)
	end
	core.after(1, try)
end)
