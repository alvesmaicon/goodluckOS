#!/usr/bin/env python3
"""Reads the main thread's folded stacks from dev/stardew/macbench.sh perf (root;...;leaf count, 1 sample = 1 ms).
  folded.py <file> [--root REGEX] [--depth N] [--min PCT] [--ticks N]
The tree below the first frame that matches --root (default Game1:_update), children by inclusive samples, then
the hottest leaf functions under it. --ticks (updates in the window, default 3600 = 60 s at 60 UPS) turns samples
into ms per update.
"""
import argparse
import re
from collections import Counter, defaultdict

ap = argparse.ArgumentParser()
ap.add_argument("file")
ap.add_argument("--root", default=r"Game1:_update$")
ap.add_argument("--depth", type=int, default=4)
ap.add_argument("--min", type=float, default=2.0)
ap.add_argument("--ticks", type=float, default=3600)
ap.add_argument("--self", type=int, default=25)
a = ap.parse_args()

root = re.compile(a.root)
patched = re.compile(r"^(.*):\1\.(\w+)_Patch\d+$")  # Harmony's replacement of a probed method
total = 0
tree = defaultdict(Counter)
leaves = Counter()
under = 0
for line in open(a.file):
    stack, n = line.rstrip("\n").rsplit(" ", 1)
    n = int(n)
    total += n
    frames = [patched.sub(r"\1:\2", f) for f in stack.split(";")]
    for i, f in enumerate(frames):
        if root.search(f):
            path = frames[i:]
            break
    else:
        continue
    under += n
    leaves[path[-1]] += n
    for d in range(1, min(len(path), a.depth + 1)):
        tree[tuple(path[:d])][path[d]] += n

ms = 1000.0 / 1000 / a.ticks
print("main thread %d samples, under %s: %d (%.1f%%), %.3f ms/update" % (total, a.root, under, 100.0 * under / max(total, 1), under * ms))


def show(path, depth):
    for name, n in tree[path].most_common():
        if 100.0 * n / under < a.min:
            break
        print("%s%6.1f%% %7.3f ms  %s" % ("  " * depth, 100.0 * n / under, n * ms, name))
        if depth + 1 < a.depth:
            show(path + (name,), depth + 1)


if under:
    for top in sorted({path[0] for path in tree}):
        print(top)
        show((top,), 1)
    print("-- hottest leaves (self)")
    for name, n in leaves.most_common(a.self):
        print("%6.1f%% %7.3f ms  %s" % (100.0 * n / under, n * ms, name))
