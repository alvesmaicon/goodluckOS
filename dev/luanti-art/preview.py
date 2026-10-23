#!/usr/bin/env python3
# Dev: a sheet of textures at 8x, on a dark ground, to look at new pixel art
#   python3 dev/luanti-art/preview.py out.png a.png b.png ...
import sys
from PIL import Image
files = sys.argv[2:]
cols = min(8, len(files))
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGBA", (cols * 138, rows * 138), (48, 48, 48, 255))
for i, f in enumerate(files):
    t = Image.open(f).convert("RGBA").resize((128, 128), Image.NEAREST)
    sheet.paste(t, ((i % cols) * 138 + 5, (i // cols) * 138 + 5), t)
sheet.save(sys.argv[1])
