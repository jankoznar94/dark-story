#!/usr/bin/env python3
"""Compare the PWA's and the port's map frames row-band by row-band, to locate the
COLOURED / DESATURATED split Jan reports on the map's artwork.

  python3 tools/import/map_bands.py <pwa.png> <port.png> [--crop x0,x1]

Prints, for each card band, the mean saturation per row and the mean RGB, so a band of
"70 % coloured, 30 % grey" is visible as a step in `sat` at a specific row rather than as a
gut feeling about a thumbnail.
"""
import sys

import numpy as np
from PIL import Image


def bands(path, crop=None):
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.int16)
    if crop:
        a = a[:, crop[0]:crop[1]]
    sat = a.max(axis=2) - a.min(axis=2)
    return a, sat


def main():
    pwa_path, port_path = sys.argv[1], sys.argv[2]
    crop = (16, 374)
    for path, name in ((pwa_path, "PWA"), (port_path, "PORT")):
        a, sat = bands(path, crop)
        print(f"== {name} {path} {a.shape}")
        for y in range(80, 340, 4):
            print(f"  y{y:3d} sat {sat[y].mean():5.1f}  mean {a[y].mean(axis=0).round(0)}"
                  f"  p10 {np.percentile(sat[y], 10):5.1f}")


if __name__ == "__main__":
    main()
