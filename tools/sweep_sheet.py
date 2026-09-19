"""Build a labelled contact sheet from a sweep_render.gd run, with per-variant
numbers next to each frame so the choice is measurable, not just a look."""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

SWEEP = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "~/.local/share/godot/app_userdata/Dark Story/sweep")
OUT = sys.argv[2] if len(sys.argv) > 2 else "/tmp/sweep_sheet.png"
COLS = 3

meta = json.load(open(os.path.join(SWEEP, "sweep.json")))
rows = sorted(meta["results"], key=lambda r: r["idx"])

cells = []
for r in rows:
    img = Image.open(r["file"]).convert("RGB")
    a = np.array(img).astype(float)
    lum = a @ np.array([0.2126, 0.7152, 0.0722])
    p10, p50, p90 = np.percentile(lum, [10, 50, 90])
    q = (a // 8).astype(int)
    distinct = len(np.unique(q.reshape(-1, 3), axis=0))
    gr = (a[..., 1] - a[..., 0]).mean()
    clip = 100.0 * (lum > 240).mean()
    label = ("%s\nlum p10 %4.0f  p50 %4.0f  p90 %4.0f\ncolours %4d   G-R %+5.1f   clipped %4.1f%%"
             % (r["name"], p10, p50, p90, distinct, gr, clip))
    cells.append((img, label, dict(p10=p10, p50=p50, p90=p90, distinct=distinct,
                                   gr=gr, clip=clip, name=r["name"])))

cw, ch = cells[0][0].size
PAD, LBL = 6, 54
rows_n = (len(cells) + COLS - 1) // COLS
sheet = Image.new("RGB", (COLS * cw + (COLS + 1) * PAD, rows_n * (ch + LBL) + (rows_n + 1) * PAD),
                  (18, 18, 20))
dr = ImageDraw.Draw(sheet)
for i, (img, label, m) in enumerate(cells):
    c, rr = i % COLS, i // COLS
    x = PAD + c * (cw + PAD)
    y = PAD + rr * (ch + LBL + PAD)
    sheet.paste(img, (x, y))
    dr.rectangle([x - 1, y - 1, x + cw, y + ch], outline=(90, 90, 95))
    dr.multiline_text((x, y + ch + 4), label, fill=(225, 225, 225))
sheet.save(OUT)
print("SHEET %s  %dx%d  variants %d" % (OUT, sheet.width, sheet.height, len(cells)))
print()
print("%-18s %5s %5s %5s %8s %7s %8s" % ("variant", "p10", "p50", "p90", "colours", "G-R", "clipped"))
for _, _, m in cells:
    print("%-18s %5.0f %5.0f %5.0f %8d %+7.1f %7.1f%%"
          % (m["name"], m["p10"], m["p50"], m["p90"], m["distinct"], m["gr"], m["clip"]))
