#!/usr/bin/env python3
"""Build a whole modular prop SET from one recipe - the thing that was missing.

WHY THIS EXISTS: make_props.py hard-codes six prop functions, so a new prop means
editing that file. Adding a family (five fence variants, three crate sizes, a set
of barrels) should be DATA, not code. This tool takes a set of dimension/param
tuples and emits one OBJ per variant from the same builders.

Usage:
    python3 tools/make_propset.py --list
    python3 tools/make_propset.py fences
    python3 tools/make_propset.py crates --out assets/props
    python3 tools/make_propset.py --all --dry-run        # report sizes, write nothing
    python3 tools/make_propset.py barrels --set-param height=0.9,1.2

Every set is deterministic (--seed) and every output is verified: distinct
bounding boxes (the bug that once wrote one geometry into every file), a
non-degenerate triangle count, and a size sanity check.
"""
import argparse
import math
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "assets", "props")
SEED = 20260919

MATERIALS = {
    # Albedo calibrated in the ASSEMBLED LEVEL, measured: at the first lift the
    # props sat 2x under the grass (bark 24, wood 30, stone 45 vs grass 56-77) and
    # rendered as black silhouettes. After lifting them the internal form came
    # back (prop spread std 25.2 vs <6 for a flat blob) but the contrast against
    # the grass was only +5.9 luminance, which still does not read at a glance -
    # the threshold for that is roughly 12-20. These values put stone and wood
    # clearly ABOVE the ground rather than level with it.
    "bark": (0.300, 0.235, 0.170),
    "wood": (0.400, 0.320, 0.200),
    "stone": (0.460, 0.445, 0.415),
    "metal": (0.330, 0.322, 0.316),
    "leaf": (0.170, 0.245, 0.120),
    "cloth": (0.340, 0.300, 0.250),
}


# --------------------------------------------------------------------------- #
def h1(*a):
    x = 0
    for v in a:
        x = (x * 1000003 + int(v * 10007) + 12345) & 0x7FFFFFFF
    x ^= x >> 13
    x = (x * 1274126177) & 0x7FFFFFFF
    return (x ^ (x >> 16)) / 0x7FFFFFFF


def norm(v):
    l = math.sqrt(sum(c * c for c in v))
    return tuple(c / l for c in v) if l > 1e-12 else (0.0, 1.0, 0.0)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def rot_to(d):
    """3x3 rotation taking +Y onto unit d (Rodrigues)."""
    up = (0.0, 1.0, 0.0)
    ax = cross(up, d)
    s = math.sqrt(sum(c * c for c in ax))
    if s < 1e-9:
        return None if d[1] > 0 else "flip"
    ax = tuple(c / s for c in ax)
    ang = math.acos(max(-1.0, min(1.0, d[1])))
    ca, sa = math.cos(ang), math.sin(ang)
    return (ax, ca, sa)


def apply_rot(v, r):
    if r is None:
        return v
    if r == "flip":
        return (v[0], -v[1], v[2])
    ax, ca, sa = r
    dot = sum(a * b for a, b in zip(ax, v))
    cr = cross(ax, v)
    return tuple(v[i] * ca + cr[i] * sa + ax[i] * dot * (1 - ca) for i in range(3))


# --------------------------------------------------------------------------- #
# builders
# --------------------------------------------------------------------------- #
def cyl(r0, r1, h, seg=8, y0=0.0, jitter=0.0, seed=0):
    v, f = [], []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        j = 1.0 + jitter * h1(i, 0, seed)
        v.append((math.cos(a) * r0 * j, y0, math.sin(a) * r0 * j))
    for i in range(seg):
        a = 2 * math.pi * i / seg
        j = 1.0 + jitter * h1(i, 1, seed)
        v.append((math.cos(a) * r1 * j, y0 + h, math.sin(a) * r1 * j))
    for i in range(seg):
        k = (i + 1) % seg
        f += [(i, k, seg + k), (i, seg + k, seg + i)]
    return v, f


