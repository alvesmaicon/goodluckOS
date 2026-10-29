#include "system/jack.h"

#include <SDL.h>
#include <dirent.h>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <cstring>
#include <string>
#include <thread>

namespace jack {

static bool hasJackSwitch(int fd) {
    unsigned long bits[SW_MAX / (8 * sizeof(long)) + 1] = {};
    if (ioctl(fd, EVIOCGBIT(EV_SW, sizeof(bits)), bits) < 0) return false;
    return bits[SW_HEADPHONE_INSERT / (8 * sizeof(long))] >> (SW_HEADPHONE_INSERT % (8 * sizeof(long))) & 1;
}

static int openJack() {
    DIR* dir = opendir("/dev/input");
    if (!dir) return -1;
    int fd = -1;
    while (dirent* e = readdir(dir)) {
        if (strncmp(e->d_name, "event", 5) != 0) continue;
        int f = open((std::string("/dev/input/") + e->d_name).c_str(), O_RDONLY | O_CLOEXEC);
        if (f < 0) continue;
        if (hasJackSwitch(f)) {
            fd = f;
            break;
        }
        close(f);
    }
    closedir(dir);
    return fd;
}

uint32_t watch() {
    int fd = openJack();
    if (fd < 0) return 0;
    uint32_t type = SDL_RegisterEvents(1);
    if (type == (uint32_t)-1) {
        close(fd);
        return 0;
    }
    std::thread([fd, type] {
        input_event ev;
        while (read(fd, &ev, sizeof ev) == (ssize_t)sizeof ev) {
            if (ev.type != EV_SW || ev.code != SW_HEADPHONE_INSERT) continue;
            SDL_Event e{};
            e.type = type;
            SDL_PushEvent(&e);
        }
        close(fd);
    }).detach();
    return type;
}

}  // namespace jack
