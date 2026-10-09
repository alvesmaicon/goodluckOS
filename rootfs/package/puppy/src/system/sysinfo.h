#pragma once
// System Info: what the console is and how it's doing.
#include <string>

struct SystemInfo {
    std::string model, os, kernel;
    int cpuMhz = -1, cpuMaxMhz = -1, tempC = -1000;
    long long memTotalKb = -1, memAvailKb = -1;
    int battery = -1;
    std::string batteryStatus;      // the kernel's: Charging, Discharging, Full...

    static SystemInfo read();
};