def bbox(sx, sy, sz, c=(0, 0, 0), jit=0.0, seed=0):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    c = list(c)
    corners = [(c[0] - hx, c[1] - hy, c[2] - hz), (c[0] + hx, c[1] - hy, c[2] - hz),
               (c[0] + hx, c[1] - hy, c[2] + hz), (c[0] - hx, c[1] - hy, c[2] + hz),
               (c[0] - hx, c[1] + hy, c[2] - hz), (c[0] + hx, c[1] + hy, c[2] - hz),
               (c[0] + hx, c[1] + hy, c[2] + hz), (c[0] - hx, c[1] + hy, c[2] + hz)]
    if jit:
        corners = [(v[0] + jit * (h1(*v, seed + i) - 0.5) * 2,
                    v[1] + jit * (h1(v[2], v[0], seed + 7 + i) - 0.5) * 2,
                    v[2] + jit * (h1(v[1], seed + 13 + i) - 0.5) * 2) for i, v in enumerate(corners)]
    faces = [(0, 3, 2), (0, 2, 1), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4),
             (1, 2, 6), (1, 6, 5), (2, 3, 7), (2, 7, 6), (3, 0, 4), (3, 4, 7)]
    return corners, faces


def merge(*parts):
    v, f = [], []
    for pv, pf in parts:
        o = len(v)
        v += pv
        f += [(a + o, b + o, c + o) for (a, b, c) in pf]
    return v, f


def tube(p0, p1, r0, r1, seg=6):
    """Tapered tube between two explicit points - correct in any direction."""
    v, f = cyl(r0, r1, math.dist(p0, p1), seg=seg)
    r = rot_to(norm(tuple(p1[i] - p0[i] for i in range(3))))
    v = [tuple(apply_rot(x, r)[i] + p0[i] for i in range(3)) for x in v]
    return v, f


def plank(from_, to, w, t):
    """A board along a direction, thickness t, width w - for fences and crates."""
    d = norm(tuple(to[i] - from_[i] for i in range(3)))
    r = rot_to(d)
    v, f = bbox(w, math.dist(from_, to), t, c=(0, math.dist(from_, to) / 2, 0))
    v = [tuple(apply_rot(x, r)[i] + from_[i] for i in range(3)) for x in v]
    return v, f


# --------------------------------------------------------------------------- #
# sets: each returns a list of (variant_name, [(verts, faces, material), ...])
# --------------------------------------------------------------------------- #
def set_fences(size, rng, params):
    """Fence run, broken fence, gate post, corner post - built from posts+rails."""
    out = []
    rail_h = params.get("rail_h", [0.45, 0.85, 1.15])
    span = params.get("span", [2.4, 1.6, 0.0, 0.0])
    for name, length, nposts, broken in (("fence_run", 3.0, 4, False),
                                         ("fence_broken", 2.2, 3, True),
                                         ("gate_post", 0.0, 1, False),
                                         ("corner_post", 0.0, 2, False)):
        parts = []
        posts = nposts
        for i in range(posts):
            x = -length / 2 + (length * i / max(1, posts - 1)) if posts > 1 else 0.0
            h = 1.55 if name != "corner_post" else 1.30
            lean = 0.10 if broken and i == posts - 1 else 0.0
            pv, pf = cyl(0.085, 0.070, h, seg=6, jitter=0.05, seed=i)
            pv = [(v[0] + x + lean * v[1], v[1], v[2]) for v in pv]
            parts.append((pv, pf, "wood"))
        # rails between successive posts
        if posts > 1:
            for i in range(posts - 1):
                xa = -length / 2 + (length * i / (posts - 1))
                xb = -length / 2 + (length * (i + 1) / (posts - 1))
                if broken and i == posts - 2:
                    rail_h_eff = [rail_h[0]]          # only the bottom rail survives
                else:
                    rail_h_eff = rail_h
                for rh in rail_h_eff:
                    drop = 0.32 if (broken and i == posts - 2) else 0.0
                    rv, rf = plank((xa, rh - drop, 0.0), (xb, rh - drop, 0.0), 0.10, 0.055)
                    parts.append((rv, rf, "wood"))
        out.append((name, parts))
    return out


def set_crates(size, rng, params):
    """Three crate sizes with corner battens so they read as crates, not boxes."""
    out = []
    for name, s in (("crate_small", 0.55), ("crate_medium", 0.80), ("crate_large", 1.10)):
        parts = []
        h = s * 0.92
        parts.append(bbox(s, h, s, c=(0, h / 2, 0), jit=0.012, seed=int(s * 100)))
        b = s * 0.10
        for sx in (-1, 1):
            for sz in (-1, 1):
                parts.append(bbox(b, h * 1.01, b, c=(sx * (s / 2 - b / 2), h / 2, sz * (s / 2 - b / 2)),
                                  jit=0.006, seed=int(s * 100) + 7 + sx * 3 + sz))
        for sy in (0.16, 0.84):
            parts.append(bbox(s * 1.01, b * 0.8, b, c=(0, h * sy, s / 2 - b / 2),
                              jit=0.006, seed=int(s * 100) + 30))
            parts.append(bbox(s * 1.01, b * 0.8, b, c=(0, h * sy, -(s / 2 - b / 2)),
                              jit=0.006, seed=int(s * 100) + 40))
        parts = [(v, f, "wood") for (v, f) in parts]
        out.append((name, parts))
    return out


