#!/usr/bin/env bash
# Regenerates rootfs/package/luanti/*.patch from the Luanti fork (github.com/alvesmaicon/luanti), one patch per
# commit of its branch on top of the release tag; README and doc/handheld stay out.
#   dev/luanti-patches.sh [fork clone, default ../luanti] [branch, default handheld/<LUANTI_VERSION minor>]
set -euo pipefail
cd "$(dirname "$0")/.."
ver=$(sed -n 's/^LUANTI_VERSION = //p' rootfs/package/luanti/luanti.mk)
repo=${1:-../luanti}
branch=${2:-handheld/${ver%.*}}
out=rootfs/package/luanti
git -C "$repo" rev-parse --verify -q "$ver^{commit}" >/dev/null || { echo "$repo has no tag $ver"; exit 1; }
git -C "$repo" rev-parse --verify -q "$branch" >/dev/null || { echo "$repo has no branch $branch"; exit 1; }
rm -f $out/[0-9][0-9][0-9][0-9]-*.patch
git -C "$repo" format-patch -q --zero-commit --no-signature --no-stat -o "$PWD/$out" "$ver..$branch" -- . ':!README.md' ':!doc/handheld'
ls $out/*.patch | sed 's|.*/||'
echo "== from $(git -C "$repo" rev-parse --short "$branch") ($branch on $ver)"
