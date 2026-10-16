-- Monsters chase at 2 nodes a second and walk at 1, half and a quarter of a walking player (4); mobs_monster's run at
-- 3, the sand monster at 4, close to a running player. The entity definitions are what each mob reads its speeds from
local RUN, WALK = 2, 1

core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_entities) do
		if name:find("^mobs_monster:") and def.run_velocity then
			def.run_velocity = math.min(def.run_velocity, RUN)
			def.walk_velocity = math.min(def.walk_velocity or WALK, WALK)
		end
	end
end)
