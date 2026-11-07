#pragma once
// The ROM folders of the launcher's tabs (Puppy's apps files) and the ScreenScraper system each one is.
#include <functional>
#include <map>
#include <string>
#include <vector>

#include "json.h"

struct RomDir {
    std::string dir, folder;            // folder: the directory's own name, e.g. gba
    std::string tab;                    // the tab's label: TAB=, else NAME=
    std::vector<std::string> names;     // NAME= and TAB=
    std::vector<std::string> exts;      // lower case
};

// Each section of Puppy's apps files (a directory: its *.puppy files, by name): its name and keys in upper case
using AppsSection = std::function<void(const std::string& section, const std::map<std::string, std::string>& kv)>;
void appsSections(const std::vector<std::string>& appsFiles, const AppsSection& each);

// The [ARCHIVE]s of these files (a directory: its *.puppy files) but music and videos. A NAME= that
// comes again replaces the earlier archive, as in Puppy; a directory counts once.
std::vector<RomDir> romDirs(const std::vector<std::string>& appsFiles);

// ScreenScraper's systems by name: their own names and the folder names of Recalbox and RetroPie
class Systems {
public:
    bool fromList(const Json& answer);      // systemesListe.php's answer
    bool load(const std::string& path);     // the cache: "own|es<TAB>name<TAB>id" lines
    std::string dump() const;
    int find(const RomDir& d) const;        // 0: ScreenScraper has no such system
    bool empty() const { return own.empty(); }

private:
    std::map<std::string, int> own, es;     // name without case or punctuation -> its lowest id
};
