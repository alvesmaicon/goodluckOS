#pragma once
// The Gallium HUD's options: ~/.config/gallium_hud.conf over the system's defaults. They're the
// in-game status bar and performance overlay (read by /etc/profile.d/gallium_hud.sh when an app
// starts) and the clock's date format and 12/24 hours, which the launcher's top bar uses too.
#include <string>
#include <vector>

struct HudSettings {
    bool statusDate = false, statusTime = false, statusBattery = false, statusAudio = false;
    bool statusCpuTemp = false, statusPmicTemp = false;
    int statusOpacity = 50;
    bool visible = false;               // the performance overlay, from the game's start
    bool cpu = true;                    // FPS and CPU; else FPS only
    bool text = false;                  // as text; else graphs
    std::string position = "top-left";  // top-left, top-right, bottom-left, bottom-right
    bool h24 = false;
    std::string dateFormat = "%m/%d";   // strftime
    std::string accent = "ffcd3c";      // the in-game feedback's colour (rrggbb): the launcher's accent

    static HudSettings load();
    void save() const;
    static void restoreDefaults();      // drops the user's file
};

// Values the file takes, with their English names
struct HudOption {
    const char* value;
    const char* name;
};
const std::vector<HudOption>& hudPositions();
const std::vector<HudOption>& dateFormats();
