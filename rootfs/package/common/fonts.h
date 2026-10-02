// The interface font of the goodluckOS apps (Puppy, System Settings, are-you-sure, Resize Home),
// chosen in System Settings and saved as "font=<key>" in the settings file shared with the launcher
// options (see i18n.h). The font files live in dirPath(); a missing one falls back to Inter.
//
// Header-only and C++11, so every app can include it.
#pragma once

#include <fstream>
#include <string>
#include <vector>

#include "i18n.h"

namespace fonts {

struct Font {
    const char* key;    // saved in the settings file
    const char* name;   // shown in System Settings
    const char* file;   // in dirPath()
    float scale;        // size for the same nominal size as Inter, so text takes about as much room
};

inline const std::vector<Font>& all() {
    static const std::vector<Font> fonts = {
        {"inter", "Inter", "Inter_24pt-Medium.ttf", 1.0f},
        {"vt323", "VT323", "VT323-Regular.ttf", 1.2f},
        {"pixelify", "Pixelify Sans", "PixelifySans-VF.ttf", 1.05f},
        {"proggy", "ProggyClean", "ProggyClean.ttf", 1.0f},     // ImGui's own font, as System Settings had
    };
    return fonts;
}

// Can be changed before use (Puppy takes it from its puppy.conf).
inline std::string& dirPath() { static std::string d = "/usr/share/fonts"; return d; }

inline std::string path(const Font& f) { return dirPath() + "/" + f.file; }

inline bool available(const Font& f) {
    std::ifstream in(path(f).c_str());
    return in.good();
}

// The key in the settings file, or "" when none was chosen.
inline std::string configuredKey() { return i18n::settingValue("font"); }

inline const Font& find(const std::string& key) {
    for (size_t i = 0; i < all().size(); ++i)
        if (key == all()[i].key) return all()[i];
    return all()[0];
}

// The chosen font when its file is there, else Inter.
inline const Font& current() {
    const Font& f = find(configuredKey());
    return available(f) ? f : all()[0];
}

}  // namespace fonts
