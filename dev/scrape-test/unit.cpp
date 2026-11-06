// gl-scrape's pieces on their own: JSON, the cached record, regions, gamelist edits, CRC and zip, the
// tabs' folders, ScreenScraper's systems and the Games tab's entries and names
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include "json.h"
#include "gamelist.h"
#include "games.h"
#include "roms.h"
#include "screenscraper.h"
#include "systems.h"
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
    // the tabs' folders: Puppy's keys in any case, a NAME= again replaces, music is no ROM folder
    { std::ofstream f("t.puppy"); f << "[ENTRY]\nNAME=x\nCOMMAND=y\n[ARCHIVE]\nNAME=Super Nintendo\nTAB=SNES\nENTRY_DIRECTORIES=/r/snes;/r/sfc/\n"
                                     "ENTRY_EXTENSIONS=SFC;smc;\n[archive]\nname = Arcade\nentry_directories = /r/mame\n[ARCHIVE]\nNAME=Music\nMEDIA=1\n"
                                     "ENTRY_DIRECTORIES=/m\n[ARCHIVE]\nNAME=Arcade\nENTRY_DIRECTORIES=/r/fbneo;/r/snes\n"; }
    std::vector<RomDir> dirs = romDirs({"t.puppy", "missing.puppy"});
    assert(dirs.size() == 3 && dirs[0].folder == "snes" && dirs[1].dir == "/r/sfc" && dirs[1].folder == "sfc" && dirs[1].tab == "SNES");
    assert(dirs[0].exts == std::vector<std::string>({"sfc", "smc"}) && dirs[2].folder == "fbneo" && dirs[2].tab == "Arcade");
    // ScreenScraper's systems: own names first, then Recalbox/RetroPie folders, then the tab; the lowest id on a tie
    assert(Json::parse(R"J({"header":{"commandRequested":"x?devpassword=SECRET"},"response":{"systemes":[
      {"id":203,"noms":{"nom_eu":"Megadrive - Sonic Hacks","nom_recalbox":"megadrive","nom_retropie":"genesis,megadrive"}},
      {"id":1,"noms":{"nom_eu":"Megadrive","nom_us":"Genesis","nom_recalbox":"megadrive","nom_retropie":"genesis,megadrive","noms_commun":"Sega Megadrive,Sega Genesis,Megadrive,Genesis"}},
      {"id":6,"noms":{"nom_eu":"Capcom Play System","nom_recalbox":"arcade,mame","noms_commun":"Capcom Play System,CPS 1"}},
      {"id":75,"noms":{"nom_eu":"Mame","nom_recalbox":"arcade,mame,fbneo","noms_commun":"MAME,Arcade"}},
      {"id":4,"noms":{"nom_eu":"Super Nintendo","nom_recalbox":"snes","noms_commun":"SNES,Super Nintendo,Super Famicom"}}]}})J", j));
    Systems sys; assert(sys.empty() && sys.fromList(j) && !sys.empty());
    auto at = [](const char* folder, std::vector<std::string> names = {}) { RomDir d; d.folder = folder; d.names = names; return d; };
    assert(sys.find(at("genesis")) == 1 && sys.find(at("Mega-Drive")) == 1 && sys.find(at("cps1")) == 6 && sys.find(at("mame")) == 75);
    assert(sys.find(at("fbneo")) == 75 && sys.find(at("sfc", {"Super Nintendo", "SNES"})) == 4 && sys.find(at("doom", {"Doom"})) == 0);
    { std::ofstream f("systems"); f << sys.dump(); }
    assert(sys.dump().find("SECRET") == std::string::npos);
    Systems back2; assert(back2.load("systems") && back2.dump() == sys.dump() && !Systems().load("missing"));
    // the Games tab: Games entries only, a NAME= again replaces, hidden ones out; then the installed apps'
    { std::ofstream f("g.puppy"); f << "[ENTRY]\nCATEGORY=Games\nNAME=Doom\nSCREENSCRAPER=489155\nCOMMAND=d\n[ENTRY]\nCATEGORY=Games\nNAME=Gone\n"
                                     "HIDE_IF_EXISTS=g.puppy\nCOMMAND=x\n[ENTRY]\nCATEGORY=Terminal\nNAME=Top\nCOMMAND=top\n[ENTRY]\nCATEGORY=Games\n"
                                     "NAME=No command\n[entry]\ncategory = Games\nname = Doom\ncommand = d2\n"; }
    system("mkdir -p inst/b inst/a && printf '[ENTRY]\\nCATEGORY=Games\\nNAME=Luanti\\nCOMMAND=./l\\n' > inst/b/app.puppy"
           " && printf '[ENTRY]\\nNAME=Tool\\nCOMMAND=./t\\n' > inst/a/app.puppy");
    std::vector<NativeGame> native = nativeGames({"g.puppy"}, "inst");
    assert(native.size() == 2 && native[0].name == "Doom" && native[0].id.empty() && native[1].name == "Luanti");
    assert(sameName("The Legend of Zelda : Ocarina of Time", "Ocarina of Time") && sameName("Half-life", "Half-Life"));
    assert(sameName("DOOM", "Doom") && sameName("Zelda - Majora's Mask", "Majoras Mask") && !sameName("Half-Life 2", "Half-Life"));
    assert(!sameName("Half-Life - Blue Shift", "Half-Life") && !sameName("Ocarina of Time 3D", "Ocarina of Time") && !sameName("x", ""));
    std::vector<Json> found(4);
    assert(Json::parse(R"J({"id":"1","names":{"ss":"Half-Life 2"},"dates":{"us":"1990"},"medias":[]})J", found[0]));
    assert(Json::parse(R"J({"id":"2","names":{"ss":"Half-life"},"dates":{"us":"2000-09-01"},"medias":[{"type":"video-normalized"}]})J", found[1]));
    assert(Json::parse(R"J({"id":"3","names":{"us":"Half-Life"},"dates":{"us":"1998-11-19","jp":"1999"},"medias":[]})J", found[2]));
    assert(Json::parse(R"J({"id":"4","names":{"us":"Half-Life"},"dates":{},"medias":[]})J", found[3]));
    assert(chooseGame(found, "Half-Life") && (*chooseGame(found, "Half-Life"))["id"].text == "3" && !chooseGame(found, "Quake"));
    std::cout << "ALL OK\n";
}
