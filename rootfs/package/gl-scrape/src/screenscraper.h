#pragma once
// ScreenScraper's API (api2): the account's quota and a game's data, at the pace the quota allows.
#include <string>
#include <vector>

#include "json.h"
#include "roms.h"

struct Account {
    std::string devId, devPassword;     // the software's
    std::string user, password;         // the player's ScreenScraper account
};

enum class Answer { Ok, NotFound, Busy, DayQuota, Unknowns, Closed, Login, Blacklisted, BadRequest, Network, Garbled };
const char* describe(Answer a);         // English, for the status file
bool fatal(Answer a);                   // no point going on today

struct Quota {
    std::string user;
    int level = 0, threads = 1, perMinute = 0, perDay = 0, today = 0, unknownToday = 0, unknownPerDay = 0;
};

class ScreenScraper {
public:
    explicit ScreenScraper(Account a) : account(std::move(a)) {}

    Answer userInfo(Quota& q);
    Answer systemList(Json& answer);    // systemesListe, as it comes (~4 MB)
    // jeuInfos, reduced to what gl-scrape keeps (see record())
    Answer gameInfo(int systemId, const std::string& file, const RomId& id, Json& game);
    Answer gameById(const std::string& id, Json& game);     // jeuInfos by ScreenScraper's id
    // jeuRecherche: the games whose names have these words, on one system (0: all), at most 30
    Answer search(const std::string& name, int systemId, std::vector<Json>& games);
    // A media URL from a record, with the credentials and, for a picture, the size
    std::string mediaUrl(const std::string& url, int maxWidth, int maxHeight) const;
    std::string detail;     // the server's words on the last failure
    int counted = 0;        // requests ScreenScraper answered with a game or a 404, which its quota counts

private:
    Account account;
    long long nextAt = 0;   // ms: no request before then (requests per minute)
    int gapMs = 1100;

    std::string credentials() const;
    Answer request(const std::string& url, Json& out, int timeout = 60);
};

// From a jeuInfos "jeu": names and dates by region, synopses and the main genre by language,
// players, developer, publisher, rating, and the media with URLs free of credentials
Json record(const Json& jeu);
