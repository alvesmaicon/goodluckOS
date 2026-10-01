#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>
#include <SDL2/SDL_ttf.h>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iterator>
#include <iostream>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <vector>

#include "i18n.h"

#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

namespace fs = std::filesystem;
using i18n::tr;

// Files and commands, from puppy.conf (see loadConfig). The defaults are goodluckOS's own layout, so
// goodluckOS needs no config file; on other firmwares a puppy.conf points Puppy at their files.
struct Config {
    std::string font          = "/usr/share/fonts/Inter_24pt-Medium.ttf";
    std::string fallbackIcon  = "/usr/share/puppy/assets/fallback.png";
    std::vector<std::string> apps     = {"/usr/share/puppy/apps.puppy", "/home/player/apps.puppy"};
    std::vector<std::string> appsDirs = {"/home/player/.local/share/applications"};   // *.puppy files
    std::vector<std::string> esSystems;     // EmulationStation es_systems.cfg files to take systems from
    std::string launchFile    = "/dev/shm/launch";      // the picked command, run by the bootstrap
    std::string stateFile     = "/dev/shm/launcher_state";
    std::string autoStartFile = "/home/player/autolaunch";
    std::string configDir     = "/home/player/.config/puppy";   // settings, favorites
    std::string cacheDir      = "/home/player/.cache/puppy";    // downscaled covers
    std::string langDir       = "/usr/share/goodluck/lang";
    std::string language;                   // overrides the one in the settings file
    std::string view, tabs;                 // defaults for the settings file's view= and tabs=
    std::string powerFifo     = "/run/power-request";   // root power-manager.sh
    std::string backlight     = "/sys/class/backlight/backlight/brightness";
    std::string osdFile       = "/dev/shm/osd";  // "volume|brightness <percent> [muted]", from osd-notify.sh
    // When set, these replace the System entries of apps.puppy and the power-manager.sh requests
    std::string settingsCommand, restartCommand, shutdownCommand, screenOffCommand;
    bool quit = false;      // a "Quit Puppy" power option, for when Puppy is started from another frontend

    std::string settingsFile() const  { return configDir + "/settings"; }
    std::string favoritesFile() const { return configDir + "/favorites"; }   // "category<TAB>id" lines
    std::string thumbDir() const      { return cacheDir + "/thumbs"; }
};
static Config cfg;

static const char* kMyListName    = "My List";
static const char* kMenuCategory  = "System";   // apps.puppy category taken out of the tabs
static const char* kSettingsName  = "System Settings";   // entry of that category opened by START

constexpr int kScreenW              = 640;
constexpr int kScreenH              = 480;

constexpr int kHeaderH              = 44;
constexpr int kTabsH                = 30;   // tab strip under the header
constexpr int kFooterH              = 30;
constexpr int kMargin               = 16;
constexpr int kBorder               = 3;

// Grid view: tiles in columns, the selected entry's name over a gradient at the bottom.
constexpr int kCellWidth            = 192;
constexpr int kCellHeight           = 128;
constexpr int kGridCols             = 3;
constexpr int kGridGap              = 16;
constexpr int kGridPitchY           = kCellHeight + kGridGap;
constexpr int kGridFullRows         = 2;    // rows kept fully visible above the title area

// List view: names on the left, a preview of the selected entry on the right.
constexpr int kListRowH             = 32;
constexpr int kListWidth            = 352;
constexpr int kPreviewX             = kMargin + kListWidth + kMargin;
constexpr int kPreviewW             = kScreenW - kPreviewX - kMargin;
constexpr int kPreviewH             = kPreviewW * 3 / 4;

constexpr int kMaxQueryLength       = 32;

constexpr Uint32 kIdleCheckMs       = 60000;
constexpr Uint32 kOsdShowMs         = 1500;  // how long the volume/brightness bar stays up
constexpr Uint32 kOsdRefreshMs      = 100;   // re-read the level while it's up (the hotkey script runs async)
constexpr Uint32 kRepeatDelayMs     = 350;  // holding the d-pad repeats the move after this...
constexpr Uint32 kRepeatRateMs      = 60;   // ...and then this often
constexpr Uint32 kScrollDelayMs     = 250;  // right stick: description scroll repeat
constexpr Uint32 kScrollRateMs      = 110;
constexpr int    kStickOn           = 20000;    // analog stick deflection that counts as a press...
constexpr int    kStickOff          = 12000;    // ...and that releases it (hysteresis, so it doesn't flicker)
constexpr size_t kMaxCachedIcons    = 64;

// The tab strip can be hidden (System Settings -> Show Tabs); the content then moves up.
static int bodyTop(bool showTabs)  { return kHeaderH + (showTabs ? kTabsH : 0); }
static int gridTop(bool showTabs)  { return bodyTop(showTabs) + 8; }
static int listTop(bool showTabs)  { return bodyTop(showTabs) + 6; }
static int listRows(bool showTabs) { return (kScreenH - kFooterH - listTop(showTabs) - 4) / kListRowH; }

constexpr SDL_Color kWhite  {255, 255, 255, 255};
constexpr SDL_Color kGrey   {170, 170, 170, 255};
constexpr SDL_Color kBlack  {0, 0, 0, 255};
constexpr SDL_Color kYellow {255, 205, 60, 255};
constexpr SDL_Color kTile   {40, 40, 44, 255};
constexpr SDL_Color kRowSel {56, 56, 64, 255};
constexpr SDL_Color kBar    {12, 12, 14, 255};
constexpr SDL_Color kClear  {24, 24, 28, 255};

// String helper functions
static std::string trim(const std::string& s) {
    size_t a = 0, b = s.size();
    while (a < b && std::isspace((unsigned char)s[a])) ++a;
    while (b > a && std::isspace((unsigned char)s[b - 1])) --b;
    return s.substr(a, b - a);
}

static std::string upper(std::string s) {
    for (auto& c : s) c = (char)std::toupper((unsigned char)c);
    return s;
}

static std::string lower(std::string s) {
    for (auto& c : s) c = (char)std::tolower((unsigned char)c);
    return s;
}

// Converts semicolon-separated-list to an vector:
// "a;b;c;" -> {"a","b","c"}
static std::vector<std::string> splitList(const std::string& s) {
    std::vector<std::string> out;
    size_t start = 0;
    while (start <= s.size()) {
        size_t end = s.find(';', start);
        if (end == std::string::npos) end = s.size();
        std::string item = trim(s.substr(start, end - start));
        if (!item.empty()) out.push_back(item);
        start = end + 1;
    }
    return out;
}

// Single-quote a string for safe use in a shell command line.
static std::string shellQuote(const std::string& s) {
    std::string out = "'";
    for (char c : s) {
        if (c == '\'') out += "'\\''";
        else out += c;
    }
    out += "'";
    return out;
}

// srcX skips that many pixels of the surface's left side (scrolling text).
static void drawSurface(SDL_Renderer* r, SDL_Surface* s, int x, int y, int maxW = 0, int srcX = 0) {
    SDL_Texture* t = SDL_CreateTextureFromSurface(r, s);
    if (!t) return;
    SDL_SetTextureBlendMode(t, SDL_BLENDMODE_BLEND);
    srcX = std::clamp(srcX, 0, s->w);
    int w = (maxW > 0) ? std::min(s->w - srcX, maxW) : s->w - srcX;   // clip, don't squash
    SDL_Rect src{srcX, 0, w, s->h};
    SDL_Rect dst{x, y, w, s->h};
    SDL_RenderCopy(r, t, &src, &dst);
    SDL_DestroyTexture(t);
}

static void drawText(SDL_Renderer* r, TTF_Font* font, const std::string& text, int x, int y, SDL_Color color, int maxW = 0,
                     int scrollX = 0) {
    if (!font || text.empty()) return;
    SDL_Surface* s = TTF_RenderUTF8_Blended(font, text.c_str(), color);
    if (!s) return;
    drawSurface(r, s, x, y, maxW, scrollX);
    SDL_FreeSurface(s);
}

static int textWidth(TTF_Font* font, const std::string& text) {
    int w = 0, h = 0;
    if (font && !text.empty()) TTF_SizeUTF8(font, text.c_str(), &w, &h);
    return w;
}

class IconCache {
public:
    struct Icon {
        SDL_Texture* tex = nullptr;
        int w = 0, h = 0;
    };

    // Images larger than boxW x boxH are scaled down: cropped to cover the box, or with 'fit' shrunk
    // to fit inside it. Smaller images are kept at their size. Scaled images are saved in
    // cfg.thumbDir(), so big covers (e.g. 800x600 scraper images) are only decoded and scaled once.
    IconCache(SDL_Renderer* r, const std::string& fallbackPath, int boxW, int boxH, bool fit)
        : renderer(r), boxW(boxW), boxH(boxH), fit(fit) {
        fallback = load(fallbackPath);
        if (!fallback.tex) std::cerr << "Warning: missing fallback icon: " << fallbackPath << "\n";
    }

    ~IconCache() {
        for (auto& [path, slot] : slots) if (slot.icon.tex) SDL_DestroyTexture(slot.icon.tex);
        if (fallback.tex) SDL_DestroyTexture(fallback.tex);
    }

    IconCache(const IconCache&) = delete;
    IconCache& operator=(const IconCache&) = delete;

    Icon get(const std::string& path) {
        if (path.empty()) return fallback;

        auto it = slots.find(path);
        if (it != slots.end()) {
            it->second.lastUsed = ++clock;
            return it->second.icon.tex ? it->second.icon : fallback;
        }

        if (slots.size() >= kMaxCachedIcons) evictOldest();

        Slot slot;
        slot.icon = load(path);
        slot.lastUsed = ++clock;
        slots[path] = slot;
        return slot.icon.tex ? slot.icon : fallback;
    }

private:
    struct Slot {
        Icon icon;
        uint64_t lastUsed = 0;
    };

