#!/usr/bin/env python3
"""World mockup v3 — CESTA DOMU (both ways), drawn from the game's own assets.

v2 answered "what does the road inside one area look like". v3 answers Jan's next question:
the way HOME must be visible on the map too — on foot AND through the town portal — and today
it is invisible: the map screen's only trace of either is two flat buttons at the bottom of the
screen (`.map-actions`), drawn nowhere near the road, with no relation to where the hero stands.

Panel 1 — walking home: the road climbs back the way the hero came, to a town marker at the
           top, and the price (the area's fights reset) is written where the choice is made.
Panel 2 — the portal: it opens ON the road at the fight the hero was standing on, and the map
           keeps that spot marked while he is in town.

Reuses look_world_mockup's own helpers, so both sheets agree about ground, road, nodes and hero.
Deterministic.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.expanduser("~/dr-godot/tools"))
import look_world_mockup as M  # noqa: E402

OUT = "/tmp/look/world_home.png"
W, H = M.W, M.H
GOLD = M.GOLD
DIM = M.DIM
BG = M.BG
TOWN_ART = "assets/town.webp"
SCROLL_ART = "assets/items/town_portal_scroll.png"
FIGHTS = 10
# The hero is standing on fight 4 of 10 with a portal open to it (the stored return position).
AT = 4


def disc(path, size, dim=1.0, ring=None, ring_w=2):
    """A circular crop of any art, the arena's own `.monster-in-ring` device."""
    art = Image.open(os.path.join(M.REPO, path))
    art = art.convert("RGB").resize((size, size), Image.LANCZOS)
    if dim != 1.0:
        art = art.point(lambda v: int(v * dim))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
    plate = Image.new("RGB", (size, size), BG)
    plate.paste(art, (0, 0), mask)
    d = ImageDraw.Draw(plate)
    d.ellipse([0, 0, size - 1, size - 1], outline=ring or (70, 70, 70), width=ring_w)
    return plate


def road_back(d, pts):
    """The stretch of road from the hero's position UP to the town — i.e. the way he came.
    Drawn as the same trodden dirt as the rest, so it reads as one road, not a new one."""
    for i in range(AT + 1, len(pts) - 1):
        x0, y0 = pts[i]
        x1, y1 = pts[i + 1]
        steps = 40
        for s in range(steps):
            t = s / float(steps)
            x = x0 + (x1 - x0) * t
            y = y0 + (y1 - y0) * t
            d.ellipse([x - 15, y - 4, x + 15, y + 4], fill=(52, 42, 31))


def town_marker(d, x, y, label, price):
    """Where home is: the town's own art, small, at the top of the road, with the COST of
    walking written under it. The price is the design decision, so it belongs on the map."""
    r = 34
    d.ellipse([x - r - 6, y - r - 6, x + r + 6, y + r + 6], fill=(12, 12, 12),
              outline=(80, 80, 80), width=2)
    d.text((x, y - r - 18), label, font=M.font(12), fill=(220, 220, 220), anchor="mm")
    d.text((x, y + r + 14), price, font=M.font(9), fill=DIM, anchor="mm")
    return (x - r, y - r, x + r, y + r)


def portal_marker(img, d, x, y, label, ring=GOLD):
    """The town portal standing ON the road, at the fight it was opened to."""
    r = 24
    disc_img = disc(SCROLL_ART, 44, dim=1.0, ring=ring, ring_w=2)
    img.paste(disc_img, (int(x - 22), int(y - 22)))
    d.ellipse([x - 30, y - 30, x + 30, y + 30], outline=ring, width=1)
    d.text((x, y + 40), label, font=M.font(10), fill=(210, 180, 90), anchor="mm")


