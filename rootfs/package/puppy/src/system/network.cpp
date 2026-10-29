#include "system/network.h"

#include <cstdio>
#include <fstream>
#include <sstream>

#include <arpa/inet.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <sys/socket.h>

#include "system/device.h"
#include "util.h"

static const char* kIface = "usb0";

static std::string readWord(const std::string& path) {
    std::ifstream in(path);
    std::string word;
    in >> word;
    return word;
}

NetworkStatus NetworkStatus::read() {
    NetworkStatus s;
    s.networkMode = readWord("/etc/player-flags/usb-mode") == "network";
    s.linkUp = readWord(std::string("/sys/class/net/") + kIface + "/carrier") == "1";
    std::error_code ec;
    for (fs::directory_iterator it("/sys/class/udc", ec), end; !ec && it != end; it.increment(ec))
        if (readWord((it->path() / "state").string()) == "configured") s.hostUp = true;

    struct ifaddrs* list = nullptr;
    if (getifaddrs(&list) == 0) {
        for (struct ifaddrs* a = list; a; a = a->ifa_next) {
            if (!a->ifa_addr || a->ifa_addr->sa_family != AF_INET || std::string(a->ifa_name) != kIface) continue;
            char text[INET_ADDRSTRLEN];
            const struct sockaddr_in* in = (const struct sockaddr_in*)a->ifa_addr;
            if (inet_ntop(AF_INET, &in->sin_addr, text, sizeof(text))) s.address = text;
        }
        freeifaddrs(list);
    }

    // /proc/net/route: Iface Destination Gateway ..., hex and little-endian
    std::ifstream route("/proc/net/route");
    for (std::string line; std::getline(route, line);) {
        std::istringstream fields(line);
        std::string iface, dest, gw;
        fields >> iface >> dest >> gw;
        if (iface != kIface || dest != "00000000") continue;
        struct in_addr addr;
        addr.s_addr = (in_addr_t)strtoul(gw.c_str(), nullptr, 16);
        s.gateway = inet_ntoa(addr);
    }

    std::ifstream resolv("/etc/resolv.conf");
    for (std::string key; resolv >> key;) {
        std::string value;
        resolv >> value;
        if (key == "nameserver" && s.dns.empty()) s.dns = value;
        resolv.ignore(256, '\n');
    }

    s.check = readWord("/tmp/usb-net.check");
    return s;
}

void setUsbMode(bool network) { runScript(std::string("usb-mode.sh ") + (network ? "network" : "files"), true); }
void checkInternet() { runScript("usb-net.sh check", false); }
void askForAddress() { runScript("usb-net.sh renew", false); }
