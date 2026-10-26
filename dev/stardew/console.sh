#!/usr/bin/env bash
# Stardew Valley on a console over its USB data port: put this checkout's port files on it, and time the title and a
# save load there with the bench mode (the game loads the save by itself, logs its times and exits). Each command
# first checks that the console holds the card named (HOME/.card-name) with no app open.
#   dev/stardew/console.sh saves <card>                      the save folders on the card
#   dev/stardew/console.sh send <card> [content]             StardewPatches.dll and the pregenerated serializers
#                                                            (content: also the LZ4 .xnb files) over MTP, over the
#                                                            port's files (no backup: build.sh makes them again)
#   dev/stardew/console.sh bench <card> <name> <save> [VAR=value...]
#                                                            one run with SDV_BENCH=<save>,1,1 and the variables in
#                                                            <port>/env (the old env comes back after it), its log in
#                                                            dev/out/stardew/results/console-<name>.log (~2 min)
# The daily card (extreme-daily) also needs --daily-card.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$(dirname "$HERE")")
OUT=$REPO/dev/out/stardew
H=/home/player
PORT=$H/ports/stardewvalley
LOG=$H/logs/stardew.log

usage() { sed -n 's/^#   //p' "$0"; exit 1; }
die() { echo "$*"; exit 1; }
g() { python3 "$REPO/dev/glserial.py" cmd "$@" | tr -d '\r'; }

DAILY=
args=()
for a in "$@"; do if [ "$a" = --daily-card ]; then DAILY=1; else args+=("$a"); fi; done
set -- ${args[@]+"${args[@]}"}
[ $# -ge 2 ] || usage
act=$1 card=$2

check_console() {
    local out have
    [ "$card" != extreme-daily ] || [ -n "$DAILY" ] || die "extreme-daily is the daily card: add --daily-card to go ahead"
    out=$(g "echo card=\$(head -n 1 $H/.card-name 2>/dev/null)" "appctl status" "[ -d $PORT/gamedata ] && echo has-port")
    have=$(echo "$out" | sed -n 's/^card=//p')
    [ "$have" = "$card" ] || die "the console has the card '$have', not $card: nothing was done"
    case $out in *"application cgroup: populated"*) die "an app is open on the console: close it first" ;; esac
    case $out in *has-port*) ;; *) die "no Stardew Valley in $PORT on $card" ;; esac
}

send() {
    local what=${1:-} tmp n
    command -v mtp-sendfile >/dev/null || die "no mtp-sendfile (libmtp)"
    tmp=$(mktemp -d)
    (cd "$OUT/stardewvalley" && ls dlls/StardewPatches.dll SdvXmlGen.exe SdvXnb.exe) > "$tmp/list"
    (cd "$OUT" && ls gamedata/StardewValley.XmlSerializers*) >> "$tmp/list"
    [ "$what" != content ] || (cd "$OUT" && find gamedata/Content -name '*.xnb' | sort) >> "$tmp/list"
    n=$(wc -l < "$tmp/list" | tr -d ' ')
    # one tar rooted at the port folder: the port's own files and gamedata side by side
    mkdir -p "$tmp/root"
    ln -s "$OUT/stardewvalley/dlls" "$OUT/stardewvalley/SdvXmlGen.exe" "$OUT/stardewvalley/SdvXnb.exe" "$OUT/gamedata" "$tmp/root/"
    COPYFILE_DISABLE=1 tar --no-xattrs -chf "$tmp/sdv-send.tar" -C "$tmp/root" -T "$tmp/list"
    check_console
    echo "== $n files ($(($(wc -c < "$tmp/sdv-send.tar") / 1048576)) MB) to HOME over MTP, ~10 MB/s"
    if [ "$(uname)" = Darwin ]; then killall ptpcamerad 2>/dev/null || true; fi
    mtp-sendfile "$tmp/sdv-send.tar" sdv-send.tar > "$tmp/mtp.log" 2>&1 || { cat "$tmp/mtp.log"; die "MTP failed: nothing was installed"; }
    echo "== unpacking on the console (FAT: a minute or two for the content)"
    g "cd $PORT && tar --no-same-owner -xf $H/sdv-send.tar && echo unpacked \$(tar -tf $H/sdv-send.tar | wc -l) && rm $H/sdv-send.tar && sync" --timeout 600
    rm -rf "$tmp"
    echo "OK: $card has them"
}

bench() {
    local name=$1 save=$2 log out i
    log=$OUT/results/console-$name.log
    shift 2
    check_console
    mkdir -p "$OUT/results"
    # the env goes back even if this is stopped
    trap 'g "if [ -f $PORT/env.bench-saved ]; then mv -f $PORT/env.bench-saved $PORT/env; else rm -f $PORT/env; fi; sync; echo env:; cat $PORT/env 2>/dev/null"' EXIT
    g "[ -f $PORT/env.bench-saved ] || { [ -f $PORT/env ] && cp $PORT/env $PORT/env.bench-saved; } ; printf '%s\n' $* SDV_BENCH=$save,1,1 > $PORT/env; cat $PORT/env; appctl launch-application 'sh $PORT/stardew.sh'"
    echo "== $name: title, load of $save, 2 s at the farm, exit"
    for i in $(seq 1 40); do
        sleep 10
        out=$(g "grep -E '^(bench|exit)' $LOG | tail -n 3")
        case $out in *"exit "*) break ;; esac
    done
    python3 "$REPO/dev/glserial.py" get $LOG "$log" > /dev/null
    grep -E '^(bench|Early|speed|xmldump|exit)|Exception' "$log" | sed 's/^/  /'
}

case $act in
    saves) g "ls $H/.config/StardewValley/Saves/" ;;
    send) send "${3:-}" ;;
    bench) [ $# -ge 4 ] || usage; bench "${@:3}" ;;
    *) usage ;;
esac
