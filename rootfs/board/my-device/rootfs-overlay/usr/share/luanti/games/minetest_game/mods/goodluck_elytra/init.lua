-- Minecraft's elytra and firework rocket. Worn in the chest's slot (in place of a chestplate, no armor points, no wear
-- from hits), jump pressed again in the air glides: the engine flies the player as Minecraft does (physics override
-- glide, patch 0046) and tells the server (control glide), which lays the player along the flight in a 0.6 box, spreads
-- the wings on the back and wears the elytra a use a second (432; it stops gliding with 1 left and shows broken; two
-- make one again at the anvil). A rocket used while gliding boosts as Minecraft's does (glide_boost), used on a block
-- it flies up and pops
local S = core.get_translator("goodluck_elytra")
local ELYTRA = "goodluck_elytra:elytra"
local ROCKET = "goodluck_elytra:firework_rocket"
local WINGS = "goodluck_elytra:wings"
local USES, WEAR = 432, 65535
-- Minecraft's fall flying pose: a 0.6 box, the eyes at 0.4, lying along the look about the feet, the head raised 45
-- degrees; the pose comes in over half a second, then follows the look
local BOX = {-0.3, 0.0, -0.3, 0.3, 0.6, 0.3}
local EYE = 0.4
local HIPS = 6.75
local RAMP, TURN = 0.5, 0.2
-- the wings on the body's bone: its top, behind the back (the mesh's own offset), at the player model's scale
local WINGS_POS, WINGS_ROT, WINGS_SIZE = vector.new(0, HIPS, 0), vector.new(0, 180, 0), 0.9
-- the wings' animation frames (dev/luanti-art/elytra.py): 0-1 spreading, 1-2 folding, 2-3 crouching, 3-4 standing,
-- a whole change in Minecraft's time to get most of the way (0.3 of what is left a tick)
local SPREAD_SPEED = 1 / 0.35
local swim = core.get_modpath("goodluck_swim") and goodluck_swim
local anvil = core.get_modpath("goodluck_anvil") and goodluck_anvil
local effects = core.get_modpath("goodluck_effects") and goodluck_effects
local sprint = core.get_modpath("goodluck_sprint") and goodluck_sprint

goodluck_elytra = {}

local function creative(player)
	return core.is_creative_enabled(player:get_player_name())
end

-- ---- the elytra: its uses kept as the tool's wear ----------------------------------------------------------------
local function used(stack)
	return math.floor(stack:get_wear() * USES / WEAR + 0.5)
end

-- as Minecraft's: no glide when the next use would break it, and its broken look
local function broken(stack)
	return used(stack) >= USES - 1
end

local function look(stack)
	local meta = stack:get_meta()
	local image = broken(stack) and "goodluck_elytra_elytra_broken.png" or ""
	if meta:get_string("inventory_image") ~= image then
		meta:set_string("inventory_image", image)
		meta:set_string("wield_image", image)
	end
	return stack
end

local function equip(itemstack, player, pointed_thing)
	if pointed_thing and pointed_thing.type == "node" and player and not player:get_player_control().sneak then
		local node = core.get_node(pointed_thing.under)
		local def = core.registered_nodes[node.name]
		if def and def.on_rightclick then
			return def.on_rightclick(pointed_thing.under, node, player, itemstack, pointed_thing)
		end
	end
	return armor:equip(player, itemstack)
end

-- 3d_armor's piece for the chest with nothing drawn on the skin: the wings are a mesh of their own
core.register_tool(ELYTRA, {
	description = S("Elytra"),
	inventory_image = "goodluck_elytra_elytra.png",
	groups = {armor_torso = 1, armor_heal = 0, armor_use = 0},
	armor_groups = {fleshy = 0},
	texture = "",
	preview = "",
	on_place = equip,
	on_secondary_use = equip,
})

-- two at the anvil: both durabilities and 12 % more (goodluck_anvil), and the look that has
if anvil then
	local calc = anvil.calc
	function anvil.calc(...)
		local r = calc(...)
		if r and r.out and r.out:get_name() == ELYTRA then
			look(r.out)
		end
		return r
	end
end

-- ---- the glide ------------------------------------------------------------------------------------------------------
-- a player wearing an elytra: its slot, whether it may glide, whether it does, for how long, its pose, wings and wind
local P = {}

core.register_on_mods_loaded(function()
	for name, model in pairs(player_api.registered_models) do
		local stand = model.animations.stand
		if stand then
			model.animations.glide = {x = stand.x, y = stand.y, eye_height = EYE, collisionbox = BOX}
			player_api.register_model(name, model)
		end
	end
end)

