#include "system/device.h"

#include <algorithm>
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
