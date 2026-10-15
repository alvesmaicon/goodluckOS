#!/usr/bin/env python3
"""One row per bench log (console-*.log from bench.sh auto, or mac-*.log from macbench.sh): fps, update and draw ms,
GL flushes, lighting, screen buffer, startup times, memory and temperature.
  benchtable.py dev/out/stardew/results/console-w1-*.log
"""
import re
import sys


def field(text, pattern, cast=float):
    m = re.search(pattern, text, re.M)
    return cast(m.group(1)) if m else None


def probe(text, name, col):
    m = re.search(r"^probe %s ([\d.]+) ms/s ([\d.]+) ms/\w+ ([\d.]+) calls" % re.escape(name), text, re.M)
    return float(m.group(col)) if m else None


cols = ["run", "fps", "update", "draw", "flush", "draws", "light", "screen", "title_s", "load_s", "avail_MB", "soc_C"]
print("| " + " | ".join(cols) + " |")
print("|" + "---|" * len(cols))
for path in sys.argv[1:]:
    t = open(path, errors="replace").read()
    name = re.sub(r"^.*/(console|mac)-|\.log$", "", path)
    light = [probe(t, n, 2) for n in ("Game1.DrawLighting", "Game1.DrawLightmapOnScreen")]
    row = [
        name,
        field(t, r"^bench .* fps ([\d.]+)"),
        field(t, r"^bench .* update ([\d.]+) ms"),
        field(t, r"^bench .* draw ([\d.]+) ms"),
        probe(t, "SpriteBatcher.FlushVertexArray", 2),
        probe(t, "SpriteBatcher.FlushVertexArray", 3),
        sum(light) if None not in light else None,
        probe(t, "Game1.renderScreenBuffer", 2),
        field(t, r"title after (\d+) s", int),
        field(t, r"loaded after (\d+) s", int),
        (lambda v: v and round(v / 1024))(field(t, r"^mem min avail (\d+)")),
        field(t, r"max soc ([\d.]+)"),
    ]
    print("| " + " | ".join("-" if v is None else ("%.1f" % v if isinstance(v, float) else str(v)) for v in row) + " |")
