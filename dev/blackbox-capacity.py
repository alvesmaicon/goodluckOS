#!/usr/bin/env python3
"""Battery capacity from a black box log (blackbox.sh): the mAh that went in or out in each stretch of charging or
discharging, by integrating the current over the uptime, next to the fuel gauge's own figures.

  dev/blackbox-capacity.py <log>...     current.log, prev.N.gz or HOME/logs/blackbox-prev.txt

A stretch ends when the status changes or the console boots again. The counter column exists only on the RK817
(the R36H); the A33's AXP keeps it in registers the log does not have.
"""
import gzip, sys


def rows(path):
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("# boot"):
                yield None
                continue
            if not line or line[0] in "#P" or ";" in line:
                continue
            p = line.split()
            if len(p) < 18 or p[0].count(":") != 2:
                continue
            try:
                up, mv, ma, cap = float(p[1]), int(p[2]), int(p[3]), int(p[4])
            except ValueError:
                continue
            st = p[5]
            cnt = int(p[19]) if len(p) > 19 and p[19].lstrip("-").isdigit() else None
            yield (p[0], up, mv, ma, cap, st, cnt)


def flush(seg, out):
    if len(seg) < 2:
        return
    mah = 0.0
    for a, b in zip(seg, seg[1:]):
        mah += (a[3] + b[3]) / 2 * (b[1] - a[1]) / 3600
    f, l = seg[0], seg[-1]
    hours = (l[1] - f[1]) / 3600
    cnt = f"  counter {f[6]} -> {l[6]} mAh ({l[6] - f[6]:+d})" if f[6] is not None and l[6] is not None else ""
    out.append(f"{f[5]:<12} {f[0]} -> {l[0]}  {hours:5.2f} h  {mah:+8.0f} mAh ({mah / hours if hours else 0:+.0f} mA avg)"
               f"  {f[2]} -> {l[2]} mV  {f[4]} -> {l[4]} %{cnt}")


for path in sys.argv[1:] or sys.exit(__doc__):
    print(f"== {path}")
    seg, out = [], []
    for r in rows(path):
        if r is None or (seg and r[5] != seg[-1][5]):
            flush(seg, out)
            seg = []
        if r is not None:
            seg.append(r)
    flush(seg, out)
    print("\n".join(out) if out else "no battery lines")
