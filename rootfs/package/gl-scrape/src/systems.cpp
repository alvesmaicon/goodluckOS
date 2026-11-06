#include "systems.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <fstream>

#include <dirent.h>
#include <sys/stat.h>

static std::string trim(const std::string& s) {
    const size_t a = s.find_first_not_of(" \t\r\n");
    return a == std::string::npos ? "" : s.substr(a, s.find_last_not_of(" \t\r\n") - a + 1);
}

static std::string upper(std::string s) {
    for (char& c : s) c = (char)toupper((unsigned char)c);
    return s;
}

static std::vector<std::string> splitList(const std::string& s, char sep) {
    std::vector<std::string> out;
    for (size_t p = 0; p <= s.size();) {
        size_t q = s.find(sep, p);
        if (q == std::string::npos) q = s.size();
        const std::string item = trim(s.substr(p, q - p));
        if (!item.empty()) out.push_back(item);
        p = q + 1;
    }
    return out;
}

struct Archive {
    std::string name, tab;
    std::vector<std::string> dirs, exts;
    bool media;
};

static void parseFile(const std::string& path, const AppsSection& each) {
    std::ifstream in(path);
    if (!in) return;
    std::string section;
    std::map<std::string, std::string> kv;
    auto flush = [&] {
        if (!section.empty()) each(section, kv);
        kv.clear();
    };
    for (std::string line; std::getline(in, line);) {
        line = trim(line);
        if (line.empty() || line[0] == '#' || line[0] == ';') continue;
        if (line.front() == '[' && line.back() == ']') {
            flush();
            section = upper(trim(line.substr(1, line.size() - 2)));
            continue;
        }
        const size_t eq = line.find('=');
        if (eq != std::string::npos) kv[upper(trim(line.substr(0, eq)))] = trim(line.substr(eq + 1));
    }
    flush();
}

void appsSections(const std::vector<std::string>& appsFiles, const AppsSection& each) {
    for (const std::string& path : appsFiles) {
        struct stat st;
        if (stat(path.c_str(), &st) != 0) continue;
        if (!S_ISDIR(st.st_mode)) {
            parseFile(path, each);
            continue;
        }
        std::vector<std::string> files;
        if (DIR* d = opendir(path.c_str())) {
            while (struct dirent* e = readdir(d)) {
                const std::string n = e->d_name;
                if (n.size() > 6 && n.compare(n.size() - 6, 6, ".puppy") == 0) files.push_back(path + "/" + n);
            }
            closedir(d);
        }
        std::sort(files.begin(), files.end());
        for (const std::string& f : files) parseFile(f, each);
    }
}

std::vector<RomDir> romDirs(const std::vector<std::string>& appsFiles) {
    std::vector<Archive> archives;
    appsSections(appsFiles, [&](const std::string& section, std::map<std::string, std::string> kv) {
        Archive a{kv["NAME"], kv["TAB"], splitList(kv["ENTRY_DIRECTORIES"], ';'), splitList(kv["ENTRY_EXTENSIONS"], ';'),
                  !kv["MEDIA"].empty() && kv["MEDIA"] != "0"};
        if (section != "ARCHIVE" || a.name.empty() || a.dirs.empty()) return;
        for (std::string& e : a.exts)
            for (char& c : e) c = (char)tolower((unsigned char)c);
        auto same = std::find_if(archives.begin(), archives.end(), [&](const Archive& b) { return b.name == a.name; });
        if (same != archives.end()) *same = a;
        else archives.push_back(a);
    });
    std::vector<RomDir> out;
    for (const Archive& a : archives)
        for (std::string dir : a.media ? std::vector<std::string>() : a.dirs) {
            while (dir.size() > 1 && dir.back() == '/') dir.pop_back();
            if (std::any_of(out.begin(), out.end(), [&](const RomDir& r) { return r.dir == dir; })) continue;
            RomDir r{dir, dir.substr(dir.find_last_of('/') + 1), a.tab.empty() ? a.name : a.tab, {a.name}, a.exts};
            if (!a.tab.empty()) r.names.push_back(a.tab);
            out.push_back(r);
        }
    return out;
}

// "Sega Mega-CD" -> "segamegacd"
static std::string key(const std::string& name) {
    std::string out;
    for (unsigned char c : name)
        if (isalnum(c) && c < 0x80) out += (char)tolower(c);
    return out;
}

static void add(std::map<std::string, int>& names, const std::string& list, int id) {
    for (const std::string& n : splitList(list, ',')) {
        const std::string k = key(n);
        if (k.empty()) continue;
        auto it = names.find(k);
        if (it == names.end() || id < it->second) names[k] = id;
    }
}

bool Systems::fromList(const Json& answer) {
    std::map<std::string, int> o, e;
    for (const Json& s : answer["response"]["systemes"].items) {
        const int id = atoi(s["id"].text.c_str());
        const Json& n = s["noms"];
        if (id <= 0) continue;
        for (const char* k : {"noms_commun", "nom_eu", "nom_us", "nom_jp"}) add(o, n[k].text, id);
        for (const char* k : {"nom_recalbox", "nom_retropie"}) add(e, n[k].text, id);
    }
    if (o.empty()) return false;
    own.swap(o);
    es.swap(e);
    return true;
}

bool Systems::load(const std::string& path) {
    std::ifstream in(path);
    std::map<std::string, int> o, e;
    for (std::string line; std::getline(in, line);) {
        const std::vector<std::string> f = splitList(line, '\t');
        if (f.size() == 3) (f[0] == "es" ? e : o)[f[1]] = atoi(f[2].c_str());
    }
    if (o.empty()) return false;
    own.swap(o);
    es.swap(e);
    return true;
}

std::string Systems::dump() const {
    std::string out;
    for (const auto& [n, id] : own) out += "own\t" + n + "\t" + std::to_string(id) + "\n";
    for (const auto& [n, id] : es) out += "es\t" + n + "\t" + std::to_string(id) + "\n";
    return out;
}

// The folder's name as a system's name (gba, megadrive, cps1), as a Recalbox or RetroPie folder
// (fbneo), then the tab's name (sfc in "Super Nintendo")
int Systems::find(const RomDir& d) const {
    const std::string folder = key(d.folder);
    if (auto it = own.find(folder); it != own.end()) return it->second;
    if (auto it = es.find(folder); it != es.end()) return it->second;
    for (const std::string& n : d.names)
        if (auto it = own.find(key(n)); it != own.end()) return it->second;
    return 0;
}
