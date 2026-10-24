-- Steps up only from the ground, as in Minecraft: the engine's legacy mode lifts a rising jump onto the block it
-- touches, still rising, and counts it as ground, so a jump held against a stair jumps again from it
core.register_on_joinplayer(function(player)
	player:set_properties({step_up_mode = "rigid"})
end)
