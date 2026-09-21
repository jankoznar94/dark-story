#!/usr/bin/env python3
"""Diff a port frame against the PWA reference and report WHERE they differ.

  python3 tools/import/diff_frame.py town
  python3 tools/import/diff_frame.py            # all screens

Prints, per screen: the share of differing pixels and the row bands where the
difference lives, so a layout bug can be aimed at instead of eyeballed. Also writes
tools/reference/diff/<screen>.png (red = port differs from the PWA).
"""

import os
import sys

from PIL import Image, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.normpath(os.path.join(HERE, "..", "reference"))
OUT = os.path.join(REF, "diff")

SCREENS = ["town", "inventory", "hero", "shop", "chest", "craft", "gamble",
           "map", "bestiary", "spellbook"]

THRESHOLD = 24  # per-channel difference that counts as a real difference


def _group(values, gap=3):
    if not values:
        return []
    out = []
    start = prev = values[0]
    for v in values[1:]:
        if v <= prev + gap:
            prev = v
            continue
        out.append((start, prev))
        start = prev = v
    out.append((start, prev))
    return out


def diff(name):
    a_path = os.path.join(REF, "pwa", f"{name}.png")
    b_path = os.path.join(REF, "port2", f"{name}.png")
    a = Image.open(a_path).convert("RGB")
    b = Image.open(b_path).convert("RGB")
    if a.size != b.size:
        print(f"{name}: SIZE MISMATCH pwa={a.size} port={b.size}")
        return
    w, h = a.size
    d = ImageChops.difference(a, b).convert("L")
    mask = d.point(lambda v: 255 if v > THRESHOLD else 0)
    pa, pb, pm = a.load(), b.load(), mask.load()

    total = w * h
    changed = sum(1 for y in range(h) for x in range(w) if pm[x, y])

    rows = []
    for y in range(h):
        n = sum(1 for x in range(w) if pm[x, y])
        if n > w * 0.02:
            rows.append(y)

    print(f"{name}: {changed * 100.0 / total:.2f}% of pixels differ")
    bands = _group(rows, gap=4)
    if not bands:
        print("  no structured difference")
    for (y0, y1) in bands[:14]:
        # x extent inside the band
        xs = []
        for y in range(y0, y1 + 1):
            xs.extend(x for x in range(w) if pm[x, y])
        if xs:
            print(f"  rows {y0}-{y1}: x {min(xs)}-{max(xs)}")
    os.makedirs(OUT, exist_ok=True)
    overlay = Image.new("RGB", (w, h))
    op = overlay.load()
    for y in range(h):
        for x in range(w):
            if pm[x, y]:
                op[x, y] = (255, 40, 40)
            else:
                op[x, y] = tuple(c // 3 for c in pa[x, y])
    overlay.save(os.path.join(OUT, f"{name}.png"))


if __name__ == "__main__":
    args = sys.argv[1:] or SCREENS
    for s in args:
        diff(s)
