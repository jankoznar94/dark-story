#!/usr/bin/env python3
"""Generic procedural texture generator for Dark Story.

WHY THIS EXISTS: texture work was done with one-off scripts (ds_tex_gen.py,
ds_build_atlas{,2,3,4}.py, make_floor_texture.py), each re-implementing the same
noise, tiling, grading and seam-check code. Adding a second surface meant writing
a third script. This is the one place surfaces are defined: a RECIPE per surface,
all sharing the same seamless-by-construction noise and the same verification.

Every recipe is:
  * seamless by construction (all noise sampled from a periodic lattice)
  * deterministic (--seed), so a texture is regenerated, never hand-edited
  * verified on write: seam continuity, tonal spread, channel balance
  * cheap (one 512/1024 px albedo, no baked lighting - that fights the engine)

Usage:
    python3 tools/make_texture.py --list
    python3 tools/make_texture.py ground_grass
    python3 tools/make_texture.py --all
    python3 tools/make_texture.py stone_wall --size 1024 --seed 7 --out /tmp
    python3 tools/make_texture.py --all --dry-run          # metrics only, no files

Adding a surface means adding one function to RECIPES that returns an HxWx3 uint8
array; everything else (tiling, checks, reporting) is shared.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "assets", "textures")
SEED = 20260919
LUMW = np.array([0.2126, 0.7152, 0.0722])


# --------------------------------------------------------------------------- #
# noise: periodic lattice, so anything built from it tiles seamlessly
# --------------------------------------------------------------------------- #
def lattice(size, freq, rng):
    g = rng.random((freq, freq))
    x = np.linspace(0.0, freq, size, endpoint=False)
    xi = np.floor(x).astype(int) % freq
    xf = x - np.floor(x)
    sx = xf * xf * (3.0 - 2.0 * xf)
    x1 = (xi + 1) % freq
    a = g[np.ix_(xi, xi)]
    b = g[np.ix_(xi, x1)]
    c = g[np.ix_(x1, xi)]
    d = g[np.ix_(x1, x1)]
    top = a + (b - a) * sx[None, :]
    bot = c + (d - c) * sx[None, :]
    return top + (bot - top) * sx[:, None]


def fbm(size, octaves, base, rng, gain=0.5):
    out = np.zeros((size, size))
    amp, freq, norm = 1.0, base, 0.0
    for _ in range(octaves):
        out += amp * lattice(size, freq, rng)
        norm += amp
        amp *= gain
        freq *= 2
    return out / max(norm, 1e-9)


def ridged(size, octaves, base, rng):
    return 1.0 - np.abs(2.0 * fbm(size, octaves, base, rng) - 1.0)


def mix(base, colour, amount):
    """base: HxWx3 float. colour: 3-tuple. amount: HxW in [0,1]."""
    return base + (np.asarray(colour, float)[None, None, :] - base) * amount[..., None]


# --------------------------------------------------------------------------- #
# recipes: each returns (H, W, 3) uint8 in sRGB
# --------------------------------------------------------------------------- #
# The project palette. Warm, dark and DESATURATED, but the ground must stay
# green-dominant or it reads as more brown-on-brown (measured failure: the first
# grass had R 93.8 > G 84.8).
def ground_grass(size, rng):
    macro = fbm(size, 2, 2, rng)
    clumps = fbm(size, 4, 6, rng)
    grain = fbm(size, 4, 48, rng)
    ridge = ridged(size, 3, 40, rng)
    blades = fbm(size, 3, 64, rng)
    strokes = np.clip((ridged(size, 3, 72, rng) - 0.35) * 1.9, 0.0, 1.0)
    deep = np.array([15.0, 21.0, 13.0])
    mid = np.array([35.0, 52.0, 28.0])
    dry = np.array([82.0, 86.0, 44.0])
    m1 = np.clip(clumps * 1.35 - 0.12, 0.0, 1.0)
    a = deep[None, None, :] + (mid - deep)[None, None, :] * m1[..., None]
    a *= (1.0 + (macro - 0.5) * 0.7)[..., None]
    blade = np.clip((grain - 0.40) * 2.6, 0.0, 1.0) * np.clip(ridge * 1.3, 0.0, 1.0)
    a = mix(a, dry, blade * 0.72)
    a = mix(a, dry, strokes * blades * 0.80)
    return a


def stone_wall(size, rng):
    """Grey-brown masonry blocks with mortar lines and lichen patches."""
    cell = max(8, size // 8)
    yy, xx = np.mgrid[0:size, 0:size]
    row = yy // (cell // 2)
    # off-set every other course so it reads as bonded masonry, and make the
    # offset itself periodic (size must divide evenly or the tile will not wrap)
    off = (row % 2) * (cell // 2)
    bx = ((xx + off) % cell) / float(cell)
    by = (yy % (cell // 2)) / float(cell // 2)
    mortar = (np.clip(1.0 - np.minimum(bx, 1.0 - bx) * 14.0, 0.0, 1.0)
              + np.clip(1.0 - np.minimum(by, 1.0 - by) * 14.0, 0.0, 1.0))
    mortar = np.clip(1.0 - mortar, 0.0, 1.0)
    grain = fbm(size, 4, 24, rng)
    blocks = 0.72 + 0.42 * fbm(size, 3, 5, rng)
    deep = np.array([54.0, 51.0, 46.0])
    light = np.array([128.0, 122.0, 110.0])
    base = deep[None, None, :] + (light - deep)[None, None, :] * blocks[..., None]
    # mortar is darker and flatter
    base = mix(base, np.array([38.0, 36.0, 34.0]), mortar * 0.85)
    # moss/lichen in the joints
    lichen = np.clip((fbm(size, 3, 3, rng) - 0.55) * 2.6, 0.0, 1.0) * (1.0 - mortar)
    base = mix(base, np.array([48.0, 60.0, 36.0]), lichen * 0.55)
    base = mix(base, np.array([150.0, 143.0, 130.0]), np.clip((grain - 0.5) * 1.6, 0.0, 1.0) * 0.22)
    return base


def bark(size, rng):
    """Vertical fissures - directional so it reads as bark, not stone."""
    stretch = ridged(size, 4, 40, rng)
    # squash horizontally to make the ridges vertical
    v = fbm(size, 4, 6, rng)
    fissure = np.clip(1.0 - np.abs(v - 0.5) * 3.4, 0.0, 1.0)
    deep = np.array([52.0, 40.0, 31.0])
    light = np.array([112.0, 92.0, 72.0])
    a = deep[None, None, :] + (light - deep)[None, None, :] * (0.35 + 0.65 * stretch)[..., None]
    a = mix(a, np.array([30.0, 23.0, 18.0]), fissure * 0.70)
    return a


def cloth(size, rng):
    """Woven weave - a cheap over/under pattern plus fibre noise."""
    yy, xx = np.mgrid[0:size, 0:size]
    period = max(4, size // 32)
    warp = 0.5 + 0.5 * np.cos(2 * np.pi * xx / period)
    weft = 0.5 + 0.5 * np.cos(2 * np.pi * yy / period)
    weave = np.maximum(warp, weft) * 0.6 + np.minimum(warp, weft) * 0.4
    fibre = fbm(size, 4, 40, rng)
    stains = fbm(size, 3, 3, rng)
    deep = np.array([44.0, 38.0, 32.0])
    light = np.array([96.0, 84.0, 70.0])
    a = deep[None, None, :] + (light - deep)[None, None, :] * weave[..., None]
    a = mix(a, np.array([26.0, 22.0, 19.0]), np.clip((0.5 - stains) * 1.4, 0.0, 1.0) * 0.45)
    a += (fibre[..., None] - 0.5) * 14.0
    return a


def metal_plate(size, rng):
    """Dull hammered iron - small dents, no specular bake (the engine lights it).

    First version measured lum 95.7 with rust at sat 0.053, and came back as
    "clearly lighter and cleaner than the rest - darken it, rust it, dirty it".
    The project palette is dark; a bright clean plate was the odd one out.
    """
    dents = ridged(size, 4, 14, rng)
    grain = fbm(size, 4, 48, rng)
    # much more rust, and it now covers rather than tints
    rust = np.clip((fbm(size, 3, 4, rng) - 0.40) * 2.2, 0.0, 1.0)
    pitting = np.clip((fbm(size, 4, 30, rng) - 0.55) * 2.6, 0.0, 1.0)
    deep = np.array([30.0, 31.0, 33.0])
    light = np.array([78.0, 80.0, 84.0])
    a = deep[None, None, :] + (light - deep)[None, None, :] * (0.3 + 0.7 * dents)[..., None]
    a = mix(a, np.array([96.0, 46.0, 22.0]), rust * 0.85)
    a = mix(a, np.array([18.0, 16.0, 15.0]), pitting * 0.55)
    a += (grain[..., None] - 0.5) * 12.0
    return a


def dirt_path(size, rng):
    """Trodden earth with grit - a path to lay over grass."""
    clumps = fbm(size, 4, 5, rng)
    grit = np.clip((fbm(size, 4, 56, rng) - 0.62) * 3.0, 0.0, 1.0)
    deep = np.array([46.0, 38.0, 29.0])
    light = np.array([116.0, 100.0, 78.0])
    a = deep[None, None, :] + (light - deep)[None, None, :] * clumps[..., None]
    a = mix(a, np.array([140.0, 134.0, 122.0]), grit * 0.35)
    return a


RECIPES = {
    "ground_grass": ground_grass,
    "stone_wall": stone_wall,
    "bark": bark,
    "cloth": cloth,
    "metal_plate": metal_plate,
    "dirt_path": dirt_path,
}
# per-recipe sanity targets: (min std, max allowed |seam|, expected cast)
CAST = {
    "ground_grass": "green",
    "stone_wall": "neutral",
    "bark": "warm",
    "cloth": "neutral",
    "metal_plate": "cool",
    "dirt_path": "warm",
}


def verify(a, name, size):
    """Seam + tonal + cast checks. Returns (ok, list of messages)."""
    a = np.asarray(a).astype(np.float64)
    lum = a @ LUMW
    msgs, ok = [], True
    # seam: the wrap-around column/row difference must not exceed the interior
    ai = np.asarray(a).astype(int)
    dlr = np.abs(ai[:, 0] - ai[:, -1]).mean()
    dud = np.abs(ai[0, :] - ai[-1, :]).mean()
    dint = np.abs(ai[:, 1] - ai[:, 0]).mean()
    dintv = np.abs(ai[1, :] - ai[0, :]).mean()
    seamless = dlr <= dint * 1.8 + 1.0 and dud <= dintv * 1.8 + 1.0
    msgs.append("seam: |col0-colN| %.2f vs interior %.2f, |row0-rowN| %.2f vs %.2f -> %s"
                % (dlr, dint, dud, dintv, "seamless" if seamless else "SEAM VISIBLE"))
    ok &= seamless
    # tonal spread: a flat texture is the thing that caused the brown-on-brown world
    msgs.append("tonal: std %5.1f  p10 %5.1f  p50 %5.1f  p90 %5.1f  -> %s"
                % (lum.std(), *np.percentile(lum, [10, 50, 90]),
                   "has structure" if lum.std() >= 6.0 else "TOO FLAT"))
    ok &= lum.std() >= 6.0
    # cast
    ch = a.mean(axis=(0, 1))
    cast = CAST.get(name, "neutral")
    if cast == "green":
        good = ch[1] - ch[0] > 2.0
        msgs.append("cast: G-R %+.1f (green surface must be positive) -> %s"
                    % (ch[1] - ch[0], "ok" if good else "READS BROWN"))
        ok &= good
    mx, mn = a.max(axis=2), a.min(axis=2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0).mean()
    msgs.append("channels R %.1f G %.1f B %.1f  sat %.3f (desaturated target < 0.55) -> %s"
                % (ch[0], ch[1], ch[2], sat, "ok" if sat < 0.55 else "TOO SATURATED"))
    ok &= sat < 0.55
    return ok, msgs


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("recipes", nargs="*")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--seed", type=int, default=SEED)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--dry-run", action="store_true", help="metrics only, write nothing")
    args = ap.parse_args()

    if args.list or (not args.recipes and not args.all):
        print("recipes: %s" % ", ".join(sorted(RECIPES)))
        print("\nusage: make_texture.py [--all | <recipe> ...] [--size N] [--seed N] [--out DIR]")
        return 0

    names = sorted(RECIPES) if args.all else args.recipes
    unknown = [n for n in names if n not in RECIPES]
    if unknown:
        print("unknown recipe(s): %s\nknown: %s" % (unknown, ", ".join(sorted(RECIPES))))
        return 1
    if not args.dry_run:
        os.makedirs(args.out, exist_ok=True)

    failures = 0
    written = []
    for name in names:
        rng = np.random.default_rng(args.seed)
        a = np.clip(RECIPES[name](args.size, rng), 0, 255).astype(np.uint8)
        img = Image.fromarray(a)
        ok, msgs = verify(img, name, args.size)
        path = os.path.join(args.out, "%s.png" % name)
        head = "%-14s %dx%d  %s" % (name, args.size, args.size,
                                    "OK" if ok else "FAILED")
        print(head)
        for m in msgs:
            print("    " + m)
        if not args.dry_run:
            img.save(path, "PNG", optimize=True)
            print("    wrote %s (%d B)" % (path, os.path.getsize(path)))
            written.append(path)
        if not ok:
            failures += 1
    print("\nTEXTURES %d  failed %d" % (len(names), failures))
    if written:
        print("files: %s" % ", ".join(os.path.basename(w) for w in written))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
