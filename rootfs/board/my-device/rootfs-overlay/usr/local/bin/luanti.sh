#!/bin/sh
# luanti.sh: Luanti with its main menu, in the launcher's language.
#   ~/.minetest/minetest.conf starts as /usr/share/goodluck/defaults/luanti.conf
dir=$HOME/.minetest
conf=$dir/minetest.conf
defaults=/usr/share/goodluck/defaults/luanti.conf
mkdir -p "$dir"
[ -f "$conf" ] || cp "$defaults" "$conf"

# defaults added in a later image reach an existing minetest.conf too; set ones stay as they are
grep -E '^[a-z0-9_]+ *=' "$defaults" | while IFS= read -r line; do
    grep -q "^${line%%[ =]*} *=" "$conf" || echo "$line" >> "$conf"
done

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
