#include "system/apps.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>
#include <memory>

#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>
#include <zlib.h>

#include "config.h"
#include "util.h"

static const char* kManifest = "app.puppy";
constexpr size_t kMaxManifestBytes = 64 << 10;
constexpr size_t kMaxIconBytes = 1 << 20;
constexpr int kMaxIconSide = 1024;
constexpr uint64_t kSpareBytes = 8 << 20;     // left free on HOME after installing

// app.puppy: the first [ENTRY], in the launcher's own format
struct Manifest {
    std::string name, description, command, icon, version;
};

static Manifest parseManifest(const std::string& text) {
    Manifest m;
    std::string section;
    size_t pos = 0;
    while (pos <= text.size()) {
        size_t end = text.find('\n', pos);
        if (end == std::string::npos) end = text.size();
        const std::string line = trim(text.substr(pos, end - pos));
        pos = end + 1;
        if (line.empty() || line[0] == '#' || line[0] == ';') continue;
        if (line.front() == '[' && line.back() == ']') {
            if (section == "ENTRY") break;   // only the first entry describes the app
            section = upper(trim(line.substr(1, line.size() - 2)));
            continue;
        }
        const size_t eq = line.find('=');
        if (section != "ENTRY" || eq == std::string::npos) continue;
        const std::string key = upper(trim(line.substr(0, eq))), v = trim(line.substr(eq + 1));
        if (key == "NAME") m.name = v;
        else if (key == "DESCRIPTION") m.description = v;
        else if (key == "COMMAND") m.command = v;
        else if (key == "ICON") m.icon = v;
        else if (key == "VERSION") m.version = v;
    }
    return m;
}

// A folder name the card (FAT) and the launcher can take: no separators, nothing FAT refuses,
// not hidden, not "." or ".."
static bool validName(const std::string& s) {
    if (s.empty() || s.size() > 128 || s[0] == '.' || s.back() == ' ' || s.back() == '.') return false;
    for (unsigned char c : s)
        if (c < 0x20 || c == 0x7F || strchr("/\\:*?\"<>|", c)) return false;
    return true;
}

// For a zip with app.puppy at its root: a folder name from the app's NAME, which stays the same
// across versions (the zip's own name usually doesn't)
static std::string folderFromName(const std::string& name) {
    std::string out;
    for (unsigned char c : name) out += (c < 0x20 || c == 0x7F || strchr("/\\:*?\"<>|", c)) ? '-' : (char)c;
    while (!out.empty() && (out[0] == '.' || out[0] == ' ')) out.erase(0, 1);
    while (!out.empty() && (out.back() == ' ' || out.back() == '.')) out.pop_back();
    return out.substr(0, 128);
}

// Zip reading: stored and deflated entries, no zip64, no encryption
struct ZipEntry {
    std::string name;            // '/'-separated, as stored (backslashes turned into '/')
    uint16_t method = 0, flags = 0;
    uint32_t crc = 0, csize = 0, usize = 0, offset = 0;
    bool dir = false, link = false;
};

static uint16_t le16(const unsigned char* p) { return (uint16_t)(p[0] | p[1] << 8); }
static uint32_t le32(const unsigned char* p) { return (uint32_t)p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }

class Zip {
public:
    std::vector<ZipEntry> entries;
    std::string error;           // English, translated where it is shown

    ~Zip() { if (f) fclose(f); }

