-- Hunger costs as in Minecraft: walking, placing and crafting are free, digging and jumping cost little
-- (stamina takes a point for every 160 of exhaustion); running drains stamina_sprint_drain points a second
if not core.get_modpath("stamina") then
	return
end
stamina.EXHAUST_MOVE = 0
stamina.EXHAUST_PLACE = 0
stamina.EXHAUST_CRAFT = 0
stamina.EXHAUST_DIG = 0.2  -- 800 nodes a point
stamina.EXHAUST_JUMP = 2   -- about 80 jumps a point
