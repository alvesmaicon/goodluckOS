// gl-scrape's pieces on their own: JSON, the cached record, regions, gamelist edits, CRC and zip
#include <cassert>
#include <cstdio>
#include <fstream>
#include <iostream>
#include "json.h"
#include "gamelist.h"
#include "roms.h"
#include "screenscraper.h"
int main() {
    // JSON
    Json j;
    assert(Json::parse(R"J({"a":"x\u00e9\ud83d\ude00","n":[1,2.5,-3e2],"t":true,"f":false,"z":null,"o":{}})J", j));
    assert(j["a"].text == "x\xc3\xa9\xf0\x9f\x98\x80");
    assert(j["n"][1].text == "2.5" && j["t"].text == "true" && j["f"].text == "false" && j["z"].isNull());
    assert(j["missing"]["deeper"].isNull());
    Json back; assert(Json::parse(j.dump(), back) && back["a"].text == j["a"].text);
    assert(!Json::parse("{\"a\":1,}", j) && !Json::parse("Erreur : Rom non trouvée", j));
    // jeuInfos-shaped answer -> record
    const char* answer = R"J({"header":{"success":"true"},"response":{"jeu":{"id":"3","noms":[{"region":"ss","text":"Super Mario World"},{"region":"jp","text":"スーパーマリオワールド"},{"region":"br","text":"Super Mario World BR"}],
      "synopsis":[{"langue":"en","text":"Mario & Luigi <go>"},{"langue":"pt","text":"Mário e Luigi"}],"dates":[{"region":"us","text":"1991-08-23"},{"region":"jp","text":"1990"}],
      "genres":[{"id":"1","principale":"0","noms":[{"langue":"en","text":"Other"}]},{"id":"2","principale":"1","noms":[{"langue":"en","text":"Platform"},{"langue":"pt","text":"Plataforma"}]}],
      "joueurs":{"text":"1-2"},"developpeur":{"id":"1","text":"Nintendo EAD"},"editeur":{"id":"2","text":"Nintendo"},"note":{"text":"18"},
      "medias":[{"type":"box-2D","region":"us","format":"png","url":"https://neoclone.screenscraper.fr/api2/mediaJeu.php?devid=SECRET&devpassword=SECRET2&softname=x&ssid=me&sspassword=PW&systemeid=4&jeuid=3&media=box-2D(us)"},
                {"type":"mixrbv2","region":"wor","format":"png","url":"https://neoclone.screenscraper.fr/api2/mediaJeu.php?devid=SECRET&systemeid=4&jeuid=3&media=mixrbv2(wor)"}]}}})J";
    assert(Json::parse(answer, j));
    Json rec = record(j["response"]["jeu"]);
    std::string dumped = rec.dump();
    assert(dumped.find("SECRET") == std::string::npos && dumped.find("PW") == std::string::npos);
    assert(rec["genre"]["en"].text == "Platform" && rec["genre"]["pt"].text == "Plataforma");
    assert(rec["names"]["br"].text == "Super Mario World BR" && rec["players"].text == "1-2");
    assert(rec["medias"][0]["url"].text == "https://neoclone.screenscraper.fr/api2/mediaJeu.php?systemeid=4&jeuid=3&media=box-2D(us)");
    ScreenScraper ss({"DEV", "DPW", "usr", "p&w"});
    std::string u = ss.mediaUrl(rec["medias"][0]["url"].text, 400, 300);
    std::cout << u << "\n";
    assert(u.find("devid=DEV&devpassword=DPW&softname=goodluckOS&ssid=usr&sspassword=p%26w&maxwidth=400&maxheight=300") != std::string::npos);
    // regions
    assert(fileRegion("Super Mario World (USA).sfc") == "us" && fileRegion("Game (Europe) (En,Fr).gba") == "eu");
    assert(fileRegion("Game (USA, Europe).gb") == "us" && fileRegion("Pokemon (B) [!].gb") == "br" && fileRegion("x (Rev 1).gb") == "");
    // gamelist: keeps foreign tags and folders, fills only missing unless overwrite
    { std::ofstream f("gl.xml"); f << "<?xml version=\"1.0\"?>\n<gameList>\n\t<folder><path>./sub</path></folder>\n\t<game id=\"9\">\n\t\t<path>./a.gb</path>\n\t\t<name>Mine</name>\n\t\t<favorite>true</favorite>\n\t</game>\n</gameList>\n"; }
    Gamelist g; g.load("gl.xml");
    assert(g.has("a.gb") && g.get("a.gb", "name") == "Mine" && !g.has("b.gb"));
    g.set("a.gb", {{"name", "Theirs"}, {"desc", "D & <x>"}}, false);
    g.set("b.gb", {{"name", "B"}, {"image", "./media/images/b.png"}, {"genre", ""}}, false);
    assert(g.get("a.gb", "name") == "Mine" && g.get("a.gb", "desc") == "D & <x>");
    g.set("a.gb", {{"name", "Theirs"}}, true);
    assert(g.get("a.gb", "name") == "Theirs");
    assert(g.save("gl.xml"));
    Gamelist g2; g2.load("gl.xml");
    assert(g2.get("b.gb", "image") == "./media/images/b.png" && g2.get("a.gb", "favorite") == "true");
    Gamelist fresh; fresh.load("none.xml"); fresh.set("c.gba", {{"name", "C"}}, false); assert(fresh.save("new.xml"));
    std::cout << "--- gl.xml\n" << std::ifstream("gl.xml").rdbuf() << "--- new.xml\n" << std::ifstream("new.xml").rdbuf();
    // CRC32 of "123456789" is CBF43926; zip with one file
    { std::ofstream f("c.bin", std::ios::binary); f << "123456789"; }   // run.sh also zips it as c.zip
    RomId id = identify("c.bin"); assert(id.crc == "CBF43926" && id.size == 9);
    RomId z = identify("c.zip"); std::cout << "zip " << z.crc << " " << z.size << "\n"; assert(z.crc == "CBF43926" && z.size == 9);
    std::cout << "ALL OK\n";
}
