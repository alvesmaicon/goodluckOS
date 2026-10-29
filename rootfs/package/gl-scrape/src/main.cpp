// gl-scrape: names, descriptions, pictures and videos of the games in the ROM folders, from
// ScreenScraper, written to each folder's gamelist.xml (and gamelist.<language>.xml), which the
// launcher reads. System Settings -> System -> Scraper runs it; it also runs from a shell.
#include <algorithm>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <map>
#include <set>
#include <string>
#include <vector>

#include <sys/stat.h>
#include <unistd.h>

#include "credentials.h"   // written at build time by credentials.sh
#include "fetch.h"
#include "gamelist.h"
#include "json.h"
#include "roms.h"
#include "screenscraper.h"

// The software's ScreenScraper credentials, kept out of the binary's plain strings
template <size_t N> struct Hidden { unsigned char b[N]; };
template <size_t N> constexpr Hidden<N> hide(const unsigned char (&s)[N]) {
    Hidden<N> h{};
    for (size_t i = 0; i < N; ++i) h.b[i] = (unsigned char)(s[i] ^ (0xA5 + 7 * i));
    return h;
}
template <size_t N> static std::string reveal(const Hidden<N>& h) {
    std::string s;
    for (size_t i = 0; i + 1 < N; ++i) s += (char)(h.b[i] ^ (unsigned char)(0xA5 + 7 * i));
    return s;
}
static constexpr unsigned char kDevIdBytes[] = {SS_DEVID_BYTES 0};
static constexpr unsigned char kDevPasswordBytes[] = {SS_DEVPASSWORD_BYTES 0};
static constexpr auto kDevId = hide(kDevIdBytes);
static constexpr auto kDevPassword = hide(kDevPasswordBytes);

// The folders of apps.puppy's systems, with ScreenScraper's system and the extensions Puppy lists
struct System {
    const char* folder;
    int id;
    const char* name;
    const char* exts;
};
static const System kSystems[] = {
    {"gb", 9, "Game Boy", "gb,zip,7z"},
    {"gbc", 10, "Game Boy Color", "gbc,gb,zip,7z"},
    {"gba", 12, "Game Boy Advance", "gba,zip,7z"},
    {"nes", 3, "NES", "nes,fds,unf,unif,zip,7z"},
    {"famicom", 3, "Famicom", "nes,fds,unf,unif,zip,7z"},
    {"snes", 4, "Super Nintendo", "sfc,smc,zip,7z"},
    {"sfc", 4, "Super Famicom", "sfc,smc,zip,7z"},
    {"genesis", 1, "Sega Genesis", "md,smd,gen,bin,zip,7z"},
    {"megadrive", 1, "Mega Drive", "md,smd,gen,bin,zip,7z"},
    {"sms", 2, "Master System", "sms,zip,7z"},
    {"mastersystem", 2, "Master System", "sms,zip,7z"},
    {"gg", 21, "Game Gear", "gg,zip,7z"},
    {"gamegear", 21, "Game Gear", "gg,zip,7z"},
    {"segacd", 20, "Sega CD", "cue,chd,iso"},
    {"psx", 57, "PlayStation", "bin,cue,chd,m3u,iso"},
    {"psp", 61, "PSP", "iso,cso,chd"},
};

static const char* kHome = "/home/player";

struct Options {
    std::string config = std::string(kHome) + "/.config/gl-scrape/settings";
    std::string cache = std::string(kHome) + "/.cache/gl-scrape";
    std::string status;
    std::vector<std::string> roots = {std::string(kHome) + "/roms", "/media/external/roms"};
    std::vector<std::string> folders;   // only these (default: all but skip)
    std::set<std::string> skip;
    std::string lang = "en";
    std::string image = "mixrbv2";      // ScreenScraper's media type, or none
    std::string region = "auto";
    bool video = false, all = false;
    int width = 400, height = 300;
    std::string user, password;
};

static volatile sig_atomic_t stopping = 0;
static void onSignal(int) { stopping = 1; }

