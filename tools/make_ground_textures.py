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

## The three tiles a ZONE THEME picks between (`scripts/ui/zone_theme.gd`). Only THREE new
## tiles on purpose: the ten zones of act 1 differ by TINT, WALL MATERIAL and PROPS as well,
## and every extra 512px tile is ~150 KB of the web build's first load.
##   needles  conifer litter — a dense forest floor
##   gravel   scree and broken stone — mountains, ruins, river banks
##   mud      swamp / riverbank — wet, dark, with standing water
NEEDLES = {
    "name": "needles",
    "style": "needles",
    "base": (0x3B, 0x2E, 0x21),
    "patches": [(0x33, 0x27, 0x1B), (0x46, 0x36, 0x25)],
    "blade_dark": (0x2B, 0x20, 0x16),
    "blade_light": (0x59, 0x41, 0x28),
    "blade_dry": (0x6B, 0x4E, 0x2D),
    "speck": (0x4B, 0x39, 0x26),
}

GRAVEL = {
    "name": "gravel",
    "style": "pebbles",
    "base": (0x4C, 0x4A, 0x45),
    "patches": [(0x42, 0x40, 0x3C), (0x57, 0x54, 0x4D)],
    "blade_dark": (0x39, 0x37, 0x33),
    "blade_light": (0x6A, 0x66, 0x5D),
    "blade_dry": (0x7A, 0x74, 0x68),
    "speck": (0x33, 0x31, 0x2E),
    "pebble": [(0x44, 0x42, 0x3D), (0x55, 0x52, 0x4B), (0x63, 0x5F, 0x56), (0x38, 0x36, 0x32)],
}

## ⚠️  The first version was the DARKEST surface in the game (base 0x33352A) and a capture of
## zone 3 read as a black hole: a tint can only multiply DOWN, so a tile that is too dark cannot
## be rescued per zone. The bog is dim, not unlit — one step up from the grass, not three.
MUD = {
    "name": "mud",
    "style": "mud",
    "base": (0x4B, 0x4E, 0x3C),
    "patches": [(0x41, 0x45, 0x35), (0x57, 0x59, 0x45)],
    "blade_dark": (0x38, 0x3C, 0x2E),
    "blade_light": (0x62, 0x66, 0x4C),
    "blade_dry": (0x74, 0x6C, 0x4A),
    "speck": (0x31, 0x34, 0x28),
}

GRASS = {
    "name": "grass",
    "style": "blades",
    "base": (0x4A, 0x4A, 0x36),
    "patches": [(0x3F, 0x40, 0x2E), (0x52, 0x52, 0x3B)],
    "blade_dark": (0x38, 0x39, 0x29),
    "blade_light": (0x61, 0x62, 0x45),
    "blade_dry": (0x6C, 0x63, 0x42),
    "speck": (0x59, 0x59, 0x40),
}

DIRT = {
    "name": "dirt",
    "style": "blades",
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

    style = spec.get("style", "blades")
    if style == "pebbles":
        _pebbles(d, spec, rnd)
    elif style == "mud":
        _mud(d, spec, rnd)
    else:
        _blades(d, spec, rnd)

    # fine speckle so a magnified tile is not flat
    for _ in range(2400):
        x, y = rnd.uniform(0, SIZE), rnd.uniform(0, SIZE)
        d.point((x, y), fill=spec["speck"] + (rnd.randint(60, 140),))
    return im


## Grass and conifer litter: short strokes, mostly pointing one way.
def _blades(d, spec, rnd):
    needles = spec.get("style") == "needles"
    # More, longer and straighter strokes for litter: needles lie flat in every direction,
    # where grass stands up. That single difference is what makes the two read apart.
    count = 5200 if not needles else 4200
    spread = 0.55 if not needles else 2.4
    for _ in range(count):
        x, y = rnd.uniform(0, SIZE), rnd.uniform(0, SIZE)
        ang = -math.pi / 2 + rnd.gauss(0, spread)
        ln = rnd.uniform(5, 13) if not needles else rnd.uniform(7, 16)
        r = rnd.random()
        col = spec["blade_dark"] if r < 0.45 else (spec["blade_light"] if r < 0.85 else spec["blade_dry"])
        _blade(d, x, y, ang, ln, col + (rnd.randint(150, 235),))


## Scree: overlapping pebbles and a few dark cracks between them.
def _pebbles(d, spec, rnd):
    tones = spec["pebble"]
    for _ in range(2600):
        x, y = rnd.uniform(0, SIZE), rnd.uniform(0, SIZE)
        rx = rnd.uniform(3, 13)
        ry = rx * rnd.uniform(0.55, 1.0)
        ang = rnd.uniform(0, math.pi)
        col = rnd.choice(tones)
        pts = []
        for k in range(7):
            a = ang + k * math.tau / 7.0
            rr = rnd.uniform(0.72, 1.0)
            pts.append((math.cos(a) * rx * rr, math.sin(a) * ry * rr))
        # one lit edge per pebble so a grey field has structure, not a flat wash
        for ox, oy in _wrap_xy(x, y):
            d.polygon([(ox + px, oy + py) for px, py in pts], fill=col + (rnd.randint(150, 225),))
    for _ in range(260):
        x, y = rnd.uniform(0, SIZE), rnd.uniform(0, SIZE)
        ln = rnd.uniform(6, 22)
        ang = rnd.uniform(0, math.pi)
        for ox, oy in _wrap_xy(x, y):
            d.line([(ox, oy), (ox + math.cos(ang) * ln, oy + math.sin(ang) * ln)],
                   fill=spec["blade_dark"] + (rnd.randint(70, 130),), width=1)


## Wet ground: dark standing water, mud ridges and a few reed stubs.
def _mud(d, spec, rnd):
    for _ in range(120):
        x, y = rnd.uniform(0, SIZE), rnd.uniform(0, SIZE)
        rx, ry = rnd.uniform(18, 62), rnd.uniform(12, 40)
        # `+ alpha 90..140` over a dark base: water reads as SLIGHTLY darker and colder,
        # never as a blue puddle — no glow, no highlight (Jan's rule).
        col = (0x24, 0x2A, 0x26) if rnd.random() < 0.6 else (0x3E, 0x3F, 0x30)
        for ox, oy in _wrap_xy(x, y):
            d.ellipse([ox - rx, oy - ry, ox + rx, oy + ry], fill=col + (rnd.randint(70, 125),))
    for _ in range(900):
        x, y = rnd.uniform(0, SIZE), rnd.uniform(0, SIZE)
        ang = rnd.uniform(-0.3, 0.3) + (0.0 if rnd.random() < 0.8 else math.pi / 2)
        ln = rnd.uniform(6, 18)
        col = spec["blade_light"] if rnd.random() < 0.5 else spec["blade_dry"]
        for ox, oy in _wrap_xy(x, y):
            d.line([(ox, oy), (ox + math.cos(ang) * ln, oy + math.sin(ang) * ln)],
                   fill=col + (rnd.randint(90, 170),), width=1)


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
    for spec, seed in ((GRASS, 11), (DIRT, 23), (NEEDLES, 31), (GRAVEL, 47), (MUD, 59)):
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
