#!/usr/bin/env python3
"""Crop the SAME row band out of the PWA frame and the port frame and stack them,
so a layout difference can be looked at instead of inferred from a pixel count.

  python3 tools/import/band.py town 780 844 [more screens...]

PWA goes on top, port underneath, with a 4px separator. Writes
tools/reference/band/<screen>_<y0>_<y1>.png and prints the path.
"""

import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.normpath(os.path.join(HERE, "..", "reference"))
OUT = os.path.join(REF, "band")


def band(name, y0, y1, x0=0, x1=None):
    a = Image.open(os.path.join(REF, "pwa", f"{name}.png")).convert("RGB")
    b = Image.open(os.path.join(REF, "port2", f"{name}.png")).convert("RGB")
    if x1 is None:
        x1 = a.size[0]
    a = a.crop((x0, y0, x1, y1))
    b = b.crop((x0, y0, x1, y1))
    w, h = a.size
    canvas = Image.new("RGB", (w, h * 2 + 22 + 6), (20, 20, 20))
    canvas.paste(a, (0, 22))
    canvas.paste(b, (0, 22 + h + 6))
    d = ImageDraw.Draw(canvas)
    d.text((6, 4), f"{name} rows {y0}-{y1}  PWA (top) / PORT (bottom)", fill=(230, 230, 230))
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, f"{name}_{y0}_{y1}.png")
    canvas.save(p)
    print(p)


if __name__ == "__main__":
    args = sys.argv[1:]
    screens = [a for a in args if not a.isdigit()]
    nums = [int(a) for a in args if a.isdigit()]
    y0, y1 = (nums + [780, 844])[:2]
    for s in screens:
        band(s, y0, y1)
