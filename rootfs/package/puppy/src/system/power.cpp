#include "system/power.h"

#include <SDL2/SDL.h>
#include <linux/netlink.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>
#include <thread>

namespace power {

uint32_t watch() {
    int fd = socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC, NETLINK_KOBJECT_UEVENT);
    if (fd < 0) return 0;
    sockaddr_nl addr{};
    addr.nl_family = AF_NETLINK;
    addr.nl_groups = 1;     // the kernel's own uevents
    uint32_t type = (uint32_t)-1;
    if (bind(fd, (sockaddr*)&addr, sizeof addr) < 0 || (type = SDL_RegisterEvents(1)) == (uint32_t)-1) {
        close(fd);
        return 0;
    }
    std::thread([fd, type] {
        char buf[4096];
        for (;;) {
            const ssize_t n = recv(fd, buf, sizeof buf - 1, 0);
            if (n < 0 && (errno == EINTR || errno == ENOBUFS)) continue;
            if (n <= 0) break;
            buf[n] = 0;
            // "change@/devices/...", then the KEY=value pairs, each ending with a NUL
            for (const char* p = buf; p < buf + n; p += strlen(p) + 1) {
                if (strcmp(p, "SUBSYSTEM=power_supply") == 0) {
                    SDL_Event e{};
                    e.type = type;
                    SDL_PushEvent(&e);
                    break;
                }
            }
        }
        close(fd);
    }).detach();
    return type;
}

}  // namespace power
