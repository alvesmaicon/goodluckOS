-- Minecraft's bonus chest, asked for when the world is made (the menu's "Bonus chest", world.mt's bonus_chest): the
-- first time someone comes into the world, a chest by them with torches around it, holding a map of the place (as
-- Bedrock's starting map), a stone pickaxe and axe, apples, bread, sticks, planks and logs
local WORLD = core.get_worldpath() .. "/world.mt"
local storage = core.get_mod_storage()

local function free(pos)
	local def = core.registered_nodes[core.get_node(pos).name]
	return def and def.buildable_to and not def.walkable and def.liquidtype == "none"
end

local function ground(pos)
	local def = core.registered_nodes[core.get_node(vector.offset(pos, 0, -1, 0)).name]
	return def and def.walkable
end

-- a free spot on the ground near pos, not where the player stands
local function spot(pos)
	local p0 = vector.round(pos)
	for r = 2, 4 do
		for dx = -r, r do
			for dz = -r, r do
				for dy = 1, -2, -1 do
					local p = vector.offset(p0, dx, dy, dz)
					if (math.abs(dx) == r or math.abs(dz) == r) and free(p) and ground(p) and
							free(vector.offset(p, 0, 1, 0)) then
						return p
					end
				end
			end
		end
	end
end

local function fill(inv, player)
	local items = {
		"default:pick_stone", "default:axe_stone", "default:apple " .. math.random(3, 5),
		"default:stick " .. math.random(6, 12), "default:wood " .. math.random(6, 12),
		"default:tree " .. math.random(2, 4), "default:torch " .. math.random(4, 8),
	}
	if core.get_modpath("farming") then
		items[#items + 1] = "farming:bread " .. math.random(1, 3)
	end
	if core.global_exists("goodluck_map") then
		table.insert(items, 1, goodluck_map.new(player:get_pos()))
	end
	for _, item in ipairs(items) do
		inv:add_item("main", item)
	end
end

local function place(player)
	local pos = spot(player:get_pos())
	if not pos then
		return false
	end
	core.set_node(pos, {name = "default:chest", param2 = core.dir_to_facedir(vector.direction(pos,
		player:get_pos()))})
	fill(core.get_meta(pos):get_inventory(), player)
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
	-- once the ground around is there
	local name = player:get_player_name()
	local tries = 0
	local function try()
		local p = core.get_player_by_name(name)
		tries = tries + 1
		if p and storage:get_string("done") == "" and (place(p) or tries >= 10) then
			storage:set_string("done", "1")
		elseif p and tries < 10 then
			core.after(1, try)
		end
	end
	core.after(1, try)
end)
