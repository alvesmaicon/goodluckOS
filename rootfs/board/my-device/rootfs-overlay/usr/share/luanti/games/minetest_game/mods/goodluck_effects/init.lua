-- Minecraft's status effects on players, each with a level and a time: a higher level replaces a lower one, the same
-- level a shorter time. They show as Minecraft's icons in the top right (the harmful ones a row lower), with the time
-- left under each and blinking in its last 10 s, and as swirls of their mixed colour; they go on death and with milk,
-- and stay over a rejoin. /effect <name> [seconds] [level] gives one, /effect clear [name] takes them away
local S = core.get_translator("goodluck_effects")
goodluck_effects = {registered = {}, order = {}, undead = {}}
local E = goodluck_effects
local active, huds, swirls = {}, {}, {}
local ICON, ROW, BLINK = 50, 66, 10
local HEARTS = {poison = "goodluck_effects_heart_poisoned.png", wither = "goodluck_effects_heart_withered.png"}

-- def: description, color ("#rrggbb"), bad, instant, physics(level) -> share for goodluck_physics, interval(level) ->
-- seconds between on_interval(player, level) calls, on_step(player, level, dtime), on_start(player, level), on_stop
function E.register(name, def)
	def.icon = def.icon or "goodluck_effects_" .. name .. ".png"
	E.registered[name] = def
	E.order[#E.order + 1] = name
end

local function save(player)
	local out = {}
	for effect, e in pairs(active[player:get_player_name()] or {}) do
		out[effect] = {e.level, math.ceil(e.left)}
	end
	player:get_meta():set_string("goodluck_effects", next(out) and core.write_json(out) or "")
end

-- poisoned hearts win over withered ones, as in Minecraft; the health bar is the engine's, found by its texture's name
-- (goodluck_mcassets turns it into Minecraft's)
local function hearts(player)
	local list = active[player:get_player_name()] or {}
	local text = list.poison and HEARTS.poison or list.wither and HEARTS.wither or "heart.png"
	for id, def in pairs(player:hud_get_all()) do
		if def.type == "statbar" and def.text:find("heart") then
			player:hud_change(id, "text", text)
		end
	end
end

local function clock(left)
	local s = math.max(0, math.ceil(left))
	return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local function with(t, more)
	local out = table.copy(t)
	for k, v in pairs(more) do
		out[k] = v
	end
	return out
end

-- one icon per effect in the top right, the good ones first, the harmful ones a row lower
local function layout(player)
	local name = player:get_player_name()
	for _, ids in pairs(huds[name] or {}) do
		player:hud_remove(ids.bg)
		player:hud_remove(ids.icon)
		player:hud_remove(ids.time)
	end
	huds[name] = {}
	local list, column = active[name] or {}, {0, 0}
	for _, effect in ipairs(E.order) do
		local e, def = list[effect], E.registered[effect]
		if e then
			local row = def.bad and 2 or 1
			column[row] = column[row] + 1
			local x, y = -8 - ICON * column[row] + ICON / 2, 4 + 24 + ROW * (row - 1)
			local at = {position = {x = 1, y = 0}, alignment = {x = 0, y = 0}, offset = {x = x, y = y},
				scale = {x = 2, y = 2}, z_index = 10}
			local ids = {}
			ids.bg = player:hud_add(with(at, {type = "image", text = "goodluck_effects_background.png"}))
			ids.icon = player:hud_add(with(at, {type = "image", text = def.icon, z_index = 11}))
			ids.time = player:hud_add({type = "text", position = at.position, alignment = at.alignment,
				offset = {x = x, y = y + 32}, text = clock(e.left), number = 0xFFFFFF, z_index = 11})
			ids.shown, ids.lit = clock(e.left), true
			huds[name][effect] = ids
		end
	end
end

-- in Minecraft's own blend of their colours, the levels as weights
local function swirl(player)
	local name = player:get_player_name()
	if swirls[name] then
		core.delete_particlespawner(swirls[name])
		swirls[name] = nil
	end
	local r, g, b, n = 0, 0, 0, 0
	for effect, e in pairs(active[name] or {}) do
		local c = tonumber(E.registered[effect].color:sub(2), 16)
		r, g, b, n = r + math.floor(c / 65536) * e.level, g + math.floor(c / 256) % 256 * e.level,
			b + c % 256 * e.level, n + e.level
	end
	if n == 0 then
		return
	end
	swirls[name] = core.add_particlespawner({
		amount = 3, time = 0, attached = player,
		minpos = {x = -0.4, y = 0.1, z = -0.4}, maxpos = {x = 0.4, y = 1.3, z = 0.4},
		minvel = {x = 0, y = 0.3, z = 0}, maxvel = {x = 0, y = 0.6, z = 0},
		minexptime = 0.8, maxexptime = 1.2, minsize = 1.5, maxsize = 2,
		texture = ("goodluck_effects_particle.png^[multiply:#%02x%02x%02x"):format(math.floor(r / n),
			math.floor(g / n), math.floor(b / n)),
	})
end

local function changed(player)
	layout(player)
	swirl(player)
	hearts(player)
	save(player)
end

local function stop(player, effect)
	local name = player:get_player_name()
	local def = E.registered[effect]
	active[name][effect] = nil
	if def.physics then
		goodluck_physics.set(player, "goodluck_effects:" .. effect, nil)
	end
	if def.on_stop then
		def.on_stop(player)
	end
	if not next(active[name]) then
		active[name] = nil
	end
	changed(player)
end

-- Instant Health heals 4 and Instant Damage takes 6, twice that a level up, times share (a splash's nearness); on
-- the undead each does the other
function E.instant(obj, effect, level, share)
	local amount = math.floor((effect == "instant_health" and 4 or 6) * 2 ^ ((level or 1) - 1) * (share or 1) + 0.5)
	local ent = not obj:is_player() and obj:get_luaentity()
	local heal = (effect == "instant_health") ~= (ent and E.undead[ent.name] or false)
	if obj:is_player() then
		if heal or not core.is_creative_enabled(obj:get_player_name()) then
			obj:set_hp(obj:get_hp() + (heal and amount or -amount),
				{type = "set_hp", cause = "goodluck_effects:" .. effect})
		end
	elseif ent and ent.health then
		local max = ent.prop and ent.prop.hp_max or obj:get_properties().hp_max
		ent.health = heal and math.min(max, ent.health + amount) or ent.health - amount
		if not heal and ent.check_for_death then
			ent:check_for_death({type = "unknown"})
		end
	end
end

function E.apply(player, effect, seconds, level)
	local def = E.registered[effect]
	if not def or not player or not player:is_player() then
		return false
	end
	level = math.max(1, math.floor(level or 1))
	if def.instant then
		E.instant(player, effect, level)
		return true
	end
	local name = player:get_player_name()
	local list = active[name] or {}
	local now = list[effect]
	if now and (now.level > level or now.level == level and now.left >= seconds) then
		return false
	end
	active[name] = list
	list[effect] = {level = level, left = seconds, timer = now and now.timer or 0}
	if def.physics then
		goodluck_physics.set(player, "goodluck_effects:" .. effect, def.physics(level))
	end
	if def.on_start then
		def.on_start(player, level)
	end
	changed(player)
	return true
end

-- the level and the seconds left, or nil
function E.get(player, effect)
	local e = (active[player:get_player_name()] or {})[effect]
	if e then
		return e.level, e.left
	end
end

function E.remove(player, effect)
	if (active[player:get_player_name()] or {})[effect] then
		stop(player, effect)
	end
end

function E.clear(player)
	for effect in pairs(active[player:get_player_name()] or {}) do
		stop(player, effect)
	end
end

local hud_timer = 0
core.register_globalstep(function(dtime)
	hud_timer = hud_timer + dtime
	local show = hud_timer >= 0.25
	if show then
		hud_timer = 0
	end
	for name, list in pairs(active) do
		local player = core.get_player_by_name(name)
		if player then
			for effect, e in pairs(list) do
				local def = E.registered[effect]
				e.left = e.left - dtime
				if def.on_step then
					def.on_step(player, e.level, dtime)
				end
				if def.interval then
					local every = def.interval(e.level)
					e.timer = e.timer + dtime
					while e.timer >= every and active[name] == list do
						e.timer = e.timer - every
						def.on_interval(player, e.level)
					end
				end
				-- death on a tick clears the list
				if active[name] ~= list then
					break
				end
				if e.left <= 0 then
					stop(player, effect)
				elseif show then
					local ids = huds[name] and huds[name][effect]
					local text, lit = clock(e.left), e.left > BLINK or math.floor(e.left * 4) % 2 == 0
					if ids and ids.shown ~= text then
						player:hud_change(ids.time, "text", text)
						ids.shown = text
					end
					if ids and ids.lit ~= lit then
						player:hud_change(ids.icon, "text", def.icon .. (lit and "" or "^[opacity:70"))
						ids.lit = lit
					end
				end
			end
		end
	end
end)

core.register_on_dieplayer(function(player)
	E.clear(player)
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	save(player)
	for effect in pairs(active[name] or {}) do
		local def = E.registered[effect]
		if def.on_stop then
			def.on_stop(player)
		end
	end
	active[name], huds[name] = nil, nil
	if swirls[name] then
		core.delete_particlespawner(swirls[name])
		swirls[name] = nil
	end
end)

core.register_on_shutdown(function()
	for _, player in ipairs(core.get_connected_players()) do
		save(player)
	end
end)

-- after the other mods' own joins (stamina's bar, the engine's hearts)
core.register_on_joinplayer(function(player)
	local text = player:get_meta():get_string("goodluck_effects")
	local saved = text ~= "" and core.parse_json(text) or {}
	local name = player:get_player_name()
	core.after(0, function()
		player = core.get_player_by_name(name)
		for effect, e in pairs(saved) do
			if player and E.registered[effect] then
				E.apply(player, effect, e[2], e[1])
			end
		end
	end)
end)

-- milk takes every effect away, as in Minecraft, and is drunk even on a full bar (stamina won't eat then)
local EMPTY = {food_milk = "bucket:bucket_empty", food_milk_glass = "vessels:drinking_glass"}
core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_items) do
		for group, empty in pairs(EMPTY) do
			if (def.groups[group] or 0) > 0 and def.on_use then
				local on_use = def.on_use
				core.override_item(name, {on_use = function(itemstack, user, pointed_thing)
					local had = user and user:is_player() and active[user:get_player_name()]
					local count = itemstack:get_count()
					itemstack = on_use(itemstack, user, pointed_thing) or itemstack
					if had then
						E.clear(user)
						if itemstack:get_name() == name and itemstack:get_count() == count then
							itemstack:take_item()
							if itemstack:is_empty() then
								itemstack = ItemStack(empty)
							else
								local left = user:get_inventory():add_item("main", empty)
								if not left:is_empty() then
									core.add_item(user:get_pos(), left)
								end
							end
						end
					end
					return itemstack
				end})
			end
		end
	end
end)

-- Strength adds 3 to a hit and Weakness takes 4, a level each (bows and other mobs' hits stay as they are)
local function melee(player)
	local list = active[player:get_player_name()]
	if not list then
		return 0
	end
	return (list.strength and 3 * list.strength.level or 0) - (list.weakness and 4 * list.weakness.level or 0)
end
if core.global_exists("mobs") and mobs.mob_class then
	local on_punch = mobs.mob_class.on_punch
	mobs.mob_class.on_punch = function(self, hitter, tflp, tool_caps, dir, damage)
		local add = hitter and hitter:is_player() and melee(hitter) or 0
		if add ~= 0 and tool_caps and tool_caps.damage_groups then
			tool_caps = table.copy(tool_caps)
			tool_caps.damage_groups.fleshy = math.max(0, (tool_caps.damage_groups.fleshy or 0) + add)
		end
		return on_punch(self, hitter, tflp, tool_caps, dir, damage)
	end
end

-- Slow Falling and Jump Boost against falls, Fire Resistance against lava, fire and anything that says it burns (a
-- hurt with fire = true, a punch by something with _fire: a fireball)
local function burns(node)
	return core.get_item_group(node or "", "lava") > 0 or core.get_item_group(node or "", "igniter") > 0 or
		core.get_item_group(node or "", "fire") > 0
end
local function fiery(reason)
	local ent = reason.type == "punch" and reason.object and reason.object:get_luaentity()
	return reason.fire or ent and ent._fire or reason.type == "node_damage" and burns(reason.node)
end
core.register_on_player_hpchange(function(player, hp_change, reason)
	local list = hp_change < 0 and active[player:get_player_name()]
	if not list then
		return hp_change
	end
	if reason.type == "fall" then
		if list.slow_falling then
			return 0
		elseif list.jump_boost then
			return math.min(0, hp_change + list.jump_boost.level)
		end
	elseif list.fire_resistance and fiery(reason) then
		return 0
	end
	return hp_change
end, true)

local function hurt(player, by, floor)
	local hp = player:get_hp()
	if hp > floor and not core.is_creative_enabled(player:get_player_name()) then
		player:set_hp(hp - 1, {type = "set_hp", cause = "goodluck_effects:" .. by})
	end
end
-- Minecraft's ticks: 20 a second, every 25, 40 and 50 at level I, half that a level up
local function every(ticks)
	return function(level)
		return math.max(1, math.floor(ticks / 2 ^ (level - 1))) / 20
	end
end

E.register("speed", {description = S("Speed"), color = "#33ebff",
	physics = function(level) return {speed = 1 + 0.2 * level} end})
E.register("slowness", {description = S("Slowness"), color = "#8bafe0", bad = true,
	physics = function(level) return {speed = math.max(0, 1 - 0.15 * level)} end})
-- 0.1 more of Minecraft's 0.42 jump speed a level
E.register("jump_boost", {description = S("Jump Boost"), color = "#fdff84",
	physics = function(level) return {jump = 1 + 0.1 / 0.42 * level} end})
-- an eighth of the gravity while going down, as in Minecraft, and no fall damage
local slow = {}
E.register("slow_falling", {description = S("Slow Falling"), color = "#f3cfb9",
	on_step = function(player)
		local name = player:get_player_name()
		local down = player:get_velocity().y < 0
		if down ~= slow[name] then
			slow[name] = down
			goodluck_physics.set(player, "goodluck_effects:slow_falling", down and {gravity = 1 / 8} or nil)
		end
	end,
	on_stop = function(player)
		slow[player:get_player_name()] = nil
		goodluck_physics.set(player, "goodluck_effects:slow_falling", nil)
	end})
-- never below half a heart
E.register("poison", {description = S("Poison"), color = "#87a363", bad = true, interval = every(25),
	on_interval = function(player) hurt(player, "poison", 1) end})
E.register("wither", {description = S("Wither"), color = "#736156", bad = true, interval = every(40),
	on_interval = function(player) hurt(player, "wither", 0) end})
E.register("regeneration", {description = S("Regeneration"), color = "#cd5cab", interval = every(50),
	on_interval = function(player)
		local hp = player:get_hp()
		if hp > 0 and hp < player:get_properties().hp_max then
			player:set_hp(hp + 1, {type = "set_hp", cause = "goodluck_effects:regeneration"})
		end
	end})
E.register("strength", {description = S("Strength"), color = "#ffc700"})
E.register("weakness", {description = S("Weakness"), color = "#484d48", bad = true})
E.register("fire_resistance", {description = S("Fire Resistance"), color = "#ff9900"})
-- the breath stays full, so its bar never shows
E.register("water_breathing", {description = S("Water Breathing"), color = "#98dac0",
	on_step = function(player)
		local full = player:get_properties().breath_max
		if player:get_breath() < full then
			player:set_breath(full)
		end
	end})
-- the player and their name tag can't be seen, and mobs_redo's mobs leave them be (mod invisibility)
local seen = {}
E.register("invisibility", {description = S("Invisibility"), color = "#f6f6f6",
	on_start = function(player)
		local name = player:get_player_name()
		if not seen[name] then
			local props = player:get_properties()
			seen[name] = {visual_size = props.visual_size, nametag_color = player:get_nametag_attributes().color}
			player:set_properties({visual_size = {x = 0, y = 0, z = 0}})
			player:set_nametag_attributes({color = {a = 0, r = 255, g = 255, b = 255}})
		end
	end,
	on_stop = function(player)
		local name = player:get_player_name()
		if seen[name] then
			player:set_properties({visual_size = seen[name].visual_size})
			player:set_nametag_attributes({color = seen[name].nametag_color})
			seen[name] = nil
		end
	end})
-- everything seen as lit as its brightest light, through the engine's night_vision lighting (handheld.25 on); in its
-- last 10 s it flickers as Minecraft's does (0.7 + 0.3 sin(ticks * pi / 5))
local function night_vision(player, value)
	if player:get_lighting().night_vision then
		player:set_lighting({night_vision = value})
	end
end
E.register("night_vision", {description = S("Night Vision"), color = "#c2ff66",
	on_start = function(player) night_vision(player, 1) end,
	on_step = function(player)
		local _, left = E.get(player, "night_vision")
		if left and left <= BLINK then
			night_vision(player, 0.7 + 0.3 * math.sin(left * 20 * math.pi * 0.2))
		end
	end,
	on_stop = function(player) night_vision(player, 0) end})
E.register("instant_health", {description = S("Instant Health"), color = "#f82423", instant = true})
E.register("instant_damage", {description = S("Instant Damage"), color = "#a9656a", bad = true, instant = true})

core.register_chatcommand("effect", {
	params = S("<effect> [<seconds>] [<level>] | clear [<effect>]"),
	description = S("Give yourself a status effect, or take them away"),
	privs = {give = true},
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then
			return false
		end
		local what, seconds, level = param:match("^(%S+)%s*(%S*)%s*(%S*)$")
		if what == "clear" then
			if seconds ~= "" then
				if not E.registered[seconds] then
					return false, S("Unknown effect: @1", seconds)
				end
				E.remove(player, seconds)
				return true, S("Removed effect @1 from @2", E.registered[seconds].description, name)
			end
			E.clear(player)
			return true, S("Removed every effect from @1", name)
		end
		local def = what and E.registered[what]
		if not def then
			return false, S("Unknown effect: @1", what or "") .. "\n" .. table.concat(E.order, ", ")
		end
		E.apply(player, what, tonumber(seconds) or 30, tonumber(level) or 1)
		return true, S("Applied effect @1 to @2", def.description, name)
	end,
})
