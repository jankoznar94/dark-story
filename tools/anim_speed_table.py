#!/usr/bin/env python3
"""List every clip in a .glb with its implied ground speed (toe-contact, thr 3 cm).

Diagnostic companion to tools/anim_gait_probe.py: use it when a locomotion clip
LOOKS too fast to find out whether a slower clip exists that matches the current
move speed better than the one wired in.

  python3 tools/anim_speed_table.py [--glb models/hero.glb] [--threshold 0.03]
"""
import argparse
import sys

import anim_gait_probe as P


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", default="models/hero.glb")
    ap.add_argument("--threshold", type=float, default=0.03)
    a = ap.parse_args()
    js, bin_ = P.load_glb(a.glb)
    rig = P.Rig(js, bin_)
    rows = []
    for an in js["animations"]:
        name = an.get("name", "")
        try:
            r = P.measure(rig, an, P.TOES, thresholds=(a.threshold,))
        except Exception as e:
            print("skip %-30s %s" % (name, e))
            continue
        rows.append((r["speed_%.2f" % a.threshold], name, r["duration"],
                     r["travel_%.2f" % a.threshold], r["frames"]))
    rows.sort(reverse=True)
    for s, name, d, t, f in rows:
        print("%7.3f m/s  %-34s len=%.3fs travel=%.3fm frames=%d" % (s, name, d, t, f))
    return 0


if __name__ == "__main__":
    sys.exit(main())