def panel_walk():
    """Cesta domů PĚŠKY — the road back is drawn, and the price is on it."""
    img = M.ground(dim=0.40)
    d = ImageDraw.Draw(img)
    pts = M.nodes()
    M.draw_road(d, pts, M.SEED, img)
    road_back(d, pts)
    img = img.filter(ImageFilter.GaussianBlur(0.5))
    d = ImageDraw.Draw(img)

    # The town, at the top of the road, where the journey started.
    tx, ty = W // 2 - 6, 196
    box = town_marker(d, tx, ty, "Město", "pěšky: souboje v této oblasti se resetují")
    art = disc(TOWN_ART, 56, dim=0.9, ring=(120, 100, 60), ring_w=2)
    img.paste(art, (int(tx - 28), int(ty - 28)))
    _ = box

    for i, (x, y) in enumerate(pts):
        n = i + 1
        st = "done" if n < AT else ("current" if n == AT else ("next" if n == AT + 1 else "locked"))
        M.node_marker(img, d, x, y, st, n)

    # The hero at fight AT, next to the town portal he could take instead.
    hx, hy = pts[AT - 1]
    M.hero_at(img, hx - 44, hy + 28)

    d.text((W // 2, 26), "Meadow", font=M.font(17), fill=(232, 232, 232), anchor="mm")
    d.text((W // 2, 46), "souboj 4/10", font=M.font(11), fill=GOLD, anchor="mm")
    d.text((W // 2, 800), "cesta domů je nakreslená - jdeš po ní nahoru",
           font=M.font(10), fill=DIM, anchor="mm")
    return img


def panel_portal():
    """Cesta domů PORTÁLEM — it opens on the road, and the return position stays marked."""
    img = M.ground(dim=0.34)
    d = ImageDraw.Draw(img)
    pts = M.nodes()
    M.draw_road(d, pts, M.SEED, img)
    img = img.filter(ImageFilter.GaussianBlur(0.5))
    d = ImageDraw.Draw(img)

    tx, ty = W // 2 - 6, 196
    d.ellipse([tx - 40, ty - 40, tx + 40, ty + 40], fill=(12, 12, 12),
              outline=(80, 80, 80), width=2)
    art = disc(TOWN_ART, 56, dim=0.9, ring=(120, 100, 60), ring_w=2)
    img.paste(art, (int(tx - 28), int(ty - 28)))
    d.text((tx, ty - 46), "Město - jsi tady", font=M.font(10), fill=GOLD, anchor="mm")

    for i, (x, y) in enumerate(pts):
        n = i + 1
        # Fight AT is NOT drawn as a node here — the portal stands in its place, so the two
        # cannot read as two different spots (an overlap that looked like an 11th node).
        if n == AT:
            continue
        st = "done" if n < AT else ("next" if n == AT + 1 else "locked")
        M.node_marker(img, d, x, y, st, n)

    # The portal stands where the hero left the road. This is the map remembering him.
    px, py = pts[AT - 1]
    portal_marker(img, d, px - 6, py - 6, "návrat sem: souboj 4/10")

    d.text((W // 2, 26), "Meadow", font=M.font(17), fill=(232, 232, 232), anchor="mm")
    d.text((W // 2, 46), "portál otevřený na souboj 4/10", font=M.font(11), fill=GOLD,
           anchor="mm")
    d.text((W // 2, 800), "portál neztratí progres - proto je vyznačený na cestě",
           font=M.font(10), fill=DIM, anchor="mm")
    return img


def main():
    a = panel_walk()
    b = panel_portal()
    sheet = Image.new("RGB", (W * 2 + 24, H + 44), (10, 10, 10))
    sheet.paste(a, (0, 44))
    sheet.paste(b, (W + 24, 44))
    d = ImageDraw.Draw(sheet)
    d.text((W // 2, 16), "cesta domů PĚŠKY", font=M.font(13), fill=GOLD, anchor="mm")
    d.text((W // 2, 33), "ztráta progresu v oblasti - cena je na mapě",
           font=M.font(10), fill=DIM, anchor="mm")
    d.text((W + 24 + W // 2, 16), "cesta domů PORTÁLEM", font=M.font(13), fill=GOLD, anchor="mm")
    d.text((W + 24 + W // 2, 33), "progres zůstává - místo návratu zůstane na cestě",
           font=M.font(10), fill=DIM, anchor="mm")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    sheet.save(OUT)
    print("world_home: %s %dx%d" % (OUT, sheet.width, sheet.height))


if __name__ == "__main__":
    main()
