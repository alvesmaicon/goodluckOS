-- Running with the head under water swims, as in Minecraft: lying face down in a 0.6 box with the eyes at 0.4,
-- going where the player looks (the engine's physics override swim) until the player leaves the water or lets go.
-- Breath is Minecraft's too.
local BOX = {-0.3, 0.0, -0.3, 0.3, 0.6, 0.3}
local EYE = 0.4
-- out of the water the pose stays while there is no room to stand, crawling as slow as sneaking
local CRAWL = 0.3
-- the body turns about the hips, lowered to the middle of the box
local HIPS = vector.new(0, 3, -3)
local TURN = 0.2

local water = {}
core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_nodes) do
		if def.liquidtype ~= "none" and (def.groups.water or 0) > 0 then
			water[name] = true
		end
	end
	-- every player model (3d_armor's too) swims with its walk
	for name, model in pairs(player_api.registered_models) do
		local walk = model.animations.walk
		if walk then
			model.animations.swim = {x = walk.x, y = walk.y, eye_height = EYE, collisionbox = BOX}
			player_api.register_model(name, model)
		end
	end
end)

local function stand_eye(player)
	local model = player_api.registered_models[player_api.get_animation(player).model or ""]
	return model and model.eye_height or 1.47
end

local swimming, lying, pitch = {}, {}, {}
-- breath as in Minecraft, in ticks: 15 s under water, then 2 HP a second; back 4 times as fast
local AIR, DROWN, BACK = 300, 20, 4
local air = {}

goodluck_swim = {}

function goodluck_swim.lying(player)
	return lying[player:get_player_name()] or false
end

local function in_water(pos)
	return water[core.get_node(pos).name] or false
end

local function room_to_stand(pos)
	for _, dy in ipairs({0.75, 1.25, 1.7}) do
		local def = core.registered_nodes[core.get_node(vector.offset(pos, 0, dy, 0)).name]
		if not def or def.walkable then
			return false
		end
	end
	return true
end

-- face down and tilted with the look, the head raised 45 degrees, as Minecraft's swimmer
local function pose(player, look)
	player:set_bone_override("Body", {
		position = {vec = HIPS, absolute = true, interpolation = TURN},
		rotation = {vec = vector.new(math.pi / 2 + look, 0, 0), absolute = true, interpolation = TURN}})
	player:set_bone_override("Head", {
		rotation = {vec = vector.new(-math.pi / 4, 0, 0), absolute = true, interpolation = TURN}})
end

local function lie(player, name, on)
	lying[name] = on or nil
	if on then
		pitch[name] = player:get_look_vertical()
		player_api.set_animation(player, "swim", 20)
		pose(player, pitch[name])
	else
		pitch[name] = nil
		player:set_bone_override("Body", nil)
		player:set_bone_override("Head", nil)
	end
end

-- player_api's animations (and so its box) leave the lying players alone
local attached = player_api.player_attached
local animate = player_api.globalstep
function player_api.globalstep(...)
	for name in pairs(lying) do
		if not attached[name] then
			attached[name] = "swim"
		end
	end
	animate(...)
	for name in pairs(lying) do
		if attached[name] == "swim" then
			attached[name] = false
		end
	end
end

local crawling = {}

-- the bubbles show whole, ten for the full breath
local function breathe(player, name, eye, dtime)
	local was = air[name] or AIR
	local now = was
	if eye and not core.is_creative_enabled(name) and not player:get_armor_groups().immortal then
		now = was - dtime * 20
		if now <= -DROWN then
			now = 0
			player:set_hp(player:get_hp() - 2, {type = "drown"})
		end
	else
		now = math.min(was + dtime * 20 * BACK, AIR)
	end
	air[name] = now
	local bubbles = math.max(0, math.ceil(now / AIR * core.PLAYER_MAX_BREATH_DEFAULT))
	if bubbles ~= player:get_breath() then
		player:set_breath(bubbles)
	end
end

local function fresh(player)
	air[player:get_player_name()] = AIR
	player:set_breath(core.PLAYER_MAX_BREATH_DEFAULT)
end

core.register_on_joinplayer(function(player)
	player:set_flags({breathing = false, drowning = false})
	player:set_properties({breath_max = core.PLAYER_MAX_BREATH_DEFAULT})
	fresh(player)
end)
core.register_on_respawnplayer(fresh)

core.register_globalstep(function(dtime)
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local pos = player:get_pos()
		local feet = in_water(pos)
		local wet = feet or in_water(vector.offset(pos, 0, 0.5, 0))
		local eye = in_water(vector.offset(pos, 0, lying[name] and EYE or stand_eye(player), 0))
		if player:get_hp() > 0 then
			breathe(player, name, eye, dtime)
		end
		local free = player:get_hp() > 0 and not attached[name]
		local run = free and goodluck_sprint.running(player)
		local swim
		if swimming[name] then
			swim = run and wet
		else
			swim = run and eye and feet
		end
		-- as in Minecraft, no run starts or goes on with the feet in water and the head out
		goodluck_sprint.stop(player, wet and not eye and not swim, "water")
		if swim ~= (swimming[name] or false) then
			swimming[name] = swim or nil
			player:set_physics_override({swim = swim})
		end
		local down = free and (swim or (lying[name] and not room_to_stand(pos))) or false
		if down ~= (lying[name] or false) then
			lie(player, name, down)
		elseif down and math.abs(player:get_look_vertical() - pitch[name]) > 0.1 then
			pitch[name] = player:get_look_vertical()
			pose(player, pitch[name])
		end
		local crawl = down and not wet
		if crawl ~= (crawling[name] or false) then
			crawling[name] = crawl or nil
			player:set_physics_override({speed_walk = crawl and CRAWL or 1})
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	swimming[name], lying[name], pitch[name], crawling[name], air[name] = nil, nil, nil, nil, nil
end)
