#!/usr/bin/env python3
"""Side-by-side PWA | port frame, so a layout difference can be SEEN.

  python3 tools/import/side_by_side.py hero chest
"""

import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.normpath(os.path.join(HERE, "..", "reference"))
OUT = os.path.join(REF, "cmp")


def make(name):
    a = Image.open(os.path.join(REF, "pwa", f"{name}.png")).convert("RGB")
    b = Image.open(os.path.join(REF, "port2", f"{name}.png")).convert("RGB")
    w, h = a.size
    gap = 20
    canvas = Image.new("RGB", (w * 2 + gap, h + 24), (20, 20, 20))
    canvas.paste(a, (0, 24))
    canvas.paste(b, (w + gap, 24))
    d = ImageDraw.Draw(canvas)
    d.text((6, 6), f"{name} — PWA (left)  |  PORT (right)", fill=(230, 230, 230))
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, f"{name}.png")
    canvas.save(p)
    print(p)


if __name__ == "__main__":
    for n in sys.argv[1:]:
        make(n)
