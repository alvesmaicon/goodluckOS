#include "system/device.h"

#include <algorithm>
#include <cstdlib>
#include <fstream>

#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

#include "config.h"
#include "util.h"

Battery Battery::read() {
    Battery b;
    std::error_code ec;
    for (fs::directory_iterator it("/sys/class/power_supply", ec), end; !ec && it != end; it.increment(ec)) {
        std::ifstream typeFile(it->path() / "type");
        std::string type;
        if (!(typeFile >> type) || type != "Battery") continue;
        std::ifstream statusFile(it->path() / "status");
        std::string status;
        statusFile >> status;
        b.charging = status == "Charging";
        b.full = status == "Full";
        std::ifstream capFile(it->path() / "capacity");
        int cap;
        if (capFile >> cap) {
            b.percent = std::clamp(cap, 0, 100);
            break;
        }
    }
    return b;
}

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

void runScript(const std::string& scriptAndArgs, bool wait) {
    const std::string cmd = "doas /usr/local/bin/" + scriptAndArgs + " >/dev/null 2>&1" + (wait ? "" : " &");
    if (std::system(cmd.c_str()) != 0) {}
}

int brightness() {
    std::ifstream in(cfg.backlight);
    int level = 5;
    in >> level;
    return std::clamp(level, 1, 10);
}

void setBrightness(int level) {
    std::ofstream out(cfg.backlight);
    if (out) out << level;
}

void saveLevels() {
    runScript("persist-settings.sh save", true);
    if (std::system("/usr/local/bin/hud-status.sh >/dev/null 2>&1") != 0) {}
}

static const char* kPowerProfileState = "/etc/player-flags/power-profile";
static const char* kPowerDefaults = "/usr/share/goodluck/defaults/power.conf";

const std::vector<PowerProfile>& powerProfiles() {
    static const std::vector<PowerProfile> profiles = {
        {"battery", "Battery saver", "Slower CPU and GPU: the battery lasts longer"},
        {"balanced", "Balanced", "Speeds up only when a game needs it"},
        {"performance", "Performance", "Always at full speed: uses more battery"},
    };
    return profiles;
}

static int powerProfileIndex(const std::string& key) {
    for (size_t i = 0; i < powerProfiles().size(); ++i)
        if (key == powerProfiles()[i].key) return (int)i;
    return -1;
}

static std::string firstLine(const std::string& path) {
    std::ifstream in(path);
    std::string line;
    std::getline(in, line);
    return trim(line);
}

int defaultPowerProfile() {
    std::ifstream in(kPowerDefaults);
    for (std::string line; std::getline(in, line);) {
        if (line.compare(0, 14, "POWER_PROFILE=") != 0) continue;
        int i = powerProfileIndex(trim(line.substr(14)));
        if (i >= 0) return i;
    }
    return 1;
}

int powerProfile() {
    int i = powerProfileIndex(firstLine(kPowerProfileState));
    // before the profiles, only "Performance mode" was stored, as the governor
    if (i < 0 && firstLine("/etc/player-flags/governor") == "performance") i = 2;
    return i >= 0 ? i : defaultPowerProfile();
}

void setPowerProfile(int index) {
    runScript(std::string("power-profile.sh ") + powerProfiles()[index].key, false);
}
