#pragma once
// The rest of the device as the launcher sees it: the battery, the screen and power requests.
#include <string>

struct Battery {
    int percent = -1;           // -1: no battery
    bool charging = false, full = false;

    bool operator!=(const Battery& o) const {
        return percent != o.percent || charging != o.charging || full != o.full;
    }

    static Battery read();
};

void runDetached(const std::string& command);
void sendPowerRequest(const char* request);
bool screenOn();
