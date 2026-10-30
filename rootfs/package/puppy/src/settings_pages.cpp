// The pages of System Settings, built from what SettingsScreen holds (see settings.h).
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <memory>

#include "accents.h"
#include "config.h"
#include "fonts.h"
#include "library.h"
#include "overlays.h"
#include "settings.h"
#include "styles.h"
#include "system/clock.h"
#include "system/device.h"
#include "system/network.h"
#include "system/scraper.h"
#include "system/retroarch.h"
#include "tester.h"
#include "util.h"

// tr() of a sentence with two "%s", filled in order
static std::string fill2(const char* english, const std::string& a, const std::string& b) {
    std::string text = tr(english);
    size_t pos = text.find("%s");
    if (pos != std::string::npos) {
        text.replace(pos, 2, a);
        pos = text.find("%s", pos + a.size());
        if (pos != std::string::npos) text.replace(pos, 2, b);
    }
    return text;
}

static std::string twoDigits(int v) {
    char s[8];
    snprintf(s, sizeof(s), "%02d", v);
    return s;
}

// How far a scraper run is through the games of all its systems, e.g. 10%
static std::string scrapedShare(const ScraperRun& run) {
    return run.games ? std::to_string(run.done * 100 / run.games) + "%" : "";
}

// From /etc/triggerhappy/triggers.d, the launcher, the RetroArch config (hotkey = FN) and /etc/mpv/input.conf
static const char* const kShortcuts[][2] = {
    {"Any app", nullptr},
    {"VOL+ / VOL-", "Volume"},
    {"FN + VOL+ / VOL-", "Brightness"},
    {"POWER", "Screen off / on"},
    {"SELECT + START", "Close the app"},
    {"FN + SELECT + START", "Force close the app"},
    {"FN + UP", "FPS / CPU overlay"},
    {"FN + DOWN", "Speaker / headphones"},
    {"Launcher", nullptr},
    {"L1 / R1", "Previous / next tab"},
    {"D-pad / left stick", "Move"},
    {"LEFT / RIGHT (list)", "Previous / next page"},
    {"Right stick up/down", "Scroll the description"},
    {"A", "Launch"},
    {"Y", "Add to / remove from My List"},
    {"L2 + R2", "Game options: rename, move to trash"},
    {"X", "Search by name"},
    {"B", "Clear the search"},
    {"SELECT", "Autolaunch on boot"},
    {"START", "System Settings"},
    {"POWER", "Display off / restart / shut down"},
    {"RetroArch", nullptr},
    {"FN + X", "Menu"},
    {"FN + R1 / L1", "Save / load state"},
    {"FN + LEFT / RIGHT", "State slot"},
    {"FN + Y", "Pause"},
    {"FN + R2", "Fast forward"},
    {"FN + L2", "Screenshot"},
    {"FN + START", "Quit the game"},
    {"Videos", nullptr},
    {"A / START", "Pause"},
    {"B", "Close the video"},
    {"LEFT / RIGHT", "Back / forward 10 s"},
    {"DOWN / UP", "Back / forward 1 min"},
    {"L1 / R1", "Previous / next video"},
    {"X", "Playlist"},
    {"Y", "Repeat on / off"},
    {"L2 / R2", "Audio / subtitle track"},
    {"Left stick up/down", "Faster / slower"},
    {"R3 / L3", "Zoom in / out"},
    {"Right stick", "Move the zoomed picture"},
    {"SELECT", "Normal speed and zoom"},
};

const std::vector<std::pair<SettingsScreen::Page, const char*>>& SettingsScreen::sections() const {
    static const std::vector<std::pair<Page, const char*>> list = {
        {Page::Display, "Display & Audio"}, {Page::Interface, "Interface"},
        {Page::Overlay, "Overlay"}, {Page::DateTime, "Date & Time"}, {Page::Storage, "Storage"},
        {Page::System, "System"}, {Page::Input, "Input Settings"}, {Page::Credits, "Credits"},
    };
    static const std::vector<std::pair<Page, const char*>> noCredits(list.begin(), list.end() - 1);
    return credits.empty() ? noCredits : list;
}

std::string SettingsScreen::title(Page p) const {
    switch (p) {
        case Page::Tabs:      return tr("Launcher tabs");
        case Page::Shortcuts: return tr("Shortcuts");
        case Page::Info:      return tr("System Info");
        case Page::Network:  return tr("Network");
        case Page::Scraper:   return tr("Scraper");
        case Page::ScraperSystems: return tr("Systems to scrape");
        case Page::ScraperRun: return tr("Scraping");
        case Page::Resize:    return tr("Resize Home");
        default:
            for (const auto& s : sections())
                if (s.first == p) return tr(s.second);
            return "";
    }
}

