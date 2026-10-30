#!/usr/bin/env bash
# Luanti on a console over its USB data port, with the packages of `dev/gl luanti-pkg`: send one to HOME/updates over
# MTP and run Update Luanti, run it on what is already there, undo, or put Update Luanti on a card whose image is older
# than it. Each command first checks that the console holds the card named (HOME/.card-name). See dev/README.md.
#   dev/luanti-console.sh send <card> <package>      MTP into HOME/updates, then Update Luanti (~1.5 min for 10 MB)
#   dev/luanti-console.sh apply <card>               Update Luanti on the newest package already in HOME/updates
#   dev/luanti-console.sh undo <card>                Undo Luanti update (again to return)
#   dev/luanti-console.sh updater <card> <commit>    Update Luanti of a commit on a card without it (seconds)
# The daily card (extreme-daily) also needs --daily-card.
set -euo pipefail

DEV=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$DEV")
O=rootfs/board/my-device/rootfs-overlay
H=/home/player
UPDATER=/usr/local/bin/luanti-update.sh
LOG=$H/logs/luanti-update.log

usage() { sed -n 's/^#   //p' "$0"; exit 1; }
die() { echo "$*"; exit 1; }
g() { python3 "$DEV/glserial.py" cmd "$@" | tr -d '\r'; }
sha() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -c1-64; }
md5of() { if command -v md5sum >/dev/null; then md5sum "$1" | cut -c1-32; else md5 -q "$1"; fi; }

DAILY=
args=()
for a in "$@"; do if [ "$a" = --daily-card ]; then DAILY=1; else args+=("$a"); fi; done
set -- ${args[@]+"${args[@]}"}
[ $# -ge 2 ] || usage
act=$1 card=$2

# the console holds the card named, with no app open; the daily card only on purpose
check_console() {
    local out have
    [ "$card" != extreme-daily ] || [ -n "$DAILY" ] || die "extreme-daily is the daily card: add --daily-card to go ahead"
    out=$(g "echo card=\$(head -n 1 $H/.card-name 2>/dev/null)" "appctl status")
    have=$(echo "$out" | sed -n 's/^card=//p')
    [ "$have" = "$card" ] || die "the console has the card '$have', not $card: nothing was done"
    case $out in *"application cgroup: populated"*) die "an app is open on the console: close it first" ;; esac
}

# Update Luanti (apply) or Undo as the launcher runs them, on the console's screen: waits for the end (its last screen
# stays 10 s), prints the lines it logged and sets $installed
run_updater() {
    local out wait
    out=$(g "[ -x $UPDATER ] && grep -q luanti-update.sh /etc/doas.conf && echo has-updater")
    case $out in *has-updater*) ;; *) die "this card has no Update Luanti: dev/luanti-console.sh updater $card <commit>" ;; esac
    echo "== luanti-update.sh $1 on the console's screen, about 30 s"
    wait="i=0; while [ \$i -lt 20 ] && ! ps | grep -q '[l]uanti-update.sh'; do sleep 1; i=\$((i + 1)); done;"
    wait="$wait while ps | grep -q '[l]uanti-update.sh'; do sleep 1; done"
    out=$(g "n=\$(cat $LOG 2>/dev/null | wc -l); appctl launch-application 'doas $UPDATER $1' 1; $wait; tail -n +\$((n + 1)) $LOG; echo installed=\$(head -n 1 /usr/share/luanti/goodluck-version)" --timeout 300)
    echo "$out" | sed '/^installed=/d; s/^/  /'
    installed=$(echo "$out" | sed -n 's/^installed=//p')
}

send() {
    local pkg=$1 name v part tmp sum have
    [ -f "$pkg" ] || die "no $pkg"
    name=${pkg##*/}
    case $name in luanti-*.tar.xz) ;; *) die "$name isn't a package (luanti-<version>.tar.xz)" ;; esac
    v=${name#luanti-}; v=${v%.tar.xz}
    command -v mtp-sendfile >/dev/null ||
        die "no mtp-sendfile (libmtp): copy $name to HOME/updates (card reader or MTP), then dev/luanti-console.sh apply $card"
    check_console
    # a name of its own, so a file left by an earlier send can't get in the way; mtp-sendfile keeps the local file's
    # name, so it sends a copy named so
    part=$name.$$.part
    tmp=$(mktemp -d)
    cp "$pkg" "$tmp/$part"
    echo "== $name ($(($(wc -c < "$pkg") / 1024)) KB) to HOME over MTP, about 1 min"
    # libmtp can hang opening the session; the next run resets the USB interface first
    for try in 1 2 3; do
        if [ "$(uname)" = Darwin ]; then killall ptpcamerad 2>/dev/null || true; fi
        perl -e 'alarm shift; exec @ARGV' 180 mtp-sendfile "$tmp/$part" "$part" > "$tmp/log" 2>&1 && break
        g "rm -f $H/$part" > /dev/null
        [ $try -lt 3 ] || { cat "$tmp/log"; rm -rf "$tmp"; die "MTP failed: nothing was installed"; }
        echo "   MTP stopped (try $try of 3), again"
    done
    rm -rf "$tmp"
    sum=$(sha "$pkg")
    have=$(g "sha256sum $H/$part | cut -c1-64" --timeout 60 | grep -E '^[0-9a-f]{64}$' || true)
    [ "$have" = "$sum" ] || die "the copy in HOME isn't the package: nothing was installed"
    g "mkdir -p $H/updates && mv -f $H/$part $H/updates/$name && sync" > /dev/null
    run_updater apply
    [ "$installed" = "$v" ] || die "Luanti is at ${installed:-?}, not $v: see the log above"
    echo "OK: the console has Luanti $v"
}

