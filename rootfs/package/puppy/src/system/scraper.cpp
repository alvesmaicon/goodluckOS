#include "system/scraper.h"

#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <fstream>

#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include "i18n.h"
#include "util.h"

static const char* kDir = "/home/player/.config/gl-scrape";
static const char* kSettings = "/home/player/.config/gl-scrape/settings";
static const char* kStatus = "/tmp/gl-scrape.status";
static const char* kCheck = "/tmp/gl-scrape-check.status";

ScraperSettings ScraperSettings::load() {
    ScraperSettings s;
    std::ifstream in(kSettings);
    for (std::string line; std::getline(in, line);) {
        const size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        const std::string k = line.substr(0, eq), v = line.substr(eq + 1);
        if (k == "user") s.user = v;
        else if (k == "password") s.password = v;
        else if (k == "image") s.image = v;
        else if (k == "video") s.video = v == "1";
        else if (k == "region") s.region = v;
        else if (k == "games") s.all = v == "all";
        else if (k == "skip") {
            for (size_t p = 0; p < v.size();) {
                size_t q = v.find(',', p);
                if (q == std::string::npos) q = v.size();
                if (q > p) s.skip.push_back(v.substr(p, q - p));
                p = q + 1;
            }
        }
    }
    return s;
}

void ScraperSettings::save() const {
    mkdir("/home/player/.config", 0755);
    mkdir(kDir, 0755);
    std::string skipped;
    for (const std::string& f : skip) skipped += (skipped.empty() ? "" : ",") + f;
    const std::string tmp = std::string(kSettings) + ".tmp";
    {
        std::ofstream out(tmp);
        out << "user=" << user << "\npassword=" << password << "\nimage=" << image << "\nvideo=" << (video ? 1 : 0)
            << "\nregion=" << region << "\ngames=" << (all ? "all" : "missing") << "\nskip=" << skipped << "\n";
    }
    rename(tmp.c_str(), kSettings);
}

static std::string language() {
    const std::string code = i18n::current();
    return code.empty() ? "en" : code.substr(0, 2);
}

std::vector<ScraperFolder> scraperFolders() {
    std::vector<ScraperFolder> out;
    const std::string cmd = "gl-scrape --systems --lang " + language() + " 2>/dev/null";
    FILE* p = popen(cmd.c_str(), "r");
    if (!p) return out;
    char line[512];
    while (fgets(line, sizeof(line), p)) {
        ScraperFolder f;
        char folder[64], name[128];
        if (sscanf(line, "%63[^\t]\t%127[^\t]\t%d\t%d", folder, name, &f.games, &f.complete) != 4) continue;
        f.folder = folder;
        f.name = name;
        out.push_back(f);
    }
    pclose(p);
    return out;
}

static ScraperRun readStatus(const char* path) {
    ScraperRun r;
    std::ifstream in(path);
    for (std::string line; std::getline(in, line);) {
        const size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        const std::string k = line.substr(0, eq), v = line.substr(eq + 1);
        const int n = atoi(v.c_str());
        if (k == "state") r.state = v;
        else if (k == "message") r.message = v;
        else if (k == "detail") r.detail = v;
        else if (k == "system") r.system = v;
        else if (k == "game") r.game = v;
        else if (k == "requests") r.requests = v;
        else if (k == "pid") r.pid = n;
        else if (k == "step") r.step = n;
        else if (k == "steps") r.steps = n;
        else if (k == "index") r.index = n;
        else if (k == "total") r.total = n;
        else if (k == "found") r.found = n;
        else if (k == "notfound") r.notFound = n;
        else if (k == "failed") r.failed = n;
        else if (k == "skipped") r.skipped = n;
    }
    // a run killed with Puppy (an app was opened) never wrote its end
    if (r.state == "running" && !r.running()) r.state = "stopped";
    return r;
}

bool ScraperRun::running() const {
    return state == "running" && pid > 0 && (kill(pid, 0) == 0 || errno == EPERM);
}

ScraperRun ScraperRun::read() { return readStatus(kStatus); }
ScraperRun ScraperRun::readCheck() { return readStatus(kCheck); }

// Detached: its own session, so a stop takes its curl along, and init reaps it
static void spawn(const std::vector<std::string>& args, const char* status) {
    remove(status);
    const pid_t child = fork();
    if (child == 0) {
        if (fork() == 0) {
            setsid();
            const int log = open("/tmp/gl-scrape.log", O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (log >= 0) {
                dup2(log, 1);
                dup2(log, 2);
                close(log);
            }
            std::vector<char*> argv;
            for (const std::string& a : args) argv.push_back(const_cast<char*>(a.c_str()));
            argv.push_back(nullptr);
            execvp("gl-scrape", argv.data());
            _exit(127);
        }
        _exit(0);
    }
    if (child > 0) waitpid(child, nullptr, 0);
}

void startScraper() {
    spawn({"gl-scrape", "--status", kStatus, "--lang", language()}, kStatus);
}

static struct timespec statusTime() {
    struct stat st;
    return stat(kStatus, &st) == 0 ? st.st_mtim : timespec{0, 0};
}

// What ended before Puppy started is in the games it loaded
static struct timespec seen = statusTime();

bool scrapeEnded() {
    const struct timespec m = statusTime();
    if ((m.tv_sec == seen.tv_sec && m.tv_nsec == seen.tv_nsec) || ScraperRun::read().running()) return false;
    seen = m;
    return true;
}

void stopScraper(const ScraperRun& run) {
    if (run.running()) kill(-run.pid, SIGTERM);
}

void checkScraperAccount() {
    spawn({"gl-scrape", "--check", "--status", kCheck}, kCheck);
}
