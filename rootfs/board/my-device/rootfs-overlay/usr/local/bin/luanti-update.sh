#!/bin/sh
# Updates Luanti from a package copied to HOME/updates over USB, or undoes the last update, and gives Luanti the
# textures of the player's own Minecraft while a copy of its .minecraft folder is in HOME. Puppy runs it through doas,
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
# the player's Minecraft: goodluck_mcassets names the textures, Luanti reads textures/server, the mod reads the list
MINETEST=$HOMEDIR/.minetest
TABLE=/$TREE/games/minetest_game/mods/goodluck_mcassets/textures.txt
SOUNDS=/$TREE/games/minetest_game/mods/goodluck_mcassets/sounds.txt
MUSIC=/$TREE/games/minetest_game/mods/goodluck_mcassets/music.txt
MC_MUSIC=$MINETEST/music
MC_DEST=$MINETEST/textures/server/minecraft
MC_LIST=$MINETEST/mod_data/goodluck_mcassets/imported.txt
MC_STAGE=/tmp/luanti-minecraft

# Puppy's language setting; the Portuguese is here, not in pt-BR.lang, so that a package brings its messages' translation
LANGUAGE=$(sed -n 's/^language=//p' "$HOMEDIR/.config/puppy/settings" 2>/dev/null | tail -n 1)
translate() {
    [ "$LANGUAGE" = pt-BR ] || return 0
    awk -v key="$1" 'index($0, key " = ") == 1 { print substr($0, length(key) + 4); exit }' <<'LANG'
Luanti update = Atualização do Luanti
Installed: %s = Instalado: %s
No update in the updates folder = Nenhuma atualização na pasta updates
Already up to date = Já está atualizado
This update (%s) is older than the installed one: nothing was changed = Esta atualização (%s) é mais antiga que a instalada: nada foi mudado
Checking %s... = Conferindo %s...
The update is damaged: nothing was changed = A atualização está com defeito: nada foi mudado
Not a whole Luanti update: nothing was changed = Não é uma atualização completa do Luanti: nada foi mudado
Not enough room on the system: nothing was changed = Falta espaço no sistema: nada foi mudado
Saving the current version to undo it... = Guardando a versão atual para poder desfazer...
Could not save the current version: nothing was changed = Não deu para guardar a versão atual: nada foi mudado
Installing %s... = Instalando %s...
Installing failed: the previous version is back = A instalação falhou: a versão anterior voltou
Installing failed: run Undo Luanti update = A instalação falhou: rode Undo Luanti update
Luanti updated to %s = Luanti atualizado para %s
Nothing to undo = Nada para desfazer
Going back to the version before the last update... = Voltando para a versão de antes da última atualização...
Luanti is back to the previous version (undo again to return) = O Luanti voltou para a versão anterior (desfaça de novo para retornar)
Undoing failed: nothing was changed = Não deu para desfazer: nada foi mudado
Minecraft found in %s: taking its textures... = Minecraft encontrado em %s: pegando as texturas dele...
No Minecraft: Java Edition client (versions/<version>/<version>.jar) in the copy: nothing was taken = Não há um cliente do Minecraft: Java Edition (versions/<versão>/<versão>.jar) na cópia: nada foi pego
None of Luanti's textures is in Minecraft %s: nothing was taken = Nenhuma textura do Luanti está no Minecraft %s: nada foi pego
Could not write to HOME: Luanti's own textures are back = Não deu para gravar na HOME: as texturas do próprio Luanti voltaram
%s of the %s textures Luanti can take are Minecraft %s's now = %s das %s texturas que o Luanti pode pegar agora são as do Minecraft %s
%s sounds came from Minecraft %s too = %s sons também vieram do Minecraft %s
Copying the music of Minecraft %s (%s tracks)... = Copiando as músicas do Minecraft %s (%s faixas)...
%s music tracks are on the card = %s músicas estão no cartão
The copy has no assets folder: Luanti keeps its own sounds = A cópia não tem a pasta assets: o Luanti fica com os sons dele
The Minecraft copy is gone from HOME: Luanti's own textures are back = A cópia do Minecraft saiu da HOME: as texturas do próprio Luanti voltaram
Back to the menu in %s s = Voltando ao menu em %s s
LANG
}