    bool open(const fs::path& path) {
        f = fopen(path.c_str(), "rb");
        if (!f || fseek(f, 0, SEEK_END) != 0) return fail("The zip can't be read");
        const long size = ftell(f);
        if (size < 22) return fail("Not a zip file");
        // End of central directory: the last 22 bytes, or up to 64 KB earlier with a comment
        const long tail = std::min<long>(size, 22 + 0xFFFF);
        std::vector<unsigned char> buf((size_t)tail);
        if (fseek(f, size - tail, SEEK_SET) != 0 || fread(buf.data(), 1, buf.size(), f) != buf.size())
            return fail("The zip can't be read");
        long eocd = -1;
        for (long i = tail - 22; i >= 0; --i)
            if (le32(&buf[(size_t)i]) == 0x06054b50) { eocd = i; break; }
        if (eocd < 0) return fail("Not a zip file, or a damaged one");
        const unsigned char* e = &buf[(size_t)eocd];
        const uint16_t count = le16(e + 10);
        const uint32_t cdSize = le32(e + 12), cdOffset = le32(e + 16);
        if (le16(e + 4) != 0 || le16(e + 6) != 0) return fail("The zip is split into parts");
        if (count == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF) return fail("Zips over 4 GB (zip64) aren't supported");
        if ((uint64_t)cdOffset + cdSize > (uint64_t)size) return fail("The zip is damaged");
        std::vector<unsigned char> cd(cdSize);
        if (fseek(f, (long)cdOffset, SEEK_SET) != 0 || fread(cd.data(), 1, cd.size(), f) != cd.size())
            return fail("The zip is damaged");
        size_t p = 0;
        for (uint16_t i = 0; i < count; ++i) {
            if (p + 46 > cd.size() || le32(&cd[p]) != 0x02014b50) return fail("The zip is damaged");
            const unsigned char* h = &cd[p];
            ZipEntry z;
            const uint16_t madeBy = le16(h + 4);
            z.flags = le16(h + 8);
            z.method = le16(h + 10);
            z.crc = le32(h + 16);
            z.csize = le32(h + 20);
            z.usize = le32(h + 24);
            const uint16_t nameLen = le16(h + 28), extraLen = le16(h + 30), commentLen = le16(h + 32);
            const uint32_t attrs = le32(h + 38);
            z.offset = le32(h + 42);
            if (p + 46 + nameLen > cd.size()) return fail("The zip is damaged");
            z.name.assign((const char*)h + 46, nameLen);
            std::replace(z.name.begin(), z.name.end(), '\\', '/');   // some Windows tools
            z.dir = !z.name.empty() && z.name.back() == '/';
            z.link = (madeBy >> 8) == 3 && ((attrs >> 16) & S_IFMT) == S_IFLNK;
            if (z.csize == 0xFFFFFFFF || z.usize == 0xFFFFFFFF || z.offset == 0xFFFFFFFF)
                return fail("Zips over 4 GB (zip64) aren't supported");
            entries.push_back(std::move(z));
            p += 46 + nameLen + extraLen + commentLen;
        }
        return true;
    }

    // Streams the entry's bytes to sink (which returns false to stop); checks size and CRC
    bool read(const ZipEntry& z, const std::function<bool(const unsigned char*, size_t)>& sink) {
        if (z.flags & 1) return fail("The zip is password protected");
        if (z.method != 0 && z.method != 8) return fail("The zip uses a compression other than Deflate: save it as a plain .zip");
        unsigned char h[30];
        if (fseek(f, (long)z.offset, SEEK_SET) != 0 || fread(h, 1, 30, f) != 30 || le32(h) != 0x04034b50)
            return fail("The zip is damaged");
        if (fseek(f, (long)z.offset + 30 + le16(h + 26) + le16(h + 28), SEEK_SET) != 0) return fail("The zip is damaged");
        uLong crc = crc32(0, nullptr, 0);
        uint64_t out = 0;
        unsigned char in[1 << 16], buf[1 << 16];
        uint32_t left = z.csize;
        if (z.method == 0) {
            if (z.csize != z.usize) return fail("The zip is damaged");
            while (left) {
                const size_t n = fread(in, 1, std::min<uint32_t>(left, sizeof in), f);
                if (n == 0) return fail("The zip is damaged");
                left -= (uint32_t)n;
                out += n;
                crc = crc32(crc, in, (uInt)n);
                if (!sink(in, n)) return false;
            }
        } else {
            z_stream s{};
            if (inflateInit2(&s, -MAX_WBITS) != Z_OK) return fail("The zip can't be unpacked");
            std::unique_ptr<z_stream, void (*)(z_stream*)> guard(&s, [](z_stream* x) { inflateEnd(x); });
            int ret = Z_OK;
            while (ret != Z_STREAM_END) {
                if (s.avail_in == 0) {
                    if (left == 0) return fail("The zip is damaged");
                    const size_t n = fread(in, 1, std::min<uint32_t>(left, sizeof in), f);
                    if (n == 0) return fail("The zip is damaged");
                    left -= (uint32_t)n;
                    s.next_in = in;
                    s.avail_in = (uInt)n;
                }
                s.next_out = buf;
                s.avail_out = sizeof buf;
                ret = inflate(&s, Z_NO_FLUSH);
                if (ret != Z_OK && ret != Z_STREAM_END) return fail("The zip is damaged");
                const size_t n = sizeof buf - s.avail_out;
                out += n;
                if (out > z.usize) return fail("The zip is damaged");   // more than it said: a zip bomb, or broken
                crc = crc32(crc, buf, (uInt)n);
                if (n && !sink(buf, n)) return false;
            }
        }
        if (out != z.usize || crc != z.crc) return fail("A file in the zip doesn't check out: the zip is damaged");
        return true;
    }