// Under the page, when the selected row has no hint of its own
std::string SettingsScreen::pageHint(Page p) const {
    switch (p) {
        case Page::Tabs: return tr("Tabs switched off are hidden; their games still show in All Games.");
        case Page::System: return tr(powerProfiles()[profile].hint);
        case Page::Network:
            return net.networkMode ? "" : tr("Set the USB cable to Network, on the System page, to use it.");
        case Page::ScraperRun: return tr("Starting a game pauses the scraper. Start goes on from where it stopped.");
        case Page::Resize:
            if (resize.pending)
                return tr("A resize is already scheduled for the next boot.") + std::string(" ") +
                       tr("Reboot the device to apply it, or cancel the request.");
            if (!resize.valid) return tr("Could not read partition table information from sysfs.");
            return tr("This utility resizes your HOME partition to fill the remaining space on your microSD card.");
        default: return "";
    }
}

std::vector<Row> SettingsScreen::rows(Page p) {
    switch (p) {
        case Page::Display:   return displayPage();
        case Page::Interface: return interfacePage();
        case Page::Overlay:   return overlayPage();
        case Page::DateTime:  return dateTimePage();
        case Page::Storage:   return storagePage();
        case Page::System:    return systemPage();
        case Page::Input:     return inputPage();
        case Page::Tabs:      return tabsPage();
        case Page::Shortcuts: return shortcutsPage();
        case Page::Info:      return infoPage();
        case Page::Network:  return networkPage();
        case Page::Scraper:   return scraperPage();
        case Page::ScraperSystems: return scraperSystemsPage();
        case Page::ScraperRun: return scraperRunPage();
        case Page::Resize:    return resizePage();
        case Page::Credits:   return creditsPage();
    }
    return {};
}

std::vector<Row> SettingsScreen::displayPage() {
    std::vector<Row> rows;
    rows.push_back(Row::level("Brightness", brightnessLevel, 1, 10, 1, [this](int v) {
        setBrightness(v);
        brightnessLevel = v;
        levelChanged();
    }));
    rows.push_back(Row::level("Master Volume", std::max(0, audio.volume), 0, 100, 10, [this](int v) {
        setVolume(v);
        if (audio.switchedOff && v > 0) setMuted(false);
        audio.read();
        app.audioChanged();
        levelChanged();
    }));
    rows.push_back(Row::toggle("Global Mute", audio.switchedOff, [this](int on) {
        setMuted(on);
        audio.read();
        app.audioChanged();
        levelChanged();
    }));
    rows.push_back(Row::choice("Audio output", {"Speaker", "Headphones"}, audio.headphones ? 1 : 0, [this](int i) {
        setOutput(i == 0);
        audio.read();
        app.audioChanged();
        levelChanged();
    }));
    return rows;
}

std::vector<Row> SettingsScreen::tabsPage() {
    std::vector<Row> rows;
    for (const Category& c : launcher.categories) {
        if (!hideable(c)) continue;
        std::string label = tr(c.label);
        if (c.label != c.name) label += "  (" + tr(c.name) + ")";
        Row r = Row::toggle(label, !c.hidden, [this, name = c.name](int on) {
            for (auto& cat : launcher.categories)
                if (hideable(cat) && cat.name == name) cat.hidden = !on;
            std::vector<std::string>& hidden = prefs.hiddenTabs;
            hidden.erase(std::remove(hidden.begin(), hidden.end(), name), hidden.end());
            if (!on) hidden.push_back(name);
            prefs.save();
        });
        r.rawLabel = true;
        rows.push_back(r);
    }
    return rows;
}

