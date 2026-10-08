#include "library.h"

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <iterator>

#include "catalog.h"
#include "config.h"
#include "system/prefs.h"
#include "util.h"

static void writeAutoStart(const Entry& e) {
    std::ofstream out(cfg.autoStartFile);
    if (out) out << "# " << e.category << "\t" << e.id << "\n" << e.command << "\n";
}

static void clearAutoStart() {
    std::error_code ec;
    fs::remove(cfg.autoStartFile, ec);
}

bool readAutoStartId(std::string& category, std::string& name) {
    std::ifstream in(cfg.autoStartFile);
    std::string line;
    if (!in || !std::getline(in, line) || line.compare(0, 2, "# ") != 0) return false;
    size_t tab = line.find('\t', 2);
    if (tab == std::string::npos) return false;
    category = line.substr(2, tab - 2);
    name = line.substr(tab + 1);
    return true;
}

void toggleAutoStart(Model& m) {
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

// Returns whether Puppy keeps running: appd stops it itself once the app starts.
bool launch(const Model& m, const Entry& e) {
    {
        std::ofstream state(cfg.stateFile);
        if (state) state << m.cur().name << "\n" << e.category << "\n" << e.id << "\n";
    }
    if (cfg.launchCommand.empty()) {
        std::ofstream out(cfg.launchFile);
        if (out) out << e.command << "\n";
        return false;
    }
    std::string command = cfg.launchCommand + " " + shellQuote(e.command) + (e.terminal ? " 1" : "");
    if (std::system(command.c_str()) != 0) {}
    return true;
}

// The autolaunch entry, once per boot: its command is the file's second line.
bool runAutoStart() {
    std::error_code ec;
    if (cfg.launchCommand.empty() || fs::exists(cfg.autoStartMark, ec)) return false;
    { std::ofstream mark(cfg.autoStartMark); }
    std::ifstream in(cfg.autoStartFile);
    std::string header, command;
    if (!std::getline(in, header) || !std::getline(in, command) || command.empty()) return false;
    command = cfg.launchCommand + " " + shellQuote(command);
    return std::system(command.c_str()) == 0;
}

void restoreCursor(Model& m) {
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
void addAllGamesTab(Model& m) {
    Category all;
    all.name = "All Games";
    all.label = "All Games";
    all.isArchive = true;
    all.mixed = true;
    for (const auto& c : m.categories) {
        if (!c.isArchive || c.media) continue;
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

void loadFavorites(Model& m) {
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

// Adds an "External Card" tab with everything found on the TF-2 card (external-card.sh mounts it).
void addExternalTab(Model& m) {
    static const std::string kRoot = "/media/external/";
    Category ext;
    ext.name = "External Card";
    ext.label = "External Card";
    ext.isArchive = true;
    ext.mixed = true;
    for (const auto& c : m.categories) {
        if (c.mixed) continue;
        for (Entry e : c.entries) {
            if (e.file.compare(0, kRoot.size(), kRoot) != 0) continue;
            e.tag = c.label;
            ext.entries.push_back(std::move(e));
        }
    }
    if (ext.entries.empty()) return;
    std::stable_sort(ext.entries.begin(), ext.entries.end(), [](const Entry& l, const Entry& r) {
        return l.searchKey < r.searchKey;
    });
    int t = myListTab(m);
    m.categories.insert(m.categories.begin() + (t < 0 ? 0 : t + 1), std::move(ext));
}

// Adds the My List tab right after All Games (one R1 press from the boot tab).
void addMyListTab(Model& m) {
    Category list;
    list.name = kMyListName;
    list.label = kMyListName;
    list.isArchive = true;
    list.mixed = true;
    bool hasAll = !m.categories.empty() && m.categories[0].name == "All Games";
    m.categories.insert(m.categories.begin() + (hasAll ? 1 : 0), std::move(list));
    rebuildMyList(m);
}

void toggleFavorite(Model& m) {
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

// In dir's gamelists (gamelist.xml, gamelist.<language>.xml), the <game> whose <path> is oldFile gets
// newFile and the shown name newName. Backups are left alone.
static void renameInGamelists(const fs::path& dir, const std::string& oldFile, const std::string& newFile,
                              const std::string& newName) {
    std::error_code ec;
    for (fs::directory_iterator it(dir, ec), end; !ec && it != end; it.increment(ec)) {
        const std::string fn = it->path().filename().string();
        if (fn.compare(0, 8, "gamelist") != 0 || it->path().extension() != ".xml" ||
            fn.find("backup") != std::string::npos) continue;
        std::string xml;
        {
            std::ifstream in(it->path(), std::ios::binary);
            xml.assign((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
        }
        bool changed = false;
        for (size_t pos = 0; (pos = xml.find("<path>", pos)) != std::string::npos;) {
            const size_t a = pos + 6;
            size_t b = xml.find("</path>", a);
            if (b == std::string::npos) break;
            if (stripDotSlash(trim(xmlUnescape(xml.substr(a, b - a)))) != oldFile) { pos = b; continue; }
            const std::string newPath = "./" + xmlEscape(newFile);
            xml.replace(a, b - a, newPath);
            b = a + newPath.size();
            // the <name> of the same <game>
            const size_t gameStart = xml.rfind("<game", a), gameEnd = xml.find("</game>", b);
            size_t na = xml.find("<name>", gameStart);
            if (na != std::string::npos && na < gameEnd) {
                na += 6;
                const size_t nb = xml.find("</name>", na);
                if (nb != std::string::npos && nb < gameEnd) xml.replace(na, nb - na, xmlEscape(newName));
            }
            changed = true;
            pos = b;
        }
        if (!changed) continue;
        const std::string tmp = it->path().string() + ".tmp";
        { std::ofstream out(tmp, std::ios::binary); if (!out) continue; out << xml; }
        std::error_code ec2;
        fs::rename(tmp, it->path(), ec2);
    }
}

// RetroArch saves and states named after a game ("<name>.srm", "<name>.state1"...), in cfg.saveDirs
// and their per-core folders.
static void renameSaves(const std::string& oldStem, const std::string& newStem) {
    const std::string prefix = oldStem + ".";
    for (const auto& root : cfg.saveDirs) {
        std::error_code ec;
        std::vector<fs::path> dirs = {root};
        for (fs::directory_iterator it(root, ec), end; !ec && it != end; it.increment(ec))
            if (it->is_directory(ec)) dirs.push_back(it->path());
        for (const auto& d : dirs) {
            std::vector<fs::path> found;
            std::error_code ec2;
            for (fs::directory_iterator it(d, ec2), end; !ec2 && it != end; it.increment(ec2))
                if (it->path().filename().string().compare(0, prefix.size(), prefix) == 0) found.push_back(it->path());
            for (const auto& f : found) {
                const fs::path to = f.parent_path() / (newStem + f.filename().string().substr(oldStem.size()));
                std::error_code ec3;
                if (!fs::exists(to, ec3)) fs::rename(f, to, ec3);
            }
        }
    }
}

// A file name for a shown name: what FAT32 can't hold in a name goes (":" becomes " -", as in
// "Castlevania : Symphony" -> "Castlevania - Symphony"), with no doubled spaces or trailing dots.
static std::string fileSafeName(const std::string& name) {
    std::string out;
    for (char c : name) {
        switch (c) {
            case ':': out += " -"; break;
            case '/': case '\\': out += '-'; break;
            case '*': case '?': case '"': case '<': case '>': case '|': break;
            default: if ((unsigned char)c >= 0x20) out += c;
        }
    }
    std::string clean;
    for (char c : out) {
        if (c == ' ' && (clean.empty() || clean.back() == ' ')) continue;
        clean += c;
    }
    while (!clean.empty() && (clean.back() == ' ' || clean.back() == '.')) clean.pop_back();
    return clean;
}

static void renamePath(const fs::path& from, const fs::path& to, std::error_code& ec) {
    // FAT32 ignores case, so a change of case only goes through a temporary name
    if (lower(from.filename().string()) == lower(to.filename().string())) {
        const fs::path tmp = from.string() + ".renaming";
        fs::rename(from, tmp, ec);
        if (!ec) fs::rename(tmp, to, ec);
    } else {
        fs::rename(from, to, ec);
    }
}

// Renames a game: newName is shown in the launcher (its gamelist entries get it), and the file takes
// a file-safe version of it (same extension), along with what goes by the file's name: the cover in
// its icons folder, its RetroArch saves and states, and the launcher's favourites and autolaunch.
// Returns the message to show.
std::string renameEntry(Model& m, const Entry& e, const std::string& newName) {
    const std::string newStem = fileSafeName(newName);
    if (newStem.empty() || newStem == "." || newStem == "..") return tr("That name can't be used");
    const fs::path from(e.file);
    const std::string oldStem = from.stem().string();
    const bool moveFile = newStem != oldStem;
    const fs::path to = moveFile ? from.parent_path() / (newStem + from.extension().string()) : from;
    std::error_code ec;
    std::string icon = e.iconPath;
    if (moveFile) {
        if (lower(newStem) != lower(oldStem) && fs::exists(to, ec)) return tr("A file with that name already exists");
        renamePath(from, to, ec);
        if (ec) return tr("Couldn't rename the file");
        if (!icon.empty() && fs::path(icon).stem().string() == oldStem) {   // the icons folder's cover
            const fs::path iconTo = fs::path(icon).parent_path() / (newStem + fs::path(icon).extension().string());
            std::error_code ec2;
            renamePath(icon, iconTo, ec2);
            if (!ec2) icon = iconTo.string();
        }
        renameSaves(oldStem, newStem);
    }
    renameInGamelists(from.parent_path(), from.filename().string(), to.filename().string(), newName);

    const bool fav = m.favorites.erase(Model::favoriteKey(e)) > 0;
    const bool autostart = m.isAutoStart(e);
    const Entry* renamed = nullptr;
    for (auto& c : m.categories) {
        for (auto& x : c.entries) {
            if (x.category != e.category || x.id != e.id) continue;
            x.id = newStem;
            x.name = newName;
            x.file = to.string();
            x.iconPath = icon;
            if (moveFile) {
                replaceAll(x.command, shellQuote(from.string()), shellQuote(to.string()));
                replaceAll(x.command, from.string(), to.string());   // unquoted, e.g. %ROM_RAW%
            }
            x.searchKey = lower(newName == newStem ? newName : newName + " " + newStem);
            if (!renamed) renamed = &x;
        }
    }
    if (renamed && fav) { m.favorites.insert(Model::favoriteKey(*renamed)); saveFavorites(m); }
    if (renamed && autostart) { writeAutoStart(*renamed); m.autoName = renamed->id; }
    return tr("Renamed");
}

// Files a game is made of besides its own: the tracks of a .cue, the discs of a .m3u.
static std::vector<fs::path> companionFiles(const fs::path& file) {
    std::vector<fs::path> out;
    const std::string ext = lower(file.extension().string());
    if (ext != ".cue" && ext != ".m3u") return out;
    std::ifstream in(file);
    for (std::string line; std::getline(in, line);) {
        line = trim(line);
        std::string ref;
        if (ext == ".cue") {
            if (line.size() < 6 || upper(line.substr(0, 5)) != "FILE ") continue;
            size_t a = line.find('"'), b = line.rfind('"');
            if (a != std::string::npos && b > a) ref = line.substr(a + 1, b - a - 1);
            else ref = trim(line.substr(5, line.rfind(' ') - 5));
        } else {
            if (line.empty() || line[0] == '#') continue;
            ref = line;
        }
        std::error_code ec;
        const fs::path p = file.parent_path() / ref;
        if (fs::is_regular_file(p, ec)) out.push_back(p);
    }
    return out;
}

// Moves a file into the trash, under its system's folder name: <trash>/<system>/<sub folders>/<file>.
static bool moveToTrash(const fs::path& file, const fs::path& systemDir) {
    std::error_code ec;
    fs::path rel = file.lexically_relative(systemDir).parent_path();
    if (!rel.empty() && *rel.begin() == "..") rel.clear();
    const fs::path dir = fs::path(cfg.trashDir) / systemDir.filename() / rel;
    fs::create_directories(dir, ec);
    fs::path to = dir / file.filename();
    for (int i = 2; fs::exists(to, ec) && i < 100; ++i)
        to = dir / (file.stem().string() + " (" + std::to_string(i) + ")" + file.extension().string());
    fs::rename(file, to, ec);
    if (ec) {   // not the same filesystem: copy, then remove
        std::error_code ec2;
        fs::copy_file(file, to, ec2);
        if (ec2) return false;
        fs::remove(file, ec2);
    }
    return true;
}

// Moves a game (and its tracks or discs) to the trash and takes it out of every tab.
std::string deleteEntry(Model& m, const Entry& e) {
    const fs::path file(e.file);
    const fs::path systemDir = file.parent_path();
    std::vector<fs::path> parts = companionFiles(file);
    for (size_t i = 0; i < parts.size() && parts.size() < 64; ++i)      // a .m3u's discs can be .cue files
        for (const auto& p : companionFiles(parts[i])) parts.push_back(p);
    if (!moveToTrash(file, systemDir)) return tr("Couldn't move the game to the trash");
    for (const auto& p : parts) moveToTrash(p, systemDir);

    if (m.favorites.erase(Model::favoriteKey(e))) saveFavorites(m);
    if (m.isAutoStart(e)) {
        clearAutoStart();
        m.autoCategory.clear();
        m.autoName.clear();
    }
    const int oldSel = m.cur().sel;
    for (auto& c : m.categories) {
        c.entries.erase(std::remove_if(c.entries.begin(), c.entries.end(), [&](const Entry& x) {
            return x.category == e.category && x.id == e.id;
        }), c.entries.end());
        c.tagColumn = -1;
    }
    m.applyFilter();
    if (!m.cur().visible.empty()) m.cur().sel = std::min(oldSel, (int)m.cur().visible.size() - 1);
    return tr("Moved to the trash");
}

// Takes the System category out of the tabs: START runs its System Settings entry when Puppy's own
// isn't used, and restarting and shutting down are in the POWER menu.
void extractSystemMenu(Model& m) {
    auto sys = std::find_if(m.categories.begin(), m.categories.end(),
                            [](const Category& c) { return c.name == kMenuCategory; });
    if (sys == m.categories.end()) return;
    for (const Entry& e : sys->entries) {
        if (e.name == kSettingsName) { m.settings = e; m.hasSettings = true; }
    }
    m.categories.erase(sys);
}

// puppy.conf's settings_command replaces the System Settings entry.
void applySettingsCommand(Model& m) {
    if (cfg.settingsCommand.empty()) return;
    m.settings = Entry();
    m.settings.category = kMenuCategory;
    m.settings.name = m.settings.id = kSettingsName;
    m.settings.command = cfg.settingsCommand;
    m.hasSettings = true;
}

// The POWER menu. Each action, in order of preference: the puppy.conf command (run in the
// background), or the request for the power_fifo daemon; actions with neither are left out.
// Restarting and shutting down ask first.
std::vector<PowerItem> powerItems() {
    std::error_code ec;
    const bool fifo = fs::exists(cfg.powerFifo, ec);
    const PowerItem all[] = {
        {"Display off", "screen-off", nullptr, nullptr, &cfg.screenOffCommand},
        {"Restart", "reboot", "Restarting...", "Are you sure you want to reboot the device?", &cfg.restartCommand},
        {"Shut down", "poweroff", "Shutting down...", "Are you sure you want to power off the device?", &cfg.shutdownCommand},
        {"Quit Puppy", nullptr, nullptr, nullptr, nullptr, true},
    };
    std::vector<PowerItem> items;
    for (const PowerItem& item : all) {
        bool available = item.quit ? cfg.quit : !item.command->empty() || (item.request && fifo);
        if (available) items.push_back(item);
    }
    return items;
}

// The launcher options set in System Settings (see Prefs).
void loadSettings(Model& m) {
    const Prefs p = Prefs::load();
    m.view = p.listView ? View::List : View::Grid;
    m.showTabs = p.showTabs;
    for (const std::string& name : p.hiddenTabs)
        for (auto& c : m.categories)
            if (!c.mixed && c.name == name) c.hidden = true;
}

// The tabs System Settings offers to hide, as "name<TAB>label" lines (rewritten only when they change).
void writeTabsList(const Model& m) {
    std::string text;
    for (const auto& c : m.categories)
        if (!c.mixed) text += c.name + "\t" + c.label + "\n";
    {
        std::ifstream in(cfg.tabsFile(), std::ios::binary);
        const std::string old((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
        if (old == text) return;
    }
    std::error_code ec;
    fs::create_directories(cfg.configDir, ec);
    const std::string tmp = cfg.tabsFile() + ".tmp";
    { std::ofstream out(tmp, std::ios::binary); if (!out) return; out << text; }
    fs::rename(tmp, cfg.tabsFile(), ec);
}

// Everything the launcher shows: the catalog, the extra tabs, favourites, the options and the
// autolaunch entry. False when there is nothing to show.
bool loadModel(Model& m) {
    m.categories = loadCatalog();
    if (m.categories.empty()) {
        std::cerr << "Nothing to show: no entries in the apps files and no games in the es_systems.cfg systems\n";
        return false;
    }
    for (auto& c : m.categories)
        for (auto& e : c.entries) e.searchKey = lower(e.id == e.name ? e.name : e.name + " " + e.id);
    extractSystemMenu(m);
    applySettingsCommand(m);
    addAllGamesTab(m);   // first tab, and the one shown at boot
    loadFavorites(m);
    addMyListTab(m);
    addExternalTab(m);
    if (m.categories.empty()) {
        std::cerr << "Nothing to show\n";
        return false;
    }

    loadSettings(m);
    writeTabsList(m);
    m.applyFilter();
    std::string cat, name;
    if (readAutoStartId(cat, name)) {
        m.autoCategory = cat;
        m.autoName = name;
    }
    return true;
}
