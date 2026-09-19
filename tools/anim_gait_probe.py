#!/usr/bin/env python3
"""Measure a locomotion clip's IMPLIED ground speed directly from a .glb.

Why: the walk/run clip and player.gd's speed are two independent numbers and the
retime factor is ground_speed / clip_ground_speed. If the clip constant is wrong
the feet slide. This reads the delivered .glb itself - glTF JSON + bin chunk,
forward kinematics over the joint hierarchy - so no Blender start is needed.

Method (same toe-contact idea as tools/blender/measure_gait.py):
  step every keyframe of the clip, take the world position of DEF-toe.L/R,
  find the lowest toe height over the cycle, and sum the horizontal travel of
  whichever toe is within a contact threshold of it.

Usage:
  python3 tools/anim_gait_probe.py [--glb models/hero.glb] [--clip "Rig|Walk_Loop"]
                                   [--all-locomotion]
"""
import argparse
import json
import math
import struct
import sys

LOCOMOTION = ["Rig|Walk_Loop", "Rig|Sprint_Loop", "Rig|Jog_Fwd_Loop", "Rig|Crouch_Fwd_Loop"]
TOES = ["DEF-toe.L", "DEF-toe.R"]


def load_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, ver, length = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67, "not a glb"
    off = 12
    js, bin_ = None, b""
    while off < length:
        clen, ctype = struct.unpack("<II", data[off:off + 8])
        chunk = data[off + 8:off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:
            bin_ = chunk
        off += 8 + clen + ((4 - clen % 4) % 4 if clen % 4 else 0)
    return js, bin_


CTYPE = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2),
         5125: ("I", 4), 5126: ("f", 4)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_accessor(js, bin_, idx):
    acc = js["accessors"][idx]
    fmt, size = CTYPE[acc["componentType"]]
    n = NCOMP[acc["type"]]
    bv = js["bufferViews"][acc["bufferView"]]
    start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride") or size * n
    out = []
    for i in range(acc["count"]):
        base = start + i * stride
        vals = struct.unpack_from("<" + fmt * n, bin_, base)
        out.append(vals[0] if n == 1 else vals)
    return out


def mat_mul(a, b):
    # column-major 4x4 flattened (glTF convention), returns a*b
    r = [0.0] * 16
    for c in range(4):
        for row in range(4):
            s = 0.0
            for k in range(4):
                s += a[k * 4 + row] * b[c * 4 + k]
            r[c * 4 + row] = s
    return r


def trs_matrix(t, r, s):
    x, y, z, w = r
    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz = x * y, x * z, y * z
    wx, wy, wz = w * x, w * y, w * z
    m = [
        (1 - 2 * (yy + zz)) * s[0], (2 * (xy + wz)) * s[0], (2 * (xz - wy)) * s[0], 0.0,
        (2 * (xy - wz)) * s[1], (1 - 2 * (xx + zz)) * s[1], (2 * (yz + wx)) * s[1], 0.0,
        (2 * (xz + wy)) * s[2], (2 * (yz - wx)) * s[2], (1 - 2 * (xx + yy)) * s[2], 0.0,
        t[0], t[1], t[2], 1.0,
    ]
    return m


def quat_slerp(a, b, u):
    d = sum(x * y for x, y in zip(a, b))
    if d < 0.0:
        b = [-x for x in b]
        d = -d
    d = max(-1.0, min(1.0, d))
    if d > 0.9995:
        q = [a[i] + u * (b[i] - a[i]) for i in range(4)]
    else:
        th = math.acos(d)
        st = math.sin(th)
        w1, w2 = math.sin((1 - u) * th) / st, math.sin(u * th) / st
        q = [a[i] * w1 + b[i] * w2 for i in range(4)]
    n = math.sqrt(sum(x * x for x in q)) or 1.0
    return [x / n for x in q]


def sample_curve(times, values, u, is_quat):
    if u <= times[0]:
        return values[0]
    if u >= times[-1]:
        return values[-1]
    lo, hi = 0, len(times) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if times[mid] <= u:
            lo = mid
        else:
            hi = mid
    t0, t1 = times[lo], times[hi]
    f = 0.0 if t1 == t0 else (u - t0) / (t1 - t0)
    if is_quat:
        return quat_slerp(values[lo], values[hi], f)
    return [values[lo][i] + f * (values[hi][i] - values[lo][i]) for i in range(len(values[0]))]


