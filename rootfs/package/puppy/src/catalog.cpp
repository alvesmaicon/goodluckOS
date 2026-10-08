#include "catalog.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <map>
#include <set>

#include "config.h"
#include "util.h"

struct Archive {
    std::string name, tab, description, command, defaultIcon;
    std::vector<std::string> dirs, exts, iconDirs;
    bool es = false;    // from es_systems.cfg: the command uses %ROM%-style placeholders
    bool media = false; // MEDIA=1: folders with matching files (albums, series) are entries too
    std::string system, emulator, core;     // for %SYSTEM%, %EMULATOR% and %CORE%
};

struct Record {
    bool isArchive = false;
    Entry entry;
    Archive archive;

    std::string key() const {
        return isArchive ? "A\x1f" + archive.name
                         : "E\x1f" + entry.category + "\x1f" + entry.name;
    }
};

static void upsert(std::vector<Record>& records, const Record& rec) {
    const std::string k = rec.key();
    for (auto& existing : records) {
        if (existing.key() == k) {
            existing = rec;
            return;
        }
    }
    records.push_back(rec);
}

static void parseAppsFile(const std::string& path, std::vector<Record>& records) {
    std::ifstream in(path);
    if (!in) return;

    std::string section;
    std::map<std::string, std::string> kv;

    auto get = [&](const char* key) {
        auto it = kv.find(key);
        return it == kv.end() ? std::string() : it->second;
    };

    auto flush = [&]() {
        if (section == "ENTRY") {
            Record rec;
            rec.entry.category    = get("CATEGORY").empty() ? "Applications" : get("CATEGORY");
            rec.entry.name        = get("NAME");
            rec.entry.id          = rec.entry.name;
            rec.entry.description = get("DESCRIPTION");
            rec.entry.command     = get("COMMAND");
            rec.entry.terminal    = !get("TERMINAL").empty();
            rec.entry.iconPath    = get("ICON");
            // HIDE_IF_EXISTS=<path>: one-time entries (e.g. a first-boot setup) disappear once their job is done
            std::error_code ec;
            const std::string hideIf = get("HIDE_IF_EXISTS");
            bool hidden = !hideIf.empty() && fs::exists(hideIf, ec);
            if (!hidden && !rec.entry.name.empty() && !rec.entry.command.empty()) upsert(records, rec);
        } else if (section == "ARCHIVE") {
            Record rec;
            rec.isArchive = true;
            Archive& a = rec.archive;
            a.name        = get("NAME");
            a.description = get("DESCRIPTION");
            a.command     = get("COMMAND");
            a.defaultIcon = get("DEFAULT_ICON");
            a.dirs        = splitList(get("ENTRY_DIRECTORIES"));
            a.exts        = splitList(get("ENTRY_EXTENSIONS"));
            a.iconDirs    = splitList(get("ENTRY_ICONS_DIRECTORIES"));
            a.tab         = get("TAB");
            a.media       = !get("MEDIA").empty() && get("MEDIA") != "0";
            if (!a.name.empty() && !a.dirs.empty()) upsert(records, rec);
        }
        kv.clear();
    };

    std::string line;
    while (std::getline(in, line)) {
        line = trim(line);
        if (line.empty() || line[0] == '#' || line[0] == ';') continue;

        if (line.front() == '[' && line.back() == ']') {
            flush();
            section = upper(trim(line.substr(1, line.size() - 2)));
            continue;
        }

        size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        kv[upper(trim(line.substr(0, eq)))] = trim(line.substr(eq + 1));
    }
    flush();
}

