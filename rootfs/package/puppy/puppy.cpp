#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>
#include <SDL2/SDL_ttf.h>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace fs = std::filesystem;

static const char* kFontFile      = "/usr/share/fonts/Inter_24pt-Medium.ttf";
static const char* kAppsFiles[]   = {"/usr/share/puppy/apps.puppy", "/home/player/apps.puppy"};
static const char* kPuppyFiles[]   = {"/home/player/.local/share/applications"};
static const char* kLaunchFile    = "/dev/shm/launch";
static const char* kStateFile     = "/dev/shm/launcher_state";
static const char* kAutoStartFile = "/home/player/autolaunch";

static const char* kSettingsFile  = "/home/player/.config/puppy/settings";
static const char* kMenuCategory  = "System";   // apps.puppy category taken out of the tabs
static const char* kSettingsName  = "System Settings";   // entry of that category opened by START
static const char* kPowerFifo     = "/run/power-request";   // root power-manager.sh
static const char* kBacklight     = "/sys/class/backlight/backlight/brightness";
static const char* kOsdFile       = "/dev/shm/osd";  // "volume|brightness <percent> [muted]", from osd-notify.sh

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

static void drawSurface(SDL_Renderer* r, SDL_Surface* s, int x, int y, int maxW = 0) {
    SDL_Texture* t = SDL_CreateTextureFromSurface(r, s);
    if (!t) return;
    SDL_SetTextureBlendMode(t, SDL_BLENDMODE_BLEND);
    int w = (maxW > 0) ? std::min(s->w, maxW) : s->w;   // clip, don't squash
    SDL_Rect src{0, 0, w, s->h};
    SDL_Rect dst{x, y, w, s->h};
    SDL_RenderCopy(r, t, &src, &dst);
    SDL_DestroyTexture(t);
}

