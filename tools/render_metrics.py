#!/usr/bin/env python3
"""One render-metrics tool for every "is this frame any good" question.

WHY THIS EXISTS: during the hero/world work I hand-wrote the same luminance /
colour / emptiness analysis FIVE times (render_check, render_check2, chk_views,
game_dark, shadow_check), each with slightly different columns, so results were
not comparable between runs and older runs could not be re-read. This replaces
all of them with one labelled table.

It answers, in one pass:
  * is the frame EMPTY (a failed capture, not a missing model)?
  * how much tonal range does it have, and is it flat?
  * how many distinct colours, and what dominates?
  * is it colour-cast (brown / green / blue) and is it clipping?
  * with --compare, what changed against a previous frame?

Usage:
    python3 tools/render_metrics.py <img> [<img> ...]
    python3 tools/render_metrics.py --compare before.png after.png
    python3 tools/render_metrics.py --json out.json <img> ...   # for scripted checks
    python3 tools/render_metrics.py --expect-min-p90 60 <img>   # non-zero exit if unmet

`--expect-*` turn this into a test instead of a report:
    --expect-fg            frame must contain foreground
    --expect-p10 N         tonal floor at least N
    --expect-p90 N         tonal ceiling at least N
    --expect-range N       p90-p10 at least N
    --expect-colours N     at least N distinct coarse colours
    --expect-green         mean G >= mean R (grass must not read as brown)
    --expect-grass-share N at least N% of pixels with G >= R
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

LUMW = np.array([0.2126, 0.7152, 0.0722])


def analyse(path):
    img = Image.open(path).convert("RGB")
    a = np.array(img).astype(np.float64)
    lum = a @ LUMW
    # foreground = pixels differing from the top-left corner colour. Using a
    # corner rather than a median catches a frame that is mostly character.
    fg = np.abs(a - a[0, 0]).sum(axis=2) > 1
    n = lum.size
    q = (a // 8).astype(int)
    vals, counts = np.unique(q.reshape(-1, 3), axis=0, return_counts=True)
    order = np.argsort(-counts)
    top = [((vals[k] * 8).tolist(), round(100.0 * counts[k] / n, 2)) for k in order[:5]]
    mx, mn = a.max(axis=2), a.min(axis=2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    ch = a.mean(axis=(0, 1))
    return {
        "file": path,
        "size": [img.width, img.height],
        "fg_percent": round(100.0 * fg.mean(), 2),
        "empty": bool(fg.mean() < 0.005),
        "lum_mean": round(float(lum.mean()), 1),
        "lum_p10": round(float(np.percentile(lum, 10)), 1),
        "lum_p50": round(float(np.percentile(lum, 50)), 1),
        "lum_p90": round(float(np.percentile(lum, 90)), 1),
        "lum_std": round(float(lum.std()), 1),
        "lum_max": round(float(lum.max()), 1),
        "below20_percent": round(100.0 * (lum < 20).mean(), 2),
        "below40_percent": round(100.0 * (lum < 40).mean(), 2),
        "clipped_percent": round(100.0 * (lum > 240).mean(), 3),
        "distinct_colours": int(len(vals)),
        "sat_mean": round(float(sat.mean()), 3),
        "ch_mean": [round(float(c), 1) for c in ch],
        "green_minus_red": round(float(ch[1] - ch[0]), 1),
        "grass_share_percent": round(100.0 * ((a[..., 1] >= a[..., 0]) & (a[..., 1] > 25)).mean(), 1),
        "top_colours": top,
    }


def report(rows):
    hdr = ("%-30s %5s %6s %6s %6s %6s %7s %8s %7s %8s %8s"
           % ("file", "fg%", "mean", "p10", "p50", "p90", "std", "colours", "sat", "G-R", ">240%"))
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        print("%-30s %5.1f %6.1f %6.1f %6.1f %6.1f %7.1f %8d %7.3f %+8.1f %8.3f"
              % (os.path.basename(r["file"])[:30], r["fg_percent"], r["lum_mean"],
                 r["lum_p10"], r["lum_p50"], r["lum_p90"], r["lum_std"],
                 r["distinct_colours"], r["sat_mean"], r["green_minus_red"],
                 r["clipped_percent"]))
    for r in rows:
        if r["empty"]:
            print("  !! %s is EMPTY (fg %.2f%%) - a failed capture, not a missing model"
                  % (os.path.basename(r["file"]), r["fg_percent"]))
        print("  %s dominant colours (share%%): %s"
              % (os.path.basename(r["file"])[:24],
                 ", ".join("%s %.1f%%" % (c, s) for c, s in r["top_colours"])))


def compare(before, after):
    print("%-22s %10s %10s %10s" % ("metric", "before", "after", "delta"))
    print("-" * 56)
    for k, fmt in (("lum_p10", "%10.1f"), ("lum_p50", "%10.1f"), ("lum_p90", "%10.1f"),
                   ("lum_std", "%10.1f"), ("distinct_colours", "%10d"),
                   ("fg_percent", "%10.1f"), ("green_minus_red", "%+10.1f"),
                   ("clipped_percent", "%10.3f")):
        b, a = before[k], after[k]
        print("%-22s " + fmt + " " + fmt + " %+10.1f" % (k, b, a, a - b))
    print()
    print("VERDICT:")
    if after["empty"]:
        print("  EMPTY frame - nothing to compare")
        return
    if after["lum_p90"] - after["lum_p10"] < 8:
        print("  still FLAT: tonal range %.1f (needs > 20 to read as an image)"
              % (after["lum_p90"] - after["lum_p10"]))
    elif after["lum_p90"] - after["lum_p10"] < 20:
        print("  range %.1f - better, but shallow" % (after["lum_p90"] - after["lum_p10"]))
    else:
        print("  tonal range %.1f - reads as an image" % (after["lum_p90"] - after["lum_p10"]))
    if after["distinct_colours"] < 60:
        print("  only %d distinct colours - likely one flat material dominating"
              % after["distinct_colours"])
    if after["clipped_percent"] > 0.5:
        print("  %.2f%% of pixels clipped - overcorrected" % after["clipped_percent"])


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("images", nargs="*")
    ap.add_argument("--compare", nargs=2, metavar=("BEFORE", "AFTER"))
    ap.add_argument("--json")
    ap.add_argument("--expect-fg", action="store_true")
    ap.add_argument("--expect-p10", type=float)
    ap.add_argument("--expect-p90", type=float)
    ap.add_argument("--expect-range", type=float)
    ap.add_argument("--expect-colours", type=int)
    ap.add_argument("--expect-green", action="store_true")
    ap.add_argument("--expect-grass-share", type=float)
    args = ap.parse_args()

    if args.compare:
        b, a = analyse(args.compare[0]), analyse(args.compare[1])
        print("BEFORE %s" % args.compare[0])
        print("AFTER  %s" % args.compare[1])
        print()
        compare(b, a)
        rows = [b, a]
    else:
        if not args.images:
            print(__doc__)
            return 1
        rows = [analyse(p) for p in args.images]
        report(rows)

    if args.json:
        with open(args.json, "w") as fh:
            json.dump(rows, fh, indent=1)
        print("\nJSON -> %s" % args.json)

    # assertions, so a metrics call can be the test rather than a report
    fails = []
    for r in rows:
        tag = os.path.basename(r["file"])
        if args.expect_fg and r["empty"]:
            fails.append("%s: empty frame" % tag)
        if args.expect_p10 is not None and r["lum_p10"] < args.expect_p10:
            fails.append("%s: p10 %.1f < %.1f" % (tag, r["lum_p10"], args.expect_p10))
        if args.expect_p90 is not None and r["lum_p90"] < args.expect_p90:
            fails.append("%s: p90 %.1f < %.1f" % (tag, r["lum_p90"], args.expect_p90))
        if args.expect_range is not None and (r["lum_p90"] - r["lum_p10"]) < args.expect_range:
            fails.append("%s: range %.1f < %.1f" % (tag, r["lum_p90"] - r["lum_p10"],
                                                    args.expect_range))
        if args.expect_colours is not None and r["distinct_colours"] < args.expect_colours:
            fails.append("%s: %d colours < %d" % (tag, r["distinct_colours"], args.expect_colours))
        if args.expect_green and r["green_minus_red"] < 0:
            fails.append("%s: G-R %+.1f (reads brown)" % (tag, r["green_minus_red"]))
        if args.expect_grass_share is not None and r["grass_share_percent"] < args.expect_grass_share:
            fails.append("%s: grass share %.1f%% < %.1f%%"
                         % (tag, r["grass_share_percent"], args.expect_grass_share))
    if fails:
        print("\nRENDER_METRICS_FAIL")
        for f in fails:
            print("  " + f)
        return 1
    if any((args.expect_fg, args.expect_p10 is not None, args.expect_p90 is not None,
            args.expect_range is not None, args.expect_colours is not None, args.expect_green,
            args.expect_grass_share is not None)):
        print("\nRENDER_METRICS_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
