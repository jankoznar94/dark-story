#!/usr/bin/env python3
"""Locomotion ground speed per cycle, sampled densely and integrated per stance.

Reads a .glb directly (glTF JSON + bin + forward kinematics; no Blender).

Axes are settled empirically on this rig: in ROOT-local space
  index 0 = x  side
  index 1 = y  UP
  index 2 = z  FORWARD
(verified on `Rig|Walk_Loop`: the toe's y stays in 0.0012..0.19 m while its z
sweeps -0.44..+0.35 m - i.e. y is height and z is travel.)

Method - no contact-threshold heuristic, which under-samples fast cycles:
  dense-sample the clip; at each sample take the foot with the LOWER y (the
  planted one) and accumulate how far it travels BACKWARD (-delta z) relative to
  the root; sum over one cycle. That is the distance the clip covers per cycle
  by construction, and a planted foot cannot move faster than the body without
  the feet sliding.

  python3 tools/anim_cycle_distance.py [--glb models/hero.glb] [--oversample 8]
"""
import argparse
import sys

import anim_gait_probe as P

FEET = ("DEF-foot.L", "DEF-foot.R")
TOES = ("DEF-toe.L", "DEF-toe.R")


def cycle_distance(rig, anim, bones, oversample=8, fps=24.0):
    dur = max(max(P.read_accessor(rig.js, rig.bin, s["input"])) for s in anim["samplers"])
    n = int(round(dur * fps * oversample)) + 1
    dt = dur / (n - 1)
    samples = []
    for i in range(n):
        pose = P.clip_pose(rig, anim, min(dur, i * dt))

        def w(name):
            m = rig.world(rig.name_to_idx[name], pose)
            return (m[12], m[13], m[14])

        root = w("root")
        samples.append({"root": root,
                        **{k: (w(k)[0] - root[0], w(k)[1] - root[1], w(k)[2] - root[2])
                           for k in bones}})
    total = 0.0
    detail = {k: 0.0 for k in bones}
    for i in range(1, n):
        low_prev = min(bones, key=lambda b: samples[i - 1][b][1])
        low_now = min(bones, key=lambda b: samples[i][b][1])
        if low_now != low_prev:
            continue
        d = samples[i][low_now][2] - samples[i - 1][low_now][2]
        step = -d
        total += step
        detail[low_now] += step
    return dur, n, total, detail


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", default="models/hero.glb")
    ap.add_argument("--oversample", type=int, default=8)
    ap.add_argument("--clip", default=None)
    a = ap.parse_args()
    js, bin_ = P.load_glb(a.glb)
    rig = P.Rig(js, bin_)
    clips = [a.clip] if a.clip else P.LOCOMOTION
    for want in clips:
        anim = None
        for an in js["animations"]:
            if an.get("name", "").replace("_Loop", "") == want.replace("_Loop", ""):
                anim = an
                break
        if anim is None:
            print("%-22s MISSING" % want)
            continue
        for label, bones in (("foot", FEET), ("toe", TOES)):
            dur, n, total, detail = cycle_distance(rig, anim, bones, a.oversample)
            print("%-22s %-4s len=%.3fs samples=%d  cycle travel %+.4f m  => %.3f m/s at 1x"
                  % (want, label, dur, n, total, total / dur))
            print("      per foot: " + "  ".join("%s %+.3f" % (k[-3:], v) for k, v in detail.items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
