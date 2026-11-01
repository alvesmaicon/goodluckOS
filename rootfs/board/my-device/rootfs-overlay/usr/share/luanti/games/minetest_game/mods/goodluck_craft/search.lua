-- The creative inventory's and the Recipes page's search: it finds an item by the name the player sees (the first
-- line of its description, in the player's language), with no regard to case or accents (the on-screen keyboard has
-- none)
local names = {}

-- Latin-1's letters (U+00C0-U+00FF) are \195\128-\195\191 in UTF-8, the capitals 32 before the small ones
local FOLD = {}
local BASE = "aaaaaaaceeeeiiiidnooooo ouuuuy  "
for i = 1, #BASE do
	local c = BASE:sub(i, i)
	if c ~= " " then
		FOLD["\195" .. string.char(127 + i)] = c
		FOLD["\195" .. string.char(159 + i)] = c
	end
end

function goodluck_craft.fold(text)
	return (text:lower():gsub("\195[\128-\191]", FOLD))
end

function goodluck_craft.lang(player)
	local info = core.get_player_information(player:get_player_name())
	return info and info.lang_code or ""
end

function goodluck_craft.search_name(item, lang)
	names[lang] = names[lang] or {}
	local name = names[lang][item]
	if not name then
		local def = core.registered_items[item]
		name = goodluck_craft.fold(core.get_translated_string(lang, def and def.description or ""):match("^[^\n]*"))
		names[lang][item] = name
	end
	return name
end