-- player_api leaves a gliding player's animation (and so its box) alone
local attached = player_api.player_attached
local animate = player_api.globalstep
function player_api.globalstep(...)
	for name, st in pairs(P) do
		if st.gliding and not attached[name] then
			attached[name] = "glide"
		end
	end
	animate(...)
	for name in pairs(P) do
		if attached[name] == "glide" then
			attached[name] = false
		end
	end
end

-- the body face down, tilted a quarter turn and the pitch about the feet (its bone turned half a turn first, as the
-- model has it)
local function pose(player, pitch, time)
	local a = math.pi / 2 + pitch
	player:set_bone_override("Body", {
		position = {vec = vector.new(0, HIPS * math.cos(a), HIPS * math.sin(a)), absolute = true, interpolation = time},
		rotation = {vec = vector.new(math.pi - a, 0, math.pi), absolute = true, interpolation = time}})
	player:set_bone_override("Head", {
		rotation = {vec = vector.new(math.pi / 4, 0, 0), absolute = true, interpolation = time}})
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

-- the wings' pose: "fold", "crouch" or the glide's spread (0 to 1), played from the one they have
local function wings(st, kind, f)
	local obj = st.wings
	if not obj or not obj:is_valid() then
		return
	end
	local from, to
	local was, at = st.wing_kind, st.wing_f or 0
	if kind == "spread" then
		if was == "spread" then
			if math.abs(f - at) < 0.05 then
				return
			end
			from, to = f > at and at or 2 - at, f > at and f or 2 - f
		else
			from, to = 0, f
		end
	elseif kind == was then
		return
	elseif kind == "crouch" then
		from, to = 2, 3
	elseif was == "spread" then
		from, to = 2 - at, 2
	else
		from, to = 3, 4
	end
	st.wing_kind, st.wing_f = kind, f
	obj:set_animation({x = from, y = to}, SPREAD_SPEED, 0, false)
end

local function add_wings(player, st)
	if st.wings and st.wings:is_valid() then
		return
	end
	local obj = core.add_entity(player:get_pos(), WINGS)
	if obj then
		obj:set_attach(player, "Body", WINGS_POS, WINGS_ROT, false)
		obj:set_animation({x = 0, y = 0}, 0, 0, false)
		st.wings, st.wing_kind, st.wing_f = obj, "fold", 0
	end
end

-- Minecraft's wind: louder with the speed squared, silent for the first second and coming in over the next
local function wind(player, st)
	local v = vector.length(player:get_velocity()) / 20
	local gain = 0.6 * math.min(v * v / 4, 1) * math.min(math.max(st.time - 1, 0), 1)
	if not st.sound then
		st.sound = core.sound_play("goodluck_elytra_wind", {to_player = player:get_player_name(), gain = 0.0001,
			loop = true})
		st.gain = 0.0001
	end
	if math.abs(gain - st.gain) > 0.02 then
		core.sound_fade(st.sound, math.max(math.abs(gain - st.gain) * 4, 0.01), math.max(gain, 0.0001))
		st.gain = gain
	end
end

local function set_gliding(player, st, on)
	st.gliding = on or nil
	-- as in Minecraft, no run starts while gliding (nor drains hunger)
	if sprint then
		sprint.stop(player, on, "elytra")
	end
	if on then
		st.time, st.wear_time, st.pitch = 0, 0, player:get_look_vertical()
		player_api.set_animation(player, "glide")
		-- from standing (a bone's first override can't ease in), into the glide's pose
		player:set_bone_override("Body", {position = {vec = vector.new(0, HIPS, 0), absolute = true},
			rotation = {vec = vector.new(math.pi, 0, math.pi), absolute = true}})
		player:set_bone_override("Head", {rotation = {vec = vector.zero(), absolute = true}})
		pose(player, st.pitch, RAMP)
		return
	end
	if st.sound then
		core.sound_stop(st.sound)
		st.sound = nil
	end
	wings(st, "fold")
	-- a glide ending in a gap 1 high (or into the water running) lies on as Minecraft's crawl (goodluck_swim)
	if swim and (swim.lying(player) or not room_to_stand(player:get_pos())) then
		swim.lie_down(player)
	else
		player:set_bone_override("Body", nil)
		player:set_bone_override("Head", nil)
		player_api.set_animation(player, "stand")
	end
end

local function slot(player)
	local inv = core.get_inventory({type = "detached", name = player:get_player_name() .. "_armor"})
	if not inv then
		return
	end
	for i, stack in ipairs(inv:get_list("armor")) do
		if stack:get_name() == ELYTRA then
			return i, stack
		end
	end
end

-- what lets the engine glide: an elytra worn that won't break, being alive and not levitating (the effect checked
-- each step, as it comes and goes)
local function levitating(player)
	return effects and effects.get(player, "levitation") ~= nil
