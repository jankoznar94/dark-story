#!/usr/bin/env python3
"""tools/art/village_tiles.py — the Village zone's art, REGENERATED from code.

Jan drew five 512x512 tiles (dead end, straight, corner, tee, cross) and the geometry is his
contract, not this script's choice:
    tile 512 x 512, walkway band 80 px centred on the tile edge (216..296), deck ring r=104,
    hut r=46, roof filling the hut's footprint, straw, jungle = anything else.
This script only adds the DETAIL he asked for ("Určitě chceme detaily") and writes the two files
the game loads:
    assets/village/tiles.png   — the FIVE archetypes in a 3 x 2 atlas; the other ten orientations
                                 are the same art rotated by the engine (90° is exact on a pixel
                                 grid, so 6 MB in VRAM instead of 16 MB)
    assets/village/forest.png  — a seamless 512 px canopy of many SMALL crowns

Run from the repo root:  python3 tools/art/village_tiles.py
Then let Godot re-import: godot --headless --path . --import
(palette PNG, no gradients, no antialiasing — Jan's flat style)

⚠️  INVARIANTS THAT HAVE BITTEN ONCE AND MUST NOT MOVE:
1. Nothing is drawn beyond r = RING_R - 1. A 2 px seam on r = RING_R poked 1-2 px outside the
   circle and read as a "zub" on the deck's edge.
2. A cast shadow NEVER crosses the tile's edge in the direction of travel: an offset rectangle over
   the whole walkway got clipped at the edge, so at every tile seam 9 px of shadow was missing and
   the walkway seemed to break. The shadow is drawn along the walkway's long side only.
3. The walkway extends UNDER the deck (to r = RING_R - 22) and the deck is drawn over it, with the
   deck's own shadow landing on the planks: that is what reads as "the bridge passes under the
   platform". Skipping the deck's rim at the mouths made it look like a threshold instead.
4. PLANK RHYTHM DIVIDES THE TILE: 512 / 16 = 32 planks per tile. At 13 px the rhythm was cut at every
   tile boundary and a seam showed across the walkway where two tiles met.
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

T = 512
CX = CY = 256
HALF = 40          # walkway is 80 px wide, centred on the edge
RING_R = 104       # the deck's outer radius
HUT_R = 46         # the hut's footprint (= the collision radius)
ROOF_R = HUT_R     # the roof FILLS the footprint: a smaller roof left a dark ring that read as a gap
BEAM = 9           # the dark edge beam along every walkway and around the deck
EDGE = RING_R - 1  # invariant 1
UNDER = 22         # how deep the walkway runs under the deck (invariant 3)
PLANK = 16         # invariant 4

P_BASE = (157, 87, 1)
P_LINE = (126, 67, 1)
P_GAP = (196, 128, 64)
P_RIM = (96, 50, 0)
P_HI = (182, 106, 10)
W_A = (150, 83, 1)
W_B = (163, 91, 2)
W_SEAM = (118, 62, 0)
W_HI = (184, 108, 12)
S_BASE = (198, 164, 92)
S_D1 = (176, 141, 72)
S_D2 = (216, 184, 112)
S_EDGE = (168, 130, 64)
## The eave, in shade: the straw's own tone stepped down, so the roof has a visible edge against the
## planks instead of dissolving into them.
S_SHADE = (132, 96, 44)
## ⚠️  A SHADOW IS NOT A TRANSPARENCY. Semi-transparent black over the green canopy produced a GREEN
## shadow — it read as the trees showing through beneath the deck, not as shade (Jan: "vadí to, že ten
## stín je zelený, působí to, jak kdyby pod tím prosvítaly stromy"). Every shadow that falls on the
## JUNGLE is drawn in this opaque warm tone instead; black at low alpha is only used where the shadow
## falls on WOOD, where it correctly darkens the planks.
SHADOW = (41, 29, 18)
## ⚠️  THE WALKWAY'S SHADE IS SYMMETRIC AND NARROW. It used to be an 8 px strip on ONE long side
## (right of a vertical walkway, below a horizontal one). On a corner or a tee the two bands shade
## OPPOSITE sides, so the strip jumped from one side of the path to the other at the deck — Jan:
## "u všech lávek je stín jen z jedné strany … uprostřed cesty je najednou zlom a místo stínu vpravo
## je najednou vlevo". The shade now runs down BOTH long sides at the same width, so every tile
## agrees with its neighbour whatever the rotation, and it is thinner than before.
SHADOW_W = 5
## The hut's cast shadow, in px, from the light at the upper left. Only the part that falls OUTSIDE
## the roof silhouette shows, so it touches the roof and reads as shade on the planks instead of a
## dark ring around a floating disc (Jan: "jen světle kolečko na podlaze").
HUT_SHX = 7
HUT_SHY = 9

DIRS = {1: (0, -1), 2: (0, 1), 4: (1, 0), 8: (-1, 0)}
ARCHETYPES = [1, 3, 5, 7, 15]
ATLAS_COLS = 3


def band_rect(direction):
    inner = CX - (RING_R - UNDER)
    if direction == "N":
        return (CX - HALF, 0, CX + HALF, inner)
    if direction == "S":
        return (CX - HALF, 2 * CY - inner, CX + HALF, T)
    if direction == "E":
        return (2 * CX - inner, CY - HALF, T, CY + HALF)
    return (0, CY - HALF, inner, CY + HALF)


def band(d, direction):
    x0, y0, x1, y1 = band_rect(direction)
    # The shade runs down BOTH long sides, at the same width, so a corner or a tee cannot hand the
    # dark side over to the other edge mid-path (see SHADOW_W). It never runs past the band's ENDS,
    # which is the direction of travel — that is what keeps the seam between two tiles invisible.
    if direction in ("N", "S"):
        d.rectangle((x0 - SHADOW_W, y0, x0 - 1, y1), fill=SHADOW)
        d.rectangle((x1 + 1, y0, x1 + SHADOW_W, y1), fill=SHADOW)
    else:
        d.rectangle((x0, y0 - SHADOW_W, x1, y0 - 1), fill=SHADOW)
        d.rectangle((x0, y1 + 1, x1, y1 + SHADOW_W), fill=SHADOW)
    d.rectangle((x0, y0, x1, y1), fill=P_BASE)
    if direction in ("N", "S"):
        d.rectangle((x0, y0, x0 + BEAM, y1), fill=P_RIM)
        d.rectangle((x1 - BEAM, y0, x1, y1), fill=P_RIM)
        d.line([(x0 + BEAM + 1, y0), (x0 + BEAM + 1, y1)], fill=P_GAP)
        d.line([(x1 - BEAM - 1, y0), (x1 - BEAM - 1, y1)], fill=P_GAP)
        # ⚠️  The rhythm is anchored on GLOBAL multiples of PLANK, not on the band's start: the
        # south band starts at y=338, which is 338 % 16 = 2, so its planks sat 2 px off the north
        # band's and the walkway showed a step at every tile seam.
        # The FLOOR (no `+ 1`) matters: a line on the tile's first row is the other half of the
        # plank joint the neighbour draws on its last row. Without it the joint at every seam was
        # twice as wide as every other plank.
        for y in range((int(y0) // PLANK) * PLANK, int(y1), PLANK):
            d.line([(x0 + BEAM + 2, y), (x1 - BEAM - 2, y)], fill=P_LINE)
            d.line([(x0 + BEAM + 2, y + 1), (x1 - BEAM - 2, y + 1)], fill=P_HI)
    else:
        d.rectangle((x0, y0, x1, y0 + BEAM), fill=P_RIM)
        d.rectangle((x0, y1 - BEAM, x1, y1), fill=P_RIM)
        d.line([(x0, y0 + BEAM + 1), (x1, y0 + BEAM + 1)], fill=P_GAP)
        d.line([(x0, y1 - BEAM - 1), (x1, y1 - BEAM - 1)], fill=P_GAP)
        for x in range((int(x0) // PLANK) * PLANK, int(x1), PLANK):
            d.line([(x, y0 + BEAM + 2), (x, y1 - BEAM - 2)], fill=P_LINE)
            d.line([(x + 1, y0 + BEAM + 2), (x + 1, y1 - BEAM - 2)], fill=P_HI)


def in_walk(mask, angle, tol):
    for bit, (dx, dy) in DIRS.items():
        if not (mask & bit):
            continue
        a = math.atan2(dy, dx)
        if abs((angle - a + math.pi) % (2 * math.pi) - math.pi) <= tol:
            return True
    return False


def wedge(d, a0, a1, r0, r1, colour):
    pts = []
    steps = max(2, int((a1 - a0) / 0.05))
    for i in range(steps + 1):
        a = a0 + (a1 - a0) * i / steps
        pts.append((CX + math.cos(a) * r1, CY + math.sin(a) * r1))
    for i in range(steps, -1, -1):
        a = a0 + (a1 - a0) * i / steps
        pts.append((CX + math.cos(a) * r0, CY + math.sin(a) * r0))
    d.polygon(pts, fill=colour)


def ring(d, mask):
    # The deck's planks are WEDGES in two wood tones — no thin lines, so the surface reads as the
    # same planking as the walkways instead of a separate object.
    for k in range(30):
        d.pieslice((CX - EDGE, CY - EDGE, CX + EDGE, CY + EDGE),
                   math.degrees(math.tau * k / 30), math.degrees(math.tau * (k + 1) / 30),
                   fill=(W_A if k % 2 == 0 else W_B))
    for k in range(30):
        a = math.tau * k / 30
        d.line([(CX + math.cos(a) * (ROOF_R + 1), CY + math.sin(a) * (ROOF_R + 1)),
                (CX + math.cos(a) * (EDGE - 1), CY + math.sin(a) * (EDGE - 1))], fill=W_SEAM, width=2)
    # The concentric seam and the rim are CONTINUOUS: the walkway passes under them.
    for k in range(360):
        wedge(d, math.radians(k), math.radians(k + 1), 74, 77, W_SEAM)
        wedge(d, math.radians(k), math.radians(k + 1), 77, 79, W_HI)
    for k in range(360):
        wedge(d, math.radians(k), math.radians(k + 2), EDGE - BEAM, EDGE, P_RIM)
    for k in range(200):
        wedge(d, math.radians(180 + k), math.radians(182 + k), EDGE - BEAM, EDGE - BEAM + 2, W_HI)
    # The deck's shadow on the planks is NOT drawn here: it has to be COMPOSITED (see `tile()`),
    # because `ImageDraw` REPLACES a pixel with the fill it is given — an `(0,0,0,90)` wedge overwrites
    # the planks with a semi-transparent black, and in the game that pixel mixes with the JUNGLE behind
    # the sprite. That was the green band across the walkway at every deck.


def hut(d):
    # ⚠️  THE HUT MUST READ AS A RAISED CONE, NOT A PALE DISC. Jan, Nov 2026: "Kolem slámových budov
    # musíme taky udělat nějaký stín a nebo nějak jinak zvýraznit, že se jedná o 3D objekt a ne jen
    # světle kolečko na podlaze." Three cues, in this order, and each one alone is not enough:
    #   1. a CAST SHADOW offset from the light at the upper left. It TOUCHES the roof's silhouette —
    #      an offset shadow with bare deck between it and the hut is what the old version was read
    #      as ("mezera kolem boudy"), so the roof keeps the full footprint and the shadow is drawn
    #      FIRST, underneath it.
    #   2. a CONCENTRIC TONE RAMP: eave in shade -> straw -> lit crown. That is the volume cue; a
    #      single flat straw fill at any radius reads as a circle painted on the planks.
    #   3. the straw strokes stay, radiating from the crown, so the ramp does not read as a bullseye.
    d.ellipse((CX - ROOF_R + HUT_SHX, CY - ROOF_R + HUT_SHY,
               CX + ROOF_R + HUT_SHX, CY + ROOF_R + HUT_SHY), fill=SHADOW)
    d.ellipse((CX - ROOF_R, CY - ROOF_R, CX + ROOF_R, CY + ROOF_R), fill=S_SHADE)
    for rad, col in ((ROOF_R - 4, S_D1), (ROOF_R - 11, S_BASE)):
        d.ellipse((CX - rad, CY - rad, CX + rad, CY + rad), fill=col)
    # The crown is pulled toward the light (upper left), so the lit cap is bigger than the shaded
    # slope instead of the ramp being a symmetric bullseye.
    d.ellipse((CX - 23 - 3, CY - 23 - 4, CX + 23 - 3, CY + 23 - 4), fill=S_D2)
    rng = random.Random(77)
    for k in range(150):
        a = rng.random() * math.tau
        r0 = rng.random() * ROOF_R * 0.4
        r1 = (ROOF_R - 3) * (0.4 + rng.random() * 0.6)
        d.line([(CX + math.cos(a) * r0, CY + math.sin(a) * r0),
                (CX + math.cos(a) * r1, CY + math.sin(a) * r1)],
               fill=(S_D1 if k % 2 else S_D2), width=2)
    d.ellipse((CX - ROOF_R, CY - ROOF_R, CX + ROOF_R, CY + ROOF_R), outline=S_EDGE, width=2)
    d.ellipse((CX - 5, CY - 5, CX + 5, CY + 5), fill=S_EDGE)


def tile(mask):
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # ⚠️  SYMMETRIC contact shadow. An ellipse offset by (8, 10) left a dark CRESCENT on the
    # bottom-right of every deck and nothing on the top-left — Jan read that asymmetrical crescent
    # as "kolem ochozu je mezera". A ring of the same width all the way round reads as "the deck
    # lies ON the canopy", which is what it is.
    d.ellipse((CX - EDGE - 6, CY - EDGE - 6, CX + EDGE + 6, CY + EDGE + 6), fill=SHADOW)
    for bit, name in ((1, "N"), (2, "S"), (4, "E"), (8, "W")):
        if mask & bit:
            band(d, name)
    ring(d, mask)
    hut(d)
    # ⚠️  PIXEL ART HERE HAS BINARY ALPHA: 0 or 255, nothing in between. A shadow that falls on WOOD
    # must DARKEN the planks, and `ImageDraw` cannot blend — it replaces. So the shadow goes on its own
    # layer and is composited, which gives an opaque darker plank instead of a see-through hole that
    # lets the canopy shine through (Jan: "u lávek chybí kus lávky a prosvítají stromy").
    shade = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for k in range(360):
        if in_walk(mask, math.radians(k + 0.5), math.radians(22)):
            wedge(sd, math.radians(k), math.radians(k + 1.5), EDGE + 1, EDGE + 7, (0, 0, 0, 115))
    # The shadow may only darken what is ALREADY there: multiplied by the base alpha it stops dead at
    # the silhouette, so no pixel is left half-transparent at the edge (20 such pixels showed up as
    # green specks before this line — they were shadow over jungle).
    shade.putalpha(ImageChops.multiply(shade.getchannel("A"), im.getchannel("A")))
    return Image.alpha_composite(im, shade)


def build_tiles(out):
    tiles = {m: tile(m) for m in ARCHETYPES}
    atlas = Image.new("RGBA", (ATLAS_COLS * T, 2 * T), (0, 0, 0, 0))
    for i, m in enumerate(ARCHETYPES):
        atlas.paste(tiles[m], ((i % ATLAS_COLS) * T, (i // ATLAS_COLS) * T))
    atlas.save(out)


def build_forest(out, size=512):
    # Jan: "stromy můžou být jak kdyby menší a hustší" — 170 small crowns instead of 42 big blobs.
    f = Image.new("RGB", (size, size), (38, 88, 79))
    d = ImageDraw.Draw(f)
    rng = random.Random(31)
    greens = [(44, 100, 90), (50, 112, 101), (41, 94, 85), (56, 122, 110), (47, 105, 94)]
    for _ in range(170):
        x, y = rng.randrange(size), rng.randrange(size)
        rad = rng.randrange(9, 22)
        c = greens[rng.randrange(5)]
        for ox in (-size, 0, size):          # seamless: every crown is stamped across the borders
            for oy in (-size, 0, size):
                d.ellipse([x + ox - rad, y + oy - rad, x + ox + rad, y + oy + rad], fill=c)
                d.ellipse([x + ox - rad, y + oy - rad + 2,
                           x + ox + rad - 3, y + oy + rad - 2],
                          fill=tuple(min(255, v + 7) for v in c))
    f.save(out)


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    build_tiles(root / "assets" / "village" / "tiles.png")
    build_forest(root / "assets" / "village" / "forest.png")
    print("wrote assets/village/tiles.png and assets/village/forest.png")
