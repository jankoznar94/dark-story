#!/usr/bin/env python3
"""World mockup v2 for Dungeon Recall (Godot) — the road BETWEEN FIGHTS inside one area.

Jan's correction of v1: the road must not only join the areas, the hero must travel between
the individual fights within an area too. `Battle.FIGHTS_PER_ZONE` is 10, so a zone IS ten
encounters and the journey happens at that level.

Composited from the game's own assets, so the mockup cannot flatter the idea:
  * the area's own landscape (assets/stops/stop_act0_0.webp) as the ground — the SAME art the
    arena now uses as its backdrop, so the two views agree about where the hero is;
  * assets/monsters/hero_body_barbarian.png (RGBA, transparent) as the walking figure;
  * a circular monster crop at the encounter node, the arena's own `.monster-in-ring` device;
  * the port's palette (#121212, #f1c40f, #333333).

Two panels, because there are two questions: what the road looks like, and what the WALK
between two encounters looks like.

Deterministic (fixed seed) so a re-run is the same picture.
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO = os.path.expanduser("~/dr-godot")
OUT = "/tmp/look/world_zone.png"
W, H = 390, 844
SEED = 20260927

BG = (18, 18, 18)
ZONE_ART = "assets/stops/stop_act0_0.webp"
MONSTER = "assets/monsters/skeleton.png"
HERO = "assets/monsters/hero_body_barbarian.png"
FIGHTS = 10
GOLD = (241, 196, 15)
DIM = (120, 120, 120)

# Node states in the two panels: the hero is at fight 3 of 10.
DONE = 3
CURRENT = 3


def font(size, bold=True):
    for c in [os.path.join(REPO, "assets/fonts", "DejaVuSans-Bold.ttf"),
              os.path.join(REPO, "assets/fonts", "DejaVuSans.ttf")]:
        if os.path.exists(c):
            try:
                return ImageFont.truetype(c, size)
            except Exception:
                pass
    return ImageFont.load_default()


def ground(dim=0.52, blur=1.0):
    """The area's landscape, cover-fitted into the panel and dimmed — exactly what the arena
    backdrop does, so the world and the fight show the same place."""
    art = Image.open(os.path.join(REPO, ZONE_ART)).convert("RGB")
    s = max(W / art.width, H / art.height)
    art = art.resize((int(art.width * s + 1), int(art.height * s + 1)), Image.LANCZOS)
    x = (art.width - W) // 2
    y = (art.height - H) // 2
    art = art.crop((x, y, x + W, y + H))
    art = art.point(lambda v: int(v * dim))
    # A vignette so the path reads against the painting.
    vg = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vg).ellipse([-W * 0.35, -H * 0.15, W * 1.35, H * 1.15], fill=90)
    vg = vg.filter(ImageFilter.GaussianBlur(70))
    art = Image.composite(art.point(lambda v: int(v * 0.55)), art, vg)
    return art


def nodes():
    """The ten fight positions along a road that climbs the panel and meanders."""
    # The port's OWN direction: the shipped map puts stop 1 at the top and the arrow points
    # DOWN, so the world must climb down too or the two screens disagree about which way the
    # journey runs.
    out = []
    top, bot = 300, 764
    for i in range(FIGHTS):
        t = i / float(FIGHTS - 1)
        y = top + t * (bot - top)
        x = W / 2 + 74 * math.sin(t * 3.35 + 0.35)
        out.append((x, y))
    return out


def draw_road(d, pts, seed, blur_img):
    """A trodden dirt road connecting the nodes, wobbling rather than ruling straight."""
    rnd = random.Random(seed)
    for i in range(len(pts) - 1):
        x0, y0 = pts[i]
        x1, y1 = pts[i + 1]
        steps = 60
        for s in range(steps):
            t = s / float(steps)
            x = x0 + (x1 - x0) * t + rnd.uniform(-5, 5)
            y = y0 + (y1 - y0) * t + rnd.uniform(-4, 4)
            w = 34 + rnd.uniform(-6, 6)
            shade = rnd.randint(-7, 7)
            d.ellipse([x - w / 2, y - 5, x + w / 2, y + 5],
                      fill=(58 + shade, 47 + shade, 35 + shade))


def node_marker(img, d, x, y, state, label):
    """One encounter on the road. `done` / `current` / `next` / `locked` are four different
    looks — an empty state is a style, not a hidden node."""
    r = 17
    if state == "done":
        d.ellipse([x - r, y - r, x + r, y + r], fill=(26, 26, 26), outline=(90, 90, 90), width=2)
        d.line([x - 7, y, x - 2, y + 6], fill=(150, 150, 150), width=3)
        d.line([x - 2, y + 6, x + 8, y - 7], fill=(150, 150, 150), width=3)
    elif state == "current":
        d.ellipse([x - r - 5, y - r - 5, x + r + 5, y + r + 5], outline=GOLD, width=3)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(20, 18, 10), outline=GOLD, width=2)
        d.text((x, y), str(label), font=font(15), fill=GOLD, anchor="mm")
    elif state == "next":
        d.ellipse([x - r, y - r, x + r, y + r], fill=(22, 22, 22), outline=(120, 120, 120), width=2)
        d.text((x, y), str(label), font=font(14), fill=(170, 170, 170), anchor="mm")
    else:
        d.ellipse([x - r + 3, y - r + 3, x + r - 3, y + r - 3], fill=(16, 16, 16),
                  outline=(58, 58, 58), width=1)
        d.text((x, y), str(label), font=font(11), fill=(80, 80, 80), anchor="mm")


def monster_disc(size, dim=1.0):
    """The arena's own circular crop of the monster portrait, as the encounter's face."""
    m = Image.open(os.path.join(REPO, MONSTER)).convert("RGB").resize((size, size), Image.LANCZOS)
    if dim != 1.0:
        m = m.point(lambda v: int(v * dim))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
    plate = Image.new("RGB", (size, size), BG)
    plate.paste(m, (0, 0), mask)
    return plate


def hero_at(img, x, y, h=112):
    hh = Image.open(os.path.join(REPO, HERO)).convert("RGBA").resize((h, h), Image.LANCZOS)
    px = int(x - hh.width / 2)
    py = int(y - hh.height + 16)
    sh = Image.new("RGBA", (hh.width, 20), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([8, 5, hh.width - 8, 17], fill=(0, 0, 0, 130))
    img.paste(sh, (px, py + hh.height - 14), sh)
    img.paste(hh, (px, py), hh)


def panel_one():
    img = ground()
    d = ImageDraw.Draw(img)
    pts = nodes()
    draw_road(d, pts, SEED, img)
    img = img.filter(ImageFilter.GaussianBlur(0.5))
    d = ImageDraw.Draw(img)

    for i, (x, y) in enumerate(pts):
        n = i + 1
        if n < CURRENT:
            st = "done"
        elif n == CURRENT:
            st = "current"
        elif n == CURRENT + 1:
            st = "next"
        else:
            st = "locked"
        node_marker(img, d, x, y, st, n)

    # The thing waiting at the next encounter.
    nx, ny = pts[CURRENT]
    disc = monster_disc(58)
    img.paste(disc, (int(nx - 29), int(ny - 52)))
    d.ellipse([nx - 30, ny - 53, nx + 30, ny + 7], outline=(150, 120, 60), width=1)

    # The hero, standing at the encounter he is on.
    cx, cy = pts[CURRENT - 1]
    hero_at(img, cx - 46, cy + 30)

    d.text((W // 2, 26), "Meadow", font=font(17), fill=(232, 232, 232), anchor="mm")
    d.text((W // 2, 46), "souboj 3/10", font=font(11), fill=GOLD, anchor="mm")
    # The path label at the top of the road, so the journey's direction is readable.
    d.text((W // 2, 282), "cesta k dal\u0161ímu souboji", font=font(10), fill=DIM, anchor="mm")
    return img


def panel_two():
    """What the WALK between two encounters looks like — the new unit of play."""
    img = ground(dim=0.46)
    d = ImageDraw.Draw(img)
    pts = nodes()
    draw_road(d, pts, SEED, img)
    img = img.filter(ImageFilter.GaussianBlur(0.5))
    d = ImageDraw.Draw(img)

    for i, (x, y) in enumerate(pts):
        n = i + 1
        if n < CURRENT + 1:
            st = "done"
        elif n == CURRENT + 1:
            st = "next"
        else:
            st = "locked"
        node_marker(img, d, x, y, st, n)

    # The hero MID-STRIDE between fight 3 and fight 4 — the travelling itself.
    ax, ay = pts[CURRENT - 1]
    bx, by = pts[CURRENT]
    mx, my = (ax + bx) / 2.0, (ay + by) / 2.0
    hero_at(img, mx + 40, my + 26, h=122)

    # The next encounter's face, ahead of him on the road.
    disc = monster_disc(58, dim=0.85)
    img.paste(disc, (int(bx - 29), int(by - 52)))
    d.ellipse([bx - 30, by - 53, bx + 30, by + 7], outline=(150, 120, 60), width=1)

    d.text((W // 2, 26), "Putuje\u0161 k dal\u0161ímu souboji", font=font(16), fill=(232, 232, 232),
           anchor="mm")
    d.text((W // 2, 46), "souboj 4/10", font=font(11), fill=GOLD, anchor="mm")
    d.text((W // 2, 812), "klepnutím na cestu jde\u0161 dál", font=font(10), fill=DIM, anchor="mm")
    return img


def main():
    a = panel_one()
    b = panel_two()
    sheet = Image.new("RGB", (W * 2 + 24, H + 34), (10, 10, 10))
    sheet.paste(a, (0, 34))
    sheet.paste(b, (W + 24, 34))
    d = ImageDraw.Draw(sheet)
    d.text((W // 2, 17), "1 - cesta uvnitr oblasti", font=font(13), fill=GOLD, anchor="mm")
    d.text((W + 24 + W // 2, 17), "2 - putovani mezi souboji", font=font(13), fill=GOLD, anchor="mm")
    sheet.save(OUT)
    print("world_zone: %s %dx%d" % (OUT, sheet.width, sheet.height))


if __name__ == "__main__":
    main()
