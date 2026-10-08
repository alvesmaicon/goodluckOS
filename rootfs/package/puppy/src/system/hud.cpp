#include "system/hud.h"

#include <algorithm>
#include <cstdlib>
#include <ctime>
#include <fstream>

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
    }
}

// The system's defaults, then the user's choices
HudSettings HudSettings::load() {
    HudSettings h;
    readHudFile(kHudDefaults, h);
    readHudFile(kHudConfig, h);
    return h;
}

std::string clockFormat() {
    const HudSettings h = HudSettings::load();
    return h.dateFormat + (h.h24 ? " %H:%M" : " %I:%M %p");
}

std::string clockText(const std::string& fmt) {
    if (fmt.empty()) return "";
    char text[32];
    time_t now = time(nullptr);
    struct tm tm;
    localtime_r(&now, &tm);
    return strftime(text, sizeof(text), fmt.c_str(), &tm) ? text : "";
}