std::vector<Row> SettingsScreen::interfacePage() {
    std::vector<Row> rows;
    // Languages come from the files in /usr/share/goodluck/lang (see i18n.h)
    const std::vector<i18n::Language> languages = i18n::available();
    std::vector<std::string> names;
    int current = 0;
    for (size_t i = 0; i < languages.size(); ++i) {
        names.push_back(languages[i].display());
        if (languages[i].code == i18n::current()) current = (int)i;
    }
    Row language = Row::choice("Language", names, current, [this, languages](int i) {
        prefs.language = languages[i].code;
        prefs.save();
        i18n::load(prefs.language);
    });
    language.rawChoices = true;
    rows.push_back(language);

    // The launcher's look: the style and the view first, as they change the most
    rows.push_back(Row::section("Look"));
    std::vector<std::string> styleNames;
    for (const styles::Style& s : styles::all()) styleNames.push_back(s.name);
    rows.push_back(Row::choice("Style", styleNames, styles::find(prefs.style), [this](int i) {
        prefs.style = styles::all()[i].key;
        prefs.save();
        styles::choose(prefs.style);
        applyFont();    // the Showcase style has its own default font
    }));
    rows.push_back(Row::choice("View", {"Grid", "List"}, launcher.view == View::List ? 1 : 0, [this](int i) {
        launcher.view = i ? View::List : View::Grid;
        prefs.listView = i;
        prefs.save();
    }));

    std::vector<std::string> fontNames, keys;
    int currentFont = 0;
    const int chosen = fonts::find(prefs.font);
    for (size_t i = 0; i < fonts::all().size(); ++i) {
        const fonts::Font& f = fonts::all()[i];
        if (!fonts::available(f)) continue;
        if ((int)i == chosen) currentFont = (int)keys.size();
        keys.push_back(f.key);
        fontNames.push_back(f.name);
    }
    if (fontNames.size() > 1) {
        rows.push_back(Row::choice("Font", fontNames, currentFont, [this, keys](int i) {
            prefs.font = keys[i];
            prefs.save();
            applyFont();
        }));
    }

    std::vector<std::string> accentNames;
    std::vector<SDL_Color> accentColors;
    for (const accents::Accent& a : accents::all()) {
        accentNames.push_back(a.name);
        accentColors.push_back(a.color);
    }
    Row accentRow = Row::choice("Accent color", accentNames, accents::find(prefs.accent), [this](int i) {
        prefs.accent = accents::all()[i].key;
        prefs.save();
        accents::choose(prefs.accent);
        hud.accent = accents::hex(accents::all()[i].color);    // the in-game feedback follows
        hud.save();
    });
    accentRow.swatches = accentColors;
    rows.push_back(accentRow);

    rows.push_back(Row::toggle("Show Puppy on loading screens", !prefs.loadingText, [this](int on) {
        prefs.loadingText = !on;
        prefs.save();
    }));
    Row sound = Row::toggle("Trailer sound", prefs.trailerSound, [this](int on) {
        launcher.trailerSound = on;
        prefs.trailerSound = on;
        prefs.save();
    });
    sound.hint = "In the Showcase style, a game's trailer plays with its sound, at the system volume.";
    rows.push_back(sound);

    rows.push_back(Row::section("Tabs"));
    rows.push_back(Row::toggle("Show tabs", launcher.showTabs, [this](int on) {
        launcher.showTabs = on;
        prefs.showTabs = on;
        prefs.save();
    }));
    if (std::any_of(launcher.categories.begin(), launcher.categories.end(), [](const Category& c) { return !c.mixed; }))
        rows.push_back(Row::link("Launcher tabs", [this] { open(Page::Tabs); }));
    return rows;
}

std::vector<Row> SettingsScreen::overlayPage() {
    std::vector<Row> rows;
    auto flag = [this](const char* label, bool HudSettings::*field) {
        return Row::toggle(label, hud.*field, [this, field](int on) {
            hud.*field = on;
            hud.save();
            app.topBarChanged();
        });
    };
    // The same items in games and in the launcher's top bar. The clock's format and 12/24 hours come
    // from Date & Time
    rows.push_back(Row::section("Status bar"));
    rows.push_back(flag("In game", &HudSettings::statusGame));
    rows.push_back(flag("In the launcher", &HudSettings::statusLauncher));
    rows.push_back(flag("Show date", &HudSettings::statusDate));
    rows.push_back(flag("Show time", &HudSettings::statusTime));
    rows.push_back(flag("Show battery", &HudSettings::statusBattery));
    rows.push_back(flag("Show audio", &HudSettings::statusAudio));
    rows.push_back(flag("Show CPU temperature", &HudSettings::statusCpuTemp));
    rows.push_back(flag("Show power chip temperature", &HudSettings::statusPmicTemp));
    rows.push_back(Row::level("Opacity in game", hud.statusOpacity, 0, 100, 10, [this](int v) {
        hud.statusOpacity = v;
        hud.save();
    }));

    rows.push_back(Row::section("Performance (FN + UP)"));
    rows.push_back(flag("Show on game start", &HudSettings::visible));
    rows.push_back(Row::choice("Content", {"FPS", "FPS + CPU"}, hud.cpu ? 1 : 0, [this](int i) {
        hud.cpu = i == 1;
        hud.save();
    }));
    rows.push_back(Row::choice("Style", {"Graph", "Text"}, hud.text ? 1 : 0, [this](int i) {
        hud.text = i == 1;
        // Mesa ignores the y offset in text mode, so it only goes at the top
        if (hud.text && hud.position == "bottom-left") hud.position = "top-left";
        if (hud.text && hud.position == "bottom-right") hud.position = "top-right";
        hud.save();
    }));
    std::vector<std::string> positions;
    int position = 0;
    for (size_t i = 0; i < (hud.text ? 2 : hudPositions().size()); ++i) {
        positions.push_back(hudPositions()[i].name);
        if (hud.position == hudPositions()[i].value) position = (int)i;
    }
    rows.push_back(Row::choice("Position", positions, position, [this](int i) {
        hud.position = hudPositions()[i].value;
        hud.save();
    }));
    return rows;
}

