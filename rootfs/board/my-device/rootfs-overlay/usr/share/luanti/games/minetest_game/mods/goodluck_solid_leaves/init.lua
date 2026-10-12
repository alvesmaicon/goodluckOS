-- Waving leaves draw all six faces of every node even with leaves_style opaque and waving off (node_visuals.cpp)
if core.settings:get("leaves_style") == "opaque" and not core.settings:get_bool("enable_waving_leaves", false) then
	core.register_on_mods_loaded(function()
		for name, def in pairs(core.registered_nodes) do
			if def.drawtype == "allfaces_optional" and (def.waving or 0) > 0 then
				core.override_item(name, {waving = 0})
			end
		end
	end)
end
