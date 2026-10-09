#pragma once
// The launcher options in ~/.config/puppy/settings, with puppy.conf's view and tabs as the defaults.
// Outside Puppy, appctl reads loading= from the same file for its loading screen and gl-tr language=.
#include <string>
#include <vector>

struct Prefs {
    bool listView = false;
    bool showTabs = true;
    std::vector<std::string> hiddenTabs;    // left out of the tab strip; their games stay in All Games
    std::string language;                   // a code of /usr/share/goodluck/lang ("" : not chosen)
    std::string font;                       // a fonts.h key ("": not chosen)
    bool loadingText = false;               // "Loading..." instead of the ASCII-art dog while an app starts

    static Prefs load();
    void save() const;                      // keeps the lines it doesn't know
};