std::vector<Row> SettingsScreen::dateTimePage() {
    std::vector<Row> rows;
    const time_t now = time(nullptr);
    struct tm tm;
    localtime_r(&now, &tm);
    char nowText[48];
    const std::string fmt = hud.dateFormat + (hud.h24 ? " %H:%M:%S" : " %I:%M:%S %p");
    if (!strftime(nowText, sizeof(nowText), fmt.c_str(), &tm)) nowText[0] = '\0';
    rows.push_back(Row::info("Now", nowText));
    rows.push_back(Row::toggle("24-hour clock", hud.h24, [this](int on) {
        hud.h24 = on;
        hud.save();
        app.topBarChanged();
    }));
    std::vector<std::string> formats;
    int format = 0;
    for (size_t i = 0; i < dateFormats().size(); ++i) {
        formats.push_back(dateFormats()[i].name);
        if (hud.dateFormat == dateFormats()[i].value) format = (int)i;
    }
    Row dateFormat = Row::choice("Date format", formats, format, [this](int i) {
        hud.dateFormat = dateFormats()[i].value;
        hud.save();
        app.topBarChanged();
    });
    dateFormat.rawChoices = true;
    rows.push_back(dateFormat);

    // The date and time to set, from the clock when the page opens
    if (clockEdit.tm_year == 0) {
        localtime_r(&now, &clockEdit);
        clockEdit.tm_sec = 0;
        clockSet = false;
    }
    const int year = clockEdit.tm_year + 1900, month = clockEdit.tm_mon + 1;
    static const int kDays[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    const bool leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    const int days = kDays[month - 1] + (month == 2 && leap ? 1 : 0);
    clockEdit.tm_mday = std::min(clockEdit.tm_mday, days);
    rows.push_back(Row::number("Year", std::to_string(year), year, 2024, 2099, [this](int v) {
        clockEdit.tm_year = v - 1900;
        clockSet = false;
    }));
    rows.push_back(Row::number("Month", twoDigits(month), month, 1, 12, [this](int v) {
        clockEdit.tm_mon = v - 1;
        clockSet = false;
    }));
    rows.push_back(Row::number("Day", twoDigits(clockEdit.tm_mday), clockEdit.tm_mday, 1, days, [this](int v) {
        clockEdit.tm_mday = v;
        clockSet = false;
    }));
    const int hour = clockEdit.tm_hour;
    const std::string hourText = hud.h24 ? twoDigits(hour) : twoDigits(hour % 12 ? hour % 12 : 12) + (hour < 12 ? " AM" : " PM");
    rows.push_back(Row::number("Hour", hourText, hour, 0, 23, [this](int v) {
        clockEdit.tm_hour = v;
        clockSet = false;
    }));
    rows.push_back(Row::number("Minute", twoDigits(clockEdit.tm_min), clockEdit.tm_min, 0, 59, [this](int v) {
        clockEdit.tm_min = v;
        clockSet = false;
    }));
    rows.push_back(Row::action("Set date and time", [this] {
        struct tm t = clockEdit;
        t.tm_isdst = -1;
        const time_t when = mktime(&t);
        if (when > 0) {
            setClock(when);
            clockSet = true;
        }
    }, clockSet ? tr("Done") : ""));

    std::vector<std::string> zones;
    for (int minutes : timezones()) zones.push_back(timezoneLabel(minutes));
    Row timeZone = Row::choice("Time zone", zones, zone, [this](int i) {
        zone = i;
        setTimezone(i);
        clockEdit.tm_year = 0;      // shows the clock in the new zone
        app.topBarChanged();
    });
    timeZone.rawChoices = true;
    rows.push_back(timeZone);
    return rows;
}

std::vector<Row> SettingsScreen::storagePage() {
    std::vector<Row> rows;
    rows.push_back(Row::info("HOME", fill2("%s used of %s", humanSize(home.usedKb), humanSize(home.totalKb))));
    // Always offered here; the page shows the details and asks before doing anything
    Row grow = Row::link("Resize Home", [this] {
        resize = Resize::read();
        open(Page::Resize);
    });
    grow.enabled = !(resize.canGrow() && !resize.fits());
    if (!grow.enabled) grow.hint = "Too much data in HOME to resize. Resize right after flashing, before copying games.";
    rows.push_back(grow);

    // The card in the TF-2 slot (external-card.sh): found at boot, or here with Detect
    rows.push_back(Row::info("Second card", card.mounted ? fill2("%s used of %s", humanSize(card.usedKb), humanSize(card.totalKb))
                                                         : tr("none")));
    rows.push_back(Row::action(card.mounted ? "Eject card" : "Detect card", [this] {
        const bool mounted = card.mounted;
        if (mounted) ejectCard();
        else detectCard();
        watchUntil = SDL_GetTicks() + (mounted ? 6000 : 10000);
        nextWatch = SDL_GetTicks() + 500;
    }));

    // Games moved to the trash in the launcher, deleted for good only from here
    if (trash.files > 0) {
        char label[160];
        snprintf(label, sizeof(label), tr("Empty trash (%llu files, %s)"), trash.files, humanSize(trash.bytes / 1024).c_str());
        Row empty = Row::action(label, [this] {
            Dialog d;
            d.title = "Empty trash";
            d.message = "Delete the games in the trash for good?";
            d.choices = {"Cancel", "Empty"};
            app.push(std::make_unique<DialogScreen>(app, d, [this](int choice) {
                if (choice != 1) return;
                emptyTrash();
                trash = trashStats();
                home = homeUsage();
                resize = Resize::read();
            }));
        });
        empty.rawLabel = true;
        rows.push_back(empty);
    }
    return rows;
}

std::vector<Row> SettingsScreen::systemPage() {
    std::vector<Row> rows;
    std::vector<std::string> modes;
    for (const PowerProfile& p : powerProfiles()) modes.push_back(p.name);
    rows.push_back(Row::choice("Power mode", modes, profile, [this](int i) {
        profile = i;
        setPowerProfile(i);
    }));
    Row mode = Row::choice("USB cable", {"Files (MTP)", "Network"}, net.networkMode ? 1 : 0, [this](int i) {
        setUsbMode(i == 1);
        net = NetworkStatus::read();
        netRead = SDL_GetTicks();
    });
    mode.hint = "Network: the PC or phone on the cable shares its connection with the console (Internet Sharing on a Mac, "
                "the adapter's Sharing tab on Windows, Ethernet tethering on a phone). Files: HOME shows up on it as a drive. "
                "Not both at once.";
    rows.push_back(mode);
    rows.push_back(Row::link("System Info", [this] {
        info = SystemInfo::read();
        home = homeUsage();
        resize = Resize::read();
        open(Page::Info);
    }));
    rows.push_back(Row::link("Network", [this] {
        net = NetworkStatus::read();
        netRead = SDL_GetTicks();
        open(Page::Network);
    }, net.address));
    rows.push_back(Row::link("Scraper", [this] {
        net = NetworkStatus::read();
        scraper = ScraperSettings::load();
        scrapeFolders = scraperFolders();
        open(Page::Scraper);
    }, run.running() ? scrapedShare(run) : ""));
    // Overlay, Date & Time, the launcher's view, tabs, font and accent, and the power mode; the language,
    // the confirm button, the time zone and the clock stay
    rows.push_back(Row::action("Restore default settings", [this] {
        Dialog d;
        d.title = "Restore default settings";
        d.message = "Restore the Overlay, Date & Time, launcher and power mode settings? The language, the confirm button and the time zone stay.";
        d.choices = {"Cancel", "Restore"};
        app.push(std::make_unique<DialogScreen>(app, d, [this](int choice) {
            if (choice == 1) restoreDefaults();
        }));
    }, defaultsRestored ? tr("Done") : ""));
    return rows;
}

void SettingsScreen::restoreDefaults() {
    HudSettings::restoreDefaults();
    hud = HudSettings::load();
    Prefs fresh;
    fresh.language = prefs.language;
    fresh.confirmBottom = prefs.confirmBottom;
    prefs = fresh;
    prefs.save();
    accents::choose(prefs.accent);
    styles::choose(prefs.style);
    launcher.view = View::Grid;
    launcher.showTabs = true;
    launcher.trailerSound = false;
    for (Category& c : launcher.categories) c.hidden = false;
    applyFont();
    profile = defaultPowerProfile();
    runScript("power-profile.sh default", false);
    app.topBarChanged();
    defaultsRestored = true;
}

std::vector<Row> SettingsScreen::infoPage() {
    std::vector<Row> rows;
    char value[160];
    rows.push_back(Row::info("Device", info.model.empty() ? tr("unknown") : info.model));
    rows.push_back(Row::info("System", info.os));
    rows.push_back(Row::info("Kernel", "Linux " + info.kernel));
    if (info.cpuMhz > 0) {
        if (info.tempC > -1000) snprintf(value, sizeof(value), "%d / %d MHz, %d C", info.cpuMhz, info.cpuMaxMhz, info.tempC);
        else snprintf(value, sizeof(value), "%d / %d MHz", info.cpuMhz, info.cpuMaxMhz);
        rows.push_back(Row::info("CPU", value));
    }
    if (info.memTotalKb > 0)
        rows.push_back(Row::info("Memory", fill2("%s free of %s", humanSize(info.memAvailKb), humanSize(info.memTotalKb))));
    if (info.battery >= 0) {
        snprintf(value, sizeof(value), "%d%% (%s)", info.battery, tr(info.batteryStatus.c_str()));
        rows.push_back(Row::info("Battery", value));
    }
    rows.push_back(Row::info("Storage", fill2("%s used of %s", humanSize(home.usedKb), humanSize(home.totalKb))));
    if (resize.canGrow()) rows.push_back(Row::info("Unused", trf("%s on the card (see Resize Home)", humanSize(resize.unusedKb))));
    return rows;
}

// The USB cable as a network (System > USB cable): the PC or phone on it shares its internet with the console
std::vector<Row> SettingsScreen::networkPage() {
    std::vector<Row> rows;
    const char* status = "Off (the cable is for files)";
    if (net.networkMode) {
        if (!net.hostUp) status = "No PC or phone on the cable";
        else if (net.address.empty()) status = "Connected, waiting for an address";
        else status = "Connected";
    }
    rows.push_back(Row::info("Status", tr(status)));
    if (net.networkMode) {
        rows.push_back(Row::info("Address", net.address.empty() ? "-" : net.address));
        rows.push_back(Row::info("Gateway", net.gateway.empty() ? "-" : net.gateway));
        rows.push_back(Row::info("DNS", net.dns.empty() ? "-" : net.dns));
        const char* check = net.check == "ok" ? "OK" : net.check == "fail" ? "no answer"
                          : net.check == "checking" ? "checking..." : "not checked";
        rows.push_back(Row::info("Internet", tr(check)));
        Row test = Row::action("Check the internet", [this] {
            checkInternet();
            net.check = "checking";
        });
        test.enabled = !net.address.empty();
        test.hint = "Fetches a page over HTTPS through the cable.";
        rows.push_back(test);
        Row ask = Row::action("Ask for an address", [this] { askForAddress(); });
        ask.enabled = net.hostUp;
        ask.hint = "Asks the PC or phone for an address now, instead of within a minute.";
        rows.push_back(ask);
    }
    return rows;
}

// ScreenScraper's media types and regions as gl-scrape takes them, with their names here
static const std::pair<const char*, const char*> kPictures[] = {
    {"mixrbv2", "Mix"}, {"box-2D", "Box"}, {"box-3D", "3D box"}, {"ss", "Screenshot"},
    {"sstitle", "Title screen"}, {"wheel", "Logo"}, {"none", "None"}};
static const std::pair<const char*, const char*> kRegions[] = {
    {"auto", "Auto"}, {"br", "Brazil"}, {"us", "USA"}, {"eu", "Europe"}, {"jp", "Japan"}, {"wor", "World"}};

template <size_t N> static int keyIndex(const std::pair<const char*, const char*> (&list)[N], const std::string& key) {
    for (size_t i = 0; i < N; ++i)
        if (key == list[i].first) return (int)i;
    return 0;
}

template <size_t N> static std::vector<std::string> names(const std::pair<const char*, const char*> (&list)[N]) {
    std::vector<std::string> out;
    for (const auto& item : list) out.push_back(item.second);
    return out;
}

// Names, descriptions, pictures and videos of the games from ScreenScraper (gl-scrape, system/scraper.h)
std::vector<Row> SettingsScreen::scraperPage() {
    std::vector<Row> rows;
    const bool busy = run.running() || (watchRun && run.state.empty());
    const bool account = !scraper.user.empty() && !scraper.password.empty();
    const char* needs = net.address.empty() ? "Needs the internet: see System -> Network."
                      : !account ? "Type your ScreenScraper account first: it's free at screenscraper.fr."
                      : "";

    rows.push_back(Row::section("ScreenScraper account"));
    Row user = Row::link("User", [this] {
        type("User:", scraper.user, [this](const std::string& v) {
            scraper.user = v;
            scraper.save();
            check = {};
        });
    }, scraper.user.empty() ? tr("not set") : scraper.user);
    user.hint = "Free at screenscraper.fr. Without one, ScreenScraper often turns the scraper away.";
    rows.push_back(user);
    rows.push_back(Row::link("Password", [this] {
        type("Password:", scraper.password, [this](const std::string& v) {
            scraper.password = v;
            scraper.save();
            check = {};
        });
    }, scraper.password.empty() ? tr("not set") : std::string(std::min<size_t>(scraper.password.size(), 12), '*')));
    std::string checked;
    if (watchCheck) checked = tr("checking...");
    else if (check.state == "done") checked = trf("OK, %s requests today", check.requests);
    else if (!check.state.empty()) checked = tr(check.message);
    Row test = Row::action("Check the account", [this] {
        checkScraperAccount();
        check = {};
        watchCheck = true;
        watchSince = runRead = SDL_GetTicks();
    }, checked);
    test.enabled = account && !net.address.empty() && !watchCheck;
    test.hint = *needs ? needs : "Logs in and shows how many of today's requests are used.";
    rows.push_back(test);

    rows.push_back(Row::section("What to get"));
    Row games = Row::choice("Games", {"Missing only", "All"}, scraper.all ? 1 : 0, [this](int i) {
        scraper.all = i == 1;
        scraper.save();
    });
    games.hint = "Missing only fills in what the games lack; All replaces it. Answers already received are kept, "
                 "so asking again costs no requests.";
    rows.push_back(games);
    Row picture = Row::choice("Picture", names(kPictures), keyIndex(kPictures, scraper.image), [this](int i) {
        scraper.image = kPictures[i].first;
        scraper.save();
    });
    picture.hint = "Mix puts the screenshot, the box and the logo in one picture.";
    rows.push_back(picture);
    Row video = Row::toggle("Videos", scraper.video, [this](int on) {
        scraper.video = on;
        scraper.save();
    });
    video.hint = "Short gameplay clips, a few MB each.";
    rows.push_back(video);
    Row region = Row::choice("Region", names(kRegions), keyIndex(kRegions, scraper.region), [this](int i) {
        scraper.region = kRegions[i].first;
        scraper.save();
    });
    region.hint = "Whose names, covers and dates come first. Auto follows the file name, e.g. (USA).";
    rows.push_back(region);
    int chosen = 0;
    for (const ScraperFolder& f : scrapeFolders)
        chosen += std::find(scraper.skip.begin(), scraper.skip.end(), f.folder) == scraper.skip.end();
    rows.push_back(Row::link("Systems", [this] { open(Page::ScraperSystems); },
                             fill2("%s of %s", std::to_string(chosen), std::to_string(scrapeFolders.size()))));

    rows.push_back(Row::section("Scrape"));
    if (busy) {
        Row going = Row::link("Scraping", [this] { open(Page::ScraperRun); }, scrapedShare(run));
        going.hint = "Starting a game pauses the scraper. Start goes on from where it stopped.";
        rows.push_back(going);
        return rows;
    }
    const std::string last = run.state == "done" ? tr("Done") : run.state == "stopped" ? tr("Stopped")
                           : run.state == "error" ? tr("Error") : "";
    Row go = Row::action("Start", [this] { startScraping(); }, last);
    go.enabled = account && !net.address.empty() && chosen > 0;
    go.hint = *needs ? needs : "Starting a game pauses the scraper. Start goes on from where it stopped.";
    rows.push_back(go);
    if (!run.state.empty()) rows.push_back(Row::link("Last run", [this] { open(Page::ScraperRun); }));
    return rows;
}

void SettingsScreen::startScraping() {
    startScraper();
    run = {};
    watchRun = true;
    watchSince = runRead = SDL_GetTicks();
    if (page() != Page::ScraperRun) open(Page::ScraperRun);
}

// A run under way, or the last one: Stop first, its progress under it
std::vector<Row> SettingsScreen::scraperRunPage() {
    std::vector<Row> rows;
    const bool busy = run.running() || (watchRun && run.state.empty());
    if (busy) {
        rows.push_back(Row::action("Stop", [this] { stopScraper(run); }));
    } else {
        Row again = Row::action("Start", [this] { startScraping(); });
        again.enabled = !scraper.user.empty() && !scraper.password.empty() && !net.address.empty();
        rows.push_back(again);
    }
    if (run.state.empty()) {
        rows.push_back(Row::info("Status", tr("Starting...")));
        return rows;
    }
    const std::string state = run.state == "done" ? tr("Done") : run.state == "stopped" ? tr("Stopped")
                            : run.state == "error" ? tr(run.message)
                            : run.steps > 1 ? run.system + " (" + fill2("%s of %s", std::to_string(run.step), std::to_string(run.steps)) + ")"
                            : run.system;
    rows.push_back(Row::info("Status", state));
    if (run.games > 0) {
        Row all = Row::info("Total", fill2("%s of %s", std::to_string(run.done), std::to_string(run.games)) + " (" +
                                         scrapedShare(run) + ")");
        all.current = run.done;
        all.max = run.games;
        rows.push_back(all);
    }
    if (busy && run.total > 0) {
        rows.push_back(Row::info("Game", fill2("%s of %s", std::to_string(run.index), std::to_string(run.total))));
        Row now = Row::info(run.game, "");
        now.rawLabel = true;
        rows.push_back(now);
    }
    rows.push_back(Row::info("Scraped", std::to_string(run.found)));
    if (run.notFound) rows.push_back(Row::info("Not found", std::to_string(run.notFound)));
    if (run.failed) rows.push_back(Row::info("Failed", std::to_string(run.failed)));
    if (run.skipped) rows.push_back(Row::info("Already complete", std::to_string(run.skipped)));
    if (!run.requests.empty()) rows.push_back(Row::info("Requests today", run.requests));
    if (!run.detail.empty() && run.state == "error") rows.push_back(Row::info("ScreenScraper", run.detail));
    return rows;
}

// The systems with games, each one on or off
std::vector<Row> SettingsScreen::scraperSystemsPage() {
    std::vector<Row> rows;
    if (scrapeFolders.empty()) rows.push_back(Row::info("No games in the ROM folders", ""));
    for (const ScraperFolder& f : scrapeFolders) {
        const bool on = std::find(scraper.skip.begin(), scraper.skip.end(), f.folder) == scraper.skip.end();
        Row t = Row::toggle(f.name + "  (" + f.folder + ")", on, [this, folder = f.folder](int v) {
            auto& skip = scraper.skip;
            skip.erase(std::remove(skip.begin(), skip.end(), folder), skip.end());
            if (!v) skip.push_back(folder);
            scraper.save();
        });
        t.rawLabel = true;
        t.hint = fill2("%s of %s games have all that's chosen.", std::to_string(f.complete), std::to_string(f.games));
        rows.push_back(t);
    }
    return rows;
}

std::vector<Row> SettingsScreen::inputPage() {
    std::vector<Row> rows;
    Row confirm = Row::choice("Confirm button", {"A (right)", "B (bottom)"}, prefs.confirmBottom ? 1 : 0, [this](int i) {
        prefs.confirmBottom = i == 1;
        prefs.save();
        setConfirmBottom(app.gamepad(), prefs.confirmBottom);
        if (prefs.confirmBottom) addRetroArchSwap();
        else removeRetroArchSwap();
    });
    confirm.hint = "The other one goes back. Apps and the Nintendo systems' games follow it from the next one you open.";
    rows.push_back(confirm);
    rows.push_back(Row::link("Shortcuts", [this] { open(Page::Shortcuts); }));
    rows.push_back(Row::link("Button Tester", [this] { app.push(std::make_unique<TesterScreen>(app)); }));
    return rows;
}

std::vector<Row> SettingsScreen::shortcutsPage() {
    std::vector<Row> rows;
    for (const auto& s : kShortcuts) {
        if (!s[1]) rows.push_back(Row::section(s[0]));
        else rows.push_back(Row::info(buttonLabel(s[0]), tr(s[1])));
    }
    return rows;
}

// Grouped by role, in the order the roles first come, each name under every role it has ("A/B" is two).
// The first line opens the list as it is (goodluckOS, is brought to you by...); lines without a role close it.
std::vector<Row> SettingsScreen::creditsPage() {
    std::vector<std::pair<std::string, std::vector<std::string>>> roles;
    std::vector<std::string> closing;
    for (size_t i = 1; i < credits.size(); ++i) {
        const auto& [name, role] = credits[i];
        if (role.empty()) closing.push_back(name);
        for (size_t from = 0; !role.empty() && from != std::string::npos;) {
            const size_t slash = role.find('/', from);
            const std::string r = trim(role.substr(from, slash == std::string::npos ? slash : slash - from));
            from = slash == std::string::npos ? slash : slash + 1;
            if (r.empty()) continue;
            auto g = std::find_if(roles.begin(), roles.end(), [&r](const auto& x) { return x.first == r; });
            if (g == roles.end()) g = roles.insert(roles.end(), {r, {}});
            g->second.push_back(name);
        }
    }
    std::vector<Row> rows;
    auto add = [&rows](Row r) { r.rawLabel = true; rows.push_back(r); };
    if (!credits.empty()) add(Row::info(credits[0].first, credits[0].second));
    for (const auto& [role, names] : roles) {
        add(Row::section(role));
        for (const std::string& n : names) add(Row::info(n, ""));
    }
    if (!closing.empty()) add(Row::section(""));
    for (const std::string& n : closing) add(Row::info(n, ""));
    return rows;
}

std::vector<Row> SettingsScreen::resizePage() {
    std::vector<Row> rows;
    if (resize.valid) {
        rows.push_back(Row::info("microSD card", humanSize(resize.cardKb)));
        rows.push_back(Row::info("HOME partition", humanSize(resize.partitionKb)));
        if (resize.home.mounted) {
            rows.push_back(Row::info("HOME filesystem", humanSize(resize.home.totalKb)));
            rows.push_back(Row::info("HOME used", humanSize(resize.home.usedKb)));
            rows.push_back(Row::info("HOME free", humanSize(resize.home.freeKb)));
        } else {
            rows.push_back(Row::info("HOME is not currently mounted.", ""));
        }
        rows.push_back(Row::info("Unused space on card", humanSize(resize.unusedKb)));
        if (!resize.last.empty()) {
            const auto result = resize.last.find("result"), when = resize.last.find("time");
            const std::string res = result != resize.last.end() ? result->second : "unknown";
            const std::string at = when != resize.last.end() ? when->second : "";
            rows.push_back(Row::info("Last resize attempt", tr(res) + (at.empty() ? "" : " (" + at + ")")));
        }
    }
    if (resize.pending) {
        rows.push_back(Row::action("Cancel Resize Request", [this] {
            std::string error;
            if (!cancelResize(error)) app.notice(error);
            resize = Resize::read();
        }));
    } else if (resize.valid) {
        rows.push_back(Row::action("Resize HOME Partition", [this] { resizeHome(); }));
    }
    return rows;
}

// Asks first; then the request flag, and S01resize-home does the rest at the next boot
void SettingsScreen::resizeHome() {
    Dialog d;
    d.title = "Are you sure?";
    d.message = trf("You will gain %s after resizing. This backs up your files, expands the partition to fill the card, "
                    "reformats it, and restores your files. The device will reboot to do this.",
                    humanSize(resize.unusedKb));
    if (resize.unusedKb == 0)
        d.message += std::string("\n\n") + tr("Heads up: there's no unused space left to reclaim.") + " " +
                     tr("You probably don't need to do this, but it's safe to run anyway.");
    d.choices = {"Back", "Do It."};
    app.push(std::make_unique<DialogScreen>(app, d, [this](int choice) {
        if (choice != 1) return;
        std::string error;
        if (!requestResize(error)) {
            app.notice(error);
            resize = Resize::read();
            return;
        }
        if (saveAt) {
            saveLevels();
            saveAt = 0;
        }
        app.push(std::make_unique<StatusScreen>(app, tr("Rebooting..."), [this] {
            if (std::system("doas /usr/local/bin/power-action.sh reboot >/dev/null 2>&1") == 0) return;
            std::string ignored;
            cancelResize(ignored);
            resize = Resize::read();
            app.pop();      // the status message
            app.notice(tr("Failed to reboot."));
        }));
    }));
}
