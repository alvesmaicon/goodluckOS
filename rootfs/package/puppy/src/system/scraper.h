#pragma once
// The scraper, gl-scrape: its settings file (~/.config/gl-scrape/settings), the folders it can
// scrape, and the progress of a run or of an account check, which it writes to /tmp.
#include <string>
#include <vector>

struct ScraperSettings {
    std::string user, password;         // the player's ScreenScraper account
    std::string image = "mixrbv2";      // ScreenScraper's media type, or none
    bool video = false;
    std::string region = "auto";        // auto (the file name's tags), br, us, eu, jp, wor
    bool all = false;                   // every game, not only what's missing
    std::vector<std::string> skip;      // folders left out

    static ScraperSettings load();
    void save() const;
};

struct ScraperFolder {
    std::string folder, name;
    int games = 0, complete = 0;
};
std::vector<ScraperFolder> scraperFolders();    // gl-scrape --systems

struct ScraperRun {
    std::string state;      // running, done, stopped, error; empty when there was none
    std::string message, detail, system, game, requests;
    int pid = 0, step = 0, steps = 0, index = 0, total = 0, found = 0, notFound = 0, failed = 0, skipped = 0;

    bool running() const;
    static ScraperRun read();           // the last run
    static ScraperRun readCheck();      // the last account check (game: the user)
};

void startScraper();        // in the background, in the interface's language
bool scrapeEnded();         // a run ended since the last call: the gamelists changed
void stopScraper(const ScraperRun& run);
void checkScraperAccount();