// Short tab labels for EmulationStation's usual system names; other systems show their full name.
static std::string esTabLabel(const std::string& name, const std::string& fullname) {
    static const std::map<std::string, std::string> kLabels = {
        {"3do", "3DO"}, {"amiga", "Amiga"}, {"arcade", "Arcade"}, {"atari2600", "2600"}, {"atari7800", "7800"},
        {"atarilynx", "Lynx"}, {"cps1", "CPS1"}, {"cps2", "CPS2"}, {"cps3", "CPS3"}, {"dreamcast", "DC"},
        {"famicom", "FC"}, {"fbneo", "FBNeo"}, {"fds", "FDS"}, {"gamegear", "GG"}, {"gb", "GB"}, {"gba", "GBA"},
        {"gbc", "GBC"}, {"genesis", "Genesis"}, {"mame", "MAME"}, {"mastersystem", "SMS"}, {"megadrive", "MD"},
        {"msx", "MSX"}, {"n64", "N64"}, {"nds", "NDS"}, {"neogeo", "Neo Geo"}, {"nes", "NES"}, {"ngp", "NGP"},
        {"ngpc", "NGPC"}, {"pcengine", "PCE"}, {"pico8", "PICO-8"}, {"ports", "Ports"}, {"psp", "PSP"},
        {"psx", "PS1"}, {"saturn", "Saturn"}, {"sega32x", "32X"}, {"segacd", "Sega CD"}, {"sfc", "SFC"},
        {"snes", "SNES"}, {"tg16", "TG16"}, {"wonderswan", "WS"}, {"wonderswancolor", "WSC"},
    };
    auto it = kLabels.find(lower(name));
    return it != kLabels.end() ? it->second : (fullname.empty() ? name : fullname);
}

