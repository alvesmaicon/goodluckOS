#pragma once
// The interface styles System Settings offers (Interface -> Style): retro, Puppy's own look; modern,
// Vitrine's (Jeferson Lopes, upstream PR 51); and vitrine, modern in Vitrine's Shelf and Streaming
// layouts. The choice is style=<key> in the settings file (see Prefs); layout.h's theme() returns the
// current one's colours.
#include <string>
#include <vector>

#include "layout.h"

namespace styles {

struct Style {
    const char* key;    // saved in the settings file
    const char* name;   // English, shown in System Settings
    Theme theme;
};

const std::vector<Style>& all();
int find(const std::string& key);       // the index in all(); 0 (retro) for an unknown key
void choose(const std::string& key);    // the colours theme() returns from now on

}  // namespace styles