class Rig:
    def __init__(self, js, bin_):
        self.js = js
        self.bin = bin_
        self.nodes = js["nodes"]
        self.parent = {}
        for i, n in enumerate(self.nodes):
            for c in n.get("children", []):
                self.parent[c] = i
        self.name_to_idx = {}
        for i, n in enumerate(self.nodes):
            self.name_to_idx[n.get("name", "")] = i

    def local(self, idx, pose):
        n = self.nodes[idx]
        t = list(pose.get(idx, {}).get("t") or n.get("translation", [0.0, 0.0, 0.0]))
        r = list(pose.get(idx, {}).get("r") or n.get("rotation", [0.0, 0.0, 0.0, 1.0]))
        s = list(pose.get(idx, {}).get("s") or n.get("scale", [1.0, 1.0, 1.0]))
        return trs_matrix(t, r, s)

    def world(self, idx, pose):
        m = self.local(idx, pose)
        p = self.parent.get(idx)
        while p is not None:
            m = mat_mul(self.local(p, pose), m)
            p = self.parent.get(p)
        return m


def clip_pose(rig, anim, u):
    pose = {}
    for ch in anim["channels"]:
        tgt = ch["target"]
        node = tgt["node"]
        path = tgt["path"]
        s = anim["samplers"][ch["sampler"]]
        times = read_accessor(rig.js, rig.bin, s["input"])
        vals = read_accessor(rig.js, rig.bin, s["output"])
        if not isinstance(vals[0], tuple):
            vals = [(v,) for v in vals]
        key = {"translation": "t", "rotation": "r", "scale": "s"}.get(path)
        if key is None:
            continue
        v = sample_curve(times, vals, u, path == "rotation")
        pose.setdefault(node, {})[key] = list(v)
    return pose


def measure(rig, anim, toes, thresholds=(0.03, 0.06), fps=24.0):
    dur = max(max(read_accessor(rig.js, rig.bin, s["input"])) for s in anim["samplers"])
    nframes = max(2, int(round(dur * fps)) + 1)
    samples = []
    for i in range(nframes):
        u = min(dur, i / fps)
        pose = clip_pose(rig, anim, u)
        row = {}
        for tn in toes:
            idx = rig.name_to_idx[tn]
            m = rig.world(idx, pose)
            row[tn] = (m[12], m[13], m[14])
        samples.append(row)
    # horizontal plane = XZ (glTF is Y-up), vertical = Y
    zmin = min(min(r[t][1] for t in toes) for r in samples)
    out = {"duration": dur, "frames": nframes, "lowest": zmin}
    for thr in thresholds:
        tot = 0.0
        for i in range(1, len(samples)):
            for tn in toes:
                a, b = samples[i - 1][tn], samples[i][tn]
                if a[1] < zmin + thr and b[1] < zmin + thr:
                    tot += math.hypot(b[0] - a[0], b[2] - a[2])
        out["travel_%.2f" % thr] = tot
        out["speed_%.2f" % thr] = tot / dur
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", default="models/hero.glb")
    ap.add_argument("--clip", default=None)
    ap.add_argument("--all-locomotion", action="store_true")
    a = ap.parse_args()
    js, bin_ = load_glb(a.glb)
    rig = Rig(js, bin_)
    print("nodes=%d animations=%d" % (len(js["nodes"]), len(js["animations"])))
    missing = [t for t in TOES if t not in rig.name_to_idx]
    if missing:
        print("ABORT: toe nodes missing:", missing)
        return 1
    clips = a.clip and [a.clip] or (LOCOMOTION if a.all_locomotion else LOCOMOTION)
    for want in clips:
        anim = None
        for an in js["animations"]:
            if an.get("name", "").replace("_Loop", "") == want.replace("_Loop", ""):
                anim = an
                break
        if anim is None:
            print("%-22s MISSING" % want)
            continue
        r = measure(rig, anim, TOES)
        print("%-22s len=%.3fs frames=%d  travel=%.4f m/cycle  => %.3f m/s at 1x "
              "(thr .03) / %.3f (thr .06)"
              % (want, r["duration"], r["frames"], r["travel_0.03"],
                 r["speed_0.03"], r["speed_0.06"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