# the console's font has no accents; one letter at a time, as BusyBox's sed reads a [...] of them byte by byte
ascii() {
    printf '%s' "$1" | sed 's/á/a/g; s/à/a/g; s/â/a/g; s/ã/a/g; s/é/e/g; s/ê/e/g; s/í/i/g; s/ó/o/g; s/ô/o/g; s/õ/o/g;
        s/ú/u/g; s/ç/c/g; s/Á/A/g; s/À/A/g; s/Â/A/g; s/Ã/A/g; s/É/E/g; s/Ê/E/g; s/Í/I/g; s/Ó/O/g; s/Ô/O/g; s/Õ/O/g;
        s/Ú/U/g; s/Ç/C/g'
}

# say "English text with %s" [args]: translated as Puppy is, on the screen and in the log
say() {
    _fmt=$(translate "$1")
    [ -n "$_fmt" ] || _fmt=$1
    shift
    _msg=$(printf "$_fmt" "$@")
    ascii "$_msg" | fold -s -w 76 | sed 's/^/  /'
    printf '\n'
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
    rm -rf "$STAGE" "$MC_STAGE"
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

# one setting in HOME/.minetest/minetest.conf, as luanti.sh sets them
set_conf() {
    mkdir -p "$MINETEST"
    if grep -q "^$1 *=" "$MINETEST/minetest.conf" 2>/dev/null; then
        sed -i "s|^$1 *=.*|$1 = $2|" "$MINETEST/minetest.conf"
    else
        echo "$1 = $2" >> "$MINETEST/minetest.conf"
    fi
}

# the newest package in HOME/updates, when it is newer than what is installed
apply() {
    installed=$(head -n 1 "/$VERSION" 2>/dev/null)
    say "Installed: %s" "${installed:-?}"
    pkg=$(ls "$UPDATES"/luanti-*.tar.xz 2>/dev/null | sort | tail -n 1)
    if [ -z "$pkg" ]; then
        say "No update in the updates folder"
        return 1
    fi
    version=$(version_of "$pkg")
    # packages older than the newest are of no use any more
    mkdir -p "$UPDATES/old"
    for p in $(ls "$UPDATES"/luanti-*.tar.xz | sort); do
        [ "$p" = "$pkg" ] || mv -f "$p" "$UPDATES/old/"
    done
    if [ "$version" = "$installed" ]; then
        mv -f "$pkg" "$UPDATES/old/"
        say "Already up to date"
        return 1
    elif [ -n "$installed" ] && older "$version" "$installed"; then
        mv -f "$pkg" "$UPDATES/old/"
        say "This update (%s) is older than the installed one: nothing was changed" "$version"
        return 1
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
}

# Luanti's look and sounds from the player's own Minecraft, a copy of its .minecraft folder in HOME: the textures
# textures.txt names ({path} = assets/minecraft/textures/<path>.png), from the client jar with the most textures among
# the copy's versions, as mc_<path with _>.png, and the list of what came; a texture the jar lacks keeps Luanti's own.
# Then the sounds sounds.txt names, found by hash in the asset index of the jar's version (the newest index when that
# is not known), each under the game's file names so that it plays in place of the game's, and the music music.txt
# names into HOME/.minetest/music/<set>, where the engine plays it (a track already there, of the same size, stays).
# The copy gone, so are they.
minecraft() {
    src=""
    for d in "$HOMEDIR/minecraft" "$HOMEDIR/.minecraft"; do
        [ -d "$d/versions" ] && src=$d && break
    done
    if [ -z "$src" ]; then
        [ -d "$MC_DEST" ] || return 1
        say "The Minecraft copy is gone from HOME: Luanti's own textures are back"
        rm -rf "$MC_DEST" "$MC_LIST" "$MC_MUSIC"
        set_conf goodluck_mc_assets false
        return 0
    fi
    say "Minecraft found in %s: taking its textures..." "${src##*/}"
    jar="" best=0
    for j in "$src"/versions/*/*.jar; do
        [ -f "$j" ] || continue
        n=$(unzip -l "$j" 2>/dev/null | grep -c 'assets/minecraft/textures/.*\.png$')
        [ "$n" -gt "$best" ] && jar=$j && best=$n
    done
    if [ -z "$jar" ]; then
        say "No Minecraft: Java Edition client (versions/<version>/<version>.jar) in the copy: nothing was taken"
        return 1
    fi
    v=${jar%/*}
    v=${v##*/}
    paths=$(awk '!/^#/ { while (match($0, /\{[^}]+\}/)) { print substr($0, RSTART + 1, RLENGTH - 2); $0 = substr($0, RSTART + RLENGTH) } }' "$TABLE" | sort -u)
    total=$(echo "$paths" | wc -l | tr -d ' ')
    rm -rf "$MC_STAGE" && mkdir -p "$MC_STAGE/new" || fail "Could not write to HOME: Luanti's own textures are back"
    # a member the jar lacks is just not there afterwards
    unzip -o -q "$jar" $(echo "$paths" | sed 's|^|assets/minecraft/textures/|; s|$|.png|') -d "$MC_STAGE" 2>/dev/null
    : > "$MC_STAGE/list"
    for p in $paths; do
        f=$MC_STAGE/assets/minecraft/textures/$p.png
        [ -f "$f" ] || continue
        mv "$f" "$MC_STAGE/new/mc_${p//\//_}.png" && echo "mc_${p//\//_}.png" >> "$MC_STAGE/list"
    done
    # "file" lines: the image under the Luanti name too, for what the game draws from code
    awk '!/^#/ && $3 ~ /file/ && match($2, /\{[^}]+\}/) { print $1, substr($2, RSTART + 1, RLENGTH - 2) }' "$TABLE" |
        while read -r to p; do
            [ -f "$MC_STAGE/new/mc_${p//\//_}.png" ] && cp "$MC_STAGE/new/mc_${p//\//_}.png" "$MC_STAGE/new/$to"
        done
    got=$(wc -l < "$MC_STAGE/list" | tr -d ' ')
    if [ "$got" -eq 0 ]; then
        rm -rf "$MC_STAGE"
        say "None of Luanti's textures is in Minecraft %s: nothing was taken" "$v"
        return 1
    fi
    # cp, not mv: as root, mv onto HOME (FAT) would try to give each file its tmpfs owner and complain
    if ! { rm -rf "$MC_DEST" && mkdir -p "${MC_DEST%/*}" "${MC_LIST%/*}" && cp -r "$MC_STAGE/new" "$MC_DEST" &&
            cp "$MC_STAGE/list" "$MC_LIST"; }; then
        rm -rf "$MC_DEST" "$MC_LIST"
        set_conf goodluck_mc_assets false
        fail "Could not write to HOME: Luanti's own textures are back"
    fi
    set_conf goodluck_mc_assets true
    say "%s of the %s textures Luanti can take are Minecraft %s's now" "$got" "$total" "$v"

    index=$(sed -n 's/.*"assets": *"\([^"]*\)".*/\1/p' "${jar%.jar}.json" 2>/dev/null | head -n 1)
    [ -n "$index" ] && [ -f "$src/assets/indexes/$index.json" ] ||
        index=$(ls -t "$src"/assets/indexes/*.json 2>/dev/null | head -n 1 | sed 's|.*/||; s|\.json$||')
    if [ -z "$index" ] || [ ! -f "$SOUNDS" ]; then
        say "The copy has no assets folder: Luanti keeps its own sounds"
        rm -rf "$MC_STAGE"
        return 0
    fi
    # the index, one object a line: "minecraft/sounds/dig/stone1.ogg":{"hash":"4ec8...","size":7434
    tr -d ' \n\r' < "$src/assets/indexes/$index.json" | tr '}' '\n' |
        awk -F'"' '$2 ~ /^minecraft\/sounds\// { print substr($2, 18), $6, substr($9, 2) }' > "$MC_STAGE/sounds.map"
    find "/$TREE/games/minetest_game/mods" -name '*.ogg' | sed 's|.*/||' | sort > "$MC_STAGE/sounds.have"
    # for each line of sounds.txt: the game's file names of that sound, then name.<n>.ogg for what is left, each with
    # one of Minecraft's objects (xx/hash) in turn
    awk 'FNR == 1 { f++ }
        f == 1 { n = $0; sub(/\.ogg$/, "", n); sub(/\.[0-9]$/, "", n); have[n] = (n in have) ? have[n] " " $0 : $0; next }
        f == 2 { hash[$1] = $2; next }
        /^#/ || NF < 2 { next }
        {
            k = 0
            for (i = 2; i <= NF; i++) if (($i ".ogg") in hash) mc[++k] = hash[$i ".ogg"]
            if (!k) next
            m = split(have[$1], out, " ")
            for (n = 1; m < k && n <= 9; n++) {
                name = $1 "." n ".ogg"
                taken = 0
                for (i = 1; i <= m; i++) if (out[i] == name) taken = 1
                if (!taken) out[++m] = name
            }
            for (i = 1; i <= m; i++) { h = mc[(i - 1) % k + 1]; print substr(h, 1, 2) "/" h, out[i] }
        }' "$MC_STAGE/sounds.have" "$MC_STAGE/sounds.map" "$SOUNDS" > "$MC_STAGE/sounds.copy"
    sgot=0
    while read -r obj name; do
        cp "$src/assets/objects/$obj" "$MC_DEST/$name" 2>/dev/null && echo "$name" >> "$MC_LIST" && sgot=$((sgot + 1))
    done < "$MC_STAGE/sounds.copy"
    say "%s sounds came from Minecraft %s too" "$sgot" "$v"

    # the index's size tells a track already copied: 250 MB would take a while every time
    awk 'FNR == 1 { f++ }
        f == 1 { hash[$1] = $2; size[$1] = $3; next }
        /^#/ || NF < 2 { next }
        { for (i = 2; i <= NF; i++) { n = "music/" $i ".ogg"; if (n in hash) { h = hash[n]; m = $i; sub(/.*\//, "", m);
            print substr(h, 1, 2) "/" h, size[n], $1 "/" m ".ogg" } } }' "$MC_STAGE/sounds.map" "$MUSIC" > "$MC_STAGE/music.copy"
    total=$(wc -l < "$MC_STAGE/music.copy" | tr -d ' ')
    if [ "$total" -gt 0 ]; then
        say "Copying the music of Minecraft %s (%s tracks)..." "$v" "$total"
        mgot=0
        while read -r obj size name; do
            mkdir -p "$MC_MUSIC/${name%/*}"
            [ -f "$MC_MUSIC/$name" ] && [ "$(wc -c < "$MC_MUSIC/$name" | tr -d ' ')" = "$size" ] ||
                cp "$src/assets/objects/$obj" "$MC_MUSIC/$name" 2>/dev/null || continue
            mgot=$((mgot + 1))
        done < "$MC_STAGE/music.copy"
        say "%s music tracks are on the card" "$mgot"
    fi
    rm -rf "$MC_STAGE"
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
    apply)
        result=1
        apply && result=0
        minecraft && result=0
        finish $result ;;
    undo) undo ;;
    *) fail "Usage: luanti-update.sh apply|undo" ;;
esac
