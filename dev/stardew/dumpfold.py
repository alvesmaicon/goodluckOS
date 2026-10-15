#!/usr/bin/env python3
"""Mono thread dumps (SIGQUIT) in a log -> the main thread's stacks, folded (root;...;leaf 1), for folded.py.
  dumpfold.py <log or log.gz> > out.folded
A poor man's profiler for the console, where perf is not available: bench.sh sample sends one dump every 1.5 s.
"""
import collections
import gzip
import re
import sys

path = sys.argv[1]
text = (gzip.open if path.endswith(".gz") else open)(path, "rt", errors="replace").read()
stacks = collections.Counter()
for dump in text.split("Full thread dump:")[1:]:
    for block in re.split(r'\n(?=")', dump):
        frames = re.findall(r"^\s+at (.+)$", block, re.M)
        if not any("StardewValley.Program.Main" in f for f in frames):
            continue
        names = []
        for f in frames:
            f = re.sub(r"^\((wrapper [a-z-]+)\) ", r"\1 ", f)
            f = re.sub(r" \(.*$| <0x.*$| \[0x.*$", "", f)
            names.append(f.replace(";", ","))
        stacks[";".join(reversed(names))] += 1
        break
for k, v in stacks.items():
    print(k, v)
