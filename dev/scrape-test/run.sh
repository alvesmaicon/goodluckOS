#!/bin/bash
# gl-scrape's tests, in the dev container (dev/gl scrape-test): the pieces under ASan and UBSan, then
# the program against fake-screenscraper.py: a first run, Missing only keeping a name of the player's,
# All from the cache without asking again, the media, the gamelists, and a cache free of credentials.
set -e
T=$(dirname "$(readlink -f "$0")")
SRC=$T/../../rootfs/package/gl-scrape/src
W=$(mktemp -d); cd "$W"
printf '#define SS_DEVID_BYTES\n#define SS_DEVPASSWORD_BYTES\n' > credentials.h
printf '123456789' > c.bin && python3 -c "import zipfile; z=zipfile.ZipFile('c.zip','w'); z.write('c.bin'); z.close()" && rm c.bin
g++ -O1 -g -std=c++17 -Wall -Wextra -fsanitize=address,undefined -I. -I"$SRC" "$T/unit.cpp" $(ls "$SRC"/*.cpp | grep -v main.cpp) -o unit
./unit | tail -1
g++ -O2 -std=c++17 -Wall -Wextra -I. "$SRC"/*.cpp -o gl-scrape

mkdir -p roms/gba roms/psx
printf 'x' > "roms/gba/Advance Wars (USA).gba"; printf 'y' > "roms/gba/Unknown Hack.gba"
python3 -c "import zipfile; z=zipfile.ZipFile('roms/gba/Golden Sun (USA).zip','w'); z.writestr('Golden Sun (USA).gba','gs'); z.close()"
printf 'FILE "Final Fantasy VII (USA) (Disc 1).bin" BINARY\n' > "roms/psx/Final Fantasy VII (USA) (Disc 1).cue"
printf 'b' > "roms/psx/Final Fantasy VII (USA) (Disc 1).bin"; printf 'c' > "roms/psx/Final Fantasy VII (USA) (Disc 1).chd"
printf '<?xml version="1.0"?>\n<gameList>\n\t<game>\n\t\t<path>./Advance Wars (USA).gba</path>\n\t\t<name>My Own Name</name>\n\t\t<favorite>true</favorite>\n\t</game>\n</gameList>\n' > roms/gba/gamelist.xml
python3 "$T/fake-screenscraper.py" 2> server.log & S=$!; trap 'kill $S 2>/dev/null' EXIT; sleep 1
export SS_API=http://localhost:8765/api2/ SS_DEVID=DEV SS_DEVPASSWORD=DPW SS_USER=player1 SS_PASSWORD='p@ss'
run() { ./gl-scrape --roots "$W/roms" --cache "$W/cache" --config /dev/null --lang pt "$@"; }
fail() { echo "FAIL: $*"; exit 1; }

[ "$(./gl-scrape --systems --roots "$W/roms" --config /dev/null | cut -f1,3 | tr '\t\n' ': ')" = "gba:3 psx:2 " ] || fail "--systems (the .bin a .cue names is no game)"
run --video --status st1
grep -q "^state=done" st1 && grep -q "^found=2" st1 && grep -q "^notfound=3" st1 && grep -q "^requests=5/" st1 || fail "first run: $(tr '\n' ' ' < st1)"
grep -q "<name>My Own Name</name>" roms/gba/gamelist.xml || fail "Missing only replaced the player's name"
grep -q "<desc>História de Advance Wars</desc>" roms/gba/gamelist.pt.xml || fail "no Portuguese description"
[ -s "roms/gba/media/images/Advance Wars (USA).png" ] && [ -s "roms/gba/media/videos/Advance Wars (USA).mp4" ] || fail "media"
grep -q "crc 06B9DF6F romtype iso" server.log || fail "a disc image goes as iso, with its CRC"
grep -q "Golden Sun (USA).zip crc A269CF19 romtype rom size 2" server.log || fail "a zip goes by the file inside"
calls=$(grep -c ^jeuInfos server.log)
run --all --image box-2D --status st2
[ "$(grep -c ^jeuInfos server.log)" = "$calls" ] || fail "All asked again instead of using the cache"
grep -q "<name>Advance Wars US</name>" roms/gba/gamelist.xml || fail "All kept the old name"
grep -q "box-2D(us) 400 300" server.log || fail "pictures are asked at 400x300"
! grep -r -q -e DPW -e 'p@ss' -e sspassword cache || fail "credentials in the cache"
echo "gl-scrape: all tests passed"
