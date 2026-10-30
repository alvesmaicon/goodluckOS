-- No text with the crosshair on a block or a thing, as in Minecraft: bookshelves, chests, furnaces, the enchanting
-- table, locked doors, arrows and the like keep their infotext empty; signs keep theirs, the only way Minetest Game
-- shows what is written on them
local SIGNS = {"default:sign_wall_wood", "default:sign_wall_steel", "goodluck_models:sign_standing_wood",
	"goodluck_models:sign_standing_steel"}
local allow = false

-- every node's metadata goes through NodeMetaRef, whose methods are one table (reachable once the map is, at the
-- first step)
local function wrap_meta()
	local methods = getmetatable(core.get_meta(vector.zero()))
	if type(methods) ~= "table" or methods.goodluck_labels then
		return
	end
	local set_string = methods.set_string
	methods.set_string = function(self, key, value)
		if key == "infotext" and not allow then
			value = ""
		end
		return set_string(self, key, value)
	end
	methods.goodluck_labels = true
end
core.after(0, wrap_meta)

core.register_on_mods_loaded(function()
	for _, name in ipairs(SIGNS) do
		local def = core.registered_nodes[name]
		if def and def.on_receive_fields then
			local receive = def.on_receive_fields
			core.override_item(name, {
				on_receive_fields = function(...)
					allow = true
					local ok, err = pcall(receive, ...)
					allow = false
					if not ok then error(err) end
				end,
			})
		end
	end
	for _, def in pairs(core.registered_entities) do
		if def.initial_properties and def.initial_properties.infotext then
			def.initial_properties.infotext = ""
		end
	end
end)

-- entities set theirs at run time too (x_bows' arrows)
core.register_on_joinplayer(function(player)
	local methods = getmetatable(player)
	if type(methods) ~= "table" or methods.goodluck_labels then
		return
	end
	local set_properties = methods.set_properties
	methods.set_properties = function(self, props)
		if type(props) == "table" and props.infotext and props.infotext ~= "" and not self:is_player() then
			props = table.copy(props)
			props.infotext = ""
		end
		return set_properties(self, props)
	end
	methods.goodluck_labels = true
end)

-- what worlds saved before this
core.register_lbm({
	label = "goodluck_labels: no infotext",
	name = "goodluck_labels:clear_infotext",
	nodenames = {"default:bookshelf", "default:chest", "default:chest_open", "default:chest_locked",
		"default:chest_locked_open", "default:furnace", "default:furnace_active", "vessels:shelf", "bones:bones",
		"x_enchanting:table", "x_enchanting:grindstone", "doors:door_steel_a", "doors:door_steel_b",
		"doors:door_steel_c", "doors:door_steel_d", "doors:trapdoor_steel", "doors:trapdoor_steel_open"},
	run_at_every_load = false,
	action = function(pos)
		local meta = core.get_meta(pos)
		if meta:get_string("infotext") ~= "" then
			meta:set_string("infotext", "")
		end
	end,
})
