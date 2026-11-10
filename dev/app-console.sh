#!/usr/bin/env bash
# An app's zip (docs/making-apps.md) into a console's HOME/apps over its USB data port, after checking that the console
# holds the card named (HOME/.card-name); installing it is then done on the console, in System Settings -> System ->
# App Installer. See dev/README.md.
#   dev/app-console.sh send <card> <zip>     MTP into HOME/apps (about 1 min for 15 MB)
# The daily card (extreme-daily) also needs --daily-card.
set -euo pipefail

DEV=$(cd "$(dirname "$0")" && pwd)
H=/home/player

usage() { sed -n 's/^#   //p' "$0"; exit 1; }
die() { echo "$*"; exit 1; }
g() { python3 "$DEV/glserial.py" cmd "$@" | tr -d '\r'; }
sha() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -c1-64; }

DAILY=
args=()
for a in "$@"; do if [ "$a" = --daily-card ]; then DAILY=1; else args+=("$a"); fi; done
set -- ${args[@]+"${args[@]}"}
[ $# -eq 3 ] && [ "$1" = send ] || usage
card=$2 zip=$3

# the console holds the card named, with no app open; the daily card only on purpose
check_console() {
    local out have
    [ "$card" != extreme-daily ] || [ -n "$DAILY" ] || die "extreme-daily is the daily card: add --daily-card to go ahead"
    out=$(g "echo card=\$(head -n 1 $H/.card-name 2>/dev/null)" "appctl status")
    have=$(echo "$out" | sed -n 's/^card=//p')
    [ "$have" = "$card" ] || die "the console has the card '$have', not $card: nothing was done"
    case $out in *"application cgroup: populated"*) die "an app is open on the console: close it first" ;; esac
}

# $1 into HOME over MTP as $part, checked against the local file; $2: what to do without libmtp
to_home() {
    local pkg=$1 tmp sum have
    command -v mtp-sendfile >/dev/null || die "no mtp-sendfile (libmtp): $2"
    # a name of its own, so a file left by an earlier send can't get in the way; mtp-sendfile keeps the local file's
    # name, so it sends a copy named so
    tmp=$(mktemp -d)
    cp "$pkg" "$tmp/$part"
    echo "== ${pkg##*/} ($(($(wc -c < "$pkg") / 1024)) KB) to HOME over MTP, about 1 min"
    # libmtp can hang opening the session; the next run resets the USB interface first. A Mac's ptpcamerad takes the
    # console as a camera and is back as soon as it is killed, so it is kept away until mtp-sendfile holds the device
    for try in 1 2 3; do
        keeper=
        if [ "$(uname)" = Darwin ]; then
            (while :; do killall -9 ptpcamerad 2>/dev/null; sleep 0.2; done) & keeper=$!
        fi
        if perl -e 'alarm shift; exec @ARGV' 180 mtp-sendfile "$tmp/$part" "$part" > "$tmp/log" 2>&1; then rc=0; else rc=$?; fi
        [ -z "$keeper" ] || kill $keeper 2>/dev/null || true
        # mtp-sendfile also exits 0 when it found no device or could not open one
        [ $rc = 0 ] && ! grep -q -E 'No devices|PANIC|Unable to open' "$tmp/log" && break
        g "rm -f $H/$part" > /dev/null
        [ $try -lt 3 ] || { cat "$tmp/log"; rm -rf "$tmp"; die "MTP failed: nothing was installed (a stuck MTP session on the console clears with a reboot; or send over serial: dev/glserial.py send)"; }
        echo "   MTP stopped (try $try of 3), again"
    done
    rm -rf "$tmp"
    # the console's MTP may put it in a folder of HOME (one a Mac left there, .fseventsd): back to HOME
    g "f=\$(find $H -maxdepth 2 -name $part | head -n 1); [ -z \"\$f\" ] || [ \"\$f\" = $H/$part ] || mv -f \"\$f\" $H/$part" > /dev/null
    sum=$(sha "$pkg")
    have=$(g "sha256sum $H/$part | cut -c1-64" --timeout 60 | grep -E '^[0-9a-f]{64}$' || true)
    [ "$have" = "$sum" ] || die "the copy in HOME isn't the file sent: nothing was installed"
}

[ -f "$zip" ] || die "no $zip"
name=${zip##*/}
case $name in *.zip) ;; *) die "$name isn't a zip" ;; esac
check_console
part=$name.$$.part
to_home "$zip" "copy $name to HOME/apps (card reader or MTP)"
g "mkdir -p $H/apps && mv -f $H/$part $H/apps/$name && sync" > /dev/null
echo "OK: $name is in HOME/apps; on the console: System Settings -> System -> App Installer"