end

local function allow(player, st)
	local can = st.ok and not levitating(player)
	if can ~= st.can then
		st.can = can
		player:set_physics_override({glide = can})
	end
end

local function update(player)
	local name = player:get_player_name()
	local i, stack = slot(player)
	local st = P[name]
	if not i then
		if st then
			if st.gliding then
				set_gliding(player, st, false)
			end
			if st.wings and st.wings:is_valid() then
				st.wings:remove()
			end
			P[name] = nil
			player:set_physics_override({glide = false})
		end
		return
	end
	if not st then
		st = {}
		P[name] = st
	end
	st.index = i
	add_wings(player, st)
	st.ok = not broken(stack) and player:get_hp() > 0
	allow(player, st)
end
goodluck_elytra.update = update

function goodluck_elytra.gliding(player)
	local st = P[player:get_player_name()]
	return st and st.gliding or false
end

armor:register_on_update(update)
core.register_on_dieplayer(update)
core.register_on_respawnplayer(update)
armor:register_on_equip(function(player, _, stack)
	if stack:get_name() == ELYTRA then
		core.sound_play("goodluck_elytra_equip", {to_player = player:get_player_name(), gain = 1}, true)
	end
end)

-- a use each 20 ticks of gliding (none in creative), the look changing when it gets to 1 left
local function wear(player, st)
	if creative(player) then
		return
	end
	local inv = core.get_inventory({type = "detached", name = player:get_player_name() .. "_armor"})
	local stack = inv and inv:get_stack("armor", st.index)
	if not stack or stack:get_name() ~= ELYTRA then
		return
	end
	stack:set_wear(math.min(math.floor((used(stack) + 1) * WEAR / USES + 0.5), WEAR))
	armor:set_inventory_stack(player, st.index, look(stack))
	if broken(stack) then
		update(player)
	end
end

core.register_globalstep(function(dtime)
	for name, st in pairs(P) do
		local player = core.get_player_by_name(name)
		if player then
			allow(player, st)
			-- the wings go with a block left unloaded behind a teleport (a portal): put on again
			add_wings(player, st)
			local ctrl = player:get_player_control()
			local gliding = st.can and ctrl.glide or false
			if gliding ~= (st.gliding or false) then
				set_gliding(player, st, gliding)
			end
			if gliding then
				st.time = st.time + dtime
				st.wear_time = st.wear_time + dtime
				while st.wear_time >= 1 do
					st.wear_time = st.wear_time - 1
					wear(player, st)
				end
				local pitch = player:get_look_vertical()
				if math.abs(pitch - st.pitch) > 0.1 then
					st.pitch = pitch
					pose(player, pitch, st.time < RAMP and RAMP - st.time or TURN)
				end
				-- spread as Minecraft's: all the way unless diving, folding as the dive gets steep
				local v = player:get_velocity()
				local speed = vector.length(v)
				wings(st, "spread", v.y < 0 and speed > 0 and 1 - (-v.y / speed) ^ 1.5 or 1)
				wind(player, st)
			else
				wings(st, ctrl.sneak and "crouch" or "fold")
			end
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local st = P[player:get_player_name()]
	if st and st.wings and st.wings:is_valid() then
		st.wings:remove()
	end
	P[player:get_player_name()] = nil
end)

core.register_entity(WINGS, {
	initial_properties = {
		visual = "mesh", mesh = "goodluck_models_elytra.glb", textures = {"goodluck_elytra_wings.png"},
		visual_size = {x = WINGS_SIZE, y = WINGS_SIZE, z = WINGS_SIZE}, backface_culling = false,
		physical = false, pointable = false, static_save = false,
	},
	-- an orphan (its player gone while it was saved) goes
	on_activate = function(self)
		core.after(0, function()
			if self.object:is_valid() and not self.object:get_attach() then
				self.object:remove()
			end
		end)
	end,
})

-- ---- the firework rocket ------------------------------------------------------------------------------------------
-- paper and 1 to 3 gunpowder make 3 rockets of that flight duration; a rocket lives 10 ticks a level and one more,
-- and 0 to 11 more at random
local GUNPOWDER = "tnt:gunpowder"

local function lifetime(flight)
	return 10 * (flight + 1) + math.random(0, 5) + math.random(0, 6)
end

-- the trail: Minecraft's sparks, a tick apart, falling back from the rocket and dying in about a second
local function trail(spec, ticks)
	core.add_particlespawner({
		amount = ticks, time = ticks / 20, minvel = {x = -1, y = -3, z = -1}, maxvel = {x = 1, y = -1, z = 1},
		minexptime = 0.6, maxexptime = 1.2, minsize = 1, maxsize = 1.5, glow = 14,
		texture = {name = "goodluck_elytra_spark.png", animation = {type = "vertical_frames", aspect_w = 8,
			aspect_h = 8, length = -1}},
		attached = spec.attached, minpos = spec.pos or vector.zero(), maxpos = spec.pos or vector.zero(),
	})
