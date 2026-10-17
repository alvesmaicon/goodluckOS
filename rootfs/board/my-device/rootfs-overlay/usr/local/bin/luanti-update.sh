#!/bin/sh
# Updates Luanti from a package copied to HOME/updates over USB, or undoes the last update. Puppy runs it through doas,
# on the text console. A package, luanti-<version>.tar.xz, is all of Luanti and data only: the engine (usr/bin/luanti,
# usr/share/luanti with its game, the engine's translation), luanti.conf's defaults, the luanti*.sh scripts and
# files.md5; nothing in it runs, and nothing changes unless every file checks out. Versions (the commit's date, then its
# hash) only go forward; Undo is the way back.
#   luanti-update.sh apply|undo
HOMEDIR=/home/player
UPDATES=$HOMEDIR/updates
UNDO=$HOMEDIR/.cache/luanti-undo.tar.gz
LOG=$HOMEDIR/logs/luanti-update.log
STAGE=/tmp/luanti-update
TREE=usr/share/luanti
VERSION=$TREE/goodluck-version
ALLOWED='^usr/share/luanti/[^ ]*$|^usr/bin/luanti$|^usr/share/locale/[^/ ]*/LC_MESSAGES/luanti\.mo$|^usr/share/goodluck/defaults/luanti\.conf$|^usr/local/bin/luanti(\.sh|-perflog\.sh|-update\.sh)$'
NEEDED="usr/bin/luanti $TREE/builtin/init.lua $TREE/games/minetest_game/game.conf $VERSION"

# the console's font has no accents; one letter at a time, as BusyBox's sed reads a [...] of them byte by byte
ascii() {
    printf '%s' "$1" | sed 's/á/a/g; s/à/a/g; s/â/a/g; s/ã/a/g; s/é/e/g; s/ê/e/g; s/í/i/g; s/ó/o/g; s/ô/o/g; s/õ/o/g;
        s/ú/u/g; s/ç/c/g; s/Á/A/g; s/À/A/g; s/Â/A/g; s/Ã/A/g; s/É/E/g; s/Ê/E/g; s/Í/I/g; s/Ó/O/g; s/Ô/O/g; s/Õ/O/g;
        s/Ú/U/g; s/Ç/C/g'
}

# say "English text with %s" [args]: translated as Puppy is, on the screen and in the log
say() {
    _fmt=$(/usr/local/bin/gl-tr "$1")
    shift
    _msg=$(printf "$_fmt" "$@")
    printf '  %s\n' "$(ascii "$_msg")"
    echo "$(date '+%F %T') $_msg" >> "$LOG"
}

finish() {
    sync
    printf '\n'
    say "Back to the menu in %s s" 10
    sleep 10
    exit "$1"
}

fail() {
    say "$@"
    rm -rf "$STAGE"
    finish 1
}

# a package's version from its name: luanti-<date>-<time>-<commit>.tar.xz
version_of() {
    _v=${1##*/luanti-}
    printf '%s' "${_v%.tar.xz}"
}

older() {  # older <a> <b>: a sorts before b
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort | head -n 1)" = "$1" ]
}

