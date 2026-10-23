-- Villagers: mobs_npc's NPC, one a bed (sleep.lua), and its trader with one of Minecraft's trades at the blacksmith
-- (armorer, toolsmith), the church (cleric), the library (librarian) and the fields (farmer). Paid in emeralds at
-- Minecraft's prices; every trader also buys something, as Minecraft's do, and that is how emeralds are earned.
local S = core.get_translator("goodluck_villages")

if not core.get_modpath("mobs_npc") then
	goodluck_villages.spawn = function() end
	return
end

local EMERALD = "goodluck_emerald:emerald"

local function emerald(n)
	return EMERALD .. " " .. n
end

-- an enchanted tool, drawn when the trader first shows its goods and kept with it
local function enchanted(name, bookshelves)
	return function()
		return goodluck_enchanting and goodluck_enchanting.enchant(name, bookshelves):to_string() or name
	end
end

local jobs = {
	armorer = {
		title = S("Armorer"),
		{"3d_armor:helmet_steel", emerald(5)},
		{"3d_armor:chestplate_steel", emerald(9)},
		{"3d_armor:leggings_steel", emerald(7)},
		{"3d_armor:boots_steel", emerald(4)},
		{"shields:shield_steel", emerald(5)},
		{"3d_armor:helmet_diamond", emerald(12)},
		{"3d_armor:chestplate_diamond", emerald(20)},
		{"3d_armor:leggings_diamond", emerald(16)},
		{"3d_armor:boots_diamond", emerald(10)},
		{EMERALD, "default:coal_lump 15"},
	},
	toolsmith = {
		title = S("Toolsmith"),
		{enchanted("default:pick_steel", 8), emerald(8)},
		{enchanted("default:axe_steel", 8), emerald(7)},
		{enchanted("default:shovel_steel", 8), emerald(5)},
		{enchanted("default:sword_steel", 8), emerald(7)},
		{enchanted("default:pick_diamond", 15), emerald(18)},
		{enchanted("default:axe_diamond", 15), emerald(16)},
		{enchanted("default:sword_diamond", 15), emerald(16)},
		{"default:pick_steel", emerald(3)},
		{EMERALD, "default:coal_lump 15"},
		{EMERALD, "default:steel_ingot 4"},
	},
	cleric = {
		title = S("Cleric"),
		{"goodluck_lapis:lapis 4", emerald(1)},
		{"goodluck_lapis:block", emerald(8)},
		{"default:mese_crystal", emerald(3)},
		{"default:obsidian 2", emerald(2)},
		{EMERALD, "vessels:glass_bottle 9"},
		{EMERALD, "default:papyrus 16"},
	},
	librarian = {
		title = S("Librarian"),
		{"default:bookshelf", emerald(3)},
		{"default:book 3", emerald(1)},
		{"default:glass 4", emerald(1)},
		{"default:torch 16", emerald(1)},
		{EMERALD, "default:paper 24"},
		{EMERALD, "default:book 4"},
	},
	farmer = {
		title = S("Farmer"),
		{"farming:bread 6", emerald(1)},
		{"default:apple 4", emerald(1)},
		{"goodluck_food:golden_carrot 3", emerald(3)},
		{EMERALD, "farming:wheat 20"},
		{EMERALD, "goodluck_food:potato 26"},
		{EMERALD, "goodluck_food:carrot 22"},
		{EMERALD, "goodluck_food:beetroot 15"},
	},
}

-- villagers stay: mobs_redo removes an untamed mob that wakes up while mob_active_limit is reached
local activate = mobs.mob_class.mob_activate
function mobs.mob_class.mob_activate(self, staticdata, def, dtime)
	if self.name == "mobs_npc:npc" or self.name == "mobs_npc:trader" then
		self.tamed = true
	end
	return activate(self, staticdata, def, dtime)
end

