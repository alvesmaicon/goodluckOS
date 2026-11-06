#!/usr/bin/env python3
"""uboot-patch.py <uboot.img> <out> [min-mV] - the factory U-Boot of the R36H, patched in its first copy.

<uboot.img> is the uboot partition as read from the card, 4 copies of 1 MiB from sector 0x4000:
  dd if=/dev/mmcblk0 of=uboot.img bs=512 skip=16384 count=8192
<out> is the first copy alone, to write back at sector 0x4000 (count=2048); the other three stay stock.
Two changes, then the header's SHA-256 and CRC are made again:
- without a charger it refuses to boot below 3530 mV (odroidgoa_power.c): min-mV instead, 3300 by default
- its text console is 320 px wide, the ODROID-GO Advance's panel, on a 640 px framebuffer: every line
  comes out in two halves, side by side; 640 px makes it the panel's width."""
import hashlib, struct, sys

LOAD, SIZE = 0x200000, 0xfc838
STOCK_SHA = "c083d295aa35ff872e8ec91ff22dd07fed77dd4f920d090558dc4484ea7b7363"
GATE, WIDTH = 0x20665c, 0x259ef4                     # cmp w0, #3529 / mov w0, #320


def rkcrc(data):
    tab = []
    for i in range(256):
        c = i << 24
        for _ in range(8):
            c = ((c << 1) ^ 0x04c10db7) if c & 0x80000000 else c << 1
        tab.append(c & 0xffffffff)
    c = 0
    for x in data:
        c = ((c << 8) & 0xffffffff) ^ tab[(c >> 24) ^ x]
    return c


def sha(data, hlen=32):
    return hashlib.sha256(data + struct.pack("<3I", LOAD, len(data), hlen)).digest()


def word(img, addr, value=None):
    o = 0x800 + addr - LOAD
    if value is not None:
        img[o:o + 4] = struct.pack("<I", value)
    return struct.unpack("<I", img[o:o + 4])[0]


if len(sys.argv) not in (3, 4):
    sys.exit(__doc__)
mv = int(sys.argv[3]) if len(sys.argv) == 4 else 3300
img = bytearray(open(sys.argv[1], "rb").read()[:0x100000])
if img[:8] != b"LOADER  " or struct.unpack("<2I", img[0x10:0x18]) != (LOAD, SIZE) or img[0x20:0x40].hex() != STOCK_SHA:
    sys.exit("not the stock U-Boot this patch was made for")
assert word(img, GATE) == 0x7137241f and word(img, WIDTH) == 0x52802800
assert 2800 <= mv <= 4095
word(img, GATE, 0x7100001f | (mv - 1) << 10)         # cmp w0, #mv-1: boot when above it
word(img, WIDTH, 0x52800000 | 640 << 5)              # mov w0, #640
data = bytes(img[0x800:0x800 + SIZE])
img[0x18:0x1c] = struct.pack("<I", rkcrc(data))
img[0x20:0x40] = sha(data)
open(sys.argv[2], "wb").write(img)
print(f"{sys.argv[2]}: boots from {mv} mV without a charger, text console 640 px")