# what is installed: the whole tree, and each other file of the list that exists
saved_paths() {
    _out=""
    for _f in $1; do
        case $_f in "$TREE"/*) ;; *) [ -e "/$_f" ] && _out="$_out $_f" ;; esac
    done
    [ -d "/$TREE" ] && _out="$_out $TREE"
    printf '%s' "$_out"
}

apply() {
    installed=$(head -n 1 "/$VERSION" 2>/dev/null)
    say "Installed: %s" "${installed:-?}"
    pkg=$(ls "$UPDATES"/luanti-*.tar.xz 2>/dev/null | sort | tail -n 1)
    [ -n "$pkg" ] || fail "No update in the updates folder"
    version=$(version_of "$pkg")
    # packages older than the newest are of no use any more
    mkdir -p "$UPDATES/old"
    for p in $(ls "$UPDATES"/luanti-*.tar.xz | sort); do
        [ "$p" = "$pkg" ] || mv -f "$p" "$UPDATES/old/"
    done
    if [ "$version" = "$installed" ]; then
        mv -f "$pkg" "$UPDATES/old/"
        fail "Already up to date"
    elif [ -n "$installed" ] && older "$version" "$installed"; then
        mv -f "$pkg" "$UPDATES/old/"
        fail "This update (%s) is older than the installed one: nothing was changed" "$version"
    fi

    say "Checking %s..." "${pkg##*/}"
    rm -rf "$STAGE" && mkdir -p "$STAGE" && xz -dc "$pkg" | tar x -C "$STAGE" 2>/dev/null ||
        fail "The update is damaged: nothing was changed"
    cd "$STAGE" || fail "The update is damaged: nothing was changed"
    [ -f files.md5 ] || fail "The update is damaged: nothing was changed"
    # every file listed, checked, and under a path an update may change
    listed=$(awk '{ print $2 }' files.md5)
    [ "$(find usr -type f | sort)" = "$(echo "$listed" | sort)" ] &&
        ! echo "$listed" | grep -v -E "$ALLOWED" | grep -q . && ! echo "$listed" | grep -q '\.\.' &&
        md5sum -c -s files.md5 || fail "The update is damaged: nothing was changed"
    for f in $NEEDED; do
        [ -f "$f" ] || fail "Not a whole Luanti update: nothing was changed"
    done
    [ "$(head -n 1 "$VERSION")" = "$version" ] || fail "The update is damaged: nothing was changed"
    need=$(du -sk usr | awk '{ print $1 }')
    free=$(df -k / | awk 'NR == 2 { print $4 }')
    [ "$free" -gt $((need + 5000)) ] || fail "Not enough room on the system: nothing was changed"

    say "Saving the current version to undo it..."
    old=$(saved_paths "$listed")
    if [ -n "$old" ]; then
        (cd / && tar czf "$UNDO.new" $old) && mv -f "$UNDO.new" "$UNDO" ||
            fail "Could not save the current version: nothing was changed"
    fi

    say "Installing %s..." "$version"
    rm -rf "/$TREE.old"
    [ -d "/$TREE" ] && mv "/$TREE" "/$TREE.old"
    if ! cp -a "$STAGE/$TREE" "/$TREE"; then
        rm -rf "/$TREE"
        [ -d "/$TREE.old" ] && mv "/$TREE.old" "/$TREE"
        fail "Installing failed: the previous version is back"
    fi
    for f in $listed; do
        case $f in "$TREE"/*) continue ;; esac
        mkdir -p "/${f%/*}" && cp -a "$STAGE/$f" "/$f.new" && mv -f "/$f.new" "/$f" ||
            fail "Installing failed: run Undo Luanti update"
    done
    (cd / && md5sum -c -s "$STAGE/files.md5") || fail "Installing failed: run Undo Luanti update"
    rm -rf "/$TREE.old" "$STAGE"
    mkdir -p "$UPDATES/installed" && mv -f "$pkg" "$UPDATES/installed/"
    say "Luanti updated to %s" "$version"
    finish 0
}

# a swap: what is installed now becomes the next undo, so undoing twice brings the update back
undo() {
    [ -f "$UNDO" ] || fail "Nothing to undo"
    # one saved by the first version of this script holds only the game: going back to it would lose the engine
    tar tzf "$UNDO" | grep -qx "$TREE/builtin/init.lua" || fail "Nothing to undo"
    say "Going back to the version before the last update..."
    files=$(tar tzf "$UNDO" | sed 's|/$||' | grep -v "^$TREE/" | grep -vx "$TREE")
    now=$(saved_paths "$files")
    if [ -n "$now" ]; then
        (cd / && tar czf "$UNDO.new" $now) || fail "Undoing failed: nothing was changed"
    fi
    rm -rf "/$TREE.undone"
    tar tzf "$UNDO" | grep -q "^$TREE/" && [ -d "/$TREE" ] && mv "/$TREE" "/$TREE.undone"
    if (cd / && tar xzf "$UNDO"); then
        rm -rf "/$TREE.undone"
        [ -f "$UNDO.new" ] && mv -f "$UNDO.new" "$UNDO"
        say "Luanti is back to the previous version (undo again to return)"
        say "Installed: %s" "$(head -n 1 "/$VERSION" 2>/dev/null || echo '?')"
        finish 0
    fi
    [ -d "/$TREE.undone" ] && rm -rf "/$TREE" && mv "/$TREE.undone" "/$TREE"
    rm -f "$UNDO.new"
    fail "Undoing failed: nothing was changed"
}

mkdir -p "${LOG%/*}" "$UPDATES"
printf '\033[2J\033[H\033[?25l\n'
say "Luanti update"
printf '\n'
case $1 in
    apply) apply ;;
    undo) undo ;;
    *) fail "Usage: luanti-update.sh apply|undo" ;;
esac
