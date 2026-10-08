// The pages of System Settings, built from what SettingsScreen holds (see settings.h).
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <memory>

#include "config.h"
#include "fonts.h"
#include "overlays.h"
#include "settings.h"
#include "system/clock.h"
#include "system/device.h"
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

// From /etc/triggerhappy/triggers.d, the launcher and the RetroArch config (hotkey = FN)
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
    {"FN + START", "Quit the game"},
};

const std::vector<std::pair<SettingsScreen::Page, const char*>>& SettingsScreen::sections() {
    static const std::vector<std::pair<Page, const char*>> list = {
        {Page::Display, "Display & Audio"}, {Page::Launcher, "Launcher"}, {Page::Interface, "Interface"},
        {Page::Overlay, "Overlay"}, {Page::DateTime, "Date & Time"}, {Page::Storage, "Storage"},
        {Page::System, "System"}, {Page::Input, "Input Settings"},
    };
    return list;
}

std::string SettingsScreen::title(Page p) const {
    switch (p) {
        case Page::Tabs:      return tr("Launcher tabs");
        case Page::Shortcuts: return tr("Shortcuts");
        case Page::Info:      return tr("System Info");
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
        case Page::Tabs: return tr("Tabs switched off are hidden; their games still show in All Games and My List.");
        case Page::System: return tr(powerProfiles()[profile].hint);
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
        case Page::Launcher:  return launcherPage();
        case Page::Interface: return interfacePage();
        case Page::Overlay:   return overlayPage();
        case Page::DateTime:  return dateTimePage();
        case Page::Storage:   return storagePage();
        case Page::System:    return systemPage();
        case Page::Input:     return inputPage();
        case Page::Tabs:      return tabsPage();
        case Page::Shortcuts: return shortcutsPage();
        case Page::Info:      return infoPage();
        case Page::Resize:    return resizePage();
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

std::vector<Row> SettingsScreen::launcherPage() {
    std::vector<Row> rows;
    rows.push_back(Row::toggle("Show launcher tabs", launcher.showTabs, [this](int on) {
        launcher.showTabs = on;
        prefs.showTabs = on;
        prefs.save();
    }));
    rows.push_back(Row::choice("Launcher view", {"Grid", "List"}, launcher.view == View::List ? 1 : 0, [this](int i) {
        launcher.view = i ? View::List : View::Grid;
        prefs.listView = i;
        prefs.save();
    }));
    if (std::any_of(launcher.categories.begin(), launcher.categories.end(), [](const Category& c) { return !c.mixed; }))
        rows.push_back(Row::link("Launcher tabs", [this] { open(Page::Tabs); }));
    return rows;
}

std::vector<Row> SettingsScreen::tabsPage() {
    std::vector<Row> rows;
    for (const Category& c : launcher.categories) {
        if (c.mixed) continue;
        std::string label = tr(c.label);
        if (c.label != c.name) label += "  (" + tr(c.name) + ")";
        Row r = Row::toggle(label, !c.hidden, [this, name = c.name](int on) {
            for (auto& cat : launcher.categories)
                if (!cat.mixed && cat.name == name) cat.hidden = !on;
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

    std::vector<std::string> fontNames, keys;
    int currentFont = 0;
    const fonts::Font& chosen = fonts::find(prefs.font);
    for (const fonts::Font& f : fonts::all()) {
        if (!fonts::available(fonts::forApp(f, true))) continue;
        if (&f == &chosen) currentFont = (int)keys.size();
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

    rows.push_back(Row::toggle("Show Puppy on loading screens", !prefs.loadingText, [this](int on) {
        prefs.loadingText = !on;
        prefs.save();
    }));
    return rows;
}

std::vector<Row> SettingsScreen::overlayPage() {
    std::vector<Row> rows;
    auto flag = [this](const char* label, bool HudSettings::*field) {
        return Row::toggle(label, hud.*field, [this, field](int on) {
            hud.*field = on;
            hud.save();
        });
    };
    // The in-game status bar; the launcher has its own top bar. The clock's format and 12/24 hours
    // come from Date & Time
    rows.push_back(Row::section("In-game status bar"));
    rows.push_back(flag("Show date", &HudSettings::statusDate));
    rows.push_back(flag("Show time", &HudSettings::statusTime));
    rows.push_back(flag("Show battery", &HudSettings::statusBattery));
    rows.push_back(flag("Show audio", &HudSettings::statusAudio));
    rows.push_back(flag("Show CPU temperature", &HudSettings::statusCpuTemp));
    rows.push_back(flag("Show power chip temperature", &HudSettings::statusPmicTemp));
    rows.push_back(Row::level("Opacity", hud.statusOpacity, 0, 100, 10, [this](int v) {
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
        app.clockChanged();
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
        app.clockChanged();
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
        app.clockChanged();
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
    rows.push_back(Row::link("System Info", [this] {
        info = SystemInfo::read();
        home = homeUsage();
        resize = Resize::read();
        open(Page::Info);
    }));
    // Overlay, Date & Time, the launcher's view, tabs and font, and the power mode; the language,
    // the time zone and the clock stay
    rows.push_back(Row::action("Restore default settings", [this] {
        Dialog d;
        d.title = "Restore default settings";
        d.message = "Restore the Overlay, Date & Time, launcher and power mode settings? The language and the time zone stay.";
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
    prefs = fresh;
    prefs.save();
    launcher.view = View::Grid;
    launcher.showTabs = true;
    for (Category& c : launcher.categories) c.hidden = false;
    applyFont();
    profile = defaultPowerProfile();
    runScript("power-profile.sh default", false);
    app.clockChanged();
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

std::vector<Row> SettingsScreen::inputPage() {
    std::vector<Row> rows;
    rows.push_back(Row::link("Shortcuts", [this] { open(Page::Shortcuts); }));
    rows.push_back(Row::link("Button Tester", [this] { app.push(std::make_unique<TesterScreen>(app)); }));
    return rows;
}

std::vector<Row> SettingsScreen::shortcutsPage() {
    std::vector<Row> rows;
    for (const auto& s : kShortcuts) {
        if (!s[1]) rows.push_back(Row::section(s[0]));
        else rows.push_back(Row::info(s[0], tr(s[1])));
    }
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
