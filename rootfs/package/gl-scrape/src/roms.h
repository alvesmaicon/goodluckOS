#pragma once
// A system folder's ROM files and what identifies each one to ScreenScraper.
#include <cstdint>
#include <string>
#include <vector>

struct RomId {
    std::string crc;        // CRC32 in upper-case hex
    uint64_t size = 0;      // of the ROM itself: the file inside a zip
};

std::vector<std::string> romFiles(const std::string& dir, const std::vector<std::string>& exts);   // sorted names
RomId identify(const std::string& path);           // reads the whole file (a zip: its directory)
std::string fileRegion(const std::string& name);   // ScreenScraper's region of the name's tags, "(USA)" -> "us"
std::string stem(const std::string& name);          // without the extension
