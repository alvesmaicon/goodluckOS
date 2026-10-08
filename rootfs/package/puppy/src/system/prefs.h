#pragma once
// The launcher options in ~/.config/puppy/settings, with puppy.conf's view and tabs as the defaults.
// appctl reads loading= from the same file for its loading screen.
#include <string>
#include <vector>

struct Prefs {
    bool listView = false;
    bool showTabs = true;
    std::vector<std::string> hiddenTabs;    // left out of the tab strip; their games stay in All Games

    static Prefs load();
};
