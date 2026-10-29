#include "roms.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

#include <dirent.h>
#include <sys/stat.h>

// Read through below this size; a CD image is matched by its name and size
static const uint64_t kMaxCrcBytes = 64ull << 20;

static std::string lower(std::string s) {
    for (char& c : s) c = (char)tolower((unsigned char)c);
    return s;
}

std::string stem(const std::string& name) {
    const size_t dot = name.rfind('.');
    return dot == std::string::npos || dot == 0 ? name : name.substr(0, dot);
}

std::vector<std::string> romFiles(const std::string& dir, const std::vector<std::string>& exts) {
    std::vector<std::string> out;
    DIR* d = opendir(dir.c_str());
    if (!d) return out;
    while (struct dirent* e = readdir(d)) {
        const std::string name = e->d_name;
        if (name.empty() || name[0] == '.') continue;
        const size_t dot = name.rfind('.');
        if (dot == std::string::npos) continue;
        if (std::find(exts.begin(), exts.end(), lower(name.substr(dot + 1))) == exts.end()) continue;
        struct stat st;
        if (stat((dir + "/" + name).c_str(), &st) == 0 && S_ISREG(st.st_mode)) out.push_back(name);
    }
    closedir(d);
    std::sort(out.begin(), out.end());
    return out;
}

static uint32_t crcTable[256];

static void makeTable() {
    for (uint32_t n = 0; n < 256; ++n) {
        uint32_t c = n;
        for (int k = 0; k < 8; ++k) c = c & 1 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
        crcTable[n] = c;
    }
}

static std::string hex8(uint32_t v) {
    char b[9];
    snprintf(b, sizeof(b), "%08X", v);
    return b;
}

static uint32_t le32(const unsigned char* p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static uint16_t le16(const unsigned char* p) { return (uint16_t)(p[0] | p[1] << 8); }

// The one file in a zip, from its central directory: its CRC and size without unpacking it
static bool zipEntry(FILE* f, uint64_t fileSize, RomId& id) {
    const long tailLen = (long)std::min<uint64_t>(fileSize, 65557);
    std::vector<unsigned char> tail(tailLen);
    if (fseek(f, -tailLen, SEEK_END) != 0 || fread(tail.data(), 1, tailLen, f) != (size_t)tailLen) return false;
    long eocd = -1;
    for (long k = tailLen - 22; k >= 0; --k)
        if (le32(&tail[k]) == 0x06054b50) { eocd = k; break; }
    if (eocd < 0) return false;
    const uint32_t cdSize = le32(&tail[eocd + 12]), cdOffset = le32(&tail[eocd + 16]);
    if (cdSize == 0 || cdSize > (16u << 20) || (uint64_t)cdOffset + cdSize > fileSize) return false;
    std::vector<unsigned char> cd(cdSize);
    if (fseek(f, cdOffset, SEEK_SET) != 0 || fread(cd.data(), 1, cdSize, f) != cdSize) return false;
    int files = 0;
    for (size_t p = 0; p + 46 <= cd.size() && le32(&cd[p]) == 0x02014b50;) {
        const uint16_t nameLen = le16(&cd[p + 28]), extra = le16(&cd[p + 30]), comment = le16(&cd[p + 32]);
        if (p + 46 + nameLen > cd.size()) return false;
        const bool folder = nameLen && cd[p + 46 + nameLen - 1] == '/';
        if (!folder) {
            ++files;
            const uint32_t size = le32(&cd[p + 24]);
            if (size == 0xFFFFFFFFu) return false;
            id.crc = hex8(le32(&cd[p + 16]));
            id.size = size;
        }
        p += 46 + nameLen + extra + comment;
    }
    return files == 1;
}

RomId identify(const std::string& path) {
    RomId id;
    struct stat st;
    if (stat(path.c_str(), &st) != 0) return id;
    id.size = (uint64_t)st.st_size;
    FILE* f = fopen(path.c_str(), "rb");
    if (!f) return id;
    const size_t dot = path.rfind('.');
    const std::string ext = dot == std::string::npos ? "" : lower(path.substr(dot + 1));
    if (ext == "zip") {
        RomId inner;
        if (zipEntry(f, id.size, inner)) id = inner;
    } else if (ext != "cue" && ext != "m3u" && id.size <= kMaxCrcBytes) {
        if (!crcTable[1]) makeTable();
        uint32_t c = 0xFFFFFFFFu;
        static unsigned char buf[1 << 16];
        for (size_t n; (n = fread(buf, 1, sizeof(buf), f)) > 0;)
            for (size_t k = 0; k < n; ++k) c = crcTable[(c ^ buf[k]) & 0xFF] ^ (c >> 8);
        if (!ferror(f)) id.crc = hex8(c ^ 0xFFFFFFFFu);
    }
    fclose(f);
    return id;
}

std::string fileRegion(const std::string& name) {
    // No-Intro / Redump tags, then GoodTools' one-letter ones
    static const std::pair<const char*, const char*> kTags[] = {
        {"usa", "us"}, {"brazil", "br"}, {"europe", "eu"}, {"world", "wor"}, {"japan", "jp"}, {"france", "fr"},
        {"germany", "de"}, {"spain", "sp"}, {"italy", "it"}, {"korea", "kr"}, {"australia", "au"}, {"china", "cn"},
        {"u", "us"}, {"b", "br"}, {"e", "eu"}, {"w", "wor"}, {"j", "jp"}, {"ju", "jp"}, {"ue", "us"}};
    const std::string n = lower(name);
    for (size_t open = n.find('('); open != std::string::npos; open = n.find('(', open + 1)) {
        const size_t close = n.find(')', open);
        if (close == std::string::npos) break;
        const std::string tag = n.substr(open + 1, close - open - 1);
        const std::string first = tag.substr(0, tag.find(','));   // "(USA, Europe)": the first one
        for (const auto& [t, region] : kTags)
            if (first == t) return region;
    }
    return "";
}