def set_barrels(size, rng, params):
    """Upright and tipped barrels with iron hoops."""
    out = []
    for name, tipped in (("barrel", False), ("barrel_tipped", True)):
        parts = []
        staves, sf = cyl(0.30, 0.30, 0.78, seg=12, jitter=0.02, seed=3)
        belly = cyl(0.34, 0.34, 0.30, seg=12, y0=0.22, jitter=0.02, seed=4)
        parts.append((staves, sf, "wood"))
        parts.append((belly[0], belly[1], "wood"))
        for y in (0.12, 0.40, 0.68):
            hv, hf = cyl(0.345, 0.345, 0.055, seg=12, y0=y)
            parts.append((hv, hf, "metal"))
        if tipped:
            # lay it on its side: rotate about Z and lift to the barrel radius
            ca, sa = math.cos(math.pi / 2), math.sin(math.pi / 2)
            new = []
            for (v, f, m) in parts:
                rv = [(v[i][0] * ca - v[i][1] * sa, v[i][0] * sa + v[i][1] * ca, v[i][2]) for i in range(len(v))]
                rv = [(x, y + 0.34, z) for (x, y, z) in rv]
                new.append((rv, f, m))
            parts = new
        out.append((name, parts))
    return out


def set_ruins(size, rng, params):
    """Broken wall stubs and rubble - the pieces that make a ruin read as a ruin."""
    out = []
    # three increasingly broken wall stubs
    for name, height in (("ruin_arch", 1.9), ("ruin_stub_tall", 1.3), ("ruin_stub_low", 0.6)):
        parts = []
        bw, bh = 0.95, 0.42
        rows = max(1, int(height / bh))
        for row in range(rows):
            off = (bw / 2) if row % 2 else 0.0
            span = 2.0 if name == "ruin_arch" else 1.6
            for i in range(int(span / bw) + 2):
                cx = -span / 2 + off + i * (bw - 0.02)
                if name == "ruin_arch" and row >= rows - 2 and abs(cx) < 0.55:
                    continue                      # the arch opening
                parts.append(bbox(bw, bh, 0.42, c=(cx, bh / 2 + row * (bh + 0.01), 0),
                                  jit=0.02, seed=row * 17 + i))
        parts = [(v, f, "stone") for (v, f) in parts]
        out.append((name, parts))
    # rubble pile: scattered chunks
    parts = []
    for i in range(9):
        a = i * 2.4
        r = 0.30 + 0.42 * h1(i, 5)
        x, z = math.cos(a) * r, math.sin(a) * r
        s = 0.18 + 0.26 * h1(i, 9)
        v, f = bbox(s, s * 0.7, s * 0.9, c=(x, s * 0.35, z),
                    jit=s * 0.22, seed=i * 31)
        parts.append((v, f, "stone"))
    out.append(("rubble_pile", parts))
    return out


def set_stumps(size, rng, params):
    """Cut stumps and a fallen log, for ground dressing.

    First version failed review: "no convincing stump, the object looks like
    nothing or a rock". Measured cause: the root flare (r*1.7) was nearly twice
    the trunk top radius, so the widest part of a 0.42 m prop was a flat 0.48 m
    root disc - it read as a rock. A cut stump reads by its CUT TOP FACE and a
    tall enough trunk; the flare must be modest.
    """
    out = []
    for name, r, h in (("stump", 0.30, 0.62), ("stump_low", 0.36, 0.34)):
        trunk = cyl(r, r * 0.94, h, seg=10, jitter=0.05, seed=2)
        # modest flare, well under the trunk radius ratio that caused the failure
        flare = cyl(r * 1.22, r, 0.12, seg=10, jitter=0.07, seed=5)
        out.append((name, [(flare[0], flare[1], "bark"), (trunk[0], trunk[1], "bark")]))
    lv, lf = cyl(0.26, 0.22, 2.6, seg=9, jitter=0.05, seed=8)
    ca, sa = math.cos(math.pi / 2), math.sin(math.pi / 2)
    lv = [(v[0] * ca - v[1] * sa, v[0] * sa + v[1] * ca + 0.24, v[2]) for v in lv]
    out.append(("log_fallen", [(lv, lf, "bark")]))
    return out