static std::vector<std::string> split(const std::string& s, char sep) {
    std::vector<std::string> out;
    for (size_t p = 0; p <= s.size();) {
        size_t q = s.find(sep, p);
        if (q == std::string::npos) q = s.size();
        if (q > p) out.push_back(s.substr(p, q - p));
        p = q + 1;
    }
    return out;
}

static bool exists(const std::string& path) {
    struct stat st;
    return stat(path.c_str(), &st) == 0;
}

static void makeDirs(const std::string& path) {
    for (size_t p = 1; p <= path.size(); ++p)
        if (p == path.size() || path[p] == '/') mkdir(path.substr(0, p).c_str(), 0755);
}

// The settings file System Settings writes: key=value lines
static void readSettings(Options& o) {
    std::ifstream in(o.config);
    for (std::string line; std::getline(in, line);) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        const size_t eq = line.find('=');
        if (eq == std::string::npos || line[0] == '#') continue;
        const std::string k = line.substr(0, eq), v = line.substr(eq + 1);
        if (k == "user") o.user = v;
        else if (k == "password") o.password = v;
        else if (k == "image") o.image = v;
        else if (k == "video") o.video = v == "1";
        else if (k == "region") o.region = v;
        else if (k == "games") o.all = v == "all";
        else if (k == "skip") for (const std::string& f : split(v, ',')) o.skip.insert(f);
    }
}

// --- progress, for System Settings ---------------------------------------------------------------

struct Progress {
    std::string state = "running", message, detail, system, game, requests;
    int step = 0, steps = 0, index = 0, total = 0, found = 0, notFound = 0, failed = 0, skipped = 0;
};

static void report(const Options& o, const Progress& p) {
    if (o.status.empty()) return;
    const std::string tmp = o.status + ".tmp";
    FILE* f = fopen(tmp.c_str(), "w");
    if (!f) return;
    fprintf(f, "state=%s\npid=%d\nmessage=%s\ndetail=%s\nsystem=%s\nstep=%d\nsteps=%d\nindex=%d\ntotal=%d\n"
               "game=%s\nfound=%d\nnotfound=%d\nfailed=%d\nskipped=%d\nrequests=%s\n",
            p.state.c_str(), (int)getpid(), p.message.c_str(), p.detail.c_str(), p.system.c_str(), p.step, p.steps,
            p.index, p.total, p.game.c_str(), p.found, p.notFound, p.failed, p.skipped, p.requests.c_str());
    fclose(f);
    rename(tmp.c_str(), o.status.c_str());
}

static int finish(const Options& o, Progress& p, const std::string& state, const std::string& message, int code) {
    p.state = state;
    p.message = message;
    report(o, p);
    if (!message.empty()) fprintf(stderr, "%s%s%s\n", message.c_str(), p.detail.empty() ? "" : ": ", p.detail.c_str());
    return code;
}

// --- choosing from a record ----------------------------------------------------------------------

static bool latin(const std::string& s) {
    // CJK, kana and hangul start with 0xE3-0xED in UTF-8: the interface fonts don't have them
    for (unsigned char c : s)
        if (c >= 0xE3 && c <= 0xED) return false;
    return true;
}

static std::string pick(const Json& byRegion, const std::vector<std::string>& order, bool latinOnly = false) {
    for (const std::string& r : order) {
        const std::string& t = byRegion[r].text;
        if (!t.empty() && (!latinOnly || latin(t))) return t;
    }
    for (const auto& f : byRegion.fields)
        if (!f.second.text.empty() && (!latinOnly || latin(f.second.text))) return f.second.text;
    return "";
}

// ScreenScraper's dates are 1991-08-23, 1991-08 or 1991; EmulationStation's 19910823T000000
static std::string esDate(const std::string& d) {
    if (d.size() < 4) return "";
    std::string out = d.substr(0, 4);
    out += d.size() >= 7 ? d.substr(5, 2) : "01";
    out += d.size() >= 10 ? d.substr(8, 2) : "01";
    return out + "T000000";
}

