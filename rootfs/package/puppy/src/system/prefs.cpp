#include "system/prefs.h"

#include <fstream>

#include "config.h"
#include "util.h"

Prefs Prefs::load() {
    Prefs p;
    std::vector<std::string> lines;
    if (!cfg.view.empty()) lines.push_back("view=" + cfg.view);
    if (!cfg.tabs.empty()) lines.push_back("tabs=" + cfg.tabs);
    std::ifstream in(cfg.settingsFile());
    for (std::string line; std::getline(in, line);) lines.push_back(line);
    for (std::string line : lines) {
        line = trim(line);
        if (line == "view=list") p.listView = true;
        else if (line == "view=grid") p.listView = false;
        else if (line == "tabs=off") p.showTabs = false;
        else if (line == "tabs=on") p.showTabs = true;
        else if (line.compare(0, 11, "hidden_tab=") == 0) p.hiddenTabs.push_back(line.substr(11));
    }
    return p;
}
