#include "device.h"

#include <ctime>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

#include "util.h"

// Runs a shell command without waiting for it (screen off, restart... from puppy.conf).
void runDetached(const std::string& command) {
    signal(SIGCHLD, SIG_IGN);   // no zombies
    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        execl("/bin/sh", "sh", "-c", command.c_str(), (char*)nullptr);
        _exit(127);
    }
}

// Non-blocking: if the power_fifo daemon isn't reading (e.g. being respawned), drop the request rather
// than freeze the launcher.
void sendPowerRequest(const char* request) {
    int fd = open(cfg.powerFifo.c_str(), O_WRONLY | O_NONBLOCK);
    if (fd < 0) return;
    std::string line = std::string(request) + "\n";
    ssize_t written = write(fd, line.c_str(), line.size());
    (void)written;
    close(fd);
}

bool screenOn() {
    std::ifstream in(cfg.backlight);
    int level = 1;
    in >> level;
    return level > 0;
}

bool batteryCharging = false, batteryFull = false;

// strftime format of the top bar's clock: the date and the time, with the date format and
// 12/24 hours System Settings writes over the system's defaults
std::string clockFormat() {
    bool h24 = false;
    std::string dateFormat = "%m/%d";
    for (const char* path : {"/usr/share/goodluck/defaults/gallium_hud.conf", "/home/player/.config/gallium_hud.conf"}) {
        std::ifstream in(path);
        for (std::string line; std::getline(in, line);) {
            if (line.compare(0, 8, "HUD_24H=") == 0) h24 = line == "HUD_24H=true";
            else if (line.compare(0, 16, "HUD_DATE_FORMAT=") == 0 && line.size() > 16) dateFormat = line.substr(16);
        }
    }
    return dateFormat + (h24 ? " %H:%M" : " %I:%M %p");
}

std::string clockText(const std::string& fmt) {
    if (fmt.empty()) return "";
    char text[32];
    time_t now = time(nullptr);
    struct tm tm;
    localtime_r(&now, &tm);
    return strftime(text, sizeof(text), fmt.c_str(), &tm) ? text : "";
}

int readBattery() {
    std::error_code ec;
    batteryCharging = batteryFull = false;
    for (fs::directory_iterator it("/sys/class/power_supply", ec), end; !ec && it != end; it.increment(ec)) {
        std::ifstream typeFile(it->path() / "type");
        std::string type;
        if (!(typeFile >> type) || type != "Battery") continue;
        std::ifstream statusFile(it->path() / "status");
        std::string status;
        statusFile >> status;
        batteryCharging = status == "Charging";
        batteryFull = status == "Full";
        std::ifstream capFile(it->path() / "capacity");
        int cap;
        if (capFile >> cap) return std::clamp(cap, 0, 100);
    }
    return -1; // no battery
}
