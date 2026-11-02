#!/usr/bin/env python3
"""Give the PS button artwork the circular alpha the PWA gets from CSS.

`assets/ps/*.png` are RGB with NO alpha, and the PWA crops each one to a circle with
`overflow:hidden` on the round parent (`border-radius:50%`). The port has no clip container, so
`CircularPortrait`'s scanline crop was painting the outside of the circle in a background
colour — and a transparent backdrop paints nothing, which left the PNG's own black square
corners showing. On screen that is a black SQUARE inside the ring instead of a round button.

Baking the crop into the asset is the same result the browser produces, once, and it needs no
shader:

  python3 tools/make_ps_alpha.py            # in place, idempotent
  python3 tools/make_ps_alpha.py --check    # exit 1 if any file is not already circular

Only the alpha channel is touched; every RGB value is preserved exactly.
"""

import os
import sys

from PIL import Image, ImageDraw

DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "ps")
# 8x supersampling for the edge, because a hard 256px circle has a visibly jagged rim at the
# 52-64px sizes the buttons actually draw at.
SUPERSAMPLE = 8


def has_alpha(path: str) -> bool:
    with Image.open(path) as im:
        return im.mode in ("RGBA", "LA") and im.getchannel("A").getextrema()[0] < 255


def bake(path: str) -> None:
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    mask = Image.new("L", (w * SUPERSAMPLE, h * SUPERSAMPLE), 0)
    ImageDraw.Draw(mask).ellipse(
        (0, 0, w * SUPERSAMPLE - 1, h * SUPERSAMPLE - 1), fill=255)
    mask = mask.resize((w, h), Image.LANCZOS)
    im.putalpha(mask)
    im.save(path)


def main() -> int:
    check = "--check" in sys.argv
    files = sorted(f for f in os.listdir(DIR) if f.endswith(".png"))
    if not files:
        print("no PNGs in", DIR)
        return 1
    stale = []
    for name in files:
        path = os.path.join(DIR, name)
        if check:
            if not has_alpha(path):
                stale.append(name)
            continue
        bake(path)
        print("baked", name)
    if check:
        if stale:
            print("NOT circular (PWA crops these with overflow:hidden):")
            for name in stale:
                print("  ", name)
            return 1
        print("all %d PS assets are circular" % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
