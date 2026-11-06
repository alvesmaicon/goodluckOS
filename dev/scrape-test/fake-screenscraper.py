# A fake ScreenScraper for dev/scrape-test/run.sh: ssuserInfos, systemesListe (a few systems), jeuInfos
# (by romnom: four known games, 404 for the rest; by gameid: Doom), jeuRecherche (native games by name and
# system, an empty game when there's none, as ScreenScraper answers) and the media, with gl-scrape's test
# credentials (DEV / DPW)
import json, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
calls = {"jeuInfos": 0}
GAMES = {"Advance Wars (USA).gba": "1", "Golden Sun (USA).gba": "2", "Final Fantasy VII (USA) (Disc 1).chd": "3", "sf2.zip": "4"}
SYSTEMS = [{"id": "12", "noms": {"nom_eu": "Game Boy Advance", "nom_recalbox": "gba", "nom_retropie": "gba", "noms_commun": "Nintendo Game Boy Advance,Game Boy Advance,GBA"}},
           {"id": "57", "noms": {"nom_eu": "Playstation", "nom_recalbox": "psx", "nom_retropie": "psx", "noms_commun": "Sony Playstation,PSX,PS1"}},
           {"id": "6", "noms": {"nom_eu": "Capcom Play System", "nom_recalbox": "arcade,mame,fba,fba_libretro", "noms_commun": "Capcom Play System,CPS 1"}},
           {"id": "75", "noms": {"nom_eu": "Mame", "nom_recalbox": "arcade,mame,fba,fba_libretro,fbneo", "noms_commun": "MAME,Arcade,FBA"}}]
# jeuRecherche: (name, system) -> [(id, name, date)]; system 0 is all of them
SEARCH = {("Ocarina of Time", "14"): [("5395", "The Legend of Zelda : Ocarina of Time", "1998-11-21"), ("98597", "The Legend of Zelda : Ocarina of Time Master Quest", "2002-11-28")],
          ("Ocarina of Time", "0"): [("59918", "The Legend of Zelda : Ocarina of Time / Master Quest", "2003-02-27")],
          ("Half-Life", "138"): [("304202", "Half-Life", "1998-11-19"), ("304206", "Half-Life 2", "2004-11-16")],
          ("Half-Life", "0"): [("13493", "Half-life", "2000-09-01")],
          ("Cave Story", "0"): [("7", "Cave Story", "2004-12-20")]}
PNG = bytes.fromhex("89504e470d0a1a0a0000000d4948445200000001000000010806000000")
def jeu(gid, name, date, q):
    base = f"http://localhost:8765/api2/mediaJeu.php?devid=DEV&devpassword=DPW&softname=goodluckOS&ssid={q.get('ssid')}&sspassword=X&systemeid={q.get('systemeid')}&jeuid={gid}"
    return {"id": gid, "noms": [{"region": "jp", "text": "アドバンス"}, {"region": "us", "text": name + " US"}, {"region": "ss", "text": name}],
            "synopsis": [{"langue": "en", "text": "English story of " + name + " & co."}, {"langue": "pt", "text": "História de " + name}],
            "dates": [{"region": "us", "text": date}, {"region": "jp", "text": "2004"}],
            "genres": [{"id": "1", "principale": "0", "noms": [{"langue": "en", "text": "Other"}]}, {"id": "2", "principale": "1", "noms": [{"langue": "en", "text": "Strategy"}, {"langue": "pt", "text": "Estratégia"}]}],
            "joueurs": {"text": "1-4"}, "developpeur": {"text": "Intelligent Systems"}, "editeur": {"text": "Nintendo"}, "note": {"text": "17"},
            "medias": [{"type": "box-2D", "region": "us", "format": "png", "url": base + "&media=box-2D(us)"},
                       {"type": "mixrbv2", "region": "wor", "format": "png", "url": base + "&media=mixrbv2(wor)"},
                       {"type": "video-normalized", "region": "wor", "format": "mp4", "url": base.replace("mediaJeu", "mediaVideoJeu") + "&media=video-normalized"}]}
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body, ctype="application/json"):
        b = body if isinstance(body, bytes) else body.encode()
        self.send_response(code); self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        u = urllib.parse.urlparse(self.path); q = dict(urllib.parse.parse_qsl(u.query))
        if q.get("devid") != "DEV" or q.get("devpassword") != "DPW":
            return self.send(403, "Erreur de login : Vérifier vos identifiants développeur !", "text/plain")
        if u.path.endswith("ssuserInfos.php"):
            return self.send(200, json.dumps({"response": {"ssuser": {"id": q.get("ssid"), "niveau": "1", "maxthreads": "1", "maxrequestsperdmin": "600", "requeststoday": str(calls["jeuInfos"]), "maxrequestsperday": "20000", "requestskotoday": "0", "maxrequestskoperday": "2000"}}}))
        if u.path.endswith("systemesListe.php"):
            print("systemesListe", file=sys.stderr, flush=True)
            return self.send(200, json.dumps({"header": {"commandRequested": self.path}, "response": {"systemes": SYSTEMS}}))
        if u.path.endswith("jeuInfos.php") and q.get("gameid"):
            calls["jeuInfos"] += 1
            print("jeuInfos gameid", q["gameid"], file=sys.stderr, flush=True)
            if q["gameid"] != "489155": return self.send(404, "Erreur : Jeu non trouvée !  ", "text/plain")
            return self.send(200, json.dumps({"header": {}, "response": {"jeu": jeu("489155", "DOOM", "1993-12-10", q)}}))
        if u.path.endswith("jeuRecherche.php"):
            calls["jeuInfos"] += 1
            system = q.get("systemeid", "0")
            print("jeuRecherche", q.get("recherche"), "system", system, file=sys.stderr, flush=True)
            found = [jeu(i, n, d, q) for i, n, d in SEARCH.get((q.get("recherche"), system), [])]
            return self.send(200, json.dumps({"header": {}, "response": {"jeux": found or [{}]}}))
        if u.path.endswith("jeuInfos.php"):
            calls["jeuInfos"] += 1
            print("jeuInfos", q.get("romnom"), "crc", q.get("crc"), "romtype", q.get("romtype"), "size", q.get("romtaille"), "system", q.get("systemeid"), file=sys.stderr, flush=True)
            gid = GAMES.get(q.get("romnom"))
            if not gid: return self.send(404, "Erreur : Rom/Iso/Dossier non trouvée !  ", "text/plain")
            return self.send(200, json.dumps({"header": {}, "response": {"jeu": jeu(gid, q["romnom"].split(" (")[0], "2001-09-10", q)}}))
        if "mediaJeu.php" in u.path or "mediaVideoJeu.php" in u.path:
            print("media", q.get("media"), q.get("maxwidth"), q.get("maxheight"), "ssid" in q, file=sys.stderr, flush=True)
            return self.send(200, PNG if "mediaJeu" in u.path else b"fakevideo", "image/png")
        self.send(404, "?", "text/plain")
HTTPServer(("127.0.0.1", 8765), H).serve_forever()
