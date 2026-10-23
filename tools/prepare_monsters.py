#!/usr/bin/env python3
"""Kruhove portrety nepratel pro Thrower.

Zdroj: portrety z Dungeon Recall (~/dr-godot/assets/monsters). Ty jsou ctvercove
a nekolik z nich ma cerne pozadi - ve hre by to byly hnusne cerné rohy. Tenhle
nastroj je prevede na kruh s pruhlednym okolim (jeden typ = jeden kruh):

  1. ctverec se zmensi na kruh vepsany (kraj se orizne),
  2. pod portret se podlozi tmava deska (0.10), aby cerne pozadi nesplynulo
     s pozadim hry a kruh byl citelny,
  3. vnejsek kruhu se vyhladi na alfa 0 (antialias), takze zadne hrany.

Pouziti:  python3 tools/prepare_monsters.py [--src ~/dr-godot/assets/monsters]
Vystup:   assets/monsters/<img>.png  (256x256 RGBA)
"""
import argparse
import os
import sys

from PIL import Image, ImageDraw

# Presne to, co hra pouziva v Game.ENEMY_TYPES - drzi se to tu, aby se poznalo,
# kdyz obrazek chybi.
IMAGES = [
    "desert_cobra",
    "desert_nomad",
    "desert_beetle",
    "ent",
    "ghost",
    "fire_ghost",
]
SIZE = 256
SS = 4  # supersampling pro hladky okraj
PLATE = (26, 24, 27, 255)


def make_round(src_path: str, dst_path: str) -> None:
    im = Image.open(src_path).convert("RGBA")
    big = SIZE * SS

    # Ctverec -> kruh: vyrezeme stredovy ctverec a zmensime.
    w, h = im.size
    side = min(w, h)
    im = im.crop(((w - side) // 2, (h - side) // 2, (w + side) // 2, (h + side) // 2))
    im = im.resize((big, big), Image.LANCZOS)

    plate = Image.new("RGBA", (big, big), PLATE)
    plate.alpha_composite(im)

    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, big - 1, big - 1), fill=255)
    plate.putalpha(mask)
    plate = plate.resize((SIZE, SIZE), Image.LANCZOS)

    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    plate.save(dst_path)
    print("  %-16s -> %s" % (os.path.basename(src_path), dst_path))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.expanduser("~/dr-godot/assets/monsters"))
    ap.add_argument("--dst", default=os.path.join(os.path.dirname(__file__), "..",
                                                  "assets", "monsters"))
    a = ap.parse_args()
    dst = os.path.normpath(a.dst)
    missing = 0
    for img in IMAGES:
        src = os.path.join(a.src, img + ".png")
        if not os.path.exists(src):
            print("CHYBI: %s" % src)
            missing += 1
            continue
        make_round(src, os.path.join(dst, img + ".png"))
    print("hotovo, chybi %d" % missing)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
