#include "system/sysinfo.h"

#include <algorithm>
#include <fstream>

#include <sys/utsname.h>

#include "util.h"

static std::string readLine(const std::string& path) {
    std::ifstream in(path);
    std::string line;
    std::getline(in, line);
    // device-tree strings end with a NUL
    line.erase(std::remove(line.begin(), line.end(), '\0'), line.end());
    return trim(line);
}

static long long readNumber(const std::string& path, long long fallback) {
    std::ifstream in(path);
    long long value;
    return (in >> value) ? value : fallback;
}

SystemInfo SystemInfo::read() {
    SystemInfo s;
    s.model = readLine("/proc/device-tree/model");

    std::ifstream osRelease("/etc/os-release");
    for (std::string line; std::getline(osRelease, line);) {
        if (line.compare(0, 12, "PRETTY_NAME=") != 0) continue;
        s.os = line.substr(12);
        s.os.erase(std::remove(s.os.begin(), s.os.end(), '"'), s.os.end());
    }

    struct utsname uts;
    if (uname(&uts) == 0) s.kernel = uts.release;

    const std::string cpufreq = "/sys/devices/system/cpu/cpu0/cpufreq";
    const long long cur = readNumber(cpufreq + "/scaling_cur_freq", -1);
    const long long max = readNumber(cpufreq + "/cpuinfo_max_freq", -1);
    if (cur > 0) s.cpuMhz = (int)(cur / 1000);
    if (max > 0) s.cpuMaxMhz = (int)(max / 1000);
    const long long temp = readNumber("/sys/class/thermal/thermal_zone0/temp", -1000000);
    if (temp > -1000000) s.tempC = (int)(temp / 1000);

    std::ifstream meminfo("/proc/meminfo");
    for (std::string key; meminfo >> key;) {
        long long value;
        if (!(meminfo >> value)) break;
        if (key == "MemTotal:") s.memTotalKb = value;
        else if (key == "MemAvailable:") s.memAvailKb = value;
        meminfo.ignore(64, '\n');
    }

    std::error_code ec;
    for (fs::directory_iterator it("/sys/class/power_supply", ec), end; !ec && it != end; it.increment(ec)) {
        if (readLine((it->path() / "type").string()) != "Battery") continue;
        s.battery = (int)readNumber((it->path() / "capacity").string(), -1);
        s.batteryStatus = readLine((it->path() / "status").string());
        break;
    }
    return s;
}
