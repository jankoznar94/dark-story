#!/usr/bin/env python3
"""Draw assets/items/coin_gold.png — the icon for the result page's GOLD row.

Jan's rule is that the game contains NO emoji: every slot, buff, spell and icon is a real
image under assets/. The gold row on the result page is the same case, so it gets one.

Drawn from code on purpose: it is a flat, three-tone coin in the same warm palette as the
rest of the item art, and a generator means the asset is reproducible instead of being one
more binary nobody can retrace. Run it from the repo root:

    python3 tools/import/make_coin.py

Flat toning only — no gradient, no glow, no outline (Jan: warm desaturated colours, large
simple elements, no glow). 256x256 like every other item icon.
"""

import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "items", "coin_gold.png"))

SIZE = 256
## The coin's own palette: a warm gold face, a darker rim and a light edge. Kept to three
## tones so it reads at 32px on the loot row.
RIM = (138, 106, 22, 255)
FACE = (198, 158, 44, 255)
LIGHT = (226, 190, 74, 255)


def main() -> None:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    cx = cy = SIZE // 2
    r = 112
    # The rim, then the face a few pixels inside it: two concentric discs are the whole
    # coin. `ellipse` takes a bounding box, so the radius is the half-width.
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=RIM)
    r2 = r - 10
    d.ellipse((cx - r2, cy - r2, cx + r2, cy + r2), fill=FACE)
    # A single light crescent along the top-left: the only shading, and what stops a flat
    # disc from reading as a hole.
    r3 = r2 - 16
    d.arc((cx - r3, cy - r3, cx + r3, cy + r3), start=185, end=300, fill=LIGHT, width=11)
    # The mark in the middle: a small square turned 45 degrees, the coin's own "value"
    # glyph. Two rectangles rather than a font, so nothing here needs a font at all.
    s = 26
    d.polygon([(cx, cy - s), (cx + s, cy), (cx, cy + s), (cx - s, cy)], fill=LIGHT)
    d.polygon([(cx, cy - s + 8), (cx + s - 8, cy), (cx, cy + s - 8), (cx - s + 8, cy)],
              fill=FACE)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print(OUT, img.size)


if __name__ == "__main__":
    main()
