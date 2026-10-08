#pragma once
#include <SDL2/SDL.h>

#include <algorithm>
#include <set>
#include <string>
#include <vector>

#include "catalog.h"
#include "util.h"

enum class View { Grid, List };

// One action of the POWER menu (see powerItems).
struct PowerItem {
    const char* label;
    const char* request;    // for the power_fifo daemon (nullptr: none)
    const char* status;     // shown while it happens (nullptr: nothing to wait for)
    const char* confirmEntry;   // System entry to launch (nullptr: none)
    const std::string* command; // puppy.conf command (nullptr: none)
    bool quit = false;      // leave Puppy without launching anything
};

struct Model {
    std::vector<Category> categories;
    int tab = 0;
    View view = View::Grid;
    bool showTabs = true;
    std::string query;
    std::string autoCategory, autoName;   // the autolaunch entry
    std::set<std::string> favorites;      // "category<TAB>name" of the entries in My List

    static std::string favoriteKey(const Entry& e) { return e.category + "\t" + e.id; }
    bool isFavorite(const Entry& e) const { return favorites.count(favoriteKey(e)) > 0; }

    // START opens System Settings; POWER opens the power menu (both from any tab)
    Entry settings;
    bool hasSettings = false;
    std::vector<Entry> systemEntries;   // the System category, e.g. Reboot/Power Off with their are-you-sure
    bool menuOpen = false;
    // The POWER menu, or the game options menu (L2 + R2) and its delete confirmation
    enum class Menu { Power, Game, ConfirmDelete };
    Menu menuKind = Menu::Power;
    std::vector<PowerItem> menuItems;   // Power: filled when the menu opens
    std::vector<std::string> menuLabels;    // Game / ConfirmDelete
    Entry menuEntry;                    // the game those act on
    int menuSel = 0;
    int menuCount() const { return menuKind == Menu::Power ? (int)menuItems.size() : (int)menuLabels.size(); }
    bool renaming = false;      // the keyboard edits renameText (the game's name), not the search
    std::string renameText;
    size_t renameCursor = 0;    // byte position in renameText, moved with L1/R1
    std::string notice;         // short message over the footer (renamed, moved to the trash...)
    std::string clock;          // date and/or time in the top bar, per System Settings -> Date & Time
    Uint32 noticeUntil = 0;
    std::string status;     // full-screen message while restarting / shutting down
    int descScroll = 0;     // lines the list preview's description is scrolled (right stick)

    Category& cur() { return categories[tab]; }
    const Category& cur() const { return categories[tab]; }

    int selectedIndex() const {
        if (categories.empty()) return -1;
        const Category& c = cur();
        if (c.visible.empty()) return -1;
        return c.visible[std::clamp(c.sel, 0, (int)c.visible.size() - 1)];
    }

    const Entry* selected() const {
        int i = selectedIndex();
        return i < 0 ? nullptr : &cur().entries[i];
    }

    // Rebuilds every tab's visible entries from the query, keeping the selection when it still matches.
    void applyFilter() {
        const std::string q = lower(query);
        for (auto& c : categories) {
            int keep = c.visible.empty() ? -1 : c.visible[std::clamp(c.sel, 0, (int)c.visible.size() - 1)];
            c.visible.clear();
            for (int i = 0; i < (int)c.entries.size(); ++i) {
                if (q.empty() || c.entries[i].searchKey.find(q) != std::string::npos) c.visible.push_back(i);
            }
            c.sel = 0;
            for (int k = 0; k < (int)c.visible.size(); ++k) {
                if (c.visible[k] == keep) { c.sel = k; break; }
            }
        }
    }

    void switchTab(int delta) {
        descScroll = 0;
        int n = (int)categories.size();
        for (int i = 0; i < n; ++i) {   // skipping hidden tabs
            tab = ((tab + delta) % n + n) % n;
            if (!categories[tab].hidden) break;
        }
    }

    void moveSel(int delta) {
        descScroll = 0;
        Category& c = cur();
        if (c.visible.empty()) return;
        c.sel = std::clamp(c.sel + delta, 0, (int)c.visible.size() - 1);
    }

    void select(int t, int entry) {
        tab = t;
        Category& c = categories[t];
        for (int k = 0; k < (int)c.visible.size(); ++k) {
            if (c.visible[k] == entry) { c.sel = k; return; }
        }
    }

    bool isAutoStart(const Entry& e) const {
        return !autoName.empty() && e.category == autoCategory && e.id == autoName;
    }

    // Finds an entry (by its category and name) in the tab called tabName.
    bool find(const std::string& tabName, const std::string& category, const std::string& name,
              int& outTab, int& outEntry) const {
        for (size_t t = 0; t < categories.size(); ++t) {
            if (categories[t].name != tabName) continue;
            for (size_t e = 0; e < categories[t].entries.size(); ++e) {
                const Entry& entry = categories[t].entries[e];
                if (entry.category == category && entry.id == name) {
                    outTab = (int)t;
                    outEntry = (int)e;
                    return true;
                }
            }
        }
        return false;
    }
};
