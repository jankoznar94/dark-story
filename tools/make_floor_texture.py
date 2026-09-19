#!/usr/bin/env python3
"""Generate the seamless ground texture for Dark Story.

Jan's report: "everything is dark brown - objects, floor, clothes. We need to
light the world a little and bring it to life so the contrast stands out."

The floor is currently ONE flat brown colour (Color(0.20,0.175,0.145)) across a
single 34 m BoxMesh, so it contributes no structure and no contrast at all.
This script paints a tileable grass/scree ground in the project's palette:

    dark moss -> olive -> dry ochre highlights

Kept deliberately dark, desaturated and *grainy* rather than lush: the art
direction is D1/D2 gothic (dark brown / ochre / grey), not cheerful. The goal is
structure and tonal range, not brightness for its own sake.

Tileable by construction: every noise octave is sampled from a periodic lattice,
so the left edge continues into the right edge exactly.

    python3 tools/make_floor_texture.py

Writes assets/textures/ground_grass.png plus a metrics line so "is it actually
brighter and more contrasty than the flat colour" is a measurement.
"""
import os
import sys

import numpy as np
from PIL import Image

SIZE = 1024
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "textures", "ground_grass.png")
SEED = 20260919
## Reported back after the first render: "silně opakující se textura trávy" - at
## 2 m per repeat on a 34 m floor the tile read as an obvious grid. 1024 px at
## ~4 m per repeat (uv1_scale 8.5) halves the number of repeats and gives the
## macro layer room to vary, at no extra draw cost.
REPEAT_METERS = 4.0


def lattice_noise(size: int, freq: int, rng: np.random.Generator) -> np.ndarray:
    """Value noise on a periodic lattice -> seamless under tiling."""
    g = rng.random((freq, freq))
    # coordinates in lattice space, wrapping
    x = np.linspace(0.0, freq, size, endpoint=False)
    y = np.linspace(0.0, freq, size, endpoint=False)
    xi = np.floor(x).astype(int) % freq
    yi = np.floor(y).astype(int) % freq
    xf = x - np.floor(x)
    yf = y - np.floor(y)
    # smoothstep
    sx = xf * xf * (3.0 - 2.0 * xf)
    sy = yf * yf * (3.0 - 2.0 * yf)
    x1 = (xi + 1) % freq
    y1 = (yi + 1) % freq
    a = g[np.ix_(yi, xi)]
    b = g[np.ix_(yi, x1)]
    c = g[np.ix_(y1, xi)]
    d = g[np.ix_(y1, x1)]
    top = a + (b - a) * sx[None, :]
    bot = c + (d - c) * sx[None, :]
    return top + (bot - top) * sy[:, None]


def fbm(size: int, octaves, base_freq: int, rng, gain: float = 0.5) -> np.ndarray:
    out = np.zeros((size, size))
    amp, freq, norm = 1.0, base_freq, 0.0
    for _ in range(octaves):
        out += amp * lattice_noise(size, freq, rng)
        norm += amp
        amp *= gain
        freq *= 2
    return out / max(norm, 1e-9)