static std::string esRating(const std::string& outOf20) {
    if (outOf20.empty()) return "";
    char b[16];
    snprintf(b, sizeof(b), "%g", std::min(20, std::max(0, atoi(outOf20.c_str()))) / 20.0);
    return b;
}

// The media of one of these types, in the regions' order
static const Json* media(const Json& rec, const std::vector<std::string>& types, const std::vector<std::string>& regions) {
    for (const std::string& t : types) {
        const Json* any = nullptr;
        for (const std::string& r : regions)
            for (const Json& m : rec["medias"].items)
                if (m["type"].text == t && m["region"].text == r) return &m;
        for (const Json& m : rec["medias"].items)
            if (m["type"].text == t && !any) any = &m;
        if (any) return any;
    }
    return nullptr;
}

static std::vector<std::string> imageTypes(const std::string& image) {
    if (image == "box-2D") return {"box-2D", "box-3D", "ss"};
    if (image == "box-3D") return {"box-3D", "box-2D", "ss"};
    if (image == "ss") return {"ss", "sstitle", "box-2D"};
    if (image == "sstitle") return {"sstitle", "ss", "box-2D"};
    if (image == "wheel") return {"wheel-hd", "wheel", "box-2D"};
    return {"mixrbv2", "mixrbv1", "box-2D", "ss"};
}

// The language's region, for names (pt -> br)
static std::string langRegion(const std::string& lang) {
    if (lang == "pt") return "br";
    if (lang == "es") return "sp";
    return lang;
}

// --- one system -----------------------------------------------------------------------------------

// Files a .cue or .m3u points to are parts of another entry, not games
static std::set<std::string> referenced(const std::string& dir, const std::vector<std::string>& files) {
    std::set<std::string> out;
    for (const std::string& f : files) {
        const std::string ext = f.size() > 4 ? f.substr(f.size() - 4) : "";
        if (ext != ".cue" && ext != ".m3u" && ext != ".CUE" && ext != ".M3U") continue;
        std::ifstream in(dir + "/" + f);
        for (std::string line; std::getline(in, line);) {
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (ext == ".cue" || ext == ".CUE") {
                const size_t a = line.find('"'), b = line.rfind('"');
                if (line.find("FILE") != std::string::npos && a != std::string::npos && b > a) out.insert(line.substr(a + 1, b - a - 1));
            } else if (!line.empty() && line[0] != '#') {
                out.insert(line.substr(line.find_last_of('/') + 1));
            }
        }
    }
    return out;
}

struct Folder {
    const System* sys;
    std::string dir;
    std::vector<std::string> roms;
};

static std::vector<Folder> folders(const Options& o, bool withSkipped = false) {
    std::vector<Folder> out;
    for (const std::string& root : o.roots)
        for (const System& s : kSystems) {
            if (!o.folders.empty() && std::find(o.folders.begin(), o.folders.end(), s.folder) == o.folders.end()) continue;
            if (!withSkipped && o.skip.count(s.folder)) continue;
            Folder f{&s, root + "/" + s.folder, {}};
            std::vector<std::string> files = romFiles(f.dir, split(s.exts, ','));
            const std::set<std::string> parts = referenced(f.dir, files);
            for (const std::string& r : files)
                if (!parts.count(r)) f.roms.push_back(r);
            if (!f.roms.empty()) out.push_back(std::move(f));
        }
    return out;
}

static bool fileThere(const std::string& dir, const std::string& rel) {
    if (rel.empty()) return false;
    const std::string p = rel.compare(0, 2, "./") == 0 ? rel.substr(2) : rel;
    return exists(p[0] == '/' ? p : dir + "/" + p);
}

// What this run would still add to the game
static bool needed(const Options& o, const Folder& f, const Gamelist& main, const Gamelist& local, const std::string& rom) {
    if (o.all || !main.has(rom)) return true;
    if (main.get(rom, "name").empty() || main.get(rom, "desc").empty()) return true;
    if (o.image != "none" && !fileThere(f.dir, main.get(rom, "image"))) return true;
    if (o.video && !fileThere(f.dir, main.get(rom, "video"))) return true;
    return o.lang != "en" && local.get(rom, "desc").empty();
}

