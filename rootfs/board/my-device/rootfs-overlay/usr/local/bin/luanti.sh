#!/bin/sh
# luanti.sh: Luanti with its main menu, in the launcher's language.
#   ~/.minetest/minetest.conf starts as /usr/share/goodluck/defaults/luanti.conf
dir=$HOME/.minetest
conf=$dir/minetest.conf
mkdir -p "$dir"
[ -f "$conf" ] || cp /usr/share/goodluck/defaults/luanti.conf "$conf"

set_conf() {
    if grep -q "^$1 *=" "$conf"; then sed -i "s|^$1 *=.*|$1 = $2|" "$conf"; else echo "$1 = $2" >> "$conf"; fi
}

# the same setting as gl-tr
code=$(sed -n 's/^language=//p' "$HOME/.config/puppy/settings" 2>/dev/null | tail -n 1)
if [ "$code" = pt-BR ]; then
    set_conf language pt_BR
    export LANG=pt_BR.UTF-8
else
    set_conf language en
fi

exec luanti
