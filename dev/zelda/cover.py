#!/usr/bin/env python3
"""Launcher icons for the Zelda ports in the style of the other covers (Skraper's mix): the screenshot behind,
a 3D N64 box and a gold cartridge at the bottom left, the logo at the bottom right, transparent, 640x480.

    dev/zelda/cover.py              both games, into dev/out/zelda/covers/<port>.png

Art comes from libretro-thumbnails (the same covers RetroArch shows) into dev/out/zelda/covers/src. It is the
games' own art, so it stays out of git: the port packs icon.png only when this has been run."""
import os
import sys
import urllib.parse
import urllib.request

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "zelda", "covers")
THUMBS = "https://raw.githubusercontent.com/libretro-thumbnails/Nintendo_-_Nintendo_64/master"
GAMES = {
    "soh": dict(name="Legend of Zelda, The - Ocarina of Time (USA)", spine=(176, 140, 52), title="OCARINA OF TIME"),
    "2ship": dict(name="Legend of Zelda, The - Majora's Mask (USA)", spine=(40, 24, 48), title="MAJORA'S MASK"),
}
GOLD = (201, 164, 72)


def fetch(kind, name):
    path = os.path.join(OUT, "src", f"{kind}-{name}.png")
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        urllib.request.urlretrieve(f"{THUMBS}/{kind}/{urllib.parse.quote(name + '.png')}", path)
    try:
        return Image.open(path).convert("RGBA")
    except OSError:
        # libretro-thumbnails keeps some regional variants as git symlinks: the file holds the target's name
        target = open(path, "rb").read().decode().strip()
        os.remove(path)
        urllib.request.urlretrieve(f"{THUMBS}/{kind}/{urllib.parse.quote(target)}", path)
        return Image.open(path).convert("RGBA")


def font(size):
    for f in ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def warp(img, quad, size):
    """img mapped onto quad (top-left, top-right, bottom-right, bottom-left) of a size canvas"""
    w, h = img.size
    src = [(0, 0), (w, 0), (w, h), (0, h)]
    a, b = [], []
    for (x, y), (u, v) in zip(quad, src):
        a += [[x, y, 1, 0, 0, 0, -u * x, -u * y], [0, 0, 0, x, y, 1, -v * x, -v * y]]
        b += [u, v]
    coeffs = np.linalg.solve(np.array(a, float), np.array(b, float))
    return img.transform(size, Image.PERSPECTIVE, tuple(coeffs), Image.BICUBIC)


def shade(img, k):
    r, g, b, a = img.split()
    return Image.merge("RGBA", [c.point(lambda v: int(v * k)) for c in (r, g, b)] + [a])


def box(front, spine_rgb, title, canvas):
    """A landscape N64 box seen from the left: spine, then the front going away"""
    x, top, bot = 4, 262, 478
    sw, fw = 30, 268
    spine = Image.new("RGBA", (bot - top, sw), spine_rgb + (255,))
    d = ImageDraw.Draw(spine)
    d.text((10, sw // 2), f"ZELDA: {title}", font=font(13), fill="white", anchor="lm")
    d.text((bot - top - 10, sw // 2), "N64", font=font(13), fill="white", anchor="rm")
    spine = spine.rotate(90, expand=True)
    layer = Image.new("RGBA", canvas.size)
    layer.alpha_composite(warp(shade(spine, 0.8), [(x, top + 7), (x + sw, top), (x + sw, bot), (x, bot - 7)], canvas.size))
    layer.alpha_composite(warp(front, [(x + sw, top), (x + sw + fw, top + 12), (x + sw + fw, bot - 12), (x + sw, bot)],
                               canvas.size))
    canvas.alpha_composite(layer)


def cartridge(label, canvas):
    """A gold US cartridge, its label cut from the box art"""
    w, h, x, y = 176, 118, 236, 362
    cart = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(cart)
    d.rounded_rectangle((0, 8, w - 1, h - 1), 10, fill=GOLD + (255,), outline=(120, 92, 30, 255), width=2)
    d.rounded_rectangle((14, 0, w - 15, 20), 6, fill=tuple(int(c * 0.9) for c in GOLD) + (255,))
    for i in range(6):
        d.line((4 + i * 3, 30, 4 + i * 3, h - 14), fill=(150, 118, 44, 255), width=1)
        d.line((w - 5 - i * 3, 30, w - 5 - i * 3, h - 14), fill=(150, 118, 44, 255), width=1)
    lw, lh = w - 46, h - 40
    art = ImageOps.fit(label.crop((0, 0, label.width - label.width // 7, label.height)), (lw, lh - 12), Image.LANCZOS,
                       centering=(0.5, 0.45))
    tag = Image.new("RGBA", (lw, lh), (0, 0, 0, 255))
    tag.paste(art, (0, 12))
    ImageDraw.Draw(tag).text((4, 6), "NINTENDO 64", font=font(9), fill="white", anchor="lm")
    cart.paste(tag, (23, 26))
    d.rectangle((22, 25, 23 + lw, 26 + lh), outline=(60, 45, 10, 255))
    shadow = Image.new("RGBA", canvas.size)
    shadow.paste((0, 0, 0, 110), (x + 6, y + 10, x + w + 6, y + h + 6))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(6)))
    canvas.alpha_composite(cart, (x, y))


def cover(port, g):
    canvas = Image.new("RGBA", (640, 480))
    shot = fetch("Named_Snaps", g["name"]).resize((536, 402), Image.LANCZOS)
    canvas.alpha_composite(shot, (100, 0))
    front = fetch("Named_Boxarts", g["name"])
    box(front, g["spine"], g["title"], canvas)
    cartridge(front, canvas)
    logo = fetch("Named_Logos", g["name"])
    logo = logo.crop(logo.getbbox())
    logo.thumbnail((300, 150), Image.LANCZOS)
    canvas.alpha_composite(logo, (636 - logo.width, 476 - logo.height))
    path = os.path.join(OUT, f"{port}.png")
    canvas.save(path)
    print(path)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for port in sys.argv[1:] or GAMES:
        cover(port, GAMES[port])
