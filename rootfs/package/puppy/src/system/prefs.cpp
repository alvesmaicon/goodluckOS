#include "system/prefs.h"

#include <fstream>

#include "config.h"
#include "util.h"

static bool startsWith(const std::string& s, const char* prefix) {
    return s.compare(0, std::char_traits<char>::length(prefix), prefix) == 0;
}

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
        else if (startsWith(line, "hidden_tab=")) p.hiddenTabs.push_back(line.substr(11));
        else if (startsWith(line, "language=") && line.size() > 9) p.language = line.substr(9);
        else if (startsWith(line, "font=") && line.size() > 5) p.font = line.substr(5);
        else if (line == "loading=text") p.loadingText = true;
    }
    return p;
}

void Prefs::save() const {
    std::vector<std::string> lines;
    {
        std::ifstream in(cfg.settingsFile());
        for (std::string line; std::getline(in, line);) {
            if (line.empty() || startsWith(line, "view=") || startsWith(line, "tabs=") || startsWith(line, "language=") ||
                startsWith(line, "font=") || startsWith(line, "hidden_tab=") || startsWith(line, "loading=")) continue;
            lines.push_back(line);
        }
    }
    lines.push_back(std::string("view=") + (listView ? "list" : "grid"));
    lines.push_back(std::string("tabs=") + (showTabs ? "on" : "off"));
    if (!language.empty()) lines.push_back("language=" + language);
    if (!font.empty()) lines.push_back("font=" + font);
    if (loadingText) lines.push_back("loading=text");
    for (const auto& t : hiddenTabs) lines.push_back("hidden_tab=" + t);

    std::error_code ec;
    fs::create_directories(cfg.configDir, ec);
    const std::string tmp = cfg.settingsFile() + ".tmp";
    {
        std::ofstream out(tmp);
        if (!out) return;
        for (const auto& line : lines) out << line << "\n";
    }
    fs::rename(tmp, cfg.settingsFile(), ec);
}
