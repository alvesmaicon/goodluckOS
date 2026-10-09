#include "system/hud.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <fstream>

#include <sys/stat.h>
#include <unistd.h>

static const char* kHudDefaults = "/usr/share/goodluck/defaults/gallium_hud.conf";
static const char* kHudConfig = "/home/player/.config/gallium_hud.conf";

static void readHudFile(const char* path, HudSettings& h) {
    std::ifstream in(path);
    for (std::string line; std::getline(in, line);) {
        const size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        const std::string key = line.substr(0, eq), value = line.substr(eq + 1);
        if (key == "HUD_STATUS_DATE") h.statusDate = value == "true";
        else if (key == "HUD_STATUS_TIME") h.statusTime = value == "true";
        else if (key == "HUD_STATUS_BATTERY") h.statusBattery = value == "true";
        else if (key == "HUD_STATUS_AUDIO") h.statusAudio = value == "true";
        else if (key == "HUD_STATUS_CPU_TEMP") h.statusCpuTemp = value == "true";
        else if (key == "HUD_STATUS_PMIC_TEMP") h.statusPmicTemp = value == "true";
        else if (key == "HUD_STATUS_OPACITY") h.statusOpacity = std::clamp(atoi(value.c_str()), 0, 100);
        else if (key == "HUD_VISIBLE") h.visible = value == "true";
        else if (key == "HUD_ITEMS") h.cpu = value == "fps,cpu";
        else if (key == "HUD_STYLE") h.text = value == "text";
        else if (key == "HUD_POSITION" && !value.empty()) h.position = value;
        else if (key == "HUD_24H") h.h24 = value == "true";
        else if (key == "HUD_DATE_FORMAT" && !value.empty()) h.dateFormat = value;
        else if (key == "HUD_ACCENT" && value.size() == 6) h.accent = value;
    }
}

// The system's defaults, then the user's choices
HudSettings HudSettings::load() {
    HudSettings h;
    readHudFile(kHudDefaults, h);
    readHudFile(kHudConfig, h);
    return h;
}

void HudSettings::save() const {
    mkdir("/home/player/.config", 0755);
    const std::string tmp = std::string(kHudConfig) + ".tmp";
    {
        std::ofstream out(tmp);
        if (!out) return;
        auto flag = [](bool on) { return on ? "true" : "false"; };
        out << "HUD_STATUS_DATE=" << flag(statusDate) << "\n"
            << "HUD_STATUS_TIME=" << flag(statusTime) << "\n"
            << "HUD_STATUS_BATTERY=" << flag(statusBattery) << "\n"
            << "HUD_STATUS_AUDIO=" << flag(statusAudio) << "\n"
            << "HUD_STATUS_CPU_TEMP=" << flag(statusCpuTemp) << "\n"
            << "HUD_STATUS_PMIC_TEMP=" << flag(statusPmicTemp) << "\n"
            << "HUD_STATUS_OPACITY=" << statusOpacity << "\n"
            << "HUD_VISIBLE=" << flag(visible) << "\n"
            << "HUD_ITEMS=" << (cpu ? "fps,cpu" : "fps") << "\n"
            << "HUD_STYLE=" << (text ? "text" : "graph") << "\n"
            << "HUD_POSITION=" << position << "\n"
            << "HUD_24H=" << flag(h24) << "\n"
            << "HUD_DATE_FORMAT=" << dateFormat << "\n"
            << "HUD_ACCENT=" << accent << "\n";
    }
    rename(tmp.c_str(), kHudConfig);
}

void HudSettings::restoreDefaults() {
    unlink(kHudConfig);
}

const std::vector<HudOption>& hudPositions() {
    static const std::vector<HudOption> positions = {
        {"top-left", "Top left"}, {"top-right", "Top right"}, {"bottom-left", "Bottom left"}, {"bottom-right", "Bottom right"},
    };
    return positions;
}

// What the settings show, and the strftime format the clocks use
const std::vector<HudOption>& dateFormats() {
    static const std::vector<HudOption> formats = {
        {"%m/%d", "MM/DD"}, {"%d/%m", "DD/MM"}, {"%m/%d/%Y", "MM/DD/YYYY"}, {"%d/%m/%Y", "DD/MM/YYYY"},
        {"%Y-%m-%d", "YYYY-MM-DD"}, {"%d/%m/%y", "DD/MM/YY"}, {"%y-%m-%d", "YY-MM-DD"},
    };
    return formats;
}
