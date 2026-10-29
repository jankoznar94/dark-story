#!/usr/bin/env python3
"""Seamless ground tiles for the survivor arena.

The project has painted landscapes for the journey screen (assets/areas) but no
TOP-DOWN ground texture, so this generates one: a 256x256 tile that repeats without
a visible seam and matches the palette Jan locked (warm, desaturated, no glow).

  python3 tools/make_ground_textures.py            # writes assets/ground/*.png
  python3 tools/make_ground_textures.py --check    # prints the seam metric only

Seam rule: every stroke/ellipse is drawn 9 times, once per wrap offset, so anything
that leaves the right edge arrives on the left. A tile is only seamless when the two
opposing edges are drawn from the SAME data — retouching the seam afterwards is what
produces the visible grid this game must not have.
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw

## 512 instead of 256: a 256 px tile repeats 1.5x across a 390 px phone screen, which read as
## wallpaper. The tile must be BIGGER than the viewport on its short axis, or the repetition is
## the first thing the eye finds.
SIZE = 512
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "ground")

GRASS = {
    "name": "grass",
    "base": (0x4A, 0x4A, 0x36),
    "patches": [(0x3F, 0x40, 0x2E), (0x52, 0x52, 0x3B)],
    "blade_dark": (0x38, 0x39, 0x29),
    "blade_light": (0x61, 0x62, 0x45),
    "blade_dry": (0x6C, 0x63, 0x42),
    "speck": (0x59, 0x59, 0x40),
}

DIRT = {
    "name": "dirt",
    "base": (0x5A, 0x50, 0x3E),
    "patches": [(0x51, 0x48, 0x37), (0x64, 0x59, 0x45)],
    "blade_dark": (0x46, 0x3E, 0x30),
    "blade_light": (0x6E, 0x62, 0x4C),
    "blade_dry": (0x74, 0x68, 0x50),
    "speck": (0x4E, 0x45, 0x36),
}


def _wrap_xy(x, y):
    for dx in (-SIZE, 0, SIZE):
        for dy in (-SIZE, 0, SIZE):
            yield x + dx, y + dy


def _blade(d, x, y, ang, ln, col, w=1):
    """One grass blade: a two-segment stroke that curls."""
    x2 = x + math.cos(ang) * ln * 0.55
    y2 = y + math.sin(ang) * ln * 0.55
    x3 = x2 + math.cos(ang + 0.5) * ln * 0.45
    y3 = y2 + math.sin(ang + 0.5) * ln * 0.45
    for ox, oy in _wrap_xy(x, y):
        d.line([(ox, oy), (ox + (x2 - x), oy + (y2 - y))], fill=col, width=w)
        d.line([(ox + (x2 - x), oy + (y2 - y)), (ox + (x3 - x), oy + (y3 - y))], fill=col, width=1)


def build(spec, seed):
    rnd = random.Random(seed)
    im = Image.new("RGB", (SIZE, SIZE), spec["base"])
    d = ImageDraw.Draw(im, "RGBA")

    # soft tonal patches, wrapped so the tile has no flat average
    for _ in range(70):
        x, y = rnd.uniform(0, SIZE), rnd.uniform(0, SIZE)
        rx, ry = rnd.uniform(44, 124), rnd.uniform(32, 88)
        col = rnd.choice(spec["patches"])
        for ox, oy in _wrap_xy(x, y):
            d.ellipse([ox - rx, oy - ry, ox + rx, oy + ry], fill=col + (rnd.randint(16, 30),))

    # blades — short, dense, mostly pointing up
    for _ in range(5200):
        x, y = rnd.uniform(0, SIZE), rnd.uniform(0, SIZE)
        ang = -math.pi / 2 + rnd.gauss(0, 0.55)
        ln = rnd.uniform(5, 13)
        r = rnd.random()
        col = spec["blade_dark"] if r < 0.45 else (spec["blade_light"] if r < 0.85 else spec["blade_dry"])
        _blade(d, x, y, ang, ln, col + (rnd.randint(150, 235),))

    # fine speckle so a magnified tile is not flat
    for _ in range(2400):
        x, y = rnd.uniform(0, SIZE), rnd.uniform(0, SIZE)
        d.point((x, y), fill=spec["speck"] + (rnd.randint(60, 140),))
    return im


def seam_error(im):
    """Mean |left-right| and |top-bottom| over the tile edges, against the tile's own
    mean neighbour difference. A seamless tile scores ~1.0 or below."""
    px = im.convert("L").load()
    w, h = im.size
    lr = sum(abs(px[0, y] - px[w - 1, y]) for y in range(h)) / h
    tb = sum(abs(px[x, 0] - px[x, h - 1]) for x in range(w)) / w
    inner = sum(abs(px[w // 2, y] - px[w // 2 + 1, y]) for y in range(h)) / h
    return lr, tb, (lr + tb) / (2 * max(inner, 1e-6))


def main():
    os.makedirs(OUT, exist_ok=True)
    check = "--check" in sys.argv
    for spec, seed in ((GRASS, 11), (DIRT, 23)):
        im = build(spec, seed)
        lr, tb, ratio = seam_error(im)
        path = os.path.join(OUT, spec["name"] + ".png")
        if not check:
            im.save(path, optimize=True)
        print("%-6s %s  seam lr=%.2f tb=%.2f  ratio=%.2f  bytes=%d"
              % (spec["name"], "check" if check else "wrote", lr, tb, ratio,
                 0 if check else os.path.getsize(path)))


if __name__ == "__main__":
    main()
