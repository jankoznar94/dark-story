#!/usr/bin/env python3
"""Measure a reference frame: where the structural borders sit, so a layout can be read
off the PWA instead of guessed.

  python3 tools/import/measure_frame.py tools/reference/pwa/town.png [colour]

Prints the y bands of rows that are mostly border-coloured plus the x runs inside each,
which is how a tile's real width/height and the grid gap come out of a PNG.
"""

import sys

from PIL import Image

BORDER = (0x33, 0x33, 0x33)


def _near(p, target, tol=12):
    return all(abs(p[c] - target[c]) <= tol for c in range(3))


def _group(values):
    if not values:
        return []
    out = []
    start = prev = values[0]
    for v in values[1:]:
        if v == prev + 1:
            prev = v
            continue
        out.append((start, prev))
        start = prev = v
    out.append((start, prev))
    return out


def main(path, target=BORDER):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    print(f"{path}: {w}x{h}")

    rows = []
    for y in range(h):
        hits = sum(1 for x in range(16, w - 16, 2) if _near(px[x, y], target))
        if hits * 2 > (w - 32) * 0.30:
            rows.append(y)
    groups = _group(rows)
    print("row bands:", groups)

    for band in groups[:10]:
        y = band[0]
        cols = [x for x in range(w) if _near(px[x, y], target)]
        print(f"  y={y}: x runs {_group(cols)}")


if __name__ == "__main__":
    argv = sys.argv[1:]
    colour = BORDER
    if len(argv) > 1:
        c = argv[1].lstrip("#")
        colour = tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))
    main(argv[0], colour)