def main() -> int:
    rng = np.random.default_rng(SEED)

    # --- structure layers -------------------------------------------------
    # A very low-frequency layer breaks the tile: without it every repeat looks
    # identical and the floor reads as wallpaper.
    macro = fbm(SIZE, 2, 2, rng)
    clumps = fbm(SIZE, 4, 6, rng)              # broad patches of denser growth
    grain = fbm(SIZE, 4, 48, rng)              # fine blade texture
    # ridged noise makes blade-like streaks instead of blobs
    ridge = 1.0 - np.abs(2.0 * fbm(SIZE, 3, 40, rng) - 1.0)
    # a directional pass: vertical-ish strokes read as individual blades
    blades = fbm(SIZE, 3, 64, rng)
    strokes = 1.0 - np.abs(2.0 * fbm(SIZE, 3, 72, rng) - 1.0)
    strokes = np.clip((strokes - 0.35) * 1.9, 0.0, 1.0)

    # --- palette (sRGB values, kept dark and desaturated) -----------------
    # Green must DOMINATE so the ground reads as grass against the brown world.
    # Measured on the first attempt: R 93.8 > G 84.8 (ochre outweighed the grass)
    # which is the same brown-on-brown Jan complained about. Verified target:
    # G - R > +8.
    deep = np.array([15.0, 21.0, 13.0])        # dark moss in shadow
    mid = np.array([35.0, 52.0, 28.0])         # olive, green-dominant
    dry = np.array([82.0, 86.0, 44.0])         # dry YELLOW-GREEN, not ochre
    scree = np.array([54.0, 56.0, 50.0])       # grey stone flecks

    m1 = np.clip(clumps * 1.35 - 0.12, 0.0, 1.0)
    base = deep[None, None, :] + (mid - deep)[None, None, :] * m1[..., None]
    # macro variation: up to ~35 % darker/lighter across the tile so consecutive
    # repeats do not look identical
    shade = 1.0 + (macro - 0.5) * 0.7
    base *= shade[..., None]

    # blades: the ridge adds local light, kept subtle so it reads as texture
    blade = np.clip((grain - 0.40) * 2.6, 0.0, 1.0) * np.clip(ridge * 1.3, 0.0, 1.0)
    base += (dry - mid)[None, None, :] * (blade * 0.72)[..., None]
    # individual blade strokes: sharper, brighter tips so grass reads as grass
    base += (dry - mid)[None, None, :] * (strokes * blades * 0.80)[..., None]

    # sparse dry patches so the ground is not one uniform green
    patches = np.clip((fbm(SIZE, 3, 3, rng) - 0.66) * 3.2, 0.0, 1.0)
    base += (dry - mid)[None, None, :] * (patches * 0.40)[..., None]

    # a few grey stone flecks - breaks up the green without becoming gravel
    fleck = np.clip((fbm(SIZE, 4, 40, rng) - 0.78) * 5.0, 0.0, 1.0)
    base += (scree - base) * (fleck * 0.55)[..., None]

    # per-pixel grain so it does not band
    base += (rng.random((SIZE, SIZE, 1)) - 0.5) * 10.0

    img = np.clip(base, 0, 255).astype(np.uint8)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray(img).save(OUT, "PNG", optimize=True)

    # --- metrics: brighter AND more contrasty than the flat colour? -------
    lum = img.astype(np.float64) @ np.array([0.2126, 0.7152, 0.0722])
    flat = np.array([0.20, 0.175, 0.145]) * 255.0
    flat_lum = float(flat @ np.array([0.2126, 0.7152, 0.0722]))
    mx = img.astype(np.float64).max(axis=2)
    mn = img.astype(np.float64).min(axis=2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    ch = img.astype(float).mean(axis=(0, 1))
    ch_g_minus_r = ch[1] - ch[0]
    print("SAVED %s  %d B  %dx%d" % (OUT, os.path.getsize(OUT), SIZE, SIZE))
    print("  mean luminance %6.1f   (flat floor colour was %.1f -> %.2fx)"
          % (lum.mean(), flat_lum, lum.mean() / flat_lum))
    print("  tonal spread   std %5.1f   p10 %5.1f  p50 %5.1f  p90 %5.1f"
          % (lum.std(), *np.percentile(lum, [10, 50, 90])))
    print("  spread vs flat floor (std 0.0): %s" % (lum.std() > 8.0))
    print("  saturation mean %.3f (desaturated target < 0.45): %s"
          % (sat.mean(), sat.mean() < 0.45))
    print("  channel means R %.1f G %.1f B %.1f  -> G-R %+.1f (grass must be positive)"
          % (*img.astype(float).mean(axis=(0, 1)), ch_g_minus_r))

    # seam check: wrap-around difference must be no worse than interior
    d_left_right = np.abs(img[:, 0].astype(int) - img[:, -1].astype(int)).mean()
    d_interior = np.abs(img[:, 1].astype(int) - img[:, 0].astype(int)).mean()
    print("  seam: mean |col0-colN| %.2f vs interior |col1-col0| %.2f -> seamless: %s"
          % (d_left_right, d_interior, d_left_right <= d_interior * 1.6))
    return 0


if __name__ == "__main__":
    sys.exit(main())
