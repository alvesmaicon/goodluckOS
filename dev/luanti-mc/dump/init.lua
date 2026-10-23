-- Dev tool, not shipped: core.after so mods that override items late are included
local function strs(t, out)
	out = out or {}
	if type(t) == "string" then out[#out + 1] = t
	elseif type(t) == "table" then
		if t.name then out[#out + 1] = t.name end
		if t.image then out[#out + 1] = t.image end
		for _, v in ipairs(t) do strs(v, out) end
	end
	return out
end

local function sounds(s)
	local out = {}
	if type(s) ~= "table" then return out end
	for k, v in pairs(s) do
		if type(v) == "table" and v.name then out[k] = v.name
		elseif type(v) == "string" then out[k] = v end
	end
	return out
end

core.after(0, function()
	local d = {nodes = {}, items = {}, entities = {}, crafts = {}, media = {}}
	for name, def in pairs(core.registered_items) do
		local e = {
			mod = def.mod_origin, type = def.type, desc = def.description,
			inv = def.inventory_image ~= "" and def.inventory_image or nil,
			wield = def.wield_image ~= "" and def.wield_image or nil,
			groups = def.groups, sound = sounds(def.sound),
		}
		if def.type == "node" then
			e.drawtype = def.drawtype
			e.tiles = strs(def.tiles)
			e.overlay = strs(def.overlay_tiles)
			e.special = strs(def.special_tiles)
			e.sounds = sounds(def.sounds)
			e.mesh = def.mesh
			d.nodes[name] = e
		else
			d.items[name] = e
		end
		local r = core.get_all_craft_recipes(name)
		if r then
			for _, c in ipairs(r) do
				d.crafts[#d.crafts + 1] = {output = c.output, method = c.method, width = c.width, items = c.items}
			end
		end
	end
	for name, def in pairs(core.registered_entities) do
		local p = def.initial_properties or def
		d.entities[name] = {
			mod = def.mod_origin, visual = p.visual, mesh = p.mesh,
			textures = strs(p.textures), sounds = sounds(def.sounds),
			mob_textures = def.textures and strs(def.textures) or nil,
		}
	end
	for _, mod in ipairs(core.get_modnames()) do
		local path = core.get_modpath(mod)
		local files = {}
		for _, sub in ipairs({"textures", "sounds", "models"}) do
			for _, f in ipairs(core.get_dir_list(path .. "/" .. sub, false) or {}) do
				files[#files + 1] = sub .. "/" .. f
			end
		end
		d.media[mod] = files
	end
	local f = assert(io.open(core.get_worldpath() .. "/dump.json", "w"))
	f:write(core.write_json(d, true))
	f:close()
	core.log("action", "goodluck_dump: done")
	core.request_shutdown("dump done")
end)