// Adds the systems of an EmulationStation es_systems.cfg as archives (one tab per system with games).
static void parseEsSystems(const std::string& path, std::vector<Record>& records) {
    std::ifstream in(path, std::ios::binary);
    if (!in) return;
    std::string xml((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    // drop comments, so commented-out systems stay out
    for (size_t a; (a = xml.find("<!--")) != std::string::npos;) {
        size_t b = xml.find("-->", a);
        xml.erase(a, b == std::string::npos ? std::string::npos : b + 3 - a);
    }

    for (size_t pos = 0; (pos = xml.find("<system>", pos)) != std::string::npos;) {
        size_t end = xml.find("</system>", pos);
        if (end == std::string::npos) break;
        const std::string block = xml.substr(pos, end - pos);
        pos = end + 9;

        Record rec;
        rec.isArchive = true;
        Archive& a = rec.archive;
        a.es = true;
        a.system = xmlTag(block, "name");
        const std::string fullname = xmlTag(block, "fullname");
        a.name = fullname.empty() ? a.system : fullname;
        a.tab = esTabLabel(a.system, fullname);
        a.description = fullname;
        a.command = xmlTag(block, "command");
        const std::string dir = expandHome(xmlTag(block, "path"));
        if (a.name.empty() || dir.empty() || a.command.empty()) continue;
        a.dirs = {dir};
        a.iconDirs = {dir + "/icons"};
        // ".nes .NES .zip"
        std::string ext;
        for (char c : xmlTag(block, "extension") + " ") {
            if (std::isspace((unsigned char)c)) {
                if (!ext.empty() && std::find(a.exts.begin(), a.exts.end(), lower(ext)) == a.exts.end())
                    a.exts.push_back(lower(ext));
                ext.clear();
            } else {
                ext += c;
            }
        }
        // ES forks with an emulator/core choice: use the first (default) ones
        size_t em = block.find("<emulator ");
        if (em != std::string::npos) {
            size_t q1 = block.find("name=\"", em), close = block.find('>', em);
            if (q1 != std::string::npos && q1 < close) {
                q1 += 6;
                a.emulator = block.substr(q1, block.find('"', q1) - q1);
            }
            a.core = xmlTag(block.substr(em), "core");
        }
        upsert(records, rec);
    }
}

// An es_systems.cfg command for one ROM. %ROM% is quoted for the shell; placeholders Puppy doesn't
// know (e.g. %GOVERNOR%) are removed.
static std::string buildEsCommand(const Archive& a, const fs::path& rom) {
    const std::map<std::string, std::string> values = {
        {"ROM", shellQuote(rom.string())}, {"ROM_RAW", rom.string()}, {"BASENAME", rom.stem().string()},
        {"SYSTEM", a.system}, {"EMULATOR", a.emulator}, {"CORE", a.core}, {"HOME", homeDir()},
    };
    std::string out;
    for (size_t i = 0; i < a.command.size();) {
        if (a.command[i] == '%') {
            size_t j = a.command.find('%', i + 1);
            if (j != std::string::npos) {
                const std::string key = a.command.substr(i + 1, j - i - 1);
                bool placeholder = !key.empty() && std::all_of(key.begin(), key.end(), [](char c) {
                    return std::isupper((unsigned char)c) || c == '_';
                });
                if (placeholder) {
                    auto it = values.find(key);
                    if (it != values.end()) out += it->second;
                    i = j + 1;
                    continue;
                }
            }
        }
        out += a.command[i++];
    }
    return out;
}

static std::string buildArchiveCommand(const std::string& tmpl, const std::string& path) {
    const std::string quoted = shellQuote(path);
    if (tmpl.empty()) return quoted;

    std::string out = tmpl;
    bool replaced = false;
    size_t pos = 0;
    while ((pos = out.find("%s", pos)) != std::string::npos) {
        out.replace(pos, 2, quoted);
        pos += quoted.size();
        replaced = true;
    }
    if (!replaced) out += " " + quoted;
    return out;
}

// Image with the ROM's name in one of the archive's icon folders, or "".
static std::string findArchiveIcon(const Archive& a, const std::string& stem) {
    static const char* kExts[] = {"png", "jpg", "jpeg"};
    for (const auto& dir : a.iconDirs) {
        for (const char* ext : kExts) {
            fs::path p = fs::path(dir) / (stem + "." + ext);
            std::error_code ec;
            if (fs::is_regular_file(p, ec)) return p.string();
        }
    }
    return {};
}

// An album's or series' cover.jpg / folder.jpg, or "".
static std::string findFolderCover(const fs::path& dir) {
    std::error_code ec;
    for (fs::directory_iterator it(dir, ec), end; !ec && it != end; it.increment(ec)) {
        const std::string stem = lower(it->path().stem().string());
        const std::string ext = lower(it->path().extension().string());
        if ((stem == "cover" || stem == "folder") && (ext == ".jpg" || ext == ".jpeg" || ext == ".png"))
            return it->path().string();
    }
    return {};
}

// What an EmulationStation/Skraper gamelist.xml says about one ROM.
struct GameInfo {
    std::string name, synopsis, image, meta;
};

static void appendUtf8(std::string& out, unsigned long cp) {
    if (cp < 0x80) out += (char)cp;
    else if (cp < 0x800) { out += (char)(0xC0 | (cp >> 6)); out += (char)(0x80 | (cp & 0x3F)); }
    else if (cp < 0x10000) { out += (char)(0xE0 | (cp >> 12)); out += (char)(0x80 | ((cp >> 6) & 0x3F)); out += (char)(0x80 | (cp & 0x3F)); }
    else { out += (char)(0xF0 | (cp >> 18)); out += (char)(0x80 | ((cp >> 12) & 0x3F)); out += (char)(0x80 | ((cp >> 6) & 0x3F)); out += (char)(0x80 | (cp & 0x3F)); }
}

std::string xmlUnescape(const std::string& s) {
    static const std::pair<const char*, const char*> kEntities[] = {
        {"&amp;", "&"}, {"&lt;", "<"}, {"&gt;", ">"}, {"&quot;", "\""}, {"&apos;", "'"}};
    std::string out;
    out.reserve(s.size());
    for (size_t i = 0; i < s.size();) {
        if (s[i] == '&') {
            size_t semi = s.find(';', i);
            if (semi != std::string::npos && semi - i <= 10) {
                const std::string ent = s.substr(i, semi - i + 1);
                bool done = false;
                for (const auto& [k, v] : kEntities) {
                    if (ent == k) { out += v; done = true; break; }
                }
                if (!done && ent.size() > 3 && ent[1] == '#') {
                    unsigned long cp = (ent[2] == 'x' || ent[2] == 'X') ? strtoul(ent.c_str() + 3, nullptr, 16)
                                                                       : strtoul(ent.c_str() + 2, nullptr, 10);
                    if (cp) { appendUtf8(out, cp); done = true; }
                }
                if (done) { i = semi + 1; continue; }
            }
        }
        out += s[i++];
    }
    return out;
}

// Text of <tag>...</tag> inside one <game> block.
std::string xmlTag(const std::string& block, const std::string& tag) {
    const std::string open = "<" + tag + ">", close = "</" + tag + ">";
    size_t a = block.find(open);
    if (a == std::string::npos) return {};
    a += open.size();
    size_t b = block.find(close, a);
    if (b == std::string::npos) return {};
    return trim(xmlUnescape(block.substr(a, b - a)));
}

std::string stripDotSlash(std::string p) {
    if (p.compare(0, 2, "./") == 0) p.erase(0, 2);
    return p;
}

// Reads one gamelist file (as written by Skraper or EmulationStation), keyed by ROM file name.
static std::map<std::string, GameInfo> readGamelistFile(const fs::path& dir, const std::string& file) {
    std::map<std::string, GameInfo> out;
    std::ifstream in(dir / file, std::ios::binary);
    if (!in) return out;
    const std::string xml((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());

    for (size_t pos = 0; (pos = xml.find("<game", pos)) != std::string::npos;) {
        // "<game>" or "<game id=...>", not "<gameList>"
        char next = pos + 5 < xml.size() ? xml[pos + 5] : '\0';
        if (next != '>' && next != ' ' && next != '\t') { pos += 5; continue; }
        size_t end = xml.find("</game>", pos);
        if (end == std::string::npos) break;
        const std::string block = xml.substr(pos, end - pos);
        pos = end + 7;

        const std::string path = stripDotSlash(xmlTag(block, "path"));
        if (path.empty()) continue;

        GameInfo g;
        g.name = xmlTag(block, "name");
        g.synopsis = xmlTag(block, "desc");
        const std::string image = stripDotSlash(xmlTag(block, "image"));
        if (!image.empty()) g.image = (image[0] == '/' ? fs::path(image) : dir / image).string();

        std::vector<std::string> meta;
        const std::string date = xmlTag(block, "releasedate");
        if (date.size() >= 4) meta.push_back(date.substr(0, 4));
        const std::string genre = xmlTag(block, "genre");
        if (!genre.empty()) meta.push_back(genre);
        const std::string players = xmlTag(block, "players");
        if (!players.empty()) meta.push_back(players + " " + tr(players == "1" ? "player" : "players"));
        for (size_t i = 0; i < meta.size(); ++i) g.meta += (i ? "  \u00b7  " : "") + meta[i];

        out[path] = std::move(g);
    }
    return out;
}

// dir/gamelist.xml, with names, descriptions and metadata replaced by the ones in the gamelist for the
// interface language when there is one: gamelist.<code>.xml (e.g. gamelist.pt-BR.xml), or
// gamelist.<language>.xml (gamelist.pt.xml). Images and anything it lacks come from gamelist.xml.
static std::map<std::string, GameInfo> loadGamelist(const fs::path& dir) {
    auto out = readGamelistFile(dir, "gamelist.xml");
    const std::string code = i18n::current();
    if (code.empty() || code == "en") return out;

    auto local = readGamelistFile(dir, "gamelist." + code + ".xml");
    if (local.empty() && code.find('-') != std::string::npos)
        local = readGamelistFile(dir, "gamelist." + code.substr(0, code.find('-')) + ".xml");
    for (auto& [path, l] : local) {
        GameInfo& g = out[path];
        if (!l.name.empty()) g.name = l.name;
        if (!l.synopsis.empty()) g.synopsis = l.synopsis;
        if (!l.meta.empty()) g.meta = l.meta;
        if (g.image.empty()) g.image = l.image;
    }
    return out;
}

static std::vector<Entry> expandArchive(const Archive& a) {
    std::vector<std::string> exts;
    for (auto e : a.exts) {
        if (!e.empty() && e[0] == '.') e.erase(0, 1);
        exts.push_back(lower(e));
    }

    auto matches = [&](const fs::path& p) {
        std::string ext = lower(p.extension().string());
        if (!ext.empty()) ext.erase(0, 1);
        return exts.empty() || std::find(exts.begin(), exts.end(), ext) != exts.end();
    };
    // a media folder (album, series) with at least one matching file
    auto mediaFolder = [&](const fs::path& d) {
        std::error_code ec;
        for (fs::directory_iterator it(d, ec), end; !ec && it != end; it.increment(ec)) {
            std::error_code ec2;
            if (it->is_regular_file(ec2) && matches(it->path())) return true;
        }
        return false;
    };

    std::vector<Entry> out;
    for (const auto& dir : a.dirs) {
        const auto gamelist = loadGamelist(dir);
        std::error_code ec;
        for (fs::directory_iterator it(dir, ec), end; !ec && it != end; it.increment(ec)) {
            const fs::path& p = it->path();
            if (p.filename().string().empty() || p.filename().string()[0] == '.') continue;

            std::error_code ec2;
            bool folder = a.media && it->is_directory(ec2) && mediaFolder(p);
            if (!folder && (!it->is_regular_file(ec2) || !matches(p))) continue;

            Entry e;
            e.category    = a.name;
            e.id          = folder ? p.filename().string() : p.stem().string();
            e.name        = e.id;
            e.description = a.description;
            e.command     = a.es ? buildEsCommand(a, p) : buildArchiveCommand(a.command, p.string());
            e.file        = p.string();
            // Cover: the icons folder wins (small, hand-picked), then the gamelist's image
            e.iconPath    = findArchiveIcon(a, e.id);
            if (folder && e.iconPath.empty()) e.iconPath = findFolderCover(p);

            auto info = gamelist.find(p.filename().string());
            if (info != gamelist.end()) {
                const GameInfo& g = info->second;
                if (!g.name.empty()) e.name = g.name;
                e.synopsis = g.synopsis;
                e.meta = g.meta;
                std::error_code ec3;
                if (e.iconPath.empty() && !g.image.empty() && fs::is_regular_file(g.image, ec3)) e.iconPath = g.image;
            }
            if (e.iconPath.empty()) e.iconPath = a.defaultIcon;
            out.push_back(std::move(e));
        }
    }

    std::sort(out.begin(), out.end(), [](const Entry& l, const Entry& r) {
        return lower(l.name) < lower(r.name);
    });
    return out;
}

static void addToCategory(std::vector<Category>& cats, const Entry& e) {
    for (auto& c : cats) {
        if (c.name != e.category) continue;
        for (auto& existing : c.entries) {
            if (existing.name == e.name) { existing = e; return; }
        }
        c.entries.push_back(e);
        return;
    }
    Category c;
    c.name = e.category;
    c.entries.push_back(e);
    cats.push_back(std::move(c));
}

std::vector<Category> loadCatalog() {
    std::vector<Record> records;
    for (const auto& path : cfg.apps) parseAppsFile(path, records);

    // individual .puppy files, e.g. in ~/.local/share/applications
    for (const auto& path : cfg.appsDirs) {
        std::error_code ec;
        if (!fs::is_directory(path, ec)) continue;
        for (const auto& entry : fs::directory_iterator(path, ec)) {
            if (entry.path().extension() == ".puppy") {
                parseAppsFile(entry.path().string(), records);
            }
        }
    }
    for (const auto& path : cfg.esSystems) parseEsSystems(path, records);

    std::vector<Category> cats;
    std::map<std::string, std::string> archiveTabs;
    std::set<std::string> mediaArchives;
    for (const auto& rec : records) {
        if (rec.isArchive) {
            archiveTabs[rec.archive.name] = rec.archive.tab;
            if (rec.archive.media) mediaArchives.insert(rec.archive.name);
            for (const auto& e : expandArchive(rec.archive)) addToCategory(cats, e);
        } else {
            addToCategory(cats, rec.entry);
        }
    }
    for (auto& c : cats) {
        auto it = archiveTabs.find(c.name);
        c.isArchive = it != archiveTabs.end();
        c.media = mediaArchives.count(c.name) > 0;
        c.label = (c.isArchive && !it->second.empty()) ? it->second : c.name;
    }
    return cats;
}

std::string xmlEscape(const std::string& s) {
    std::string out;
    for (char c : s) {
        switch (c) {
            case '&':  out += "&amp;";  break;
            case '<':  out += "&lt;";   break;
            case '>':  out += "&gt;";   break;
            case '"':  out += "&quot;"; break;
            case '\'': out += "&apos;"; break;
            default:   out += c;
        }
    }
    return out;
}
