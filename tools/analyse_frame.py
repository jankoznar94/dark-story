#!/usr/bin/env python3
"""MEASURE A CAPTURE instead of asking a model to describe it.

The vision pass on `corpse_world.png` reported "a dark stone next to the corpse",
which is a rock, not a defect - and it proves the point: a language model looking
at a 960x540 isometric frame cannot tell a defect from a prop. This tool answers
the questions a bug report actually asks, in numbers:

  * how much of the frame is near-black, and WHERE (a defect is a compact blob,
    a shadow is a large soft region - so the blob's size is the discriminator);
  * the same split into a coarse grid, so "top left" / "under the corpse" is a
    cell index rather than a guess;
  * `--compare` on two frames (before the fix / after) with a per-cell delta, so
    "the black object is gone" is a number that went down.

Usage:
    python3 tools/analyse_frame.py shot.png
    python3 tools/analyse_frame.py --compare before.png after.png
    python3 tools/analyse_frame.py --black 0.06 --grid 8 shot.png
"""

import argparse
import os

import numpy as np
from PIL import Image


def load(path: str) -> np.ndarray:
    img = Image.open(path).convert("RGB")
    return np.asarray(img).astype(np.float32) / 255.0


def luminance(a: np.ndarray) -> np.ndarray:
    return a @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)


def analyse(path: str, black: float, grid: int) -> dict:
    a = load(path)
    h, w, _ = a.shape
    lum = luminance(a)
    dark = lum < black

    # connected components without scipy: flood fill over the mask with a stack.
    lab = np.zeros((h, w), dtype=np.int32)
    blobs: list[dict] = []
    next_id = 0
    ys, xs = np.nonzero(dark)
    for y0, x0 in zip(ys, xs):
        if lab[y0, x0] != 0:
            continue
        next_id += 1
        stack = [(y0, x0)]
        lab[y0, x0] = next_id
        n = 0
        minx = maxx = x0
        miny = maxy = y0
        while stack:
            y, x = stack.pop()
            n += 1
            minx, maxx = min(minx, x), max(maxx, x)
            miny, maxy = min(miny, y), max(maxy, y)
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and dark[ny, nx] and lab[ny, nx] == 0:
                    lab[ny, nx] = next_id
                    stack.append((ny, nx))
        if n >= 40:      # ignore speckle
            blobs.append({
                "px": n,
                "share": n / float(h * w),
                "w": maxx - minx + 1,
                "h": maxy - miny + 1,
                "fill": n / float((maxx - minx + 1) * (maxy - miny + 1)),
                "box": (minx, miny, maxx, maxy),
            })
    blobs.sort(key=lambda b: -b["px"])

    gy, gx = np.mgrid[0:h, 0:w]
    cells = np.zeros((grid, grid), dtype=np.float32)
    counts = np.zeros((grid, grid), dtype=np.float32)
    cy = np.clip((gy * grid) // h, 0, grid - 1)
    cx = np.clip((gx * grid) // w, 0, grid - 1)
    flat_dark = dark.ravel()
    idx = (cy * grid + cx).ravel()
    np.add.at(cells.ravel(), idx, flat_dark.astype(np.float32))
    np.add.at(counts.ravel(), idx, 1.0)
    cells = (cells / counts).reshape(grid, grid)

    return {
        "path": path,
        "size": (w, h),
        "mean": float(lum.mean()),
        "p10": float(np.percentile(lum, 10)),
        "p90": float(np.percentile(lum, 90)),
        "black_share": float(dark.mean()),
        "blobs": blobs[:8],
        "cells": cells,
    }


def report(r: dict, black: float) -> None:
    print("== %s  %dx%d" % (os.path.basename(r["path"]), r["size"][0], r["size"][1]))
    print("   luma  mean %.3f  p10 %.3f  p90 %.3f" % (r["mean"], r["p10"], r["p90"]))
    print("   pixels below %.2f: %.4f of the frame" % (black, r["black_share"]))
    if not r["blobs"]:
        print("   no compact dark blob (>=40 px)")
    for b in r["blobs"]:
        print("   blob  %6d px (%.4f)  %dx%d  fill %.2f  box x%d..%d y%d..%d"
              % (b["px"], b["share"], b["w"], b["h"], b["fill"],
                 b["box"][0], b["box"][2], b["box"][1], b["box"][3]))


def grid_report(cells: np.ndarray, label: str) -> None:
    g = cells.shape[0]
    print("   %s dark fraction, %dx%d grid (rows = top to bottom):" % (label, g, g))
    for i in range(g):
        print("     " + " ".join("%5.3f" % cells[i, j] for j in range(g)))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("images", nargs="+")
    ap.add_argument("--black", type=float, default=0.08,
                    help="luminance below this counts as black (default 0.08)")
    ap.add_argument("--grid", type=int, default=8)
    ap.add_argument("--compare", action="store_true",
                    help="second image is the AFTER frame; print the change per blob/cell")
    args = ap.parse_args()

    results = [analyse(p, args.black, args.grid) for p in args.images]
    for r in results:
        report(r, args.black)

    if len(results) == 1:
        grid_report(results[0]["cells"], "")
    elif args.compare and len(results) == 2:
        before, after = results
        print("\n== CHANGE  %s -> %s" % (os.path.basename(before["path"]),
                                         os.path.basename(after["path"])))
        print("   black pixels: %.4f -> %.4f   (%+.4f)"
              % (before["black_share"], after["black_share"],
                 after["black_share"] - before["black_share"]))
        print("   mean luma:    %.3f -> %.3f" % (before["mean"], after["mean"]))
        print("   largest blob: %s -> %s"
              % (("%d px" % before["blobs"][0]["px"]) if before["blobs"] else "none",
                 ("%d px" % after["blobs"][0]["px"]) if after["blobs"] else "none"))
        d = after["cells"] - before["cells"]
        print("   per-cell change (+ = more dark):")
        for i in range(d.shape[0]):
            print("     " + " ".join("%+5.3f" % d[i, j] for j in range(d.shape[1])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
