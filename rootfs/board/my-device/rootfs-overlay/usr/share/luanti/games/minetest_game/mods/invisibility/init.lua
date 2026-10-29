-- mobs_redo leaves a player alone when a mod by this name says they can't be seen: goodluck_effects' Invisibility
invisibility = {}

function invisibility.is_visible(name)
	local player = core.get_player_by_name(name)
	return not (player and core.global_exists("goodluck_effects") and goodluck_effects.get(player, "invisibility"))
end
