#!/bin/sh
# Updates Luanti from a package copied to HOME/updates over USB, or undoes the last update. Puppy's Terminal tab runs
# it through doas, on the text console. A package (luanti-*.tar.xz) is data only: files under the paths below, VERSION
# and files.md5; nothing in it runs, and nothing changes unless every file checks out.
#   luanti-update.sh apply|undo
HOMEDIR=/home/player
UPDATES=$HOMEDIR/updates
UNDO=$HOMEDIR/.cache/luanti-undo.tar.gz
LOG=$HOMEDIR/logs/luanti-update.log
STAGE=/tmp/luanti-update
GAME=usr/share/luanti/games/minetest_game
ALLOWED='^usr/share/luanti/[^ ]*$|^usr/bin/luanti$|^usr/share/goodluck/defaults/luanti\.conf$|^usr/local/bin/luanti(\.sh|-perflog\.sh|-update\.sh)$'

# the console's font has no accents
ascii() {
    printf '%s' "$1" | sed 's/[áàâã]/a/g; s/[éê]/e/g; s/í/i/g; s/[óôõ]/o/g; s/ú/u/g; s/ç/c/g; s/[ÁÀÂÃ]/A/g;
        s/[ÉÊ]/E/g; s/Í/I/g; s/[ÓÔÕ]/O/g; s/Ú/U/g; s/Ç/C/g'
}

# say "English text with %s" [arg]: translated as Puppy is, on the screen and in the log
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

apply() {
    pkg=$(ls "$UPDATES"/luanti-*.tar.xz 2>/dev/null | sort | tail -n 1)
    [ -n "$pkg" ] || fail "No update in the updates folder"
    say "Checking %s..." "${pkg##*/}"
    rm -rf "$STAGE" && mkdir -p "$STAGE" && xz -dc "$pkg" | tar x -C "$STAGE" 2>/dev/null ||
        fail "The update is damaged: nothing was changed"
    cd "$STAGE" || fail "The update is damaged: nothing was changed"
    [ -f files.md5 ] && [ -f VERSION ] || fail "The update is damaged: nothing was changed"
    # every file listed, checked, and under a path an update may change
    listed=$(awk '{ print $2 }' files.md5)
    [ "$(find usr -type f | sort)" = "$(echo "$listed" | sort)" ] &&
        ! echo "$listed" | grep -v -E "$ALLOWED" | grep -q . && ! echo "$listed" | grep -q '\.\.' &&
        md5sum -c -s files.md5 || fail "The update is damaged: nothing was changed"
    need=$(du -sk usr | awk '{ print $1 }')
    free=$(df -k / | awk 'NR == 2 { print $4 }')
    [ "$free" -gt $((need + 5000)) ] || fail "Not enough room on the system: nothing was changed"
    version=$(head -n 1 VERSION)

    say "Saving the current version to undo it..."
    old=""
    for f in $listed; do
        case $f in $GAME/*) ;; *) [ -e "/$f" ] && old="$old $f" ;; esac
    done
    echo "$listed" | grep -q "^$GAME/" && [ -d "/$GAME" ] && old="$old $GAME"
    if [ -n "$old" ]; then
        (cd / && tar czf "$UNDO.new" $old) && mv -f "$UNDO.new" "$UNDO" || fail "Could not save the current version: nothing was changed"
    fi

    say "Installing %s..." "$version"
    if echo "$listed" | grep -q "^$GAME/"; then
        rm -rf "/$GAME.old"
        [ -d "/$GAME" ] && mv "/$GAME" "/$GAME.old"
        mkdir -p "/${GAME%/*}"
        if ! cp -a "$STAGE/$GAME" "/$GAME"; then
            rm -rf "/$GAME"
            [ -d "/$GAME.old" ] && mv "/$GAME.old" "/$GAME"
            fail "Installing failed: the previous version is back"
        fi
    fi
    for f in $listed; do
        case $f in $GAME/*) continue ;; esac
        mkdir -p "/${f%/*}" && cp -a "$STAGE/$f" "/$f.new" && mv -f "/$f.new" "/$f" ||
            fail "Installing failed: run Undo Luanti update"
    done
    (cd / && md5sum -c -s "$STAGE/files.md5") || fail "Installing failed: run Undo Luanti update"
    rm -rf "/$GAME.old" "$STAGE"
    mkdir -p "$UPDATES/installed" && mv -f "$pkg" "$UPDATES/installed/"
    say "Luanti updated to %s" "$version"
    finish 0
}

# a swap: what is installed now becomes the next undo, so undoing twice brings the update back
undo() {
    [ -f "$UNDO" ] || fail "Nothing to undo"
    say "Going back to the version before the last update..."
    paths=$(tar tzf "$UNDO" | sed 's|/$||' | awk -v g="$GAME" 'index($0, g "/") == 1 || $0 == g { print g; next } { print }' | sort -u)
    now=""
    for f in $paths; do
        [ -e "/$f" ] && now="$now $f"
    done
    if [ -n "$now" ]; then
        (cd / && tar czf "$UNDO.new" $now) || fail "Undoing failed: nothing was changed"
    fi
    if echo "$paths" | grep -qx "$GAME"; then
        rm -rf "/$GAME.undone"
        [ -d "/$GAME" ] && mv "/$GAME" "/$GAME.undone"
    fi
    if (cd / && tar xzf "$UNDO"); then
        rm -rf "/$GAME.undone"
        [ -f "$UNDO.new" ] && mv -f "$UNDO.new" "$UNDO"
        say "Luanti is back to the previous version (undo again to return)"
        finish 0
    fi
    [ -d "/$GAME.undone" ] && rm -rf "/$GAME" && mv "/$GAME.undone" "/$GAME"
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