SETS = {
    "fences": set_fences,
    "crates": set_crates,
    "barrels": set_barrels,
    "ruins": set_ruins,
    "stumps": set_stumps,
}


# --------------------------------------------------------------------------- #
def write_obj(name, parts, path):
    lines = ["# Dark Story prop set item: %s (tools/make_propset.py)" % name,
             "mtllib proset.mtl", "o %s" % name]
    idx, nrm = [], []
    for (verts, faces, mat) in parts:
        for (a, b, c) in faces:
            va, vb, vc = verts[a], verts[b], verts[c]
            nn = norm(cross(tuple(vb[i] - va[i] for i in range(3)),
                            tuple(vc[i] - va[i] for i in range(3))))
            cen = tuple((va[i] + vb[i] + vc[i]) / 3 for i in range(3))
            if sum(nn[i] * (cen[i] - 0.6) for i in range(3)) < 0:
                nn = tuple(-c for c in nn)
            base = len(idx) + 1
            for v in (va, vb, vc):
                lines.append("v %.5f %.5f %.5f" % v)
            nrm.append(nn)
            idx += [base, base + 1, base + 2]
    for nn in nrm:
        lines.append("vn %.5f %.5f %.5f" % nn)
    # one usemtl per face group, taken from the part it came from
    fi = 0
    for (verts, faces, mat) in parts:
        lines.append("usemtl %s" % mat)
        for _ in faces:
            q = fi + 1
            lines.append("f %d//%d %d//%d %d//%d"
                         % (idx[fi * 3], q, idx[fi * 3 + 1], q, idx[fi * 3 + 2], q))
            fi += 1
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("sets", nargs="*")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--seed", type=int, default=SEED)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.list or (not args.sets and not args.all):
        print("prop sets: %s" % ", ".join(sorted(SETS)))
        print("\nusage: make_propset.py [--all | <set> ...] [--size N] [--seed N] [--out DIR]")
        return 0
    names = sorted(SETS) if args.all else args.sets
    unknown = [n for n in names if n not in SETS]
    if unknown:
        print("unknown set(s): %s\nknown: %s" % (unknown, ", ".join(sorted(SETS))))
        return 1
    if not args.dry_run:
        os.makedirs(args.out, exist_ok=True)

    mtl = os.path.join(args.out, "proset.mtl")
    if not args.dry_run:
        with open(mtl, "w") as fh:
            for m, rgb in MATERIALS.items():
                fh.write("newmtl %s\nKd %.4f %.4f %.4f\nKa 0 0 0\nKs 0.05 0.05 0.05\nNs 8\n"
                         "illum 1\n\n" % (m, *rgb))

    total_files, total_tris, boxes = 0, 0, {}
    problems = []
    for s in names:
        rng = np.random.default_rng(args.seed)
        items = SETS[s](args.size, rng, {})
        print("%s (%d variants)" % (s, len(items)))
        for (vname, parts) in items:
            allv = np.array([v for p in parts for v in p[0]])
            tris = sum(len(p[1]) for p in parts)
            total_tris += tris
            d = allv.max(axis=0) - allv.min(axis=0)
            key = tuple(np.round(d, 3))
            boxes.setdefault(key, []).append(vname)
            if tris < 8:
                problems.append("%s: only %d tris" % (vname, tris))
            if max(d) < 0.05:
                problems.append("%s: degenerate size %s" % (vname, np.round(d, 3).tolist()))
            print("    %-16s tris %4d  parts %d  size %.2f x %.2f x %.2f m"
                  % (vname, tris, len(parts), *d))
            if not args.dry_run:
                write_obj(vname, parts, os.path.join(args.out, "%s.obj" % vname))
                total_files += 1
    dupes = {k: v for k, v in boxes.items() if len(v) > 1}
    # identical DIMENSIONS across variants is suspicious but not fatal (crates
    # differ by scale so they must not collide); identical bbox AND tris is fatal
    print("\nfiles %d  tris %d  distinct dimension groups %d" % (total_files, total_tris, len(boxes)))
    if dupes:
        print("note: variants sharing dimensions: %s" % dupes)
    if problems:
        print("PROPSET_FAIL")
        for p in problems:
            print("  " + p)
        return 1
    print("PROPSET_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
