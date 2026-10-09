#pragma once
#include <string>
#include <vector>

struct Entry {
    std::string category;
    std::string id;         // stable identity (the ROM file name without extension, or the app name),
                            // used for favourites, autolaunch and the cursor; the name can come from a gamelist
    std::string name;
    std::string description;    // the system or app description
    bool terminal = false;      // apps.puppy TERMINAL=: runs on the text console (less, vim, shells)
    std::string synopsis;       // from gamelist.xml
    std::string meta;           // "year · genre · players", from gamelist.xml
    std::string command;
    std::string iconPath;
    std::string searchKey;  // lowercase name, filled once the catalog is loaded
    std::string tag;        // short system name, shown next to the entry in the "All Games" tab
    std::string file;       // the ROM file (archive entries): what Rename and Delete act on
};

// One tab of the launcher (a console or an apps category).
struct Category {
    std::string name;
    std::string label;          // short name for the tab strip (TAB= in apps.puppy), defaults to the name
    bool isArchive = false;     // games from a ROM folder, as opposed to apps
    bool media = false;         // music or videos: not games, so left out of All Games
    bool mixed = false;         // the "All Games" tab: entries from every system
    std::vector<Entry> entries;
    std::vector<int> visible;   // indices of the entries matching the search, in display order
    int sel = 0;                // position in 'visible'
    mutable int scroll = 0;     // first list row / grid row on screen, kept in view by the renderer
    mutable int tagColumn = -1; // list view: width of the system tag column (-1: to be measured)
    bool hidden = false;        // left out of the tab strip (System Settings); still in All Games / My List
};

std::vector<Category> loadCatalog();

// XML helpers, also used to rename a game in its gamelists
std::string xmlTag(const std::string& block, const std::string& tag);
std::string xmlUnescape(const std::string& s);
std::string xmlEscape(const std::string& s);
std::string stripDotSlash(std::string p);