-- a floor with two free nodes over it, anywhere in the box
local function standing_spot(p1, p2)
	local spots = {}
	local function free(p)
		local def = core.registered_nodes[core.get_node(p).name]
		return def and not def.walkable and def.liquidtype == "none" and (def.damage_per_second or 0) == 0
	end
	for x = p1.x, p2.x do
		for y = p1.y, p2.y do
			for z = p1.z, p2.z do
				local p = vector.new(x, y, z)
				local below = core.registered_nodes[core.get_node(vector.offset(p, 0, -1, 0)).name]
				if below and below.walkable and free(p) and free(vector.offset(p, 0, 1, 0)) then
					spots[#spots + 1] = p
				end
			end
		end
	end
	return spots[math.random(math.max(1, #spots))]
end

function goodluck_villages.spawn(p1, p2, job, bed)
	local pos = standing_spot(p1, p2)
	if not pos then
		return
	end
	local obj = core.add_entity(vector.offset(pos, 0, 0.5, 0), job == "villager" and "mobs_npc:npc" or "mobs_npc:trader")
	local ent = obj and obj:get_luaentity()
	if ent and jobs[job] then
		ent.goodluck_job = job
		ent.game_name = jobs[job].title
		-- no name over their heads, as in Minecraft (the trade window says who they are); mobs_npc names traders
		ent.nametag, ent._nametag = nil, nil
		obj:set_properties({nametag = ""})
	end
	if ent and bed then
		goodluck_villages.give_bed(ent, bed)
	end
	return ent
end

-- villagers saved with their job, or mobs_npc's "Trader", over their heads lose it
local trader = core.get_translator("mobs_npc")("Trader")
for _, name in ipairs({"mobs_npc:npc", "mobs_npc:trader"}) do
	local def = core.registered_entities[name]
	local activate = def and def.on_activate
	if activate then
		def.on_activate = function(self, ...)
			local r = activate(self, ...)
			local job = jobs[self.goodluck_job or ""]
			local tag = self._nametag or self.nametag
			if job and self.object:get_pos() and (tag == job.title or tag == trader) then
				self._nametag, self.nametag = nil, nil
				self.object:set_properties({nametag = ""})
			end
			return r
		end
	end
end

-- mobs_npc's shop, for item strings that carry an enchantment: buttons show the item and its count, the
-- tooltip its description (the trade itself is still mobs_npc's, by the button's name)
local shop_trade = mobs_npc.shop_trade
function mobs_npc.shop_trade(self, clicker, race)
	local job = jobs[self.goodluck_job]
	if not job then
		return shop_trade(self, clicker, race)
	end
	if not self.trades then
		self.trades = {}
		for i, t in ipairs(job) do
			self.trades[i] = {type(t[1]) == "function" and t[1]() or t[1], t[2]}
		end
	end
	-- goods enchanted before get the moving glint
	for _, t in ipairs(self.trades) do
		local goods = ItemStack(t[1])
		if goodluck_enchanting and goodluck_enchanting.update(goods) then
			t[1] = goods:to_string()
		end
	end
	self.id = set_npc_id(self)
	local fs = {"size[8,10]", default.gui_bg_img or "", default.gui_slots or "",
		"label[0.5,-0.1;" .. core.formspec_escape(job.title) .. "]"}
	for i, t in ipairs(self.trades) do
		if i > 10 then
			break
		end
		local x, y = i < 6 and 0.5 or 4.5, i < 6 and i - 0.5 or i - 5.5
		local goods, price = ItemStack(t[1]), ItemStack(t[2])
		-- an enchanted item is drawn with its glint, which only its meta has
		local function button(stack, kind)
			local id = kind .. "#" .. i .. "#" .. self.id
			local bx = kind == "prices" and x or x + 2
			local image = goodluck_enchanting and goodluck_enchanting.preview(stack) or ""
			local b = image ~= "" and ("image_button[%s,%s;1,1;%s;%s;]"):format(bx, y, core.formspec_escape(image), id) or
				("item_image_button[%s,%s;1,1;%s;%s;]"):format(bx, y, stack:get_name() .. " " .. stack:get_count(), id)
			return b .. ("tooltip[%s;%s]"):format(id, core.formspec_escape(stack:get_description()))
		end
		fs[#fs + 1] = button(price, "prices") .. button(goods, "goods") ..
			("image[%s,%s;1,1;gui_arrow_blank.png]"):format(x + 1, y)
	end
	fs[#fs + 1] = "list[current_player;main;0,6;8,4;]"
	core.show_formspec(clicker:get_player_name(), "mobs_npc:trade", table.concat(fs))
end

-- what the villagers say, in the player's language
local lines = {S("Hello"), S("Hi there"), S("What a lovely day"), S("Is it lunch time yet?"),
	S("Diamonds are a villager's best friend."), S("Will you come to my block party?"),
	S("If you got any emeralds, the traders have a few things to sell you."), S("Watch out for monsters at night!")}
function mobs_npc.npc_talk(self, player)
	local msg = self.state == "attack" and S("I'm kinda busy!") or lines[math.random(#lines)]
	local who = self.nametag and self.nametag ~= "" and self.nametag or S("Villager")
	core.chat_send_player(player:get_player_name(), "<" .. who .. "> " .. msg)
end
