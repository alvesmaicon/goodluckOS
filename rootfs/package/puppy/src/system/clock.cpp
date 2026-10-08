#include "system/clock.h"

#include <cstdio>
#include <cstdlib>
#include <fstream>

#include <sys/stat.h>

#include "system/device.h"
#include "system/hud.h"

static const char* kTimezoneFile = "/home/player/.config/timezone";

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

void setClock(time_t when) {
    runScript("set-time.sh " + std::to_string((long long)when), false);
}

const std::vector<int>& timezones() {
    static const std::vector<int> offsets = {-720, -660, -600, -570, -540, -480, -420, -360, -300, -240, -210, -180,
                                             -120, -60, 0, 60, 120, 180, 210, 240, 270, 300, 330, 345, 360, 390,
                                             420, 480, 525, 540, 570, 600, 630, 660, 720, 765, 780, 840};
    return offsets;
}

std::string timezoneLabel(int minutes) {
    char text[16];
    snprintf(text, sizeof(text), "UTC%c%02d:%02d", minutes < 0 ? '-' : '+', abs(minutes) / 60, abs(minutes) % 60);
    return text;
}

// "<-03>3" for UTC-3: POSIX counts west of Greenwich as positive
static std::string timezonePosix(int minutes) {
    if (minutes == 0) return "UTC0";
    char text[24];
    int h = abs(minutes) / 60, m = abs(minutes) % 60;
    if (m) snprintf(text, sizeof(text), "<%c%02d%02d>%s%d:%02d", minutes < 0 ? '-' : '+', h, m, minutes < 0 ? "" : "-", h, m);
    else snprintf(text, sizeof(text), "<%c%02d>%s%d", minutes < 0 ? '-' : '+', h, minutes < 0 ? "" : "-", h);
    return text;
}

int timezoneIndex() {
    std::ifstream in(kTimezoneFile);
    std::string line;
    std::getline(in, line);
    const std::vector<int>& zones = timezones();
    for (size_t i = 0; i < zones.size(); ++i)
        if (timezonePosix(zones[i]) == line) return (int)i;
    for (size_t i = 0; i < zones.size(); ++i)
        if (zones[i] == 0) return (int)i;
    return 0;
}

void setTimezone(int index) {
    const std::string tz = timezonePosix(timezones()[index]);
    mkdir("/home/player/.config", 0755);
    {
        std::ofstream out(kTimezoneFile);
        out << tz << "\n";
    }
    setenv("TZ", tz.c_str(), 1);
    tzset();
}
