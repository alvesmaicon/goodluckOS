#include "system/osd.h"

#include <cstdint>
#include <cstring>

#include <sys/inotify.h>
#include <unistd.h>

// Blocked in read() until something in /dev/shm is written: no wakeups otherwise
static int watch(void* data) {
    const Uint32 type = (Uint32)(uintptr_t)data;
    const int fd = inotify_init1(IN_CLOEXEC);
    if (fd < 0) return 0;
    // osd-notify.sh writes hud-osd.tmp and renames it over the panel
    if (inotify_add_watch(fd, "/dev/shm", IN_MOVED_TO | IN_CLOSE_WRITE) < 0) {
        close(fd);
        return 0;
    }
    alignas(struct inotify_event) char buf[4096];
    for (ssize_t n; (n = read(fd, buf, sizeof(buf))) > 0;) {
        bool panel = false;
        for (char* p = buf; p < buf + n;) {
            const struct inotify_event* e = (const struct inotify_event*)p;
            if (e->len && strcmp(e->name, "hud-osd") == 0) panel = true;
            p += sizeof(struct inotify_event) + e->len;
        }
        if (!panel) continue;
        SDL_Event ev = {};
        ev.type = type;
        SDL_PushEvent(&ev);
    }
    close(fd);
    return 0;
}

void watchOsd(Uint32 eventType) {
    if (eventType == (Uint32)-1) return;
    if (SDL_Thread* t = SDL_CreateThread(watch, "osd-watch", (void*)(uintptr_t)eventType)) SDL_DetachThread(t);
}
