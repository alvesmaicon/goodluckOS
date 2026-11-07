#include "games.h"

#include <algorithm>
#include <cctype>
#include <map>

#include <dirent.h>
#include <sys/stat.h>

#include "systems.h"

std::vector<NativeGame> nativeGames(const std::vector<std::string>& appsFiles, const std::string& installed) {
    std::vector<NativeGame> out;
    auto add = [&](const std::string& section, const std::map<std::string, std::string>& kv, const char* category) {
        auto get = [&](const char* k) {
            auto it = kv.find(k);
            return it == kv.end() ? std::string() : it->second;
        };
        const std::string cat = get("CATEGORY").empty() ? category : get("CATEGORY");
        struct stat st;
        const std::string hideIf = get("HIDE_IF_EXISTS");
        if (section != "ENTRY" || cat != "Games" || get("NAME").empty() || get("COMMAND").empty() ||
            (!hideIf.empty() && stat(hideIf.c_str(), &st) == 0))
            return;
        NativeGame g{get("NAME"), get("SCREENSCRAPER")};
        auto same = std::find_if(out.begin(), out.end(), [&](const NativeGame& o) { return o.name == g.name; });
        if (same != out.end()) *same = g;
        else out.push_back(g);
    };
    appsSections(appsFiles, [&](const std::string& s, const std::map<std::string, std::string>& kv) { add(s, kv, "Applications"); });
    std::vector<std::string> apps;
    if (DIR* d = opendir(installed.c_str())) {
        while (struct dirent* e = readdir(d))
            if (e->d_name[0] != '.') apps.push_back(installed + "/" + e->d_name + "/app.puppy");
        closedir(d);
    }
    std::sort(apps.begin(), apps.end());
    for (const std::string& f : apps)
        appsSections({f}, [&](const std::string& s, const std::map<std::string, std::string>& kv) { add(s, kv, "Apps"); });
    return out;
}

static std::string letters(const std::string& s) {
    std::string out;
    for (unsigned char c : s)
        if (isalnum(c) || c >= 0x80) out += (char)tolower(c);
    return out;
}

bool sameName(const std::string& theirs, const std::string& ours) {
    const std::string want = letters(ours);
    if (want.empty()) return false;
    if (letters(theirs) == want) return true;
    size_t cut = theirs.rfind(':');
    const size_t dash = theirs.rfind(" - ");
    if (dash != std::string::npos && (cut == std::string::npos || dash > cut)) cut = dash + 2;
    return cut != std::string::npos && letters(theirs.substr(cut + 1)) == want;
}

const Json* chooseGame(const std::vector<Json>& games, const std::string& name) {
    const Json* best = nullptr;
    std::string bestDate;
    bool bestVideo = false;
    for (const Json& g : games) {
        bool named = false;
        for (const auto& n : g["names"].fields) named = named || sameName(n.second.text, name);
        if (!named) continue;
        std::string date = "9999";
        for (const auto& d : g["dates"].fields)
            if (!d.second.text.empty() && d.second.text < date) date = d.second.text;
        bool video = false;
        for (const Json& m : g["medias"].items) video = video || m["type"].text == "video-normalized";
        if (!best || date.substr(0, 4) < bestDate.substr(0, 4) ||
            (date.substr(0, 4) == bestDate.substr(0, 4) && (video > bestVideo || (video == bestVideo && date < bestDate)))) {
            best = &g;
            bestDate = date;
            bestVideo = video;
        }
    }
    return best;
}