    bool readString(const ZipEntry& z, std::string& s, size_t max) {
        if (z.usize > max) return fail("A file in the zip is too big");
        s.clear();
        s.reserve(z.usize);
        return read(z, [&](const unsigned char* p, size_t n) { s.append((const char*)p, n); return true; });
    }

private:
    FILE* f = nullptr;
    bool fail(const char* why) { error = why; return false; }
};

// A path inside the app: relative, each part a name the card takes, nothing climbing out
static bool safeRelative(const std::string& rel) {
    if (rel.empty() || rel[0] == '/') return false;
    size_t start = 0;
    while (start < rel.size()) {
        size_t end = rel.find('/', start);
        if (end == std::string::npos) end = rel.size();
        const std::string part = rel.substr(start, end - start);
        if (part.empty() || part == "." || part == "..") return false;
        for (unsigned char c : part)
            if (c < 0x20 || c == 0x7F || strchr("\\:*?\"<>|", c)) return false;
        start = end + 1;
    }
    return true;
}

// Files macOS, Windows and editors add that aren't part of anyone's app
static bool junk(const std::string& name) {
    if (name.rfind("__MACOSX/", 0) == 0) return true;
    std::string path = name;
    while (!path.empty() && path.back() == '/') path.pop_back();
    const std::string base = lower(path.substr(path.find_last_of('/') + 1));
    return base.rfind("._", 0) == 0 || base == ".ds_store" || base == "thumbs.db" || base == "desktop.ini";
}

// The checks every entry of the app has to pass, at inspection and again when installing
static std::string checkEntry(const ZipEntry& e, const std::string& rel) {
    if (e.flags & 1) return tr("The zip is password protected");
    if (!e.dir && e.method != 0 && e.method != 8) return tr("The zip uses a compression other than Deflate: save it as a plain .zip");
    if (e.link) return trf("It contains a link (%s): zip the real files instead", rel);
    if (!safeRelative(e.dir ? rel.substr(0, rel.size() - 1) : rel)) return trf("It contains a file name the card can't take: %s", rel);
    return "";
}

static bool pngSize(const std::string& b, int& w, int& h) {
    if (b.size() < 24 || b.compare(0, 8, "\x89PNG\r\n\x1a\n", 8) != 0 || b.compare(12, 4, "IHDR") != 0) return false;
    const unsigned char* p = (const unsigned char*)b.data();
    w = (int)((uint32_t)p[16] << 24 | p[17] << 16 | p[18] << 8 | p[19]);
    h = (int)((uint32_t)p[20] << 24 | p[21] << 16 | p[22] << 8 | p[23]);
    return w > 0 && h > 0;
}

