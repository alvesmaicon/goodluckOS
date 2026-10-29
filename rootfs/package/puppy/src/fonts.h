#pragma once
// The interface fonts System Settings offers, in the folder of puppy.conf's font. "Default" is that
// font itself (Inter on goodluckOS), or Atkinson Hyperlegible in the Showcase style. The choice is
// font=<key> in the settings file (see Prefs).
#include <string>
#include <vector>

namespace fonts {

struct Font {
    const char* key;    // saved in the settings file
    const char* name;   // shown in System Settings
    const char* file;   // next to puppy.conf's font; nullptr for "default", that font
    float scale;        // size for the same nominal size as Inter, so text takes about as much room
};

const std::vector<Font>& all();
int find(const std::string& key);       // the index in all(); 0 ("default") for an unknown key
std::string path(const Font& f);
bool available(const Font& f);
// The default for a missing file. bold: the face of the Showcase style's titles, the regular one when
// the font has none; "" in the retro style, which has no bold.
void choose(const std::string& key, bool showcase, std::string& path, std::string& bold, float& scale);

}  // namespace fonts
