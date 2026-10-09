#pragma once
// The accent colours System Settings offers (Interface -> Accent color): the selection, the hints'
// buttons, the bars. The choice is accent=<key> in the settings file (see Prefs); layout.h's accent()
// returns the current one. All are bright enough for black text on them.
#include <SDL2/SDL.h>

#include <string>
#include <vector>

namespace accents {

struct Accent {
    const char* key;    // saved in the settings file
    const char* name;   // English, shown in the list of System Settings
    SDL_Color color;
};

const std::vector<Accent>& all();
int find(const std::string& key);       // the index in all(); 0 (yellow) for an unknown key
void choose(const std::string& key);    // the colour accent() returns from now on
std::string hex(SDL_Color c);           // "rrggbb", as gallium_hud.conf has it

}  // namespace accents
