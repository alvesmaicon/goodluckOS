-- Villagers sleep in their beds at night, as in Minecraft: at dusk each one walks home (core.find_path to the house's
-- door, through it, then to the bed), lies down, and in the morning gets up and walks out again, opening the door and
-- closing it behind. By day one that wanders far turns back toward home. A villager without a bed (from an older
-- village, or whose bed is gone) takes the nearest free one; one that can't find its way for a while (walled in) goes
-- straight there.
local DUSK, DAWN = 0.76, 0.24
local REACH = 24
local STUCK, GIVE_UP = 3, 20
local AWAY = 24
-- lying down: the mob's own frames, else the character model's
local LAY = {x = 162, y = 166}
local npc = core.registered_entities["mobs_npc:npc"]

-- the villager's feet under its position, by its collision box
local function bottom(self)
	return (self.base_colbox or self.collisionbox)[2]
end
local SIDES = {vector.new(1, 0, 0), vector.new(-1, 0, 0), vector.new(0, 0, 1), vector.new(0, 0, -1)}

local function night()
	local t = core.get_timeofday()
	return t >= DUSK or t < DAWN
end

local function solid(pos)
	local def = core.registered_nodes[core.get_node(pos).name]
	return not def or def.walkable
end

local function free(pos)
	return not solid(pos) and not solid(vector.offset(pos, 0, 1, 0))
end

local function nearest(list, pos)
	table.sort(list, function(a, b)
		return vector.distance(a, pos) < vector.distance(b, pos)
	end)
	return list[1]
end

-- a free cell over the ground, at most 3 down
local function ground(pos)
	for y = 0, 3 do
		local p = vector.offset(pos, 0, -y, 0)
		if free(p) and solid(vector.offset(p, 0, -1, 0)) then
			return p
		end
	end
end

local function claim(self, bed)
	local doors = core.find_nodes_in_area(vector.offset(bed, -7, -2, -7), vector.offset(bed, 7, 2, 7), {"group:door"})
	self.goodluck_bed, self.goodluck_door = bed, nearest(doors, bed)
	local meta = core.get_meta(bed)
	meta:set_string("goodluck_villager", self.goodluck_id)
	meta:set_int("goodluck_day", core.get_day_count())
end

function goodluck_villages.give_bed(self, bed)
	self.goodluck_id = self.goodluck_id or tostring(math.random(1, 2147483646))
	claim(self, bed)
end

-- the nearest bed no other villager slept in lately
local function find_bed(self, pos)
	self.goodluck_id = self.goodluck_id or tostring(math.random(1, 2147483646))
	local beds = core.find_nodes_in_area(vector.offset(pos, -12, -3, -12), vector.offset(pos, 12, 3, 12),
		{"beds:bed_bottom"})
	nearest(beds, pos)
	local today = core.get_day_count()
	for _, bed in ipairs(beds) do
		local meta = core.get_meta(bed)
		local who = meta:get_string("goodluck_villager")
		if who == "" or who == self.goodluck_id or today - meta:get_int("goodluck_day") > 2 then
			claim(self, bed)
			return true
		end
	end
end

-- the bed, the cells on both sides of the door (inside is the one nearer the bed) and a free cell by the bed
local function home(self)
	local bed = self.goodluck_bed
	local node = bed and core.get_node(bed)
	if not node or node.name ~= "beds:bed_bottom" then
		if node and node.name ~= "ignore" then
			self.goodluck_bed, self.goodluck_door = nil, nil
		end
		return
	end
	local h = {bed = bed, dir = core.facedir_to_dir(node.param2 % 4)}
	local door = self.goodluck_door
	if door and core.get_item_group(core.get_node(door).name, "door") > 0 then
		for _, d in ipairs({SIDES[1], SIDES[3]}) do
			local a, b = vector.add(door, d), vector.subtract(door, d)
			if free(a) and free(b) then
				if vector.distance(a, bed) > vector.distance(b, bed) then
					a, b = b, a
				end
				h.door, h.inside, h.outside, h.out = door, a, b, vector.subtract(b, a)
				break
			end
		end
	end
	local best
	for _, part in ipairs({bed, vector.add(bed, h.dir)}) do
		for _, d in ipairs(SIDES) do
			local c = vector.add(part, d)
			if free(c) and solid(vector.offset(c, 0, -1, 0)) then
				local k = vector.distance(c, h.inside or bed)
				if not best or k < best.k then
					best = {c = c, k = k}
				end
			end
		end
	end
	h.spot = best and best.c
	return h.spot and h
end
goodluck_villages.home = home

local function feet(self)
	local pos = self.object:get_pos()
	return vector.new(math.floor(pos.x + 0.5), math.floor(pos.y + bottom(self) + 0.5), math.floor(pos.z + 0.5))
end

local function path(self, to, reach)
	local from = feet(self)
	if solid(from) then
		from.y = from.y + 1
	end
	return core.find_path(from, to, reach or REACH, 1, 3, "A*_noprefetch")
end

local function place(self, cell)
	self.object:set_pos(vector.offset(cell, 0, -0.5 - bottom(self), 0))
end

-- walking: legs of {to = cell, door = pos, soft = true}, a door leg straight across with the door open, a soft one
-- given up rather than skipped when the way isn't found
local function go(self, legs)
	self._goodluck_legs, self._goodluck_way = legs[1] and legs, nil
	self._goodluck_time, self._goodluck_best, self._goodluck_since, self._goodluck_fails = 0, math.huge, 0, 0
end

