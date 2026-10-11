#!/bin/sh
# luanti.sh creative|survival: opens that world straight away, without Luanti's main menu.
#   ~/.minetest/minetest.conf starts as /usr/share/goodluck/defaults/luanti.conf
mode=${1:-creative}
dir=$HOME/.minetest
conf=$dir/minetest.conf
mkdir -p "$dir/worlds"
[ -f "$conf" ] || cp /usr/share/goodluck/defaults/luanti.conf "$conf"

set_conf() {
    if grep -q "^$1 *=" "$conf"; then sed -i "s|^$1 *=.*|$1 = $2|" "$conf"; else echo "$1 = $2" >> "$conf"; fi
}

# --go skips the main menu, which is what copies a world's modes into the settings
case $mode in
    survival) set_conf creative_mode false; set_conf enable_damage true ;;
    *)        mode=creative; set_conf creative_mode true; set_conf enable_damage false ;;
esac

# the launcher's language (gl-tr reads the same setting)
code=$(sed -n 's/^language=//p' "$HOME/.config/puppy/settings" 2>/dev/null | tail -n 1)
if [ "$code" = pt-BR ]; then
    set_conf language pt_BR
    export LANG=pt_BR.UTF-8
else
    set_conf language en
fi

exec luanti --go --world "$dir/worlds/$mode" --gameid minetest_game
