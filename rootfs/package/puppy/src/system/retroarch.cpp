#include "system/retroarch.h"

#include <fstream>
#include <vector>

#include "util.h"

static const char* kRemapDir = "/home/player/.config/retroarch/config/remaps";
static const char* kCores[] = {"Gambatte", "mGBA", "FCEUmm", "Snes9x 2005"};    // the cores' library names
// RetroPad ids: B is 0, A is 8
static const std::string kA = "input_player1_btn_a", kB = "input_player1_btn_b";

static fs::path remapFile(const std::string& core) {
    return fs::path(kRemapDir) / core / (core + ".rmp");
}

static std::vector<std::string> readLines(const fs::path& file) {
    std::vector<std::string> lines;
    std::ifstream in(file);
    for (std::string line; std::getline(in, line);) lines.push_back(line);
    return lines;
}

static void writeLines(const fs::path& file, const std::vector<std::string>& lines) {
    std::error_code ec;
    fs::create_directories(file.parent_path(), ec);
    const fs::path tmp = file.string() + ".tmp";
    {
        std::ofstream out(tmp);
        if (!out) return;
        for (const auto& line : lines) out << line << "\n";
    }
    fs::rename(tmp, file, ec);
}

// 'input_player1_btn_a = "0"' -> key and value
static void split(const std::string& line, std::string& key, std::string& value) {
    const size_t eq = line.find('=');
    key = eq == std::string::npos ? "" : trim(line.substr(0, eq));
    value = eq == std::string::npos ? "" : trim(line.substr(eq + 1));
    if (value.size() >= 2 && value.front() == '"' && value.back() == '"') value = value.substr(1, value.size() - 2);
}

void addRetroArchSwap() {
    for (const char* core : kCores) {
        const fs::path file = remapFile(core);
        auto lines = readLines(file);
        bool mapped = false;
        std::string key, value;
        for (const auto& line : lines) {
            split(line, key, value);
            if (key == kA || key == kB) mapped = true;
        }
        if (mapped) continue;
        lines.push_back(kA + " = \"0\"");
        lines.push_back(kB + " = \"8\"");
        writeLines(file, lines);
    }
}

void removeRetroArchSwap() {
    for (const char* core : kCores) {
        const fs::path file = remapFile(core);
        std::error_code ec;
        if (!fs::is_regular_file(file, ec)) continue;
        std::vector<std::string> kept;
        int swap = 0;
        bool otherRemaps = false;
        std::string key, value;
        for (const auto& line : readLines(file)) {
            split(line, key, value);
            if ((key == kA && value == "0") || (key == kB && value == "8")) { ++swap; continue; }
            // RetroArch also saves the ports' devices and the turbo settings; they aren't remaps
            if (key.compare(0, 12, "input_player") == 0 && (key.find("_btn_") != std::string::npos ||
                key.find("_key_") != std::string::npos || key.find("_stk_") != std::string::npos))
                otherRemaps = true;
            kept.push_back(line);
        }
        if (swap != 2) continue;
        if (otherRemaps) writeLines(file, kept);
        else fs::remove(file, ec);
    }
}