static void drawText(SDL_Renderer* r, TTF_Font* font, const std::string& text, int x, int y, SDL_Color color, int maxW = 0) {
    if (!font || text.empty()) return;
    SDL_Surface* s = TTF_RenderUTF8_Blended(font, text.c_str(), color);
    if (!s) return;
    drawSurface(r, s, x, y, maxW);
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
    // to fit inside it. Smaller images are kept at their size.
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

    Icon load(const std::string& path) {
        Icon icon;
        SDL_Surface* loaded = IMG_Load(path.c_str());
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
    std::string name;
    std::string description;
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
};

enum class View { Grid, List };

struct Model {
    std::vector<Category> categories;
    int tab = 0;
    View view = View::Grid;
    bool showTabs = true;
    std::string query;
    std::string autoCategory, autoName;   // the autolaunch entry

    // START opens System Settings; POWER opens the power menu (both from any tab)
    Entry settings;
    bool hasSettings = false;
    bool menuOpen = false;
    int menuSel = 0;
    std::string status;     // full-screen message while restarting / shutting down

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
        int n = (int)categories.size();
        if (n > 0) tab = ((tab + delta) % n + n) % n;
    }

    void moveSel(int delta) {
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
        return !autoName.empty() && e.category == autoCategory && e.name == autoName;
    }

    // Finds an entry (by its category and name) in the tab called tabName.
    bool find(const std::string& tabName, const std::string& category, const std::string& name,
              int& outTab, int& outEntry) const {
        for (size_t t = 0; t < categories.size(); ++t) {
            if (categories[t].name != tabName) continue;
            for (size_t e = 0; e < categories[t].entries.size(); ++e) {
                const Entry& entry = categories[t].entries[e];
                if (entry.category == category && entry.name == name) {
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

static std::string findArchiveIcon(const Archive& a, const std::string& stem) {
    static const char* kExts[] = {"png", "jpg", "jpeg"};
    for (const auto& dir : a.iconDirs) {
        for (const char* ext : kExts) {
            fs::path p = fs::path(dir) / (stem + "." + ext);
            std::error_code ec;
            if (fs::is_regular_file(p, ec)) return p.string();
        }
    }
    return a.defaultIcon;
}

static std::vector<Entry> expandArchive(const Archive& a) {
    std::vector<std::string> exts;
    for (auto e : a.exts) {
        if (!e.empty() && e[0] == '.') e.erase(0, 1);
        exts.push_back(lower(e));
    }

    std::vector<Entry> out;
    for (const auto& dir : a.dirs) {
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
            e.name        = p.stem().string();
            e.description = a.description;
            e.command     = buildArchiveCommand(a.command, p.string());
            e.iconPath    = findArchiveIcon(a, e.name);
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
    for (const char* path : kAppsFiles) parseAppsFile(path, records);

    //parse indiviual .puppy files in ~/.local/share/applications
    for (const auto& path : kPuppyFiles) {
        if (!fs::exists(path) || !fs::is_directory(path)) continue;
        for (const auto& entry : fs::directory_iterator(path)) {
            if (entry.path().extension() == ".puppy") {
                parseAppsFile(entry.path().string(), records);
            }
        }
    }

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
    std::ofstream out(kAutoStartFile);
    if (out) out << "# " << e.category << "\t" << e.name << "\n" << e.command << "\n";
}

static void clearAutoStart() {
    std::error_code ec;
    fs::remove(kAutoStartFile, ec);
}

static bool readAutoStartId(std::string& category, std::string& name) {
    std::ifstream in(kAutoStartFile);
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
        m.autoName = e->name;
    }
}

static void launch(const Model& m, const Entry& e) {
    { std::ofstream out(kLaunchFile); if (out) out << e.command << "\n"; }
    std::ofstream state(kStateFile);
    if (state) state << m.cur().name << "\n" << e.category << "\n" << e.name << "\n";
}

static void restoreCursor(Model& m) {
    std::ifstream in(kStateFile);
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

// Takes the System category out of the tabs: its settings entry opens with START and the power
// actions live in the POWER menu, so they don't mean scrolling through every tab.
static void extractSystemMenu(Model& m) {
    auto sys = std::find_if(m.categories.begin(), m.categories.end(),
                            [](const Category& c) { return c.name == kMenuCategory; });
    if (sys == m.categories.end()) return;
    for (const Entry& e : sys->entries) {
        if (e.name == kSettingsName) { m.settings = e; m.hasSettings = true; }
    }
    m.categories.erase(sys);
}

// The POWER menu. Each item is a request for the root power-manager.sh.
struct PowerItem {
    const char* label;
    const char* request;
    const char* status;     // shown while it happens (nullptr: nothing to wait for)
};
static const PowerItem kPowerItems[] = {
    {"Display off", "screen-off", nullptr},
    {"Restart", "reboot", "Restarting..."},
    {"Shut down", "poweroff", "Shutting down..."},
};
constexpr int kPowerItemCount = sizeof(kPowerItems) / sizeof(kPowerItems[0]);

static void sendPowerRequest(const char* request) {
    std::ofstream fifo(kPowerFifo);
    if (fifo) fifo << request << "\n";
}

static bool screenOn() {
    std::ifstream in(kBacklight);
    int level = 1;
    in >> level;
    return level > 0;
}

// Launcher options, set in System Settings: "view=grid|list" and "tabs=on|off".
static void loadSettings(Model& m) {
    std::ifstream in(kSettingsFile);
    for (std::string line; std::getline(in, line);) {
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
        std::ifstream in(kOsdFile);
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

        uiFont    = TTF_OpenFont(kFontFile, 22);
        titleFont = TTF_OpenFont(kFontFile, 30);
        descFont  = TTF_OpenFont(kFontFile, 20);
        smallFont = TTF_OpenFont(kFontFile, 15);
        if (!uiFont || !titleFont || !descFont || !smallFont)
            std::cerr << "Warning: could not load font " << kFontFile << "\n";

        gridIcons    = std::make_unique<IconCache>(renderer, "/usr/share/puppy/assets/fallback.png", kCellWidth, kCellHeight, false);
        previewIcons = std::make_unique<IconCache>(renderer, "/usr/share/puppy/assets/fallback.png", kPreviewW, kPreviewH, true);
        ok_ = true;
    }

    ~Ui() {
        gridIcons.reset();
        previewIcons.reset();
        for (TTF_Font* f : {uiFont, titleFont, descFont, smallFont}) if (f) TTF_CloseFont(f);
        if (renderer) SDL_DestroyRenderer(renderer);
        if (window) SDL_DestroyWindow(window);
        if (sdlUp) { TTF_Quit(); IMG_Quit(); SDL_Quit(); }
    }

    Ui(const Ui&) = delete;
    Ui& operator=(const Ui&) = delete;

    bool ok() const { return ok_; }
    bool animating() const { return tabOffset != 0.0f; }

    void render(const Model& m, const Keyboard& kb, const Osd& osd, int battery) {
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

        SDL_RenderPresent(renderer);
    }

private:
    bool sdlUp = false, ok_ = false;
    SDL_Window* window = nullptr;
    SDL_Renderer* renderer = nullptr;
    TTF_Font *uiFont = nullptr, *titleFont = nullptr, *descFont = nullptr, *smallFont = nullptr;
    std::unique_ptr<IconCache> gridIcons, previewIcons;
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
        if (!m.query.empty()) count += " of " + std::to_string(c.entries.size());
        count += c.isArchive ? (c.entries.size() == 1 ? " game" : " games") : (c.entries.size() == 1 ? " app" : " apps");
        if (!m.query.empty()) count += "  \u00b7  \"" + m.query + "\"";
        int countW = textWidth(smallFont, count);

        int maxNameW = batX - 24 - countW - 10 - kMargin;
        int nameW = std::min(textWidth(uiFont, c.name), maxNameW);
        drawText(renderer, uiFont, c.name, kMargin, nameY, kWhite, maxNameW);
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
        auto width = [&](int t) { return textWidth(smallFont, m.categories[t].label) + 2 * pad; };

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
                drawText(renderer, smallFont, m.categories[t].label, x + pad, pillY + 2, kWhite);
            } else {
                drawText(renderer, smallFont, m.categories[t].label, x + pad, pillY + 2, kGrey);
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
            hints = {{"A", "Select"}, {"B", "Close"}};
        } else if (kb.open) {
            hints = {{"A", "Type"}, {"B", "Delete"}, {"START", "Done"}};
        } else {
            hints = {{"L1", "Prev"}, {"R1", "Next"}, {"A", "Launch"}, {"Y", "Autolaunch"}};
            // while searching, clearing the search is more useful than starting a new one
            if (m.query.empty()) hints.push_back({"X", "Search"});
            else hints.push_back({"B", "Clear"});
            if (m.hasSettings) hints.push_back({"START", "Settings"});
        }

        // Button in the highlight colour, followed by what it does
        const int y = top + (kFooterH - TTF_FontHeight(smallFont)) / 2;
        int x = kScreenW - kMargin;
        for (auto it = hints.rbegin(); it != hints.rend(); ++it) {
            x -= textWidth(smallFont, it->second);
            drawText(renderer, smallFont, it->second, x, y, kGrey);
            int keyW = textWidth(smallFont, it->first);
            x -= 6 + keyW;
            drawText(renderer, smallFont, it->first, x, y, kYellow);
            x -= 16;
        }
    }

    void renderEmpty(const Model& m) {
        std::string s = m.query.empty() ? "Nothing here" : "No matches for \"" + m.query + "\"";
        int w = textWidth(uiFont, s);
        drawText(renderer, uiFont, s, std::max(kMargin, (kScreenW - w) / 2), kScreenH / 2 - 40, kGrey, kScreenW - 2 * kMargin);
        if (!m.query.empty()) {
            std::string hint = "L1/R1 to search other tabs";
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
            if (m.isAutoStart(entry)) pill("autolaunch", cell.x, cell.y, kYellow, kBlack);
            if (c.mixed) {
                int w = textWidth(smallFont, entry.tag) + 12;
                pill(entry.tag, cell.x + cell.w - w, cell.y + cell.h - TTF_FontHeight(smallFont) - 4, kBar, kGrey);
            }
        }

        const Entry* e = m.selected();
        if (!e) return;
        const int bottom = kScreenH - kFooterH;
        const int textW = kScreenW - 2 * kMargin;
        int descH = wrappedHeight(descFont, e->description, textW);
        int titleH = TTF_FontHeight(titleFont);
        int textTop = bottom - 8 - descH - titleH;
        gradient({0, textTop - 70, kScreenW, 70}, kClear);
        fill(kClear, {0, textTop, kScreenW, bottom - textTop});
        drawText(renderer, titleFont, e->name, kMargin, textTop, kWhite, textW);
        drawWrapped(descFont, e->description, kMargin, textTop + titleH, kGrey, textW);
    }

    void renderList(const Model& m) {
        const Category& c = m.cur();
        if (c.sel < c.scroll) c.scroll = c.sel;
        const int rows = listRows(m.showTabs), top = listTop(m.showTabs);
        if (c.sel >= c.scroll + rows) c.scroll = c.sel - rows + 1;

        const int fontH = TTF_FontHeight(descFont);
        for (int row = 0; row < rows && c.scroll + row < (int)c.visible.size(); ++row) {
            int k = c.scroll + row;
            const Entry& e = c.entries[c.visible[k]];
            SDL_Rect r{kMargin, top + row * kListRowH, kListWidth, kListRowH - 2};
            if (k == c.sel) {
                fill(kRowSel, r);
                fill(kYellow, {r.x, r.y, 4, r.h});
            }
            int maxW = r.w - 22;
            int tagX = r.x + r.w - 4;
            const int tagY = r.y + (r.h - TTF_FontHeight(smallFont) - 4) / 2;
            if (c.mixed) {
                int w = textWidth(smallFont, e.tag) + 12;
                tagX -= w;
                pill(e.tag, tagX, tagY, kTile, kGrey);
                maxW -= w + 8;
            }
            if (m.isAutoStart(e)) {
                int w = textWidth(smallFont, "auto") + 12;
                tagX -= w + 4;
                pill("auto", tagX, tagY, kYellow, kBlack);
                maxW -= w + 8;
            }
            drawText(renderer, descFont, e.name, r.x + 14, r.y + (r.h - fontH) / 2, k == c.sel ? kWhite : kGrey, maxW);
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
        y += drawWrapped(uiFont, e->name, kPreviewX, y, kWhite, kPreviewW) + 6;
        drawWrapped(smallFont, e->description, kPreviewX, y, kGrey, kPreviewW);

        std::string pos = std::to_string(c.sel + 1) + " / " + std::to_string(total);
        drawText(renderer, smallFont, pos, kScreenW - kMargin - textWidth(smallFont, pos),
                 kScreenH - kFooterH - TTF_FontHeight(smallFont) - 6, kGrey);
    }

    void renderOsd(const Osd& osd, int top) {
        const int w = 300, h = 64, pad = 14;
        SDL_Rect panel{(kScreenW - w) / 2, top + 12, w, h};
        fill({12, 12, 14, 235}, panel);
        frame(kTile, panel, 2);

        std::string label = osd.kind == "brightness" ? "Brightness" : (osd.kind == "volume" ? "Volume" : osd.kind);
        std::string value = osd.muted ? "Muted" : std::to_string(osd.percent) + "%";
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
        const int panelH = titleH + kPowerItemCount * rowH + 2 * pad;
        const int bodyY = bodyTop(m.showTabs);
        SDL_Rect panel{(kScreenW - panelW) / 2, bodyY + (kScreenH - kFooterH - bodyY - panelH) / 2, panelW, panelH};
        fill({0, 0, 0, 150}, {0, kHeaderH, kScreenW, kScreenH - kFooterH - kHeaderH});   // dim the tab behind
        fill(kBar, panel);
        frame(kTile, panel, 2);
        drawText(renderer, uiFont, "Power options", panel.x + pad + 4, panel.y + pad, kWhite);

        const int fontH = TTF_FontHeight(descFont);
        for (int i = 0; i < kPowerItemCount; ++i) {
            SDL_Rect r{panel.x + pad, panel.y + pad + titleH + i * rowH, panelW - 2 * pad, rowH - 4};
            bool sel = i == m.menuSel;
            if (sel) {
                fill(kRowSel, r);
                fill(kYellow, {r.x, r.y, 4, r.h});
            }
            drawText(renderer, descFont, kPowerItems[i].label, r.x + 16, r.y + (r.h - fontH) / 2,
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

        drawText(renderer, uiFont, "Search: " + m.query + "_", panel.x + pad, panel.y + pad, kWhite, panelW - 2 * pad);

        for (int r = 0; r < Keyboard::kRows; ++r) {
            const auto& keys = Keyboard::keys(r);
            for (int c = 0; c < (int)keys.size(); ++c) {
                const Keyboard::Key& key = keys[c];
                SDL_Rect k{panel.x + pad + (int)(key.x * unit), panel.y + pad + queryH + r * (keyH + gap),
                           (int)(key.w * unit) - gap, keyH};
                bool sel = r == kb.row && c == kb.col;
                fill(sel ? kYellow : kTile, k);
                std::string label = key.label;
                TTF_Font* f = label.size() > 1 ? smallFont : uiFont;
                if (label.size() == 1) label = upper(label);
                drawText(renderer, f, label, k.x + (k.w - textWidth(f, label)) / 2,
                         k.y + (k.h - TTF_FontHeight(f)) / 2, sel ? kBlack : kWhite);
            }
        }
    }
};

enum class Action { None, Up, Down, Left, Right, Launch, Back, ToggleAutoStart, Search, PrevTab, NextTab, Start, Power };

static bool isRepeatable(Action a) {
    return a == Action::Up || a == Action::Down || a == Action::Left || a == Action::Right;
}

// Keyboard bindings, mostly for running the launcher on a PC: F1/F2 = L1/R1, F4 = X, F5 = Start,
// F6 = POWER (the real power key arrives as SDLK_POWER).
static Action actionFromKey(SDL_Keycode k) {
    switch (k) {
        case SDLK_UP:        return Action::Up;
        case SDLK_DOWN:      return Action::Down;
        case SDLK_LEFT:      return Action::Left;
        case SDLK_RIGHT:     return Action::Right;
        case SDLK_RETURN:    return Action::Launch;
        case SDLK_ESCAPE:
        case SDLK_BACKSPACE: return Action::Back;
        case SDLK_SPACE:     return Action::ToggleAutoStart;
        case SDLK_F1:        return Action::PrevTab;
        case SDLK_F2:        return Action::NextTab;
        case SDLK_F4:        return Action::Search;
        case SDLK_F5:        return Action::Start;
        case SDLK_POWER:
        case SDLK_F6:        return Action::Power;
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
        case SDL_CONTROLLER_BUTTON_Y:             return Action::ToggleAutoStart;
        case SDL_CONTROLLER_BUTTON_START:         return Action::Start;
        case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:  return Action::PrevTab;
        case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: return Action::NextTab;
        default:                                  return Action::None;
    }
}

int main() {
    Model model;
    model.categories = loadCatalog();
    if (model.categories.empty()) {
        std::cerr << "No entries found in apps.puppy files!\n";
        return 1;
    }
    for (auto& c : model.categories)
        for (auto& e : c.entries) e.searchKey = lower(e.name);
    extractSystemMenu(model);
    addAllGamesTab(model);   // first tab, and the one shown at boot
    if (model.categories.empty()) {
        std::cerr << "No entries found in apps.puppy files!\n";
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
            const int n = kPowerItemCount;
            switch (a) {
                case Action::Up:     model.menuSel = (model.menuSel + n - 1) % n; break;
                case Action::Down:   model.menuSel = (model.menuSel + 1) % n;     break;
                case Action::Launch: {
                    const PowerItem& item = kPowerItems[model.menuSel];
                    model.menuOpen = false;
                    if (item.status) model.status = item.status;
                    sendPowerRequest(item.request);
                    break;
                }
                case Action::Back:
                case Action::Power:  model.menuOpen = false; break;
                default: break;
            }
            return;
        }
        if (a == Action::Power) {
            // with the screen off, toggle-screen.sh turns it back on; don't open a menu in the dark
            if (screenOn()) {
                kb.open = false;
                model.menuOpen = true;
                model.menuSel = 0;
            }
            return;
        }
        if (a == Action::Start && !kb.open && model.hasSettings) {
            launch(model, model.settings);
            running = false;
            return;
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

        SDL_Event ev;
        if (!SDL_WaitEventTimeout(&ev, timeout)) {
            now = SDL_GetTicks();
            if (held != Action::None && (Sint32)(now - nextRepeat) >= 0) {
                apply(held);
                nextRepeat = now + kRepeatRateMs;
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
                    action = actionFromButton(ev.cbutton.button);
                    break;
                case SDL_CONTROLLERBUTTONUP:
                    if (actionFromButton(ev.cbutton.button) == held) held = Action::None;
                    break;
            }

            if (action != Action::None) {
                apply(action);
                if (isRepeatable(action)) {
                    held = action;
                    nextRepeat = SDL_GetTicks() + kRepeatDelayMs;
                }
                dirty = true;
                lastActivity = SDL_GetTicks();
            }
        } while (running && SDL_PollEvent(&ev));
    }

    if (pad) SDL_GameControllerClose(pad);
    return 0;
}
