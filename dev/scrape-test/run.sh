#!/bin/bash
# gl-scrape's tests, in the dev container (dev/gl scrape-test): the pieces under ASan and UBSan, then
# the program against fake-screenscraper.py: the folders of the apps files' tabs and their systems, a
# first run, Missing only keeping a name of the player's, All from the cache without asking again, the
# media, the gamelists, and a cache free of credentials.
set -e
T=$(dirname "$(readlink -f "$0")")
SRC=$T/../../rootfs/package/gl-scrape/src
W=$(mktemp -d); cd "$W"
printf '#define SS_DEVID_BYTES\n#define SS_DEVPASSWORD_BYTES\n' > credentials.h
printf '123456789' > c.bin && python3 -c "import zipfile; z=zipfile.ZipFile('c.zip','w'); z.write('c.bin'); z.close()" && rm c.bin
g++ -O1 -g -std=c++17 -Wall -Wextra -fsanitize=address,undefined -I. -I"$SRC" "$T/unit.cpp" $(ls "$SRC"/*.cpp | grep -v main.cpp) -o unit
./unit | tail -1
g++ -O2 -std=c++17 -Wall -Wextra -I. "$SRC"/*.cpp -o gl-scrape

mkdir -p roms/gba roms/psx roms/fbneo roms/doom media/music apps.d
printf '[ARCHIVE]\nNAME=Game Boy Advance\nTAB=GBA\nENTRY_DIRECTORIES=%s/roms/gba/\nENTRY_EXTENSIONS=gba;ZIP;7z\n\n[ARCHIVE]\nNAME=Playstation\nTAB=PS1\nENTRY_DIRECTORIES=%s/roms/psx;%s/roms/gba\nENTRY_EXTENSIONS=bin;cue;chd;m3u;iso\n\n[ARCHIVE]\nNAME=Doom\nENTRY_DIRECTORIES=%s/roms/doom\nENTRY_EXTENSIONS=wad;\n\n[ARCHIVE]\nNAME=Music\nMEDIA=1\nENTRY_DIRECTORIES=%s/media/music\nENTRY_EXTENSIONS=mp3\n' "$W" "$W" "$W" "$W" "$W" > apps.puppy
printf '[archive]\nname = FBNeo\nentry_directories = %s/roms/fbneo\nentry_extensions = zip;7z\n' "$W" > apps.d/fbneo.puppy
python3 -c "import zipfile; z=zipfile.ZipFile('roms/fbneo/sf2.zip','w'); z.writestr('sf2_29b.10e','a'); z.writestr('sf2_28b.11e','b'); z.close()"
printf 'w' > roms/doom/doom.wad; printf 'm' > media/music/song.mp3
printf 'x' > "roms/gba/Advance Wars (USA).gba"; printf 'y' > "roms/gba/Unknown Hack.gba"
python3 -c "import zipfile; z=zipfile.ZipFile('roms/gba/Golden Sun (USA).zip','w'); z.writestr('Golden Sun (USA).gba','gs'); z.close()"
printf 'FILE "Final Fantasy VII (USA) (Disc 1).bin" BINARY\n' > "roms/psx/Final Fantasy VII (USA) (Disc 1).cue"
printf 'b' > "roms/psx/Final Fantasy VII (USA) (Disc 1).bin"; printf 'c' > "roms/psx/Final Fantasy VII (USA) (Disc 1).chd"
printf '<?xml version="1.0"?>\n<gameList>\n\t<game>\n\t\t<path>./Advance Wars (USA).gba</path>\n\t\t<name>My Own Name</name>\n\t\t<favorite>true</favorite>\n\t</game>\n</gameList>\n' > roms/gba/gamelist.xml
python3 "$T/fake-screenscraper.py" 2> server.log & S=$!; trap 'kill $S 2>/dev/null' EXIT; sleep 1
export SS_API=http://localhost:8765/api2/ SS_DEVID=DEV SS_DEVPASSWORD=DPW SS_USER=player1 SS_PASSWORD='p@ss'
run() { ./gl-scrape --apps "$W/apps.puppy:$W/apps.d" --cache "$W/cache" --config /dev/null --lang pt "$@"; }
fail() { echo "FAIL: $*"; exit 1; }

[ "$(run --systems | tr '\t\n' ':|')" = "gba:GBA:3:0|psx:PS1:2:0|doom:Doom:1:0|fbneo:FBNeo:1:0|" ] || fail "--systems before the systems are known (the .bin a .cue names is no game; music isn't scraped)"
run --video --status st1
grep -q "^state=done" st1 && grep -q "^found=3" st1 && grep -q "^notfound=3" st1 && grep -q "^requests=6/" st1 || fail "first run: $(tr '\n' ' ' < st1)"
grep -q "^es	fbneo	75$" cache/systems && grep -q "^own	gba	12$" cache/systems || fail "the systems' cache"
[ "$(run --systems | cut -f1 | tr '\n' ' ')" = "gba psx fbneo " ] || fail "--systems: a folder ScreenScraper has no system for is left out"
grep -q "sf2.zip crc None romtype rom size .* system 75" server.log || fail "an arcade zip goes by its name, fbneo as Mame"
grep -q "Advance Wars (USA).gba .* system 12" server.log || fail "gba as Game Boy Advance"
! grep -q doom.wad server.log || fail "doom has no system but was asked"
grep -q "<name>My Own Name</name>" roms/gba/gamelist.xml || fail "Missing only replaced the player's name"
grep -q "<desc>História de Advance Wars</desc>" roms/gba/gamelist.pt.xml || fail "no Portuguese description"
[ -s "roms/gba/media/images/Advance Wars (USA).png" ] && [ -s "roms/gba/media/videos/Advance Wars (USA).mp4" ] || fail "media"
grep -q "crc 06B9DF6F romtype iso" server.log || fail "a disc image goes as iso, with its CRC"
grep -q "Golden Sun (USA).zip crc A269CF19 romtype rom size 2" server.log || fail "a zip goes by the file inside"
calls=$(grep -c ^jeuInfos server.log)
run --all --image box-2D --status st2
[ "$(grep -c ^jeuInfos server.log)" = "$calls" ] || fail "All asked again instead of using the cache"
[ "$(grep -c ^systemesListe server.log)" = 1 ] || fail "the systems were asked again within the month"
grep -q "<name>Advance Wars US</name>" roms/gba/gamelist.xml || fail "All kept the old name"
grep -q "box-2D(us) 400 300" server.log || fail "pictures are asked at 400x300"
! grep -r -q -e DPW -e 'p@ss' -e sspassword cache || fail "credentials in the cache"
echo "gl-scrape: all tests passed"
