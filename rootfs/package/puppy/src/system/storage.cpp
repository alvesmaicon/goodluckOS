#include "system/storage.h"

#include <cerrno>
#include <cstring>
#include <fstream>

#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

#include "config.h"
#include "system/device.h"
#include "util.h"

static const char* kHome = "/home/player";
static const char* kExternal = "/media/external";
static const char* kRequestFlag = "/etc/player-flags/.home_resize_requested";
static const char* kStatusFile = "/etc/player-flags/.home_resize_status";
static const char* kCardSysfs = "/sys/class/block/mmcblk0";
static const char* kHomePartSysfs = "/sys/class/block/mmcblk0p2";
// S01resize-home grows the partition and leaves less than this untouched
static const unsigned long long kMinFreeKb = 8192;

static Usage usage(const char* path) {
    Usage u;
    struct statvfs vfs;
    if (statvfs(path, &vfs) != 0) return u;
    u.mounted = true;
    u.totalKb = (unsigned long long)vfs.f_blocks * vfs.f_frsize / 1024;
    u.freeKb = (unsigned long long)vfs.f_bfree * vfs.f_frsize / 1024;
    u.usedKb = u.totalKb > u.freeKb ? u.totalKb - u.freeKb : 0;
    return u;
}

Usage homeUsage() { return usage(kHome); }

Usage externalCard() {
    bool mounted = false;
    std::ifstream mounts("/proc/mounts");
    for (std::string line; std::getline(mounts, line);)
        if (line.find(std::string(" ") + kExternal + " ") != std::string::npos) mounted = true;
    return mounted ? usage(kExternal) : Usage();     // statvfs fails too for a card that came out without Eject
}

void detectCard() { runScript("external-card.sh detect", false); }
void ejectCard() { runScript("external-card.sh eject", false); }

// Counts the files under dir; with remove, deletes them and the folders too.
static void trashWalk(const std::string& dir, TrashStats& stats, bool remove) {
    DIR* d = opendir(dir.c_str());
    if (!d) return;
    while (struct dirent* e = readdir(d)) {
        const std::string name = e->d_name;
        if (name == "." || name == "..") continue;
        const std::string path = dir + "/" + name;
        struct stat st;
        if (lstat(path.c_str(), &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) {
            trashWalk(path, stats, remove);
            if (remove) rmdir(path.c_str());
        } else {
            stats.files++;
            stats.bytes += (unsigned long long)st.st_size;
            if (remove) unlink(path.c_str());
        }
    }
    closedir(d);
}

TrashStats trashStats() {
    TrashStats stats;
    trashWalk(cfg.trashDir, stats, false);
    return stats;
}

void emptyTrash() {
    TrashStats stats;
    trashWalk(cfg.trashDir, stats, true);
    sync();
}

static long long readNumber(const std::string& path) {
    std::ifstream in(path);
    long long value;
    return (in >> value) ? value : -1;
}

bool Resize::canGrow() const { return unusedKb >= kMinFreeKb; }
bool Resize::fits() const { return home.usedKb < tmpFreeKb; }

Resize Resize::read() {
    Resize r;
    std::error_code ec;
    r.pending = fs::exists(kRequestFlag, ec);
    r.home = homeUsage();
    struct statvfs vfs;
    if (statvfs("/tmp", &vfs) == 0) r.tmpFreeKb = (unsigned long long)vfs.f_bavail * vfs.f_frsize / 1024;

    std::ifstream status(kStatusFile);
    for (std::string line; std::getline(status, line);) {
        size_t eq = line.find('=');
        if (eq != std::string::npos) r.last[line.substr(0, eq)] = line.substr(eq + 1);
    }

    // sizes in 512-byte sectors, whatever the card's own sector size
    const long long disk = readNumber(std::string(kCardSysfs) + "/size");
    const long long start = readNumber(std::string(kHomePartSysfs) + "/start");
    const long long size = readNumber(std::string(kHomePartSysfs) + "/size");
    if (disk <= 0 || start <= 0 || size <= 0) return r;
    r.valid = true;
    r.cardKb = (unsigned long long)disk / 2;
    r.partitionKb = (unsigned long long)size / 2;
    r.unusedKb = disk > start + size ? (unsigned long long)(disk - start - size) / 2 : 0;
    return r;
}

bool requestResize(std::string& error) {
    int fd = open(kRequestFlag, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        error = trf("Could not create resize-home flag file: %s", strerror(errno));
        return false;
    }
    close(fd);
    sync();
    return true;
}

bool cancelResize(std::string& error) {
    std::error_code ec;
    if (!fs::remove(kRequestFlag, ec)) {
        error = ec ? trf("Could not remove request flag: %s", ec.message())
                   : tr("Request flag was not found (it may have already been removed).");
        return false;
    }
    return true;
}