# what the commit's image adds for Update Luanti, each only if missing: the script and its doas line, the two
# apps.puppy entries after Luanti's, the pt-BR.lang lines of its messages; a readme in HOME/updates
updater() {
    local c tmp f out
    c=$(git -C "$REPO" rev-parse --short=7 "$1^{commit}")
    tmp=$(mktemp -d)
    git -C "$REPO" show "$c:$O$UPDATER" > "$tmp/luanti-update.sh" 2>/dev/null || die "$c has no $UPDATER"
    git -C "$REPO" show "$c:$O/etc/doas.conf" | sed -n '/ cmd \/usr\/local\/bin\/luanti-update\.sh$/p' > "$tmp/doas"
    git -C "$REPO" show "$c:$O/usr/share/puppy/apps.puppy" |
        awk -v RS= '/luanti-update\.sh/ { if (n++) print ""; print }' > "$tmp/entries"
    sed -n -E 's/.*(say|fail) "([^"$]+)".*/\2/p' "$tmp/luanti-update.sh" > "$tmp/keys"
    git -C "$REPO" show "$c:$O/usr/share/goodluck/lang/pt-BR.lang" |
        awk -F ' = ' 'NR == FNR { k[$0]; next } $1 in k' "$tmp/keys" - > "$tmp/lang"
    [ -s "$tmp/doas" ] || die "$c has no doas line for luanti-update.sh"
    [ "$(grep -c '^\[ENTRY\]' "$tmp/entries")" = 2 ] || die "$c has no Update Luanti entries in apps.puppy"
    echo "$c: luanti-update.sh, its doas line, 2 launcher entries, $(wc -l < "$tmp/lang" | tr -d ' ') pt-BR lines"
    cat > "$tmp/README.txt" <<'TXT'
Luanti updates

1. Copy the luanti-....tar.xz file you got into this folder ("updates").
2. On the console, in the Games tab, open "Update Luanti". The screen shows each step and goes back to the menu by itself.
3. If something looks wrong, "Undo Luanti update" brings back the version before (undo again to return).

Installed files move to the "installed" folder. The log is logs/luanti-update.log.
TXT
    cat > "$tmp/LEIA-ME.txt" <<'TXT'
Atualizações do Luanti

1. Copie aqui (nesta pasta "updates") o arquivo luanti-....tar.xz que você recebeu.
2. No console, na aba Jogos, abra "Update Luanti". A tela mostra cada passo e volta sozinha ao menu.
3. Se algo ficar estranho, "Undo Luanti update" volta para a versão anterior (e desfazer de novo retorna).

Os arquivos já instalados vão para a pasta "installed". O registro fica em logs/luanti-update.log.
TXT
    check_console
    echo "== 6 small files over serial, about 30 s"
    for f in luanti-update.sh doas entries lang README.txt LEIA-ME.txt; do
        python3 "$DEV/glserial.py" send "$tmp/$f" "$H/.cache/updater-$f" | tr -d '\r' | grep -qx MATCH || die "sending $f failed"
    done
    echo "== installing"
    g "cp $H/.cache/updater-luanti-update.sh $UPDATER && chmod 755 $UPDATER" \
      "grep -qxF -f $H/.cache/updater-doas /etc/doas.conf || cat $H/.cache/updater-doas >> /etc/doas.conf" \
      "grep -q '^COMMAND=doas $UPDATER' /usr/share/puppy/apps.puppy || awk -v f=$H/.cache/updater-entries '{ print } /^COMMAND=luanti.sh\$/ { print \"\"; while ((getline l < f) > 0) print l }' /usr/share/puppy/apps.puppy > /tmp/apps.puppy && cp /tmp/apps.puppy /usr/share/puppy/apps.puppy" \
      "while IFS= read -r l; do grep -qF \"\${l%% = *} = \" /usr/share/goodluck/lang/pt-BR.lang || printf '%s\n' \"\$l\" >> /usr/share/goodluck/lang/pt-BR.lang; done < $H/.cache/updater-lang" \
      "r=README.txt; grep -q '^language=pt' $H/.config/puppy/settings 2>/dev/null && r=LEIA-ME.txt; mkdir -p $H/updates $H/logs && cp $H/.cache/updater-\$r $H/updates/\$r" \
      "rm -f $H/.cache/updater-*; sync" --timeout 120 > /dev/null
    out=$(g "echo md5=\$(md5sum $UPDATER | cut -c1-32) doas=\$(grep -c luanti-update.sh /etc/doas.conf) entries=\$(grep -c '^COMMAND=doas $UPDATER' /usr/share/puppy/apps.puppy)")
    echo "$out" | sed 's/^/  /'
    case $out in
        *"md5=$(md5of "$tmp/luanti-update.sh") doas=1 entries=2"*) ;;
        *) die "the card doesn't have all of it: see the line above" ;;
    esac
    rm -rf "$tmp"
    # the launcher reads apps.puppy and the translations when it starts: an app that ends at once restarts it
    g "appctl launch-application true" > /dev/null
    echo "OK: Update Luanti of $c is on $card (the launcher restarted)"
}

case $act in
    send) [ $# -eq 3 ] || usage; send "$3" ;;
    apply) [ $# -eq 2 ] || usage; check_console; run_updater apply; echo "the console has Luanti ${installed:-?}" ;;
    undo) [ $# -eq 2 ] || usage; check_console; run_updater undo; echo "the console has Luanti ${installed:-?}" ;;
    updater) [ $# -eq 3 ] || usage; updater "$3" ;;
    *) usage ;;
esac
