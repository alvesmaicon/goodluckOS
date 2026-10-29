# A fake ScreenScraper for dev/scrape-test/run.sh: ssuserInfos, jeuInfos (by romnom: three known games,
# 404 for the rest) and the media, with gl-scrape's test credentials (DEV / DPW)
import json, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
calls = {"jeuInfos": 0}
GAMES = {"Advance Wars (USA).gba": "1", "Golden Sun (USA).gba": "2", "Final Fantasy VII (USA) (Disc 1).chd": "3"}
PNG = bytes.fromhex("89504e470d0a1a0a0000000d4948445200000001000000010806000000")
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
        if u.path.endswith("jeuInfos.php"):
            calls["jeuInfos"] += 1
            print("jeuInfos", q.get("romnom"), "crc", q.get("crc"), "romtype", q.get("romtype"), "size", q.get("romtaille"), file=sys.stderr, flush=True)
            gid = GAMES.get(q.get("romnom"))
            if not gid: return self.send(404, "Erreur : Rom/Iso/Dossier non trouvée !  ", "text/plain")
            base = f"http://localhost:8765/api2/mediaJeu.php?devid=DEV&devpassword=DPW&softname=goodluckOS&ssid={q.get('ssid')}&sspassword=X&systemeid={q.get('systemeid')}&jeuid={gid}"
            name = q["romnom"].split(" (")[0]
            jeu = {"id": gid, "noms": [{"region": "jp", "text": "アドバンス"}, {"region": "us", "text": name + " US"}, {"region": "ss", "text": name}],
                   "synopsis": [{"langue": "en", "text": "English story of " + name + " & co."}, {"langue": "pt", "text": "História de " + name}],
                   "dates": [{"region": "us", "text": "2001-09-10"}, {"region": "jp", "text": "2004"}],
                   "genres": [{"id": "1", "principale": "0", "noms": [{"langue": "en", "text": "Other"}]}, {"id": "2", "principale": "1", "noms": [{"langue": "en", "text": "Strategy"}, {"langue": "pt", "text": "Estratégia"}]}],
                   "joueurs": {"text": "1-4"}, "developpeur": {"text": "Intelligent Systems"}, "editeur": {"text": "Nintendo"}, "note": {"text": "17"},
                   "medias": [{"type": "box-2D", "region": "us", "format": "png", "url": base + "&media=box-2D(us)"},
                              {"type": "mixrbv2", "region": "wor", "format": "png", "url": base + "&media=mixrbv2(wor)"},
                              {"type": "video-normalized", "region": "wor", "format": "mp4", "url": base.replace("mediaJeu", "mediaVideoJeu") + "&media=video-normalized"}]}
            return self.send(200, json.dumps({"header": {}, "response": {"jeu": jeu}}))
        if "mediaJeu.php" in u.path or "mediaVideoJeu.php" in u.path:
            print("media", q.get("media"), q.get("maxwidth"), q.get("maxheight"), "ssid" in q, file=sys.stderr, flush=True)
            return self.send(200, PNG if "mediaJeu" in u.path else b"fakevideo", "image/png")
        self.send(404, "?", "text/plain")
HTTPServer(("127.0.0.1", 8765), H).serve_forever()