static AppItem inspectZip(const fs::path& zipPath) {
    AppItem it;
    it.path = zipPath.string();
    it.name = zipPath.stem().string();
    Zip z;
    if (!z.open(zipPath)) { it.error = tr(z.error); return it; }
    const ZipEntry* manifest = nullptr;
    int found = 0;
    for (const auto& e : z.entries) {
        if (e.dir || junk(e.name)) continue;
        if (e.name == kManifest) { manifest = &e; it.prefix = ""; found = 100; break; }   // at the root: that's it
        const size_t slash = e.name.find('/');
        if (slash != std::string::npos && e.name.compare(slash + 1, std::string::npos, kManifest) == 0) {
            manifest = &e;
            it.prefix = e.name.substr(0, slash + 1);
            ++found;
        }
    }
    if (!manifest) { it.error = tr("Not an app: there is no app.puppy in it"); return it; }
    if (found > 1 && found < 100) { it.error = tr("More than one app in one zip: give each its own zip"); return it; }
    std::string text;
    if (!z.readString(*manifest, text, kMaxManifestBytes)) { it.error = tr(z.error); return it; }
    const Manifest m = parseManifest(text);
    if (m.name.empty() || m.command.empty()) { it.error = tr("app.puppy needs a NAME and a COMMAND"); return it; }
    it.name = m.name;
    it.description = m.description;
    it.version = m.version;
    it.folder = it.prefix.empty() ? folderFromName(m.name) : it.prefix.substr(0, it.prefix.size() - 1);
    if (!validName(it.folder)) { it.error = trf("\"%s\" can't be a folder name on the card", it.folder); return it; }
    for (const auto& e : z.entries) {
        if (junk(e.name) || e.name.compare(0, it.prefix.size(), it.prefix) != 0) continue;
        const std::string rel = e.name.substr(it.prefix.size());
        if (rel.empty()) continue;
        it.error = checkEntry(e, rel);
        if (!it.error.empty()) return it;
        it.bytes += e.usize;
    }
    if (!m.icon.empty() && m.icon[0] != '/') {
        std::string icon = m.icon;
        if (icon.rfind("./", 0) == 0) icon.erase(0, 2);
        const ZipEntry* e = nullptr;
        for (const auto& x : z.entries) if (!x.dir && x.name == it.prefix + icon) e = &x;
        if (!e) { it.error = trf("ICON=%s isn't in the zip", m.icon); return it; }
        std::string data;
        int w = 0, h = 0;
        if (!z.readString(*e, data, kMaxIconBytes) || !pngSize(data, w, h) || w > kMaxIconSide || h > kMaxIconSide) {
            it.error = tr("The icon has to be a PNG, at most 1024 x 1024");
            return it;
        }
    }
    std::error_code ec;
    it.update = fs::exists(fs::path(cfg.installedApps) / it.folder / kManifest, ec);
    return it;
}

static bool byName(const AppItem& a, const AppItem& b) { return lower(a.name) < lower(b.name); }

std::vector<AppItem> appZips() {
    std::vector<AppItem> items;
    std::error_code ec;
    for (fs::directory_iterator d(cfg.installedApps, ec), end; !ec && d != end; d.increment(ec)) {
        const std::string n = d->path().filename().string();
        std::error_code e2;
        if (n.empty() || n[0] == '.' || lower(d->path().extension().string()) != ".zip" || !d->is_regular_file(e2)) continue;
        items.push_back(inspectZip(d->path()));
    }
    std::sort(items.begin(), items.end(), byName);
    return items;
}

std::vector<AppItem> installedApps() {
    std::vector<AppItem> items;
    std::error_code ec;
    for (fs::directory_iterator d(cfg.installedApps, ec), end; !ec && d != end; d.increment(ec)) {
        const std::string n = d->path().filename().string();
        std::error_code e2;
        if (n.empty() || n[0] == '.' || !d->is_directory(e2)) continue;
        std::ifstream in(d->path() / kManifest);
        if (!in) continue;
        std::string text;
        text.resize(kMaxManifestBytes);
        in.read(&text[0], (std::streamsize)text.size());
        text.resize((size_t)in.gcount());
        const Manifest m = parseManifest(text);
        AppItem it;
        it.path = d->path().string();
        it.folder = n;
        it.name = m.name.empty() ? n : m.name;
        it.description = m.description;
        it.version = m.version;
        items.push_back(std::move(it));
    }
    std::sort(items.begin(), items.end(), byName);
    return items;
}

// Leftovers of an install the power cut: a half-unpacked folder goes, a replaced copy comes back
void recoverApps() {
    std::error_code ec;
    const fs::path apps = cfg.installedApps;
    std::vector<fs::path> names;
    for (fs::directory_iterator d(apps, ec), end; !ec && d != end; d.increment(ec)) {
        const std::string n = d->path().filename().string();
        if (n.rfind(".old-", 0) == 0 || n.rfind(".install-", 0) == 0) names.push_back(d->path());
    }
    if (names.empty()) return;
    for (const auto& p : names) {   // first put back any app that was set aside...
        const std::string n = p.filename().string();
        if (n.rfind(".old-", 0) != 0) continue;
        const fs::path app = apps / n.substr(5);
        if (fs::exists(app, ec)) fs::remove_all(p, ec);
        else fs::rename(p, app, ec);
    }
    for (const auto& p : names) {   // ...then drop half-unpacked ones, giving back the data they held
        const std::string n = p.filename().string();
        if (n.rfind(".install-", 0) != 0) continue;
        const fs::path app = apps / n.substr(9);
        if (fs::exists(p / "data", ec) && fs::exists(app, ec) && !fs::exists(app / "data", ec)) fs::rename(p / "data", app / "data", ec);
        fs::remove_all(p, ec);
    }
    sync();
}

