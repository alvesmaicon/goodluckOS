#include "screenscraper.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <ctime>

#include <unistd.h>

#include "fetch.h"

static const char* kDefaultApi = "https://api.screenscraper.fr/api2/";

// SS_API in the environment points the tests at a fake server
static std::string api() {
    const char* a = getenv("SS_API");
    return a && *a ? a : kDefaultApi;
}
static const char* kSoftname = "goodluckOS";

const char* describe(Answer a) {
    switch (a) {
        case Answer::Ok: return "OK";
        case Answer::NotFound: return "Not found";
        case Answer::Busy: return "ScreenScraper is busy";
        case Answer::DayQuota: return "Today's ScreenScraper quota is used up";
        case Answer::Unknowns: return "Too many unknown games for today";
        case Answer::Closed: return "ScreenScraper is closed to this account right now";
        case Answer::Login: return "ScreenScraper refused the login";
        case Answer::Blacklisted: return "ScreenScraper refuses this version";
        case Answer::BadRequest: return "ScreenScraper refused the request";
        case Answer::Network: return "No internet";
        case Answer::Garbled: return "Unexpected answer from ScreenScraper";
    }
    return "";
}

bool fatal(Answer a) {
    return a == Answer::DayQuota || a == Answer::Unknowns || a == Answer::Closed || a == Answer::Login ||
           a == Answer::Blacklisted;
}