local function walk(self, dtime)
	local leg = self._goodluck_legs and self._goodluck_legs[1]
	if not leg then
		return false
	end
	local pos = self.object:get_pos()
	local left = vector.distance(vector.new(pos.x, leg.to.y, pos.z), leg.to)
	if left < 0.4 and math.abs(feet(self).y - leg.to.y) <= 1 then
		local door = leg.door and doors and doors.get(leg.door)
		if door then
			door:close(nil)
		end
		table.remove(self._goodluck_legs, 1)
		go(self, self._goodluck_legs)
		self:set_velocity(0)
		return true
	end
	self._goodluck_time = self._goodluck_time + dtime
	self._goodluck_since = self._goodluck_since + dtime
	if left < self._goodluck_best - 0.3 then
		self._goodluck_best, self._goodluck_since = left, 0
	elseif self._goodluck_since > STUCK then
		self._goodluck_way, self._goodluck_since, self._goodluck_fails = nil, 0, self._goodluck_fails + 1
	end
	if self._goodluck_time > GIVE_UP or self._goodluck_fails >= 3 then
		if leg.soft then
			go(self, {})
			self._goodluck_rest = 30
			return false
		end
		place(self, leg.to)
		self._goodluck_since, self._goodluck_best = 0, math.huge
		return true
	end
	local target = leg.to
	if leg.door then
		local door = doors and doors.get(leg.door)
		if door then
			door:open(nil)
		end
	else
		local way = self._goodluck_way
		if not way then
			way = path(self, leg.to)
			if not way then
				self._goodluck_fails = self._goodluck_fails + 1
				self:set_velocity(0)
				self:set_animation("stand")
				return true
			end
			self._goodluck_way, self._goodluck_step = way, math.min(2, #way)
		end
		local wp = way[self._goodluck_step]
		while wp and self._goodluck_step < #way and vector.distance(vector.new(pos.x, wp.y, pos.z), wp) < 0.4 do
			self._goodluck_step = self._goodluck_step + 1
			wp = way[self._goodluck_step]
		end
		target = wp or leg.to
	end
	self:yaw_to_pos(target)
	self:set_velocity(self.walk_velocity)
	self:set_animation("walk")
	return true
end

local function lie(self, h)
	local p = vector.add(h.bed, vector.multiply(h.dir, 0.5))
	p.y = h.bed.y + 0.5 - bottom(self) - 0.45
	self.goodluck_sleeping, self.disable_falling, self.state = true, true, "stand"
	self.object:set_properties({physical = false})
	self.object:set_velocity(vector.zero())
	self.object:set_acceleration(vector.zero())
	self.object:set_pos(p)
	self:set_yaw(core.dir_to_yaw(h.dir) + math.pi)
	local anim = self.animation or {}
	self.object:set_animation(anim.lay_start and {x = anim.lay_start, y = anim.lay_end} or LAY, 0, 0, false)
	self.animation_current = "lay"
	core.get_meta(h.bed):set_int("goodluck_day", core.get_day_count())
end

local function get_up(self, h)
	self.goodluck_sleeping, self.disable_falling = nil, nil
	self.object:set_properties({physical = true})
	if h then
		place(self, h.spot)
	end
	self:set_animation("stand", true)
end

-- out of the house: to the door, through it, and a few steps on
local function go_out(self, h)
	local away = ground(vector.add(h.outside, vector.multiply(h.out, 2))) or h.outside
	go(self, {{to = h.inside}, {to = h.outside, door = h.door}, {to = away}})
end

local function inside(self, h)
	return h.inside and not path(self, h.outside, 12) and path(self, h.inside, 12)
end

local function think(self)
	local h = home(self)
	if night() then
		if not h then
			if not self.goodluck_bed and (self._goodluck_rest or 0) <= 0 then
				self._goodluck_rest = 60
				find_bed(self, self.object:get_pos())
			end
			return
		end
		if vector.distance(feet(self), h.spot) < 1 then
			lie(self, h)
		elseif path(self, h.spot, 12) or not h.inside then
			go(self, {{to = h.spot}})
		else
			go(self, {{to = h.outside}, {to = h.inside, door = h.door}, {to = h.spot}})
		end
	elseif not h or (self._goodluck_rest or 0) > 0 then
		return
	elseif h.inside and vector.distance(feet(self), h.door) < 8 then
		self._goodluck_rest = 5
		if inside(self, h) then
			go_out(self, h)
		end
	elseif vector.distance(feet(self), h.bed) > AWAY then
		local near = h.inside and ground(vector.add(h.outside, vector.multiply(h.out, 3))) or h.outside or h.spot
		go(self, {{to = near, soft = true}})
	end
end

local function sleep_step(self, dtime)
	if self.goodluck_sleeping then
		if night() then
			self.state = "stand"
			self.object:set_velocity(vector.zero())
			return false
		end
		local h = home(self)
		get_up(self, h)
		if h and h.inside then
			go_out(self, h)
		end
		return false
	end
	if walk(self, dtime) then
		return false
	end
	self._goodluck_think = (self._goodluck_think or math.random()) + dtime
	if self._goodluck_think >= 1 then
		self._goodluck_rest = (self._goodluck_rest or 0) - self._goodluck_think
		self._goodluck_think = 0
		think(self)
		if self._goodluck_legs or self.goodluck_sleeping then
			return false
		end
	end
end

if npc then
	local do_custom = npc.do_custom
	npc.do_custom = function(self, dtime, moveresult)
		if sleep_step(self, dtime) == false then
			return false
		end
		if do_custom then
			return do_custom(self, dtime, moveresult)
		end
	end
	-- one saved asleep lies down again; a walk saved half done starts over
	local activate = npc.on_activate
	npc.on_activate = function(self, ...)
		local r = activate(self, ...)
		self._goodluck_legs, self._goodluck_way = nil, nil
		if self.goodluck_sleeping and self.object:get_pos() then
			local h = home(self)
			if h and night() then
				lie(self, h)
			else
				get_up(self, h)
			end
		end
		return r
	end
end
