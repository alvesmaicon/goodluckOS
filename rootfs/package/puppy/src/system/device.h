#pragma once
// The rest of the device: the battery, the screen and its brightness, the power profiles, and power
// requests and the root scripts.
#include <string>
#include <vector>

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

// One of the /usr/local/bin scripts doas.conf lets the player run as root; wait: until it's done
// (what runs in the background dies with Puppy when it starts an app).
void runScript(const std::string& scriptAndArgs, bool wait);

int brightness();               // 1-10
void setBrightness(int level);
// Keeps the brightness and the mixer for the next boot (persist-settings.sh), and gives the in-game
// status bar the new volume and output.
void saveLevels();

// Power profiles, applied and remembered by power-profile.sh
struct PowerProfile {
    const char* key;    // for power-profile.sh
    const char* name;   // English
    const char* hint;
};
const std::vector<PowerProfile>& powerProfiles();
int powerProfile();             // index in powerProfiles()
int defaultPowerProfile();
void setPowerProfile(int index);