end

local function boost(player, stack, flight)
	local ticks = lifetime(flight) + 1
	player:set_physics_override({glide_boost = ticks})
	core.sound_play("goodluck_elytra_launch", {pos = player:get_pos(), gain = 1, max_hear_distance = 48}, true)
	trail({attached = player, pos = vector.new(0, 0.3, 0)}, ticks)
	if not creative(player) then
		stack:take_item()
	end
	return stack
end

-- a block's own use first, as in Minecraft; then with the elytra spread from the hand, or else from the block's face
local function use(flight)
	return function(stack, user, pointed)
		if not user or not user:is_player() then
			return
		end
		local node = pointed and pointed.type == "node" and core.get_node(pointed.under)
		local def = node and core.registered_nodes[node.name]
		if def and def.on_rightclick and not user:get_player_control().sneak then
			return def.on_rightclick(pointed.under, node, user, stack, pointed)
		end
		if goodluck_elytra.gliding(user) then
			return boost(user, stack, flight)
		end
		if not node then
			return
		end
		local face = vector.subtract(pointed.above, pointed.under)
		local at = vector.add(core.pointed_thing_to_face_pos(user, pointed), vector.multiply(face, 0.15))
		core.add_entity(at, "goodluck_elytra:rocket", tostring(lifetime(flight)))
		if not creative(user) then
			stack:take_item()
		end
		return stack
	end
end

for flight = 1, 3 do
	local name = flight == 1 and ROCKET or ROCKET .. "_" .. flight
	core.register_craftitem(name, {
		description = S("Firework Rocket") .. "\n" .. core.colorize("#aaaaaa", S("Flight Duration: @1", flight)),
		short_description = S("Firework Rocket"),
		inventory_image = "goodluck_elytra_firework_rocket.png",
		on_place = use(flight),
		on_secondary_use = use(flight),
	})
	local recipe = {"default:paper"}
	for _ = 1, flight do
		recipe[#recipe + 1] = GUNPOWDER
	end
	core.register_craft({type = "shapeless", output = name .. " 3", recipe = recipe})
end

-- launched from a block: up at 0.05 a tick and 0.04 more each tick, its drift growing 15 % a tick; at its end a puff
-- of smoke (it has no stars, so no blast and no harm)
local function triangle()
	return (math.random() - math.random()) * 0.002297
end

core.register_entity("goodluck_elytra:rocket", {
	initial_properties = {
		visual = "sprite", textures = {"goodluck_elytra_firework_rocket.png"}, visual_size = {x = 0.5, y = 0.5},
		physical = true, collide_with_objects = false, collisionbox = {-0.125, -0.125, -0.125, 0.125, 0.125, 0.125},
		pointable = false, static_save = false,
	},
	on_activate = function(self, staticdata)
		self._lifetime = tonumber(staticdata) or lifetime(1)
		self._life, self._tick = 0, 0
		self._v = vector.new(triangle(), 0.05, triangle())
		self.object:set_velocity(vector.multiply(self._v, 20))
		core.sound_play("goodluck_elytra_launch", {pos = self.object:get_pos(), gain = 1, max_hear_distance = 48}, true)
		trail({attached = self.object}, self._lifetime)
	end,
	on_step = function(self, dtime, moveresult)
		self._tick = self._tick + dtime
		local wall = moveresult and moveresult.collides and moveresult.collisions[1] and
			moveresult.collisions[1].axis ~= "y"
		while self._tick >= 0.05 do
			self._tick = self._tick - 0.05
			local h = wall and 1 or 1.15
			self._v = vector.new(self._v.x * h, self._v.y + 0.04, self._v.z * h)
			self._life = self._life + 1
			if self._life > self._lifetime then
				local pos = self.object:get_pos()
				core.add_particlespawner({
					amount = math.random(2, 4), time = 0.05, minpos = pos, maxpos = pos,
					minvel = {x = -1, y = 0, z = -1}, maxvel = {x = 1, y = 0.2, z = 1},
					minexptime = 0.4, maxexptime = 0.8, minsize = 2, maxsize = 3,
					texture = {name = "goodluck_elytra_poof.png", animation = {type = "vertical_frames", aspect_w = 8,
						aspect_h = 8, length = -1}},
				})
				self.object:remove()
				return
			end
		end
		self.object:set_velocity(vector.multiply(self._v, 20))
	end,
})
