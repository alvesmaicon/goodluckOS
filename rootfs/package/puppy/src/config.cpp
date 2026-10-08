#include "config.h"

#include <cstdlib>
#include <fstream>
#include <iostream>
#include <map>

#include "util.h"

Config cfg;

// Reads puppy.conf: "key = value" lines, "#" comments, lists separated by ";". Relative paths are
// relative to the file, "~/" is the home folder. The file is the one given with --config, else
// $PUPPY_CONFIG, else /etc/puppy.conf; without one, the goodluckOS defaults stay.
bool loadConfig(int argc, char** argv) {
    std::string path;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if ((arg == "--config" || arg == "-c") && i + 1 < argc) path = argv[++i];
        else if (arg.compare(0, 9, "--config=") == 0) path = arg.substr(9);
        else { std::cerr << "Usage: puppy [--config puppy.conf]\n"; return false; }
    }
    const bool given = !path.empty() || getenv("PUPPY_CONFIG");
    if (path.empty() && getenv("PUPPY_CONFIG")) path = getenv("PUPPY_CONFIG");
    if (path.empty()) path = "/etc/puppy.conf";

    std::ifstream in(path);
    if (!in) {
        if (given) { std::cerr << "Can't read " << path << "\n"; return false; }
        return true;
    }
    const fs::path base = fs::absolute(fs::path(path)).parent_path();
    auto file = [&](const std::string& v) {
        if (v.empty()) return v;
        const std::string p = expandHome(v);
        return p[0] == '/' ? p : (base / p).lexically_normal().string();
    };
    auto files = [&](const std::string& v) {
        std::vector<std::string> out;
        for (const auto& item : splitList(v)) out.push_back(file(item));
        return out;
    };
    std::map<std::string, std::string*> paths = {
        {"font", &cfg.font}, {"fallback_icon", &cfg.fallbackIcon}, {"launch_file", &cfg.launchFile},
        {"autolaunch_mark", &cfg.autoStartMark},
        {"state_file", &cfg.stateFile}, {"autolaunch_file", &cfg.autoStartFile}, {"config_dir", &cfg.configDir},
        {"cache_dir", &cfg.cacheDir}, {"lang_dir", &cfg.langDir}, {"power_fifo", &cfg.powerFifo},
        {"backlight", &cfg.backlight}, {"trash_dir", &cfg.trashDir},
        {"alsa_card", &cfg.alsaCard},
    };
    std::map<std::string, std::string*> texts = {
        {"language", &cfg.language}, {"view", &cfg.view}, {"tabs", &cfg.tabs},
        {"launch_command", &cfg.launchCommand},
        {"settings_command", &cfg.settingsCommand}, {"restart_command", &cfg.restartCommand},
        {"shutdown_command", &cfg.shutdownCommand}, {"screen_off_command", &cfg.screenOffCommand},
    };
    std::map<std::string, std::vector<std::string>*> lists = {
        {"apps", &cfg.apps}, {"apps_dirs", &cfg.appsDirs}, {"es_systems", &cfg.esSystems},
        {"save_dirs", &cfg.saveDirs},
    };

    int lineNo = 0;
    for (std::string line; std::getline(in, line);) {
        ++lineNo;
        line = trim(line);
        if (line.empty() || line[0] == '#') continue;
        size_t eq = line.find('=');
        if (eq == std::string::npos) { std::cerr << path << ":" << lineNo << ": expected key = value\n"; continue; }
        const std::string key = lower(trim(line.substr(0, eq))), value = trim(line.substr(eq + 1));
        if (auto it = paths.find(key); it != paths.end()) *it->second = file(value);
        else if (auto it = texts.find(key); it != texts.end()) *it->second = value;
        else if (auto it = lists.find(key); it != lists.end()) *it->second = files(value);
        else if (key == "quit") cfg.quit = value == "on" || value == "yes" || value == "true" || value == "1";
        else std::cerr << path << ":" << lineNo << ": unknown setting " << key << "\n";
    }
    return true;
}