// By name and size, so a disc image is only read through (its CRC) the first time
static std::string cacheKey(const std::string& rom, uint64_t size) {
    std::string key = stem(rom);
    for (char& c : key)
        if (strchr("\\/:*?\"<>|", c)) c = '_';
    return key + "-" + std::to_string(size) + ".json";
}

static bool readFile(const std::string& path, std::string& out) {
    std::ifstream in(path, std::ios::binary);
    if (!in) return false;
    out.assign((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    return true;
}

static void writeFile(const std::string& path, const std::string& text) {
    const std::string tmp = path + ".tmp";
    if (FILE* f = fopen(tmp.c_str(), "wb")) {
        const bool ok = fwrite(text.data(), 1, text.size(), f) == text.size();
        if (fclose(f) == 0 && ok) rename(tmp.c_str(), path.c_str());
        else remove(tmp.c_str());
    }
}

// Downloads a media file next to the ROMs unless it's there; the gamelist's path for it
static std::string fetchMedia(ScreenScraper& ss, const Options& o, const Folder& f, const Json* m, const char* sub,
                              const std::string& rom, const std::string& now, bool picture, Progress& p) {
    if (!m) return "";
    std::string ext = (*m)["format"].text;
    if (ext.empty()) ext = picture ? "png" : "mp4";
    const std::string rel = std::string("./media/") + sub + "/" + stem(rom) + "." + ext;
    const std::string path = f.dir + "/" + rel.substr(2);
    if (!o.all && exists(path)) return rel;
    if (!o.all && fileThere(f.dir, now)) return now;
    makeDirs(f.dir + "/media/" + sub);
    const std::string url = ss.mediaUrl((*m)["url"].text, picture ? o.width : 0, picture ? o.height : 0);
    for (int attempt = 0; attempt < 3; ++attempt) {
        const Fetched r = download(url, path, picture ? 60 : 300);
        if (r.status == 200) return rel;
        p.detail = r.status ? r.body.substr(0, r.body.find('\n')).substr(0, 160) : r.error;
        if (r.status != 429 && r.status < 500) break;
        sleep(5);
    }
    return "";
}

// --- main -----------------------------------------------------------------------------------------

static void usage() {
    puts("usage: gl-scrape [options] [folder...]\n"
         "  Scrapes the ROM folders (gb, gba, snes...) under /home/player/roms and /media/external/roms from\n"
         "  ScreenScraper into their gamelist.xml. Options default to the settings file.\n"
         "  --check          the account's quota, nothing scraped\n"
         "  --systems        the folders with games: folder, name, games, complete\n"
         "  --all            every game, not only what's missing\n"
         "  --image TYPE     mixrbv2, box-2D, box-3D, ss, sstitle, wheel or none\n"
         "  --video          gameplay clips too (--no-video)\n"
         "  --region R       auto (the file name's tags), br, us, eu, jp or wor\n"
         "  --lang CODE      descriptions in this language too (gamelist.<code>.xml), e.g. pt\n"
         "  --size WxH       pictures' largest size (400x300)\n"
         "  --status FILE    progress as key=value lines, for System Settings\n"
         "  --config FILE    settings (/home/player/.config/gl-scrape/settings)\n"
         "  --roots A:B      ROM roots\n"
         "  --cache DIR      answers already received (/home/player/.cache/gl-scrape)\n"
         "SS_DEVID, SS_DEVPASSWORD, SS_USER and SS_PASSWORD in the environment replace the credentials.");
}

int main(int argc, char** argv) {
    Options o;
    for (int i = 1; i < argc; ++i)
        if (!strcmp(argv[i], "--config") && i + 1 < argc) o.config = argv[++i];
    readSettings(o);
    bool check = false, list = false;
    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        const bool more = i + 1 < argc;
        if (a == "--check") check = true;
        else if (a == "--systems") list = true;
        else if (a == "--all") o.all = true;
        else if (a == "--video") o.video = true;
        else if (a == "--no-video") o.video = false;
        else if (a == "--image" && more) o.image = argv[++i];
        else if (a == "--region" && more) o.region = argv[++i];
        else if (a == "--lang" && more) o.lang = std::string(argv[++i]).substr(0, 2);
        else if (a == "--status" && more) o.status = argv[++i];
        else if (a == "--config" && more) ++i;
        else if (a == "--cache" && more) o.cache = argv[++i];
        else if (a == "--roots" && more) o.roots = split(argv[++i], ':');
        else if (a == "--size" && more) sscanf(argv[++i], "%dx%d", &o.width, &o.height);
        else if (a == "-h" || a == "--help") { usage(); return 0; }
        else if (!a.empty() && a[0] != '-') o.folders.push_back(a);
        else { usage(); return 2; }
    }
    if (o.lang.empty()) o.lang = "en";

    if (list) {
        for (const Folder& f : folders(o, true)) {
            Gamelist main, local;
            main.load(f.dir + "/gamelist.xml");
            if (o.lang != "en") local.load(f.dir + "/gamelist." + o.lang + ".xml");
            int complete = 0;
            for (const std::string& r : f.roms) complete += !needed(o, f, main, local, r);
            printf("%s\t%s\t%zu\t%d\n", f.sys->folder, f.sys->name, f.roms.size(), complete);
        }
        return 0;
    }

    Account acc{reveal(kDevId), reveal(kDevPassword), o.user, o.password};
    for (auto [var, field] : {std::pair<const char*, std::string*>{"SS_DEVID", &acc.devId}, {"SS_DEVPASSWORD", &acc.devPassword},
                              {"SS_USER", &acc.user}, {"SS_PASSWORD", &acc.password}})
        if (const char* v = getenv(var)) *field = v;

    signal(SIGTERM, onSignal);
    signal(SIGINT, onSignal);
    signal(SIGHUP, onSignal);
    Progress p;
    report(o, p);
    if (acc.devId.empty()) return finish(o, p, "error", "This build has no ScreenScraper developer credentials", 1);
    if (acc.user.empty() || acc.password.empty()) return finish(o, p, "error", "No ScreenScraper account", 1);

    ScreenScraper ss(acc);
    Quota q;
    Answer a = ss.userInfo(q);
    p.detail = ss.detail;
    if (a != Answer::Ok) return finish(o, p, "error", describe(a), 1);
    p.requests = std::to_string(q.today) + "/" + std::to_string(q.perDay);
    if (check) {
        printf("user=%s\nlevel=%d\nthreads=%d\nrequests=%d/%d\nper_minute=%d\nunknown=%d/%d\n", q.user.c_str(), q.level,
               q.threads, q.today, q.perDay, q.perMinute, q.unknownToday, q.unknownPerDay);
        p.game = q.user;
        return finish(o, p, "done", "", 0);
    }

    const std::vector<Folder> work = folders(o);
    p.steps = (int)work.size();
    int offline = 0;
    for (const Folder& f : work) {
        ++p.step;
        p.system = f.sys->name;
        p.total = (int)f.roms.size();
        p.index = 0;
        const std::string mainPath = f.dir + "/gamelist.xml", localPath = f.dir + "/gamelist." + o.lang + ".xml";
        Gamelist main, local;
        main.load(mainPath);
        if (o.lang != "en") local.load(localPath);
        const std::string cacheDir = o.cache + "/" + std::to_string(f.sys->id);
        makeDirs(cacheDir);
        auto save = [&] {
            main.save(mainPath);
            if (o.lang != "en") local.save(localPath);
        };

        for (const std::string& rom : f.roms) {
            if (stopping) break;
            ++p.index;
            p.game = stem(rom);
            if (!needed(o, f, main, local, rom)) {
                ++p.skipped;
                continue;
            }
            report(o, p);

            struct stat st;
            const std::string path = f.dir + "/" + rom;
            const std::string cached = cacheDir + "/" + cacheKey(rom, stat(path.c_str(), &st) == 0 ? (uint64_t)st.st_size : 0);
            Json rec;
            std::string text;
            if (readFile(cached, text) && Json::parse(text, rec)) {
                // an unknown game is asked again after a week
                if (rec["notfound"].text == "true" && stat(cached.c_str(), &st) == 0 && time(nullptr) - st.st_mtime > 7 * 86400)
                    rec = Json();
            } else {
                rec = Json();
            }
            if (rec.isNull()) {
                const RomId id = identify(path);
                a = Answer::Busy;
                for (int attempt = 0; attempt < 3 && (a == Answer::Busy || a == Answer::Network) && !stopping; ++attempt) {
                    if (attempt) sleep(a == Answer::Busy ? 10 : 5);
                    a = ss.gameInfo(f.sys->id, rom, id, rec);
                }
                p.detail = ss.detail;
                if (a == Answer::Ok || a == Answer::NotFound) {
                    ++q.today;      // ScreenScraper counts both
                    p.requests = std::to_string(q.today) + "/" + std::to_string(q.perDay);
                }
                if (fatal(a)) {
                    save();
                    return finish(o, p, "error", describe(a), 1);
                }
                if (a == Answer::Network && ++offline >= 3) {
                    save();
                    return finish(o, p, "error", describe(a), 1);
                }
                if (a == Answer::NotFound) {
                    writeFile(cached, "{\"notfound\":true}");
                    ++p.notFound;
                    continue;
                }
                if (a != Answer::Ok) {
                    ++p.failed;
                    continue;
                }
                offline = 0;
                writeFile(cached, rec.dump());
            }
            if (rec["notfound"].text == "true") {
                ++p.notFound;
                continue;
            }

            // the regions to prefer for names, dates and pictures
            std::vector<std::string> regions;
            const std::string own = o.region == "auto" ? fileRegion(rom) : o.region;
            if (!own.empty()) regions.push_back(own);
            if (o.region == "auto" && o.lang == "pt") regions.push_back("br");
            for (const char* r : {"wor", "us", "eu", "ss", "jp"}) regions.push_back(r);

            std::string image, video;
            if (o.image != "none")
                image = fetchMedia(ss, o, f, media(rec, imageTypes(o.image), regions), "images", rom, main.get(rom, "image"), true, p);
            if (o.video)
                video = fetchMedia(ss, o, f, media(rec, {"video-normalized", "video"}, regions), "videos", rom, main.get(rom, "video"), false, p);

            const std::string date = esDate(pick(rec["dates"], regions));
            std::string desc = rec["synopsis"]["en"].text;
            if (desc.empty()) desc = pick(rec["synopsis"], {o.lang});
            std::string genre = rec["genre"]["en"].text;
            if (genre.empty()) genre = pick(rec["genre"], {o.lang});
            const std::string players = rec["players"].text;
            main.set(rom, {{"name", pick(rec["names"], regions, true)}, {"desc", desc}, {"image", image}, {"video", video},
                           {"releasedate", date}, {"developer", rec["developer"].text}, {"publisher", rec["publisher"].text},
                           {"genre", genre}, {"players", players}, {"rating", esRating(rec["rating"].text)}},
                     o.all);
            if (o.lang != "en") {
                const std::string ownDesc = rec["synopsis"][o.lang].text, ownGenre = rec["genre"][o.lang].text;
                const std::string ownName = rec["names"][langRegion(o.lang)].text;
                if (!ownDesc.empty() || !ownGenre.empty() || !ownName.empty())
                    local.set(rom, {{"name", ownName}, {"desc", ownDesc}, {"genre", ownGenre.empty() ? genre : ownGenre},
                                    {"releasedate", date}, {"players", players}},
                              o.all);
            }
            ++p.found;
            if (p.found % 10 == 0) save();
        }
        save();
        if (stopping) return finish(o, p, "stopped", "Stopped", 0);
    }
    p.game.clear();
    return finish(o, p, "done", "", 0);
}