static long long nowMs() {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (long long)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static int number(const Json& j) {
    return atoi(j.text.c_str());
}

std::string ScreenScraper::credentials() const {
    std::string q = "devid=" + urlEncode(account.devId) + "&devpassword=" + urlEncode(account.devPassword) +
                    "&softname=" + kSoftname;
    if (!account.user.empty()) q += "&ssid=" + urlEncode(account.user) + "&sspassword=" + urlEncode(account.password);
    return q;
}

Answer ScreenScraper::request(const std::string& url, Json& out) {
    const long long wait = nextAt - nowMs();
    if (wait > 0) usleep((useconds_t)wait * 1000);
    const Fetched r = fetch(url, 60);
    nextAt = nowMs() + gapMs;
    detail = r.status ? r.body.substr(0, r.body.find('\n')).substr(0, 160) : r.error;
    detail.erase(detail.find_last_not_of(" \t\r") + 1);
    switch (r.status) {
        case 200: break;
        case 0: return Answer::Network;
        case 400: return Answer::BadRequest;
        case 401: case 423: return Answer::Closed;
        case 403: return Answer::Login;
        case 404: return Answer::NotFound;
        case 426: return Answer::Blacklisted;
        case 429: return Answer::Busy;
        case 430: return Answer::DayQuota;
        case 431: return Answer::Unknowns;
        default: return r.status >= 500 ? Answer::Busy : Answer::Garbled;
    }
    if (!Json::parse(r.body, out)) return Answer::Garbled;
    detail.clear();
    return Answer::Ok;
}

Answer ScreenScraper::userInfo(Quota& q) {
    Json j;
    const Answer a = request(api() + "ssuserInfos.php?output=json&" + credentials(), j);
    if (a != Answer::Ok) return a;
    const Json& u = j["response"]["ssuser"];
    if (u.isNull()) return Answer::Garbled;
    q.user = u["id"].text;
    q.level = number(u["niveau"]);
    q.threads = std::max(1, number(u["maxthreads"]));
    q.perMinute = number(u["maxrequestspermin"].isNull() ? u["maxrequestsperdmin"] : u["maxrequestspermin"]);
    q.perDay = number(u["maxrequestsperday"]);
    q.today = number(u["requeststoday"]);
    q.unknownToday = number(u["requestskotoday"]);
    q.unknownPerDay = number(u["maxrequestskoperday"]);
    if (q.perMinute > 0) gapMs = 60000 / q.perMinute + 100;
    return Answer::Ok;
}

// A disc image is an "iso" to ScreenScraper, a cartridge a "rom"
static const char* romType(const std::string& file) {
    std::string ext = file.substr(file.rfind('.') + 1);
    for (char& c : ext) c = (char)tolower((unsigned char)c);
    for (const char* disc : {"cue", "chd", "iso", "cso", "pbp", "m3u", "cdi", "gdi"})
        if (ext == disc) return "iso";
    return "rom";
}

Answer ScreenScraper::gameInfo(int systemId, const std::string& file, const RomId& id, Json& game) {
    std::string url = api() + "jeuInfos.php?output=json&" + credentials() +
                      "&systemeid=" + std::to_string(systemId) + "&romtype=" + romType(file) + "&romnom=" + urlEncode(file) +
                      "&romtaille=" + std::to_string(id.size);
    if (!id.crc.empty()) url += "&crc=" + id.crc;
    Json j;
    const Answer a = request(url, j);
    if (a != Answer::Ok) return a;
    const Json& jeu = j["response"]["jeu"];
    if (jeu.isNull() || jeu["id"].text.empty()) return Answer::NotFound;
    game = record(jeu);
    return Answer::Ok;
}

// A media URL without the query's credentials, which the cache must not keep
static std::string stripCredentials(const std::string& url) {
    const size_t q = url.find('?');
    if (q == std::string::npos) return url;
    std::string out = url.substr(0, q), sep = "?";
    for (size_t p = q + 1; p <= url.size();) {
        size_t amp = url.find('&', p);
        if (amp == std::string::npos) amp = url.size();
        const std::string param = url.substr(p, amp - p);
        const std::string key = param.substr(0, param.find('='));
        if (!param.empty() && key != "devid" && key != "devpassword" && key != "softname" && key != "ssid" &&
            key != "sspassword" && key != "output") {
            out += sep + param;
            sep = "&";
        }
        p = amp + 1;
    }
    return out;
}

std::string ScreenScraper::mediaUrl(const std::string& url, int maxWidth, int maxHeight) const {
    std::string out = url + (url.find('?') == std::string::npos ? "?" : "&") + credentials();
    if (maxWidth > 0) out += "&maxwidth=" + std::to_string(maxWidth);
    if (maxHeight > 0) out += "&maxheight=" + std::to_string(maxHeight);
    return out;
}

// [{"region": "us", "text": "..."}] -> {"us": "..."}
static Json byKey(const Json& list, const char* key) {
    Json out = Json::object();
    for (const Json& item : list.items)
        if (!item[key].text.empty() && !item["text"].text.empty() && out[item[key].text].isNull())
            out.set(item[key].text, Json::str(item["text"].text));
    return out;
}

Json record(const Json& jeu) {
    Json r = Json::object();
    r.set("id", Json::str(jeu["id"].text));
    r.set("names", byKey(jeu["noms"], "region"));
    r.set("synopsis", byKey(jeu["synopsis"], "langue"));
    r.set("dates", byKey(jeu["dates"], "region"));
    const Json* main = nullptr;
    for (const Json& g : jeu["genres"].items) {
        if (g["principale"].text == "1") {
            main = &g;
            break;
        }
        if (!main) main = &g;
    }
    if (main) r.set("genre", byKey((*main)["noms"], "langue"));
    r.set("players", Json::str(jeu["joueurs"]["text"].text));
    r.set("developer", Json::str(jeu["developpeur"]["text"].text));
    r.set("publisher", Json::str(jeu["editeur"]["text"].text));
    r.set("rating", Json::str(jeu["note"]["text"].text));
    Json medias = Json::array();
    for (const Json& m : jeu["medias"].items) {
        const std::string& type = m["type"].text;
        if (type.empty() || m["url"].text.empty()) continue;
        Json k = Json::object();
        k.set("type", Json::str(type));
        k.set("region", Json::str(m["region"].text));
        k.set("format", Json::str(m["format"].text));
        k.set("url", Json::str(stripCredentials(m["url"].text)));
        medias.push(std::move(k));
    }
    r.set("medias", std::move(medias));
    return r;
}