    SDL_Renderer* renderer;
    int boxW, boxH;
    bool fit;
    Icon fallback;
    std::map<std::string, Slot> slots;
    uint64_t clock = 0;

    // Name of the scaled copy of an image for this cache's box; changes when the image does.
    std::string thumbPath(const std::string& path) const {
        std::error_code ec;
        auto size = fs::file_size(path, ec);
        auto time = fs::last_write_time(path, ec).time_since_epoch().count();
        std::string key = path + "|" + std::to_string(size) + "|" + std::to_string(time) + "|" +
                          std::to_string(boxW) + "x" + std::to_string(boxH) + (fit ? "f" : "c");
        char name[32];
        snprintf(name, sizeof(name), "%016zx.png", std::hash<std::string>{}(key));
        return cfg.thumbDir() + "/" + name;
    }

    Icon load(const std::string& path) {
        Icon icon;
        const std::string thumb = thumbPath(path);
        bool fromThumb = true;
        SDL_Surface* loaded = IMG_Load(thumb.c_str());
        if (!loaded) {
            fromThumb = false;
            loaded = IMG_Load(path.c_str());
        }
        if (!loaded) return icon;
        SDL_Surface* src = SDL_ConvertSurfaceFormat(loaded, SDL_PIXELFORMAT_RGBA32, 0);
        SDL_FreeSurface(loaded);
        if (!src) return icon;

        SDL_Surface* result = src;

        if (src->w > boxW || src->h > boxH) {
            SDL_Rect crop{0, 0, src->w, src->h};
            int outW = boxW, outH = boxH;
            if (fit) {
                float scale = std::min((float)boxW / src->w, (float)boxH / src->h);
                outW = std::max(1, (int)std::lround(src->w * scale));
                outH = std::max(1, (int)std::lround(src->h * scale));
            } else {
                // Scale and crop so icons cover the cell if they're too large.
                float scale = std::max((float)boxW / src->w, (float)boxH / src->h);
                crop.w = std::min(src->w, (int)std::lround(boxW / scale));
                crop.h = std::min(src->h, (int)std::lround(boxH / scale));
                crop.x = (src->w - crop.w) / 2;
                crop.y = (src->h - crop.h) / 2;
            }

            SDL_Surface* out = SDL_CreateRGBSurfaceWithFormat(0, outW, outH, 32, SDL_PIXELFORMAT_RGBA32);
            if (!out) { SDL_FreeSurface(src); return icon; }

            SDL_SetSurfaceBlendMode(src, SDL_BLENDMODE_NONE);
            SDL_SoftStretchLinear(src, &crop, out, nullptr);
            SDL_FreeSurface(src);
            result = out;
            if (!fromThumb) {
                std::error_code ec;
                fs::create_directories(cfg.thumbDir(), ec);
                IMG_SavePNG(result, thumb.c_str());
            }
        }

        icon.w = result->w;
        icon.h = result->h;
        icon.tex = SDL_CreateTextureFromSurface(renderer, result);
        SDL_FreeSurface(result);
        if (icon.tex) SDL_SetTextureBlendMode(icon.tex, SDL_BLENDMODE_BLEND);
        return icon;
    }

    void evictOldest() {
        auto oldest = slots.begin();
        for (auto it = slots.begin(); it != slots.end(); ++it)
            if (it->second.lastUsed < oldest->second.lastUsed) oldest = it;
        if (oldest->second.icon.tex) SDL_DestroyTexture(oldest->second.icon.tex);
        slots.erase(oldest);
    }
};

struct Entry {
    std::string category;
    std::string id;         // stable identity (the ROM file name without extension, or the app name),
                            // used for favourites, autolaunch and the cursor; the name can come from a gamelist
    std::string name;
    std::string description;    // the system or app description
    std::string synopsis;       // from gamelist.xml
    std::string meta;           // "year · genre · players", from gamelist.xml
    std::string command;
    std::string iconPath;
    std::string searchKey;  // lowercase name, filled once the catalog is loaded
    std::string tag;        // short system name, shown next to the entry in the "All Games" tab
};

// One tab of the launcher (a console or an apps category).
struct Category {
    std::string name;
    std::string label;          // short name for the tab strip (TAB= in apps.puppy), defaults to the name
    bool isArchive = false;     // games from a ROM folder, as opposed to apps
    bool mixed = false;         // the "All Games" tab: entries from every system
    std::vector<Entry> entries;
    std::vector<int> visible;   // indices of the entries matching the search, in display order
    int sel = 0;                // position in 'visible'
    mutable int scroll = 0;     // first list row / grid row on screen, kept in view by the renderer
    mutable int tagColumn = -1; // list view: width of the system tag column (-1: to be measured)
};

enum class View { Grid, List };