std::string installApp(const AppItem& it, const std::function<void(float)>& progress) {
    Zip z;
    if (!z.open(it.path)) return tr(z.error);
    const fs::path apps = cfg.installedApps, tmp = apps / (".install-" + it.folder), dest = apps / it.folder;
    std::error_code ec;
    uint64_t total = 0, done = 0;
    std::vector<const ZipEntry*> files;
    for (const auto& e : z.entries) {
        if (junk(e.name) || e.name.compare(0, it.prefix.size(), it.prefix) != 0 || e.name.size() == it.prefix.size()) continue;
        const std::string why = checkEntry(e, e.name.substr(it.prefix.size()));   // the zip may have changed since
        if (!why.empty()) return why;
        files.push_back(&e);
        total += e.usize;
    }
    struct statvfs vfs;
    if (statvfs(apps.c_str(), &vfs) == 0 && (uint64_t)vfs.f_bavail * vfs.f_frsize < total + kSpareBytes)
        return trf("Not enough space on HOME (%s needed)", humanSize((total + kSpareBytes) >> 10));
    fs::remove_all(tmp, ec);
    if (!fs::create_directories(tmp, ec)) return tr("Can't create a folder in HOME/apps");
    std::string err;
    auto last = std::chrono::steady_clock::now();   // for the whole install: many small files must show progress too
    for (const ZipEntry* e : files) {
        const fs::path out = tmp / e->name.substr(it.prefix.size());
        if (e->dir) { fs::create_directories(out, ec); continue; }
        fs::create_directories(out.parent_path(), ec);
        FILE* f = fopen(out.c_str(), "wb");
        if (!f) { err = trf("Can't write %s", out.filename().string()); break; }
        bool writeOk = true;
        const bool ok = z.read(*e, [&](const unsigned char* p, size_t n) {
            if (fwrite(p, 1, n, f) != n) return writeOk = false;
            done += n;
            const auto now = std::chrono::steady_clock::now();
            if (now - last > std::chrono::milliseconds(200)) {
                last = now;
                progress(total ? (float)done / (float)total : 1.0f);
            }
            return true;
        });
        if (fclose(f) != 0) writeOk = false;
        if (!writeOk) { err = tr("Couldn't write to the card (is it full?)"); break; }
        if (!ok) { err = tr(z.error); break; }
    }
    if (err.empty()) progress(1.0f);   // what is left (swap, and sync to the card) can take a moment
    if (err.empty()) {
        // The old copy aside, its data/ into the new one, the new one in place: recoverApps() fixes a cut at any step
        const fs::path old = apps / (".old-" + it.folder);
        fs::remove_all(old, ec);
        ec.clear();
        if (fs::exists(dest)) fs::rename(dest, old, ec);
        if (ec) err = tr("Can't replace the installed copy");
        else if (fs::exists(old / "data")) {
            fs::remove_all(tmp / "data", ec);   // a data/ in the zip is only the starting point
            ec.clear();
            fs::rename(old / "data", tmp / "data", ec);
            if (ec) {
                std::error_code ec2;
                fs::rename(old, dest, ec2);
                err = tr("Can't keep the app's data");
            }
        }
        if (err.empty()) {
            fs::rename(tmp, dest, ec);
            if (ec) {
                std::error_code ec2;
                fs::rename(tmp / "data", old / "data", ec2);
                fs::rename(old, dest, ec2);
                err = tr("Can't move the app into place");
            } else {
                fs::remove_all(old, ec);
            }
        }
    }
    if (!err.empty()) {
        fs::remove_all(tmp, ec);
        sync();
        return err;
    }
    sync();                       // HOME is FAT: onto the card before anyone holds the power button
    fs::remove(it.path, ec);      // installed: the zip has done its job
    sync();
    return "";
}

std::string uninstallApp(const AppItem& it) {
    std::error_code ec;
    fs::remove_all(it.path, ec);
    // An autolaunch entry pointing into the app would now fail at every boot
    std::ifstream in(cfg.autoStartFile);
    const std::string text((std::istreambuf_iterator<char>(in)), {});
    in.close();
    if (text.find(it.path + "'") != std::string::npos || text.find(it.path + "/") != std::string::npos)
        fs::remove(cfg.autoStartFile, ec);
    sync();
    return fs::exists(it.path, ec) ? trf("Couldn't remove all of %s", it.folder) : "";
}
