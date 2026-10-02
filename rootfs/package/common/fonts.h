// The interface font of the goodluckOS apps (Puppy, System Settings, are-you-sure, Resize Home),
// chosen in System Settings and saved as "font=<key>" in the settings file shared with the launcher
// options (see i18n.h). The font files live in dirPath(); a missing one falls back to Inter.
// "Original", the default, keeps each app's own font: Inter in the launcher and ProggyClean (ImGui's
// font) at its usual size in the other apps, as goodluckOS always had them.
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
    const char* file;   // in dirPath(); nullptr for "original"
    float scale;        // size for the same nominal size as Inter, so text takes about as much room
};

inline const std::vector<Font>& all() {
    static const std::vector<Font> fonts = {
        {"original", "Original", nullptr, 1.0f},
        {"inter", "Inter", "Inter_24pt-Medium.ttf", 1.0f},
        {"vt323", "VT323", "VT323-Regular.ttf", 1.2f},
        {"pixelify", "Pixelify Sans", "PixelifySans-VF.ttf", 1.05f},
        {"proggy", "ProggyClean", "ProggyClean.ttf", 1.25f},    // a bit bigger than in "original"
    };
    return fonts;
}

// Can be changed before use (Puppy takes it from its puppy.conf).
inline std::string& dirPath() { static std::string d = "/usr/share/fonts"; return d; }

// The font an app draws with for a choice: "original" means Inter in the launcher and ProggyClean at
// its usual size elsewhere.
inline const Font& forApp(const Font& f, bool launcher) {
    static const Font inter = {"inter", "Inter", "Inter_24pt-Medium.ttf", 1.0f};
    static const Font proggy = {"proggy", "ProggyClean", "ProggyClean.ttf", 1.0f};
    if (f.file) return f;
    return launcher ? inter : proggy;
}

inline std::string path(const Font& f) { return dirPath() + "/" + forApp(f, false).file; }

inline bool available(const Font& f) {
    std::ifstream in(path(f).c_str());
    return in.good();
}

// The key in the settings file, or "" when none was chosen.
inline std::string configuredKey() { return i18n::settingValue("font"); }

// The choice with this key; "original" for an unknown or empty one.
inline const Font& find(const std::string& key) {
    for (size_t i = 0; i < all().size(); ++i)
        if (key == all()[i].key) return all()[i];
    return all()[0];
}

// The font this app draws with: the chosen one when its file is there, else Inter.
inline const Font& current(bool launcher) {
    const Font& f = forApp(find(configuredKey()), launcher);
    return available(f) ? f : forApp(find("inter"), launcher);
}

}  // namespace fonts
