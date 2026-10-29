#pragma once
// An EmulationStation gamelist.xml, edited as text: games, tags and anything else gl-scrape
// doesn't write stay as they were.
#include <string>
#include <utility>
#include <vector>

using Tags = std::vector<std::pair<std::string, std::string>>;

class Gamelist {
public:
    void load(const std::string& path);         // a missing file is an empty list
    bool has(const std::string& file) const;    // a <game> for this ROM file name
    std::string get(const std::string& file, const std::string& tag) const;
    // Adds the game or fills its tags: only the empty ones unless overwrite; empty values are skipped
    void set(const std::string& file, const Tags& tags, bool overwrite);
    bool save(const std::string& path);          // only when changed, through a temporary file
    bool changed = false;

private:
    struct Part {
        std::string text;
        std::string file;       // a game's ROM file; empty for the text between games
    };
    std::vector<Part> parts;

    int find(const std::string& file) const;
};

std::string xmlEscape(const std::string& s);
