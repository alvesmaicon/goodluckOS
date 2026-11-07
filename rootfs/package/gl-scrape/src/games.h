#pragma once
// The launcher's Games tab: the native games of Puppy's apps files and of the App Installer's apps.
// ScreenScraper has no file of theirs to recognise: an entry's SCREENSCRAPER= id, else a search by name.
#include <string>
#include <vector>

#include "json.h"

struct NativeGame {
    std::string name;   // NAME=, the key in the tab's gamelist
    std::string id;     // SCREENSCRAPER=, ScreenScraper's game id
};

// The [ENTRY]s with CATEGORY=Games of the apps files (a directory: its *.puppy files), then of each
// <installed>/<app>/app.puppy; a NAME= that comes again replaces the earlier one, as in Puppy
std::vector<NativeGame> nativeGames(const std::vector<std::string>& appsFiles, const std::string& installed);

// Whether a ScreenScraper name is this game's: the same letters and digits, alone or after the name's
// last ":" or " - " ("The Legend of Zelda : Ocarina of Time" is "Ocarina of Time")
bool sameName(const std::string& theirs, const std::string& ours);

// Among search results (records), the game named so: the oldest release, which is the original and not
// a later port of it, then one with a video; null when none has the name
const Json* chooseGame(const std::vector<Json>& games, const std::string& name);