// One action of the POWER menu (see powerItems).
struct PowerItem {
    const char* label;
    const char* request;    // for the root power-manager.sh (nullptr: none)
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
    std::vector<PowerItem> menuItems;   // filled when the menu opens
    int menuSel = 0;
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
        if (n > 0) tab = ((tab + delta) % n + n) % n;
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

struct Archive {
    std::string name, tab, description, command, defaultIcon;
    std::vector<std::string> dirs, exts, iconDirs;
    bool es = false;    // from es_systems.cfg: the command uses %ROM%-style placeholders
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
            rec.entry.iconPath    = get("ICON");
            // HIDE_IF_EXISTS=<path>: one-time entries (e.g. Resize Home) disappear once their job is done
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

static std::string homeDir() {
    const char* home = getenv("HOME");
    return home && *home ? home : "/root";
}

// "~/x" -> "$HOME/x"
static std::string expandHome(const std::string& path) {
    if (path == "~" || path.compare(0, 2, "~/") == 0) return homeDir() + path.substr(1);
    return path;
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

// Text of <tag>...</tag> inside one <game> block.
static std::string xmlTag(const std::string& block, const std::string& tag);

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

static std::string xmlUnescape(const std::string& s) {
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
static std::string xmlTag(const std::string& block, const std::string& tag) {
    const std::string open = "<" + tag + ">", close = "</" + tag + ">";
    size_t a = block.find(open);
    if (a == std::string::npos) return {};
    a += open.size();
    size_t b = block.find(close, a);
    if (b == std::string::npos) return {};
    return trim(xmlUnescape(block.substr(a, b - a)));
}

static std::string stripDotSlash(std::string p) {
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

    std::vector<Entry> out;
    for (const auto& dir : a.dirs) {
        const auto gamelist = loadGamelist(dir);
        std::error_code ec;
        for (fs::directory_iterator it(dir, ec), end; !ec && it != end; it.increment(ec)) {
            std::error_code ec2;
            if (!it->is_regular_file(ec2)) continue;

            const fs::path& p = it->path();
            if (p.filename().string().empty() || p.filename().string()[0] == '.') continue;

            std::string ext = lower(p.extension().string());
            if (!ext.empty()) ext.erase(0, 1);
            if (!exts.empty() && std::find(exts.begin(), exts.end(), ext) == exts.end()) continue;

            Entry e;
            e.category    = a.name;
            e.id          = p.stem().string();
            e.name        = e.id;
            e.description = a.description;
            e.command     = a.es ? buildEsCommand(a, p) : buildArchiveCommand(a.command, p.string());
            // Cover: the icons folder wins (small, hand-picked), then the gamelist's image
            e.iconPath    = findArchiveIcon(a, e.id);

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

static std::vector<Category> loadCatalog() {
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
    for (const auto& rec : records) {
        if (rec.isArchive) {
            archiveTabs[rec.archive.name] = rec.archive.tab;
            for (const auto& e : expandArchive(rec.archive)) addToCategory(cats, e);
        } else {
            addToCategory(cats, rec.entry);
        }
    }
    for (auto& c : cats) {
        auto it = archiveTabs.find(c.name);
        c.isArchive = it != archiveTabs.end();
        c.label = (c.isArchive && !it->second.empty()) ? it->second : c.name;
    }
    return cats;
}

static void writeAutoStart(const Entry& e) {
    std::ofstream out(cfg.autoStartFile);
    if (out) out << "# " << e.category << "\t" << e.id << "\n" << e.command << "\n";
}

static void clearAutoStart() {
    std::error_code ec;
    fs::remove(cfg.autoStartFile, ec);
}

static bool readAutoStartId(std::string& category, std::string& name) {
    std::ifstream in(cfg.autoStartFile);
    std::string line;
    if (!in || !std::getline(in, line) || line.compare(0, 2, "# ") != 0) return false;
    size_t tab = line.find('\t', 2);
    if (tab == std::string::npos) return false;
    category = line.substr(2, tab - 2);
    name = line.substr(tab + 1);
    return true;
}

static void toggleAutoStart(Model& m) {
    const Entry* e = m.selected();
    if (!e) return;
    if (m.isAutoStart(*e)) {
        clearAutoStart();
        m.autoCategory.clear();
        m.autoName.clear();
    } else {
        writeAutoStart(*e);
        m.autoCategory = e->category;
        m.autoName = e->id;
    }
}

static void launch(const Model& m, const Entry& e) {
    { std::ofstream out(cfg.launchFile); if (out) out << e.command << "\n"; }
    std::ofstream state(cfg.stateFile);
    if (state) state << m.cur().name << "\n" << e.category << "\n" << e.id << "\n";
}

static void restoreCursor(Model& m) {
    std::ifstream in(cfg.stateFile);
    std::string tabName, category, name;
    if (!in || !std::getline(in, tabName) || !std::getline(in, category)) return;
    if (!std::getline(in, name)) {   // older two-line format: category, name
        name = category;
        category = tabName;
    }
    int t, e;
    if (m.find(tabName, category, name, t, e)) { m.select(t, e); return; }
    // started from the START menu: just go back to the tab that was open
    for (size_t i = 0; i < m.categories.size(); ++i)
        if (m.categories[i].name == tabName) m.tab = (int)i;
}

// Prepends an "All Games" tab with the games of every system, sorted by name.
static void addAllGamesTab(Model& m) {
    Category all;
    all.name = "All Games";
    all.label = "All Games";
    all.isArchive = true;
    all.mixed = true;
    for (const auto& c : m.categories) {
        if (!c.isArchive) continue;
        for (Entry e : c.entries) {
            e.tag = c.label;
            all.entries.push_back(std::move(e));
        }
    }
    if (all.entries.empty()) return;
    std::stable_sort(all.entries.begin(), all.entries.end(), [](const Entry& l, const Entry& r) {
        return l.searchKey < r.searchKey;
    });
    m.categories.insert(m.categories.begin(), std::move(all));
}

static void loadFavorites(Model& m) {
    std::ifstream in(cfg.favoritesFile());
    for (std::string line; std::getline(in, line);) {
        if (line.find('\t') != std::string::npos) m.favorites.insert(line);
    }
}

static void saveFavorites(const Model& m) {
    std::error_code ec;
    fs::create_directories(cfg.configDir, ec);
    const std::string tmp = cfg.favoritesFile() + ".tmp";
    {
        std::ofstream out(tmp);
        if (!out) return;
        for (const auto& key : m.favorites) out << key << "\n";
    }
    fs::rename(tmp, cfg.favoritesFile(), ec);
}

static int myListTab(const Model& m) {
    for (size_t t = 0; t < m.categories.size(); ++t)
        if (m.categories[t].name == kMyListName) return (int)t;
    return -1;
}

// Fills My List with the favourite entries of every tab (except the mixed ones), sorted by name.
static void rebuildMyList(Model& m) {
    int t = myListTab(m);
    if (t < 0) return;
    std::vector<Entry> list;
    for (const auto& c : m.categories) {
        if (c.mixed) continue;
        for (Entry e : c.entries) {
            if (!m.isFavorite(e)) continue;
            e.tag = c.label;
            list.push_back(std::move(e));
        }
    }
    std::stable_sort(list.begin(), list.end(), [](const Entry& l, const Entry& r) {
        return l.searchKey < r.searchKey;
    });
    m.categories[t].entries = std::move(list);
    m.categories[t].tagColumn = -1;
}

// Adds the My List tab right after All Games (one R1 press from the boot tab).
static void addMyListTab(Model& m) {
    Category list;
    list.name = kMyListName;
    list.label = kMyListName;
    list.isArchive = true;
    list.mixed = true;
    bool hasAll = !m.categories.empty() && m.categories[0].name == "All Games";
    m.categories.insert(m.categories.begin() + (hasAll ? 1 : 0), std::move(list));
    rebuildMyList(m);
}

static void toggleFavorite(Model& m) {
    const Entry* e = m.selected();
    if (!e) return;
    const std::string key = Model::favoriteKey(*e);
    if (!m.favorites.erase(key)) m.favorites.insert(key);
    saveFavorites(m);

    // Removing from inside My List shrinks it: keep the cursor at the same position
    const bool inMyList = m.cur().name == kMyListName;
    const int oldSel = m.cur().sel;
    rebuildMyList(m);
    m.applyFilter();
    if (inMyList && !m.cur().visible.empty()) m.cur().sel = std::min(oldSel, (int)m.cur().visible.size() - 1);
}

// Takes the System category out of the tabs: its settings entry opens with START and the power
// actions live in the POWER menu, so they don't mean scrolling through every tab.
static void extractSystemMenu(Model& m) {
    auto sys = std::find_if(m.categories.begin(), m.categories.end(),
                            [](const Category& c) { return c.name == kMenuCategory; });
    if (sys == m.categories.end()) return;
    for (const Entry& e : sys->entries) {
        if (e.name == kSettingsName) { m.settings = e; m.hasSettings = true; }
    }
    m.systemEntries = sys->entries;
    m.categories.erase(sys);
}

// puppy.conf's settings_command replaces the System Settings entry.
static void applySettingsCommand(Model& m) {
    if (cfg.settingsCommand.empty()) return;
    m.settings = Entry();
    m.settings.category = kMenuCategory;
    m.settings.name = m.settings.id = kSettingsName;
    m.settings.command = cfg.settingsCommand;
    m.hasSettings = true;
}

// The POWER menu. Each action, in order of preference: the puppy.conf command (run in the
// background); the System entry of apps.puppy (launched, so Reboot/Power Off ask for confirmation
// with are-you-sure); the request for the root power-manager.sh. Actions with none are left out.
static std::vector<PowerItem> powerItems(const Model& m) {
    std::error_code ec;
    const bool fifo = fs::exists(cfg.powerFifo, ec);
    const PowerItem all[] = {
        {"Display off", "screen-off", nullptr, nullptr, &cfg.screenOffCommand},
        {"Restart", "reboot", "Restarting...", "Reboot", &cfg.restartCommand},
        {"Shut down", "poweroff", "Shutting down...", "Power Off", &cfg.shutdownCommand},
        {"Quit Puppy", nullptr, nullptr, nullptr, nullptr, true},
    };
    std::vector<PowerItem> items;
    for (const PowerItem& item : all) {
        bool entry = item.confirmEntry && std::any_of(m.systemEntries.begin(), m.systemEntries.end(),
                                                      [&](const Entry& e) { return e.name == item.confirmEntry; });
        bool available = item.quit ? cfg.quit
                       : !item.command->empty() || entry || (item.request && fifo);
        if (available) items.push_back(item);
    }
    return items;
}

// Runs a shell command without waiting for it (screen off, restart... from puppy.conf).
static void runDetached(const std::string& command) {
    signal(SIGCHLD, SIG_IGN);   // no zombies
    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        execl("/bin/sh", "sh", "-c", command.c_str(), (char*)nullptr);
        _exit(127);
    }
}

// Non-blocking: if power-manager.sh isn't reading (e.g. being respawned), drop the request rather
// than freeze the launcher.
static void sendPowerRequest(const char* request) {
    int fd = open(cfg.powerFifo.c_str(), O_WRONLY | O_NONBLOCK);
    if (fd < 0) return;
    std::string line = std::string(request) + "\n";
    ssize_t written = write(fd, line.c_str(), line.size());
    (void)written;
    close(fd);
}

static bool screenOn() {
    std::ifstream in(cfg.backlight);
    int level = 1;
    in >> level;
    return level > 0;
}

// Launcher options, set in System Settings: "view=grid|list" and "tabs=on|off" (puppy.conf can give
// the defaults).
static void loadSettings(Model& m) {
    std::vector<std::string> lines;
    if (!cfg.view.empty()) lines.push_back("view=" + cfg.view);
    if (!cfg.tabs.empty()) lines.push_back("tabs=" + cfg.tabs);
    std::ifstream in(cfg.settingsFile());
    for (std::string line; std::getline(in, line);) lines.push_back(line);
    for (std::string line : lines) {
        line = trim(line);
        if (line == "view=list") m.view = View::List;
        else if (line == "view=grid") m.view = View::Grid;
        else if (line == "tabs=off") m.showTabs = false;
        else if (line == "tabs=on") m.showTabs = true;
    }
}

static int readBattery() {
    std::error_code ec;
    for (fs::directory_iterator it("/sys/class/power_supply", ec), end; !ec && it != end; it.increment(ec)) {
        std::ifstream typeFile(it->path() / "type");
        std::string type;
        if (!(typeFile >> type) || type != "Battery") continue;
        std::ifstream capFile(it->path() / "capacity");
        int cap;
        if (capFile >> cap) return std::clamp(cap, 0, 100);
    }
    return -1; // no battery
}

// Volume/brightness level written by the hotkey scripts, shown as a bar for a moment.
struct Osd {
    bool visible = false;
    std::string kind;
    int percent = 0;
    bool muted = false;

    void read() {
        std::ifstream in(cfg.osdFile);
        std::string flag;
        if (!(in >> kind >> percent)) { kind.clear(); return; }
        muted = (in >> flag) && flag == "muted";
        percent = std::clamp(percent, 0, 100);
    }
};

// On-screen keyboard for the name search, driven by the d-pad. QWERTY like Android's: rows are
// staggered and some keys are wider, so positions and widths are in key units (10 per row).
struct Keyboard {
    struct Key {
        std::string label;
        float x, w;     // in key units
    };
    static constexpr int kRows = 5;
    static constexpr float kRowUnits = 10.0f;

    bool open = false;
    int row = 1, col = 0;   // starts on Q

    static const std::vector<Key>& keys(int r) {
        static const std::vector<std::vector<Key>> kLayout = [] {
            auto evenRow = [](const char* chars, float x0) {
                std::vector<Key> keys;
                for (const char* c = chars; *c; ++c) keys.push_back({std::string(1, *c), x0++, 1.0f});
                return keys;
            };
            std::vector<std::vector<Key>> rows;
            rows.push_back(evenRow("1234567890", 0.0f));
            rows.push_back(evenRow("qwertyuiop", 0.0f));
            rows.push_back(evenRow("asdfghjkl", 0.5f));
            std::vector<Key> r3 = {{"-", 0.0f, 1.5f}};
            for (const Key& k : evenRow("zxcvbnm", 1.5f)) r3.push_back(k);
            r3.push_back({"del", 8.5f, 1.5f});
            rows.push_back(r3);
            rows.push_back({{"'", 0.0f, 1.5f}, {"space", 1.5f, 6.0f}, {"ok", 7.5f, 2.5f}});
            return rows;
        }();
        return kLayout[r];
    }

    const std::string& current() const { return keys(row)[col].label; }

    void move(int dx, int dy) {
        if (dx) {
            int n = (int)keys(row).size();
            col = (col + dx + n) % n;
        }
        if (dy) {
            // the rows are staggered: land on the key closest to the centre of the current one
            const Key& from = keys(row)[col];
            float centre = from.x + from.w / 2;
            row = (row + dy + kRows) % kRows;
            const auto& to = keys(row);
            col = 0;
            for (int i = 1; i < (int)to.size(); ++i) {
                if (std::fabs(to[i].x + to[i].w / 2 - centre) < std::fabs(to[col].x + to[col].w / 2 - centre)) col = i;
            }
        }
    }
};

class Ui {
public:
    Ui() {
        SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "linear");

        if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER) != 0) {
            std::cerr << "SDL_Init failed: " << SDL_GetError() << "\n";
            return;
        }
        sdlUp = true;
        IMG_Init(IMG_INIT_PNG | IMG_INIT_JPG);
        TTF_Init();

        window = SDL_CreateWindow("Puppy Launcher", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, kScreenW, kScreenH, 0);
        if (!window) { std::cerr << "SDL_CreateWindow failed: " << SDL_GetError() << "\n"; return; }

        renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
        if (!renderer) { std::cerr << "SDL_CreateRenderer failed: " << SDL_GetError() << "\n"; return; }

        SDL_RenderSetLogicalSize(renderer, kScreenW, kScreenH);
        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);

        const char* font = cfg.font.c_str();
        uiFont    = TTF_OpenFont(font, 22);
        titleFont = TTF_OpenFont(font, 30);
        descFont  = TTF_OpenFont(font, 20);
        smallFont = TTF_OpenFont(font, 15);
        if (!uiFont || !titleFont || !descFont || !smallFont)
            std::cerr << "Warning: could not load font " << cfg.font << "\n";

        gridIcons    = std::make_unique<IconCache>(renderer, cfg.fallbackIcon, kCellWidth, kCellHeight, false);
        previewIcons = std::make_unique<IconCache>(renderer, cfg.fallbackIcon, kPreviewW, kPreviewH, true);
        ok_ = true;
    }

    ~Ui() {
        gridIcons.reset();
        previewIcons.reset();
        if (clipTex) SDL_DestroyTexture(clipTex);
        for (TTF_Font* f : {uiFont, titleFont, descFont, smallFont}) if (f) TTF_CloseFont(f);
        if (renderer) SDL_DestroyRenderer(renderer);
        if (window) SDL_DestroyWindow(window);
        if (sdlUp) { TTF_Quit(); IMG_Quit(); SDL_Quit(); }
    }

    Ui(const Ui&) = delete;
    Ui& operator=(const Ui&) = delete;

    bool ok() const { return ok_; }
    bool animating() const { return tabOffset != 0.0f; }
    Uint32 marqueeDue() const { return marqueeNext; }   // when the scrolling name needs a frame (0: never)
    int descMaxScroll() const { return descMax; }   // of the description drawn in the last frame

    void render(const Model& m, const Keyboard& kb, const Osd& osd, int battery) {
        marqueeNext = 0;    // set again below if the selected name is still scrolling
        setColor(kClear);
        SDL_RenderClear(renderer);

        if (m.cur().visible.empty()) renderEmpty(m);
        else if (m.view == View::Grid) renderGrid(m);
        else renderList(m);

        // Bars are drawn last so long descriptions or scrolled tiles never spill over them
        renderHeader(m, battery);
        renderFooter(m, kb);
        if (kb.open) renderKeyboard(m, kb);
        if (m.menuOpen) renderMenu(m);
        if (!m.status.empty()) renderStatus(m.status);
        if (osd.visible && !osd.kind.empty()) renderOsd(osd, bodyTop(m.showTabs));
        if (!marqueeNext) marqueeKey.clear();   // coming back to the same name starts it over

        SDL_RenderPresent(renderer);
    }

private:
    bool sdlUp = false, ok_ = false;
    SDL_Window* window = nullptr;
    SDL_Renderer* renderer = nullptr;
    TTF_Font *uiFont = nullptr, *titleFont = nullptr, *descFont = nullptr, *smallFont = nullptr;
    std::unique_ptr<IconCache> gridIcons, previewIcons;
    SDL_Texture* clipTex = nullptr;     // drawWrappedClipped's last text
    std::string clipText;
    int clipWidth = 0, clipW = 0, clipH = 0;
    int descMax = 0;
    int lastTab = -1;           // tab drawn in the previous frame, to animate the strip
    float tabOffset = 0.0f;     // remaining slide of the tab strip, in pixels

    void setColor(SDL_Color c) { SDL_SetRenderDrawColor(renderer, c.r, c.g, c.b, c.a); }

    void fill(SDL_Color c, const SDL_Rect& r) {
        setColor(c);
        SDL_RenderFillRect(renderer, &r);
    }

    void frame(SDL_Color c, const SDL_Rect& r, int t) {
        setColor(c);
        SDL_Rect strips[4] = {
            {r.x, r.y, r.w, t},                 // top
            {r.x, r.y + r.h - t, r.w, t},       // bottom
            {r.x, r.y, t, r.h},                 // left
            {r.x + r.w - t, r.y, t, r.h},       // right
        };
        SDL_RenderFillRects(renderer, strips, 4);
    }

    // Vertical fade from transparent (top) to the colour (bottom).
    void gradient(const SDL_Rect& r, SDL_Color c) {
        SDL_Vertex v[4];
        const float xs[2] = {(float)r.x, (float)(r.x + r.w)};
        const float ys[2] = {(float)r.y, (float)(r.y + r.h)};
        for (int i = 0; i < 4; ++i) {
            v[i].position = {xs[i % 2], ys[i / 2]};
            v[i].color = {c.r, c.g, c.b, (Uint8)(i < 2 ? 0 : 255)};
            v[i].tex_coord = {0, 0};
        }
        const int idx[6] = {0, 1, 2, 1, 3, 2};
        SDL_RenderGeometry(renderer, nullptr, v, 4, idx, 6);
    }

    // Filled five-pointed star centred on (cx, cy), the My List badge.
    void star(int cx, int cy, int r, SDL_Color c) {
        SDL_Vertex v[11];
        v[0].position = {(float)cx, (float)cy};
        for (int i = 0; i < 10; ++i) {
            float a = (float)M_PI * (-0.5f + i * 0.2f);
            float rad = (i % 2 == 0) ? r : r * 0.45f;
            v[i + 1].position = {cx + rad * std::cos(a), cy + rad * std::sin(a)};
        }
        int idx[30];
        for (int i = 0; i < 10; ++i) {
            idx[i * 3] = 0;
            idx[i * 3 + 1] = i + 1;
            idx[i * 3 + 2] = (i + 1) % 10 + 1;
        }
        for (auto& vert : v) { vert.color = c; vert.tex_coord = {0, 0}; }
        SDL_RenderGeometry(renderer, nullptr, v, 11, idx, 30);
    }

    // Text on a rounded-looking label; returns its width.
    int pill(const std::string& text, int x, int y, SDL_Color bg, SDL_Color fg) {
        const int padX = 6, padY = 2;
        SDL_Rect r{x, y, textWidth(smallFont, text) + padX * 2, TTF_FontHeight(smallFont) + padY * 2};
        fill(bg, r);
        drawText(renderer, smallFont, text, x + padX, y + padY, fg);
        return r.w;
    }

    void drawIcon(IconCache& cache, const std::string& path, const SDL_Rect& box) {
        IconCache::Icon icon = cache.get(path);
        if (!icon.tex) return;
        SDL_Rect dst{box.x + (box.w - icon.w) / 2, box.y + (box.h - icon.h) / 2, icon.w, icon.h};
        SDL_RenderCopy(renderer, icon.tex, nullptr, &dst);
    }

    // Draws wrapped text and returns its height.
    int drawWrapped(TTF_Font* font, const std::string& text, int x, int y, SDL_Color color, int width) {
        if (!font || text.empty()) return 0;
        SDL_Surface* s = TTF_RenderUTF8_Blended_Wrapped(font, text.c_str(), color, width);
        if (!s) return 0;
        int h = s->h;
        drawSurface(renderer, s, x, y);
        SDL_FreeSurface(s);
        return h;
    }

    // Wrapped text cut to the whole lines that fit in maxH. The last texture is kept, since a long
    // synopsis is expensive to lay out again on every frame.
    // Returns how many lines it can scroll; scrollLines starts the text that many lines down.
    int drawWrappedClipped(TTF_Font* font, const std::string& text, int x, int y, SDL_Color color, int width, int maxH,
                           int scrollLines = 0) {
        if (!font || text.empty() || maxH <= 0) return 0;
        if (text != clipText || width != clipWidth || !clipTex) {
            if (clipTex) SDL_DestroyTexture(clipTex);
            clipTex = nullptr;
            clipText = text;
            clipWidth = width;
            SDL_Surface* surf = TTF_RenderUTF8_Blended_Wrapped(font, text.c_str(), color, width);
            if (!surf) return 0;
            clipTex = SDL_CreateTextureFromSurface(renderer, surf);
            clipW = surf->w;
            clipH = surf->h;
            SDL_FreeSurface(surf);
            if (!clipTex) return 0;
        }
        const int line = std::max(1, TTF_FontLineSkip(font));
        const int h = std::min(clipH, maxH / line * line);
        if (h <= 0) return 0;
        const int maxScroll = std::max(0, (clipH - h + line - 1) / line);
        const int scroll = std::clamp(scrollLines, 0, maxScroll);
        const int srcY = std::min(scroll * line, clipH - h);
        SDL_Rect src{0, srcY, clipW, h}, dst{x, y, clipW, h};
        SDL_RenderCopy(renderer, clipTex, &src, &dst);

        // Arrows just right of the text when there's more above / below (callers leave room for them)
        const int ax = x + width + 8;
        if (scroll > 0) triangle(ax, y + 5, 5, true, kYellow);
        if (scroll < maxScroll) triangle(ax, y + h - 5, 5, false, kYellow);
        return maxScroll;
    }

    void triangle(int cx, int cy, int r, bool up, SDL_Color c) {
        SDL_Vertex v[3];
        const float d = up ? -1.0f : 1.0f;
        v[0].position = {(float)cx, cy + d * r};
        v[1].position = {(float)(cx - r), cy - d * r};
        v[2].position = {(float)(cx + r), cy - d * r};
        for (auto& vert : v) { vert.color = c; vert.tex_coord = {0, 0}; }
        SDL_RenderGeometry(renderer, nullptr, v, 3, nullptr, 0);
    }

    int wrappedHeight(TTF_Font* font, const std::string& text, int width) {
        if (!font || text.empty()) return 0;
        SDL_Surface* s = TTF_RenderUTF8_Blended_Wrapped(font, text.c_str(), kWhite, width);
        if (!s) return 0;
        int h = s->h;
        SDL_FreeSurface(s);
        return h;
    }

    void renderHeader(const Model& m, int battery) {
        fill(kBar, {0, 0, kScreenW, kHeaderH});
        const Category& c = m.cur();
        const int nameY = (kHeaderH - TTF_FontHeight(uiFont)) / 2;

        std::string bat = battery >= 0 ? std::to_string(battery) + "%" : "??";
        int batX = kScreenW - kMargin - textWidth(uiFont, bat);
        drawText(renderer, uiFont, bat, batX, nameY, kWhite);

        // "686 games", or "12 of 686 games" while searching
        std::string count = std::to_string(c.visible.size());
        if (!m.query.empty()) count += std::string(" ") + tr("of") + " " + std::to_string(c.entries.size());
        count += std::string(" ") + tr(c.isArchive ? (c.entries.size() == 1 ? "game" : "games")
                                                   : (c.entries.size() == 1 ? "app" : "apps"));
        if (!m.query.empty()) count += "  \u00b7  \"" + m.query + "\"";
        int countW = textWidth(smallFont, count);

        int maxNameW = batX - 24 - countW - 10 - kMargin;
        const std::string title = tr(c.name);
        int nameW = std::min(textWidth(uiFont, title), maxNameW);
        drawText(renderer, uiFont, title, kMargin, nameY, kWhite, maxNameW);
        drawText(renderer, smallFont, count, kMargin + nameW + 10,
                 nameY + TTF_FontAscent(uiFont) - TTF_FontAscent(smallFont), m.query.empty() ? kGrey : kYellow);

        if (m.showTabs) renderTabs(m);
    }

    // Strip with the neighbouring tabs around the current one (L1/R1 are listed in the footer hints).
    void renderTabs(const Model& m) {
        const int top = kHeaderH;
        fill(kClear, {0, top, kScreenW, kTabsH});
        fill(kTile, {0, top + kTabsH - 1, kScreenW, 1});
        const int pillH = TTF_FontHeight(smallFont) + 4;
        const int pillY = top + (kTabsH - pillH) / 2;

        // Arrows at the ends: the tabs wrap around in both directions
        const int arrowW = textWidth(smallFont, "\u2039") + 6;
        drawText(renderer, smallFont, "\u2039", kMargin, pillY + 2, kGrey);
        drawText(renderer, smallFont, "\u203a", kScreenW - kMargin - arrowW + 6, pillY + 2, kGrey);
        const int left = kMargin + arrowW + 6, right = kScreenW - kMargin - arrowW - 6;

        const int n = (int)m.categories.size();
        const int gap = 18, pad = 8;
        auto width = [&](int t) { return textWidth(smallFont, tr(m.categories[t].label)) + 2 * pad; };

        // Slide: start the new tab where it was drawn before the switch and ease it to the centre
        if (lastTab >= 0 && lastTab != m.tab && lastTab < n) {
            int dir = (lastTab + 1) % n == m.tab ? 1 : ((m.tab + 1) % n == lastTab ? -1 : 0);
            tabOffset += dir * (width(lastTab) / 2.0f + gap + width(m.tab) / 2.0f);
        }
        lastTab = m.tab;

        auto drawTab = [&](int t, int x) {
            int w = width(t);
            if (t == m.tab) {
                fill(kRowSel, {x, pillY - 2, w, pillH + 4});
                fill(kYellow, {x, pillY + pillH + 1, w, 2});
                drawText(renderer, smallFont, tr(m.categories[t].label), x + pad, pillY + 2, kWhite);
            } else {
                drawText(renderer, smallFont, tr(m.categories[t].label), x + pad, pillY + 2, kGrey);
            }
        };

        // A ring: the current tab in the middle, neighbours on both sides wrapping around, each tab
        // drawn once. Tabs cut by the edges are clipped.
        SDL_Rect clip{left, top, right - left, kTabsH};
        SDL_RenderSetClipRect(renderer, &clip);
        const int cx = (left + right) / 2 + (int)std::lround(tabOffset);
        drawTab(m.tab, cx - width(m.tab) / 2);
        int xr = cx + (width(m.tab) + 1) / 2 + gap;
        int xl = cx - width(m.tab) / 2 - gap;
        int used = 1;
        for (int i = 1; used < n; ++i) {
            bool placed = false;
            if (xr < right && used < n) {
                int t = (m.tab + i) % n;
                drawTab(t, xr);
                xr += width(t) + gap;
                ++used;
                placed = true;
            }
            if (xl > left && used < n) {
                int t = ((m.tab - i) % n + n) % n;
                xl -= width(t);
                drawTab(t, xl);
                xl -= gap;
                ++used;
                placed = true;
            }
            if (!placed) break;
        }
        SDL_RenderSetClipRect(renderer, nullptr);

        tabOffset *= 0.6f;
        if (std::fabs(tabOffset) < 0.5f) tabOffset = 0.0f;
    }

    void renderFooter(const Model& m, const Keyboard& kb) {
        const int top = kScreenH - kFooterH;
        fill(kBar, {0, top, kScreenW, kFooterH});

        std::vector<std::pair<std::string, std::string>> hints;
        if (m.menuOpen) {
            hints = {{"A", tr("Select")}, {"B", tr("Close")}};
        } else if (kb.open) {
            hints = {{"A", tr("Type")}, {"B", tr("Delete")}, {"START", tr("Done")}};
        } else {
            const Entry* sel = m.selected();
            hints = {{"L1", tr("Prev")}, {"R1", tr("Next")}, {"A", tr("Launch")},
                     {"Y", tr(sel && m.isFavorite(*sel) ? "Remove" : "My List")}};
            // while searching, clearing the search is more useful than starting a new one
            if (m.query.empty()) hints.push_back({"X", tr("Search")});
            else hints.push_back({"B", tr("Clear")});
            hints.push_back({"SELECT", tr("Autolaunch")});
            if (m.hasSettings) hints.push_back({"START", tr("Settings")});
        }

        // Button in the highlight colour, followed by what it does. The gap between hints shrinks
        // when they wouldn't fit on one line (e.g. "Y Remove" is wider than "Y My List").
        const int y = top + (kFooterH - TTF_FontHeight(smallFont)) / 2;
        const int keyGap = 6;
        int textW = 0;
        for (const auto& h : hints) textW += textWidth(smallFont, h.first) + keyGap + textWidth(smallFont, h.second);
        const int slots = std::max(1, (int)hints.size() - 1);
        const int gap = std::clamp((kScreenW - 2 * kMargin - textW) / slots, 4, 16);
        int x = kScreenW - kMargin;
        for (auto it = hints.rbegin(); it != hints.rend(); ++it) {
            x -= textWidth(smallFont, it->second);
            drawText(renderer, smallFont, it->second, x, y, kGrey);
            int keyW = textWidth(smallFont, it->first);
            x -= keyGap + keyW;
            drawText(renderer, smallFont, it->first, x, y, kYellow);
            x -= gap;
        }
    }

    void renderEmpty(const Model& m) {
        if (m.query.empty() && m.cur().name == kMyListName) {
            std::string s = tr("Your list is empty");
            std::string hint = tr("Press Y on any game to add it here");
            drawText(renderer, uiFont, s, (kScreenW - textWidth(uiFont, s)) / 2, kScreenH / 2 - 40, kGrey);
            drawText(renderer, smallFont, hint, (kScreenW - textWidth(smallFont, hint)) / 2, kScreenH / 2, kGrey);
            return;
        }
        std::string s = m.query.empty() ? tr("Nothing here") : tr("No matches for") + std::string(" \"") + m.query + "\"";
        int w = textWidth(uiFont, s);
        drawText(renderer, uiFont, s, std::max(kMargin, (kScreenW - w) / 2), kScreenH / 2 - 40, kGrey, kScreenW - 2 * kMargin);
        if (!m.query.empty()) {
            std::string hint = tr("L1/R1 to search other tabs");
            drawText(renderer, smallFont, hint, (kScreenW - textWidth(smallFont, hint)) / 2, kScreenH / 2, kGrey);
        }
    }

    void renderGrid(const Model& m) {
        const Category& c = m.cur();
        int selRow = c.sel / kGridCols;
        if (selRow < c.scroll) c.scroll = selRow;
        if (selRow >= c.scroll + kGridFullRows) c.scroll = selRow - kGridFullRows + 1;

        const int totalW = kGridCols * kCellWidth + (kGridCols - 1) * kGridGap;
        const int x0 = (kScreenW - totalW) / 2;
        for (int k = c.scroll * kGridCols; k < (int)c.visible.size(); ++k) {
            int row = k / kGridCols - c.scroll;
            if (row > kGridFullRows) break;    // one extra, partly hidden row hints that the list goes on
            int col = k % kGridCols;
            SDL_Rect cell{x0 + col * (kCellWidth + kGridGap), gridTop(m.showTabs) + row * kGridPitchY, kCellWidth, kCellHeight};
            fill(kTile, cell);
            drawIcon(*gridIcons, c.entries[c.visible[k]].iconPath, cell);
            if (k == c.sel) frame(kYellow, cell, kBorder);
            const Entry& entry = c.entries[c.visible[k]];
            if (m.isAutoStart(entry)) pill(tr("autolaunch"), cell.x, cell.y, kYellow, kBlack);
            if (m.isFavorite(entry)) {
                fill(kBar, {cell.x + cell.w - 26, cell.y + 2, 24, 24});
                star(cell.x + cell.w - 14, cell.y + 14, 9, kYellow);
            }
            if (c.mixed) {
                int w = textWidth(smallFont, entry.tag) + 12;
                pill(entry.tag, cell.x + cell.w - w, cell.y + cell.h - TTF_FontHeight(smallFont) - 4, kBar, kGrey);
            }
        }

        const Entry* e = m.selected();
        if (!e) return;
        const int bottom = kScreenH - kFooterH;
        const int textW = kScreenW - 2 * kMargin;
        const std::string sub = e->meta.empty() ? tr(e->description) : e->meta;
        int descH = sub.empty() ? 0 : TTF_FontHeight(descFont);
        int titleH = TTF_FontHeight(titleFont);
        int textTop = bottom - 8 - descH - titleH;
        gradient({0, textTop - 70, kScreenW, 70}, kClear);
        fill(kClear, {0, textTop, kScreenW, bottom - textTop});
        drawText(renderer, titleFont, e->name, kMargin, textTop, kWhite, textW);
        drawText(renderer, descFont, sub, kMargin, textTop + titleH, kGrey, textW);
    }

    // Width of a pill() with this text; the system tags are measured once.
    int pillWidth(const std::string& text) {
        auto it = pillWidths.find(text);
        if (it != pillWidths.end()) return it->second;
        return pillWidths[text] = textWidth(smallFont, text) + 12;
    }
    std::map<std::string, int> pillWidths;

    // The selected list row's name, when it doesn't fit, scrolls left to show the rest: it waits a
    // moment, scrolls to the end, waits again and starts over.
    static constexpr Uint32 kMarqueeHoldMs = 1200;
    static constexpr int kMarqueeSpeed = 40;            // pixels per second
    static constexpr Uint32 kMarqueeFrameMs = 33;
    std::string marqueeKey;
    Uint32 marqueeStart = 0, marqueeNext = 0;

    int marqueeOffset(const std::string& key, int overflow) {
        const Uint32 now = SDL_GetTicks();
        if (key != marqueeKey) { marqueeKey = key; marqueeStart = now; }
        const Uint32 scrollMs = (Uint32)overflow * 1000 / kMarqueeSpeed;
        Uint32 t = now - marqueeStart;
        if (t >= 2 * kMarqueeHoldMs + scrollMs) { marqueeStart = now; t = 0; }
        if (t < kMarqueeHoldMs) {
            marqueeNext = marqueeStart + kMarqueeHoldMs;
            return 0;
        }
        if (t < kMarqueeHoldMs + scrollMs) {
            marqueeNext = now + kMarqueeFrameMs;
            return (int)((t - kMarqueeHoldMs) * kMarqueeSpeed / 1000);
        }
        marqueeNext = marqueeStart + 2 * kMarqueeHoldMs + scrollMs;
        return overflow;
    }

    void renderList(const Model& m) {
        const Category& c = m.cur();
        if (c.sel < c.scroll) c.scroll = c.sel;
        const int rows = listRows(m.showTabs), top = listTop(m.showTabs);
        if (c.sel >= c.scroll + rows) c.scroll = c.sel - rows + 1;

        // Rows are laid out in columns, like a table: [star] name ... [auto] [system]. The star has a
        // fixed slot before the name, and the system column is as wide as the widest tag in the tab,
        // with the tags at its left edge, so both line up from row to row.
        const int fontH = TTF_FontHeight(descFont);
        const int starW = 20;
        if (c.mixed && c.tagColumn < 0) {
            c.tagColumn = 0;
            for (const Entry& e : c.entries) c.tagColumn = std::max(c.tagColumn, pillWidth(e.tag));
        }
        const int tagColW = c.mixed ? c.tagColumn : 0;
        for (int row = 0; row < rows && c.scroll + row < (int)c.visible.size(); ++row) {
            int k = c.scroll + row;
            const Entry& e = c.entries[c.visible[k]];
            SDL_Rect r{kMargin, top + row * kListRowH, kListWidth, kListRowH - 2};
            if (k == c.sel) {
                fill(kRowSel, r);
                fill(kYellow, {r.x, r.y, 4, r.h});
            }
            const int tagY = r.y + (r.h - TTF_FontHeight(smallFont) - 4) / 2;
            const int nameX = r.x + 12 + starW;
            int right = r.x + r.w - 4;      // the name ends before this
            if (c.mixed) {
                right -= tagColW;
                pill(e.tag, right, tagY, kTile, kGrey);
                right -= 8;
            }
            if (m.isAutoStart(e)) {
                right -= pillWidth(tr("auto"));
                pill(tr("auto"), right, tagY, kYellow, kBlack);
                right -= 8;
            }
            if (m.isFavorite(e)) star(r.x + 12 + starW / 2, r.y + r.h / 2, 7, kYellow);
            int scrollX = 0;
            if (k == c.sel) {
                const int overflow = textWidth(descFont, e.name) - (right - nameX);
                if (overflow > 0) scrollX = marqueeOffset(c.name + "\x1f" + e.category + "\x1f" + e.id, overflow);
            }
            drawText(renderer, descFont, e.name, nameX, r.y + (r.h - fontH) / 2, k == c.sel ? kWhite : kGrey,
                     right - nameX, scrollX);
        }

        // Scrollbar, only when the tab doesn't fit on one screen
        int total = (int)c.visible.size();
        if (total > rows) {
            SDL_Rect track{kMargin + kListWidth + 4, top, 4, rows * kListRowH - 2};
            fill(kTile, track);
            int thumbH = std::max(16, track.h * rows / total);
            int thumbY = track.y + (track.h - thumbH) * c.scroll / std::max(1, total - rows);
            fill(kGrey, {track.x, thumbY, track.w, thumbH});
        }

        const Entry* e = m.selected();
        if (!e) return;
        SDL_Rect box{kPreviewX, top, kPreviewW, kPreviewH};
        fill(kTile, box);
        drawIcon(*previewIcons, e->iconPath, box);
        int y = box.y + box.h + 10;
        y += drawWrapped(uiFont, e->name, kPreviewX, y, kWhite, kPreviewW) + 4;
        if (!e->meta.empty()) {
            drawText(renderer, smallFont, e->meta, kPreviewX, y, kYellow, kPreviewW);
            y += TTF_FontLineSkip(smallFont) + 4;
        }
        const int textBottom = kScreenH - kFooterH - TTF_FontHeight(smallFont) - 10;   // above the "n / total"
        descMax = drawWrappedClipped(smallFont, e->synopsis.empty() ? tr(e->description) : e->synopsis,
                                     kPreviewX, y, kGrey, kPreviewW - 16, textBottom - y, m.descScroll);

        std::string pos = std::to_string(c.sel + 1) + " / " + std::to_string(total);
        drawText(renderer, smallFont, pos, kScreenW - kMargin - textWidth(smallFont, pos),
                 kScreenH - kFooterH - TTF_FontHeight(smallFont) - 6, kGrey);
    }

    void renderOsd(const Osd& osd, int top) {
        const int w = 300, h = 64, pad = 14;
        SDL_Rect panel{(kScreenW - w) / 2, top + 12, w, h};
        fill({12, 12, 14, 235}, panel);
        frame(kTile, panel, 2);

        std::string label = osd.kind == "brightness" ? tr("Brightness") : (osd.kind == "volume" ? tr("Volume") : osd.kind);
        std::string value = osd.muted ? tr("Muted") : std::to_string(osd.percent) + "%";
        drawText(renderer, descFont, label, panel.x + pad, panel.y + 8, kWhite);
        drawText(renderer, descFont, value, panel.x + w - pad - textWidth(descFont, value), panel.y + 8, kYellow);

        SDL_Rect track{panel.x + pad, panel.y + h - 20, w - 2 * pad, 8};
        fill(kTile, track);
        fill(kYellow, {track.x, track.y, osd.muted ? 0 : track.w * osd.percent / 100, track.h});
    }

    void renderStatus(const std::string& text) {
        fill(kClear, {0, 0, kScreenW, kScreenH});
        drawText(renderer, titleFont, text, (kScreenW - textWidth(titleFont, text)) / 2,
                 (kScreenH - TTF_FontHeight(titleFont)) / 2, kWhite);
    }

    void renderMenu(const Model& m) {
        const int pad = 12, rowH = 40;
        const int titleH = TTF_FontHeight(uiFont) + 14;
        const int panelW = 320;
        const int count = (int)m.menuItems.size();
        const int panelH = titleH + count * rowH + 2 * pad;
        const int bodyY = bodyTop(m.showTabs);
        SDL_Rect panel{(kScreenW - panelW) / 2, bodyY + (kScreenH - kFooterH - bodyY - panelH) / 2, panelW, panelH};
        fill({0, 0, 0, 150}, {0, kHeaderH, kScreenW, kScreenH - kFooterH - kHeaderH});   // dim the tab behind
        fill(kBar, panel);
        frame(kTile, panel, 2);
        drawText(renderer, uiFont, tr("Power options"), panel.x + pad + 4, panel.y + pad, kWhite);

        const int fontH = TTF_FontHeight(descFont);
        for (int i = 0; i < count; ++i) {
            SDL_Rect r{panel.x + pad, panel.y + pad + titleH + i * rowH, panelW - 2 * pad, rowH - 4};
            bool sel = i == m.menuSel;
            if (sel) {
                fill(kRowSel, r);
                fill(kYellow, {r.x, r.y, 4, r.h});
            }
            drawText(renderer, descFont, tr(m.menuItems[i].label), r.x + 16, r.y + (r.h - fontH) / 2,
                     sel ? kWhite : kGrey, r.w - 24);
        }
    }

    void renderKeyboard(const Model& m, const Keyboard& kb) {
        const int pad = 12, gap = 4, unit = 58, keyH = 36;
        const int queryH = TTF_FontHeight(uiFont) + 12;
        const int panelW = (int)(Keyboard::kRowUnits * unit) - gap + 2 * pad;
        const int panelH = queryH + Keyboard::kRows * keyH + (Keyboard::kRows - 1) * gap + 2 * pad;
        SDL_Rect panel{(kScreenW - panelW) / 2, kScreenH - kFooterH - panelH - 6, panelW, panelH};
        fill({12, 12, 14, 240}, panel);
        frame(kTile, panel, 2);

        drawText(renderer, uiFont, tr("Search:") + std::string(" ") + m.query + "_", panel.x + pad, panel.y + pad, kWhite, panelW - 2 * pad);

        for (int r = 0; r < Keyboard::kRows; ++r) {
            const auto& keys = Keyboard::keys(r);
            for (int c = 0; c < (int)keys.size(); ++c) {
                const Keyboard::Key& key = keys[c];
                SDL_Rect k{panel.x + pad + (int)(key.x * unit), panel.y + pad + queryH + r * (keyH + gap),
                           (int)(key.w * unit) - gap, keyH};
                bool sel = r == kb.row && c == kb.col;
                fill(sel ? kYellow : kTile, k);
                std::string label = key.label.size() > 1 ? tr(key.label) : key.label;   // space / del / ok
                TTF_Font* f = key.label.size() > 1 ? smallFont : uiFont;
                if (label.size() == 1) label = upper(label);
                drawText(renderer, f, label, k.x + (k.w - textWidth(f, label)) / 2,
                         k.y + (k.h - TTF_FontHeight(f)) / 2, sel ? kBlack : kWhite);
            }
        }
    }
};

enum class Action { None, Up, Down, Left, Right, Launch, Back, ToggleAutoStart, ToggleFavorite, Search, PrevTab, NextTab, Start, Power,
                    ScrollUp, ScrollDown };

static bool isRepeatable(Action a) {
    return a == Action::Up || a == Action::Down || a == Action::Left || a == Action::Right ||
           a == Action::ScrollUp || a == Action::ScrollDown;
}

static bool isScroll(Action a) { return a == Action::ScrollUp || a == Action::ScrollDown; }

// Left stick as a d-pad: the dominant axis past kStickOn picks the direction, which holds until the
// stick comes back under kStickOff.
static Action stickDirection(int x, int y, Action current) {
    auto magnitude = [&](Action a) {
        switch (a) {
            case Action::Left:  return -x;
            case Action::Right: return x;
            case Action::Up:    return -y;
            case Action::Down:  return y;
            default:            return 0;
        }
    };
    if (current != Action::None && magnitude(current) > kStickOff) return current;
    if (std::max(std::abs(x), std::abs(y)) < kStickOn) return Action::None;
    if (std::abs(x) > std::abs(y)) return x < 0 ? Action::Left : Action::Right;
    return y < 0 ? Action::Up : Action::Down;
}

// Keyboard bindings, mostly for running the launcher on a PC: F1/F2 = L1/R1, Space = Y, F3 = Select,
// F4 = X, F5 = Start,
// F6 = POWER (the real power key arrives as SDLK_POWER), PageUp/PageDown = right stick.
static Action actionFromKey(SDL_Keycode k) {
    switch (k) {
        case SDLK_UP:        return Action::Up;
        case SDLK_DOWN:      return Action::Down;
        case SDLK_LEFT:      return Action::Left;
        case SDLK_RIGHT:     return Action::Right;
        case SDLK_RETURN:    return Action::Launch;
        case SDLK_ESCAPE:
        case SDLK_BACKSPACE: return Action::Back;
        case SDLK_SPACE:     return Action::ToggleFavorite;
        case SDLK_F3:        return Action::ToggleAutoStart;
        case SDLK_F1:        return Action::PrevTab;
        case SDLK_F2:        return Action::NextTab;
        case SDLK_F4:        return Action::Search;
        case SDLK_F5:        return Action::Start;
        case SDLK_POWER:
        case SDLK_F6:        return Action::Power;
        case SDLK_PAGEUP:    return Action::ScrollUp;
        case SDLK_PAGEDOWN:  return Action::ScrollDown;
        default:             return Action::None;
    }
}

static Action actionFromButton(Uint8 b) {
    switch (b) {
        case SDL_CONTROLLER_BUTTON_DPAD_UP:       return Action::Up;
        case SDL_CONTROLLER_BUTTON_DPAD_DOWN:     return Action::Down;
        case SDL_CONTROLLER_BUTTON_DPAD_LEFT:     return Action::Left;
        case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:    return Action::Right;
        case SDL_CONTROLLER_BUTTON_A:             return Action::Launch;
        case SDL_CONTROLLER_BUTTON_B:             return Action::Back;
        case SDL_CONTROLLER_BUTTON_X:             return Action::Search;
        case SDL_CONTROLLER_BUTTON_Y:             return Action::ToggleFavorite;
        case SDL_CONTROLLER_BUTTON_START:         return Action::Start;
        case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:  return Action::PrevTab;
        case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: return Action::NextTab;
        default:                                  return Action::None;
    }
}

// Reads puppy.conf: "key = value" lines, "#" comments, lists separated by ";". Relative paths are
// relative to the file, "~/" is the home folder. The file is the one given with --config, else
// $PUPPY_CONFIG, else /etc/puppy.conf; without one, the goodluckOS defaults stay.
static bool loadConfig(int argc, char** argv) {
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
        {"state_file", &cfg.stateFile}, {"autolaunch_file", &cfg.autoStartFile}, {"config_dir", &cfg.configDir},
        {"cache_dir", &cfg.cacheDir}, {"lang_dir", &cfg.langDir}, {"power_fifo", &cfg.powerFifo},
        {"backlight", &cfg.backlight}, {"osd_file", &cfg.osdFile},
    };
    std::map<std::string, std::string*> texts = {
        {"language", &cfg.language}, {"view", &cfg.view}, {"tabs", &cfg.tabs},
        {"settings_command", &cfg.settingsCommand}, {"restart_command", &cfg.restartCommand},
        {"shutdown_command", &cfg.shutdownCommand}, {"screen_off_command", &cfg.screenOffCommand},
    };
    std::map<std::string, std::vector<std::string>*> lists = {
        {"apps", &cfg.apps}, {"apps_dirs", &cfg.appsDirs}, {"es_systems", &cfg.esSystems},
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

int main(int argc, char** argv) {
    if (!loadConfig(argc, argv)) return 2;
    i18n::langDirPath() = cfg.langDir;
    i18n::settingsPath() = cfg.settingsFile();
    if (!cfg.language.empty()) i18n::load(cfg.language);
    else i18n::loadConfigured();

    Model model;
    model.categories = loadCatalog();
    if (model.categories.empty()) {
        std::cerr << "Nothing to show: no entries in the apps files and no games in the es_systems.cfg systems\n";
        return 1;
    }
    for (auto& c : model.categories)
        for (auto& e : c.entries) e.searchKey = lower(e.id == e.name ? e.name : e.name + " " + e.id);
    extractSystemMenu(model);
    applySettingsCommand(model);
    addAllGamesTab(model);   // first tab, and the one shown at boot
    loadFavorites(model);
    addMyListTab(model);
    if (model.categories.empty()) {
        std::cerr << "Nothing to show\n";
        return 1;
    }

    loadSettings(model);
    model.applyFilter();
    restoreCursor(model);
    {
        std::string cat, name;
        if (readAutoStartId(cat, name)) { model.autoCategory = cat; model.autoName = name; }
    }

    Ui ui;
    if (!ui.ok()) return 1;

    SDL_GameController* pad = nullptr;
    for (int i = 0; i < SDL_NumJoysticks(); ++i) {
        if (SDL_IsGameController(i)) { pad = SDL_GameControllerOpen(i); break; }
    }

    Keyboard kb;
    Osd osd;
    bool consoleCleared = false;
    bool selectHeld = false, selectCombo = false;
    Action leftStick = Action::None, rightStick = Action::None;
    Uint32 osdUntil = 0, osdNextRead = 0;
    bool running = true;
    bool dirty = true;
    int shownBattery = -2;
    Uint32 lastActivity = SDL_GetTicks();

    // d-pad auto-repeat
    Action held = Action::None;
    Uint32 nextRepeat = 0;

    auto typeKey = [&](const std::string& key) {
        if (key == "ok") { kb.open = false; return; }
        if (key == "del") { if (!model.query.empty()) model.query.pop_back(); }
        else if ((int)model.query.size() < kMaxQueryLength) model.query += (key == "space" ? " " : key);
        model.applyFilter();
    };

    auto apply = [&](Action a) {
        const bool grid = model.view == View::Grid;

        if (!model.status.empty()) return;   // restarting / shutting down

        if (model.menuOpen) {
            const int n = (int)model.menuItems.size();
            switch (a) {
                case Action::Up:     model.menuSel = (model.menuSel + n - 1) % n; break;
                case Action::Down:   model.menuSel = (model.menuSel + 1) % n;     break;
                case Action::Launch: {
                    const PowerItem item = model.menuItems[model.menuSel];
                    model.menuOpen = false;
                    if (item.quit) {
                        running = false;
                        break;
                    }
                    if (item.command && !item.command->empty()) {
                        if (item.status) model.status = tr(item.status);
                        runDetached(*item.command);
                        break;
                    }
                    if (item.confirmEntry) {
                        auto confirm = std::find_if(model.systemEntries.begin(), model.systemEntries.end(),
                                                    [&](const Entry& e) { return e.name == item.confirmEntry; });
                        if (confirm != model.systemEntries.end()) {
                            launch(model, *confirm);
                            running = false;
                            break;
                        }
                    }
                    if (item.status) model.status = tr(item.status);
                    if (item.request) sendPowerRequest(item.request);
                    break;
                }
                case Action::Back:
                case Action::Power:  model.menuOpen = false; break;
                default: break;
            }
            return;
        }
        auto openMenu = [&]() {
            model.menuItems = powerItems(model);
            if (model.menuItems.empty()) return;
            kb.open = false;
            model.menuOpen = true;
            model.menuSel = 0;
        };
        if (a == Action::Power) {
            // with the screen off, toggle-screen.sh turns it back on; don't open a menu in the dark
            if (screenOn()) openMenu();
            return;
        }
        if (a == Action::Start && !kb.open) {
            if (model.hasSettings) {
                launch(model, model.settings);
                running = false;
                return;
            }
            // no settings app (e.g. on other firmwares, where POWER may suspend): START opens the menu
            openMenu();
            if (model.menuOpen) return;
        }

        switch (a) {
            case Action::PrevTab:    model.switchTab(-1); return;
            case Action::NextTab:    model.switchTab(1);  return;
            default: break;
        }

        if (kb.open) {
            switch (a) {
                case Action::Up:     kb.move(0, -1); break;
                case Action::Down:   kb.move(0, 1);  break;
                case Action::Left:   kb.move(-1, 0); break;
                case Action::Right:  kb.move(1, 0);  break;
                case Action::Launch: typeKey(kb.current()); break;
                case Action::Back:
                    if (model.query.empty()) kb.open = false;
                    else typeKey("del");
                    break;
                case Action::Start:
                case Action::Search: kb.open = false; break;
                default: break;
            }
            return;
        }

        switch (a) {
            case Action::Up:    model.moveSel(grid ? -kGridCols : -1); break;
            case Action::Down:  model.moveSel(grid ? kGridCols : 1);   break;
            case Action::Left:  model.moveSel(grid ? -1 : -listRows(model.showTabs)); break;
            case Action::Right: model.moveSel(grid ? 1 : listRows(model.showTabs));   break;
            case Action::Search: kb.open = true; break;
            case Action::Back:
                if (!model.query.empty()) { model.query.clear(); model.applyFilter(); }
                break;
            case Action::ToggleAutoStart: toggleAutoStart(model); break;
            case Action::ToggleFavorite:  toggleFavorite(model);  break;
            case Action::ScrollUp:   model.descScroll = std::max(0, model.descScroll - 1); break;
            case Action::ScrollDown: model.descScroll = std::min(ui.descMaxScroll(), model.descScroll + 1); break;
            case Action::Launch:
                if (const Entry* e = model.selected()) {
                    launch(model, *e);
                    running = false;
                }
                break;
            default: break;
        }
    };

    while (running) {
        if (dirty) {
            shownBattery = readBattery();
            ui.render(model, kb, osd, shownBattery);
            if (!consoleCleared) {
                // The boot's "Starting system..." stays on the text console, which flashes between
                // apps; we can't write to it as player, so ask the root power-manager.sh
                sendPowerRequest("clear-console");
                consoleCleared = true;
            }
            dirty = false;
        }

        Uint32 now = SDL_GetTicks();
        Uint32 elapsed = now - lastActivity;
        int timeout = elapsed >= kIdleCheckMs ? 0 : (int)(kIdleCheckMs - elapsed);
        if (held != Action::None) timeout = std::min(timeout, (int)std::max<Sint32>(0, (Sint32)(nextRepeat - now)));
        if (osd.visible) {
            if ((Sint32)(now - osdUntil) >= 0) {
                osd.visible = false;
                dirty = true;
                timeout = 0;
            } else {
                if ((Sint32)(now - osdNextRead) >= 0) {
                    osd.read();
                    osdNextRead = now + kOsdRefreshMs;
                    dirty = true;
                }
                timeout = std::min(timeout, (int)kOsdRefreshMs);
            }
        }
        if (ui.animating()) {   // keep drawing until the tab strip has slid into place (paced by vsync)
            dirty = true;
            timeout = 0;
        }
        if (Uint32 due = ui.marqueeDue()) {   // a long selected name is scrolling
            if ((Sint32)(now - due) >= 0) {
                dirty = true;
                timeout = 0;
            } else {
                timeout = std::min(timeout, (int)(due - now));
            }
        }

        SDL_Event ev;
        if (!SDL_WaitEventTimeout(&ev, timeout)) {
            now = SDL_GetTicks();
            if (held != Action::None && (Sint32)(now - nextRepeat) >= 0) {
                apply(held);
                nextRepeat = now + (isScroll(held) ? kScrollRateMs : kRepeatRateMs);
                dirty = true;
                lastActivity = now;
            } else if (now - lastActivity >= kIdleCheckMs) {
                lastActivity = now;
                if (readBattery() != shownBattery) dirty = true;
            }
            continue;
        }

        do {
            Action action = Action::None;
            switch (ev.type) {
                case SDL_QUIT:
                    running = false;
                    break;
                case SDL_WINDOWEVENT:
                    if (ev.window.event == SDL_WINDOWEVENT_EXPOSED) dirty = true;
                    break;
                case SDL_KEYDOWN: {
                    SDL_Keycode k = ev.key.keysym.sym;
                    // volume keys (and FN + volume for brightness) are handled by triggerhappy scripts;
                    // just show the resulting level
                    if (k == SDLK_VOLUMEUP || k == SDLK_VOLUMEDOWN) {
                        osd.visible = true;
                        osdUntil = SDL_GetTicks() + kOsdShowMs;
                        osdNextRead = SDL_GetTicks() + 30;   // give the script a moment to write it
                        break;
                    }
                    if (kb.open && ((k >= SDLK_a && k <= SDLK_z) || (k >= SDLK_0 && k <= SDLK_9))) {
                        typeKey(std::string(1, (char)k));
                        dirty = true;
                    } else if (!ev.key.repeat) {
                        action = actionFromKey(k);
                    }
                    break;
                }
                case SDL_KEYUP:
                    if (actionFromKey(ev.key.keysym.sym) == held) held = Action::None;
                    break;
                case SDL_CONTROLLERBUTTONDOWN:
                    // SELECT toggles autolaunch when released on its own: SELECT + START is the
                    // close-app shortcut, which must neither set autolaunch nor open the settings
                    if (ev.cbutton.button == SDL_CONTROLLER_BUTTON_BACK) {
                        selectHeld = true;
                        selectCombo = false;
                        break;
                    }
                    if (selectHeld) {
                        selectCombo = true;
                        break;
                    }
                    action = actionFromButton(ev.cbutton.button);
                    break;
                case SDL_CONTROLLERAXISMOTION: {
                    // Left stick navigates like the d-pad; right stick up/down scrolls the description
                    const Uint8 axis = ev.caxis.axis;
                    if (axis == SDL_CONTROLLER_AXIS_LEFTX || axis == SDL_CONTROLLER_AXIS_LEFTY) {
                        Action dir = stickDirection(SDL_GameControllerGetAxis(pad, SDL_CONTROLLER_AXIS_LEFTX),
                                                    SDL_GameControllerGetAxis(pad, SDL_CONTROLLER_AXIS_LEFTY), leftStick);
                        if (dir != leftStick) {
                            if (held == leftStick) held = Action::None;
                            leftStick = dir;
                            action = dir;
                        }
                    } else if (axis == SDL_CONTROLLER_AXIS_RIGHTY) {
                        const int v = ev.caxis.value;
                        Action dir = v < -kStickOn ? Action::ScrollUp : v > kStickOn ? Action::ScrollDown
                                   : std::abs(v) < kStickOff ? Action::None : rightStick;
                        if (dir != rightStick) {
                            if (held == rightStick) held = Action::None;
                            rightStick = dir;
                            action = dir;
                        }
                    }
                    break;
                }
                case SDL_CONTROLLERBUTTONUP:
                    if (ev.cbutton.button == SDL_CONTROLLER_BUTTON_BACK) {
                        if (selectHeld && !selectCombo) action = Action::ToggleAutoStart;
                        selectHeld = false;
                        break;
                    }
                    if (actionFromButton(ev.cbutton.button) == held) held = Action::None;
                    break;
            }

            if (action != Action::None) {
                apply(action);
                if (isRepeatable(action)) {
                    held = action;
                    nextRepeat = SDL_GetTicks() + (isScroll(action) ? kScrollDelayMs : kRepeatDelayMs);
                }
                dirty = true;
                lastActivity = SDL_GetTicks();
            }
        } while (running && SDL_PollEvent(&ev));
    }

    if (pad) SDL_GameControllerClose(pad);
    return 0;
}
