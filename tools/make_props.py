#!/usr/bin/env python3
"""Generate Dark Story's modular prop set as OBJ + MTL.

Jan's correction after the first props discussion:
    "I would not want a purely low-poly design - I don't want objects looking like
     cubes. It doesn't have to be 4K resolution, but in shape it should at least
     resemble the given object. A tree, a rock, a wall."

So every prop here spends its budget on SILHOUETTE. Polygons stay cheap (8-10
segment cylinders, subdiv-2 spheres, flat shaded, no micro-detail) but the FORM
is real: a tapered trunk under stacked canopy cones, a noise-displaced boulder,
courses of offset wall blocks, a column with base and capital.

Flat shading is deliberate and matches the project's faceted look: every triangle
is emitted with its own vertices and a face normal, so nothing is smoothed away.

Deterministic (SEED fixed) so the whole set can be regenerated rather than
hand-edited.

    python3 tools/make_props.py

Writes assets/props/*.obj + props.mtl.
"""
import math
import os
import sys

SEED = 20260919
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "props")


# --------------------------------------------------------------------------- #
# tiny deterministic hash noise (no numpy dependency, stable across runs)
# --------------------------------------------------------------------------- #
def _h(*args) -> float:
    x = 0
    for a in args:
        x = (x * 1000003 + int(a * 10007) + 12345) & 0x7FFFFFFF
    x ^= x >> 13
    x = (x * 1274126177) & 0x7FFFFFFF
    x ^= x >> 16
    return x / 0x7FFFFFFF


def n3(x, y, z, seed=0) -> float:
    """value-ish noise in [-1,1] from summed sines - deterministic, seedable."""
    return (math.sin(x * 3.1 + seed * 1.7) * math.cos(y * 2.7 - seed * 0.9)
            + math.sin(y * 4.3 + seed * 2.3) * math.cos(z * 3.9 + seed * 1.1)
            + math.sin(z * 2.1 - seed * 0.5) * math.cos(x * 4.7 + seed * 3.1)) / 3.0


def norm(v):
    l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    return (v[0] / l, v[1] / l, v[2] / l) if l > 1e-12 else (0.0, 1.0, 0.0)


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


# --------------------------------------------------------------------------- #
# primitive builders -> (verts, faces)
# --------------------------------------------------------------------------- #
def cyl(r0, r1, h, seg=9, y0=0.0, twist=0.0, jitter=0.0):
    verts, faces = [], []
    for i in range(seg):
        a = 2 * math.pi * i / seg + twist
        j = 1.0 + jitter * n3(i * 0.7, 0.0, 0.0, 5)
        verts.append((math.cos(a) * r0 * j, y0, math.sin(a) * r0 * j))
    for i in range(seg):
        a = 2 * math.pi * i / seg + twist
        j = 1.0 + jitter * n3(i * 0.7, 1.0, 0.0, 5)
        verts.append((math.cos(a) * r1 * j, y0 + h, math.sin(a) * r1 * j))
    for i in range(seg):
        k = (i + 1) % seg
        faces.append((i, k, seg + k))
        faces.append((i, seg + k, seg + i))
    return verts, faces


def cone(r, h, seg=10, y0=0.0, tip=0.06):
    verts, faces = [], []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        verts.append((math.cos(a) * r, y0, math.sin(a) * r))
    verts.append((0.0, y0 + h, 0.0))          # apex
    apex = seg
    for i in range(seg):
        k = (i + 1) % seg
        faces.append((i, k, apex))
    return verts, faces


def box(sx, sy, sz, cx=0.0, cy=0.0, cz=0.0, jitter=0.0, seed=0):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    c = [(cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
         (cx + hx, cy - hy, cz + hz), (cx - hx, cy - hy, cz + hz),
         (cx - hx, cy + hy, cz - hz), (cx + hx, cy + hy, cz - hz),
         (cx + hx, cy + hy, cz + hz), (cx - hx, cy + hy, cz + hz)]
    if jitter:
        c = [(v[0] + jitter * n3(v[0], v[1], v[2], seed + i),
              v[1] + jitter * n3(v[2], v[0], v[1], seed + 7 + i),
              v[2] + jitter * n3(v[1], v[2], v[0], seed + 13 + i)) for i, v in enumerate(c)]
    f = [(0, 3, 2), (0, 2, 1), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4),
         (1, 2, 6), (1, 6, 5), (2, 3, 7), (2, 7, 6), (3, 0, 4), (3, 4, 7)]
    return c, f


def icosphere(subdiv=2):
    t = (1.0 + 5.0 ** 0.5) / 2.0
    verts = [norm(v) for v in [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0),
                               (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
                               (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]]
    faces = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
             (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
             (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
             (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    for _ in range(subdiv):
        cache, nf = {}, []
        def mid(a, b):
            key = (min(a, b), max(a, b))
            if key not in cache:
                verts.append(norm(((verts[a][0] + verts[b][0]), (verts[a][1] + verts[b][1]),
                                   (verts[a][2] + verts[b][2]))))
                cache[key] = len(verts) - 1
            return cache[key]
        for (a, b, c) in faces:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        faces = nf
    return verts, faces


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def merge(*parts):
    verts, faces = [], []
    for vs, fs in parts:
        off = len(verts)
        verts += vs
        faces += [(a + off, b + off, c + off) for (a, b, c) in fs]
    return verts, faces


def xform(verts, scale=(1, 1, 1), rot=(0, 0, 0), trans=(0, 0, 0)):
    sx, sy, sz = rot
    cx, sxx = math.cos(sx), math.sin(sx)
    cy, syy = math.cos(sy), math.sin(sy)
    cz, szz = math.cos(sz), math.sin(sz)
    out = []
    for (x, y, z) in verts:
        x, y, z = x * scale[0], y * scale[1], z * scale[2]
        y, z = y * cx - z * sxx, y * sxx + z * cx
        x, z = x * cy + z * syy, -x * syy + z * cy
        x, y = x * cz - y * szz, x * szz + y * cz
        out.append((x + trans[0], y + trans[1], z + trans[2]))
    return out


def flatten_floor(verts, floor=0.0):
    return [(v[0], v[1] if v[1] > floor else floor, v[2]) for v in verts]


# --------------------------------------------------------------------------- #
# the props
# --------------------------------------------------------------------------- #
def tree_conifer():
    """Tapered trunk under three stacked canopy tiers - unmistakably a tree.

    The trunk alone rendered as a short stub ("too short and blocky, reads as a
    stump"), so it is taller here and gets a flared root so its base is not a
    bare cylinder cross-section.

    Returns PARTS with explicit materials. An earlier version split trunk from
    canopy by a height threshold, which broke as soon as the trunk grew past the
    first canopy tier - the top of the trunk would have been painted as needles.
    Material by construction has no such failure mode.
    """
    trunk = merge(cyl(0.42, 0.26, 0.35, seg=8, y0=0.0, jitter=0.06),   # root flare
                  cyl(0.26, 0.17, 1.75, seg=8, y0=0.35, jitter=0.05),
                  cyl(0.17, 0.10, 1.35, seg=8, y0=2.10, jitter=0.05))   # reaches y=3.45
    tiers = []
    for i, (r, h, y) in enumerate(((1.35, 1.7, 2.05), (1.00, 1.5, 3.15), (0.62, 1.3, 4.15))):
        cv, cf = cone(r, h, seg=10, y0=y)
        # a little per-tier jitter so the tiers are not mechanical
        cv = [(v[0] + 0.05 * n3(v[0], y, v[2], 20 + i), v[1],
               v[2] + 0.05 * n3(v[2], y, v[0], 30 + i)) for v in cv]
        tiers.append((cv, cf))
    return ([(trunk[0], trunk[1], "bark")] +
            [(v, f, "leaf") for (v, f) in tiers])


def tree_dead():
    """Bare trunk with several levels of forks - must read as a barren tree.

    First attempt failed: the branches were built with cylinder->rotate->translate
    but `xform` was applied to a copy and the fork tips were placed at a fixed
    height, so every branch collapsed onto the trunk and the prop rendered as a
    plain spike. Build each branch as its own segment chain from an explicit foot
    point instead, so the forking is real geometry.
    """
    parts = [merge(cyl(0.28, 0.17, 1.5, seg=8, jitter=0.06),
                   cyl(0.17, 0.11, 1.3, seg=8, y0=1.5, jitter=0.06))]

    def limb(foot, direction, length, r0, r1, depth):
        """A tapered segment from `foot` along `direction`, forking at the tip."""
        d = norm(direction)
        vs, fs = cyl(r0, r1, length, seg=6)
        # cyl is built along +Y; rotate it onto d
        up = (0.0, 1.0, 0.0)
        ax = cross(up, d)
        if math.sqrt(ax[0] ** 2 + ax[1] ** 2 + ax[2] ** 2) < 1e-6:
            rot = (0.0, 0.0, 0.0) if d[1] > 0 else (math.pi, 0.0, 0.0)
        else:
            ang = math.acos(max(-1.0, min(1.0, up[0] * d[0] + up[1] * d[1] + up[2] * d[2])))
            axn = norm(ax)
            # Rodrigues on each vertex
            ca, sa = math.cos(ang), math.sin(ang)
            rot = None
            out = []
            for (x, y, z) in vs:
                dot = x * axn[0] + y * axn[1] + z * axn[2]
                cr = cross(axn, (x, y, z))
                out.append((x * ca + cr[0] * sa + axn[0] * dot * (1 - ca),
                            y * ca + cr[1] * sa + axn[1] * dot * (1 - ca),
                            z * ca + cr[2] * sa + axn[2] * dot * (1 - ca)))
            vs = out
        vs = [(v[0] + foot[0], v[1] + foot[1], v[2] + foot[2]) for v in vs]
        got = [(vs, fs)]
        tip = (foot[0] + d[0] * length, foot[1] + d[1] * length, foot[2] + d[2] * length)
        if depth > 0:
            spread = 0.72 / (depth + 0.5)
            for sgn in (1.0, -1.0):
                # fork sideways in the branch's own plane
                side = norm(cross(d, up))
                nd = norm((d[0] + side[0] * spread * sgn,
                           d[1] + 0.42,                    # forks sweep upward
                           d[2] + side[2] * spread * sgn))
                got += limb(tip, nd, length * 0.60, r1, r1 * 0.45, depth - 1)
        return got

    trunk_top = (0.0, 2.75, 0.0)
    for i, (ang, tilt, ln) in enumerate([(0.30, 1.15, 1.5), (1.85, 1.05, 1.35),
                                         (3.30, 1.25, 1.25), (4.75, 1.10, 1.4),
                                         (5.90, 0.95, 1.15)]):
        d = (math.cos(ang) * math.sin(tilt) * 0.85, math.cos(tilt), math.sin(ang) * math.sin(tilt) * 0.85)
        foot = (0.0, 1.45 + (i % 3) * 0.42, 0.0)
        parts += limb(foot, d, ln, 0.115, 0.075, 2)
    parts += limb(trunk_top, (0.18, 1.0, 0.12), 1.15, 0.12, 0.05, 2)
    v, f = merge(*parts)
    return [(v, f, "bark")]


def rock_boulder():
    """Noise-displaced icosphere, squashed and with a flat base."""
    v, f = icosphere(2)
    out = []
    for (x, y, z) in v:
        # two octaves of displacement along the radial direction
        d = 0.20 * n3(x * 2.0, y * 2.0, z * 2.0, 3) + 0.09 * n3(x * 5.0, y * 5.0, z * 5.0, 11)
        r = 1.0 + d
        out.append((x * r, y * r, z * r))
    out = xform(out, scale=(1.05, 0.66, 0.86))
    out = flatten_floor(out, 0.02)
    return [(out, f, "stone")]


def rock_small():
    v, f = icosphere(1)
    out = []
    for (x, y, z) in v:
        d = 0.26 * n3(x * 2.4, y * 2.4, z * 2.4, 17)
        r = 1.0 + d
        out.append((x * r, y * r, z * r))
    out = xform(out, scale=(0.55, 0.34, 0.48))
    out = flatten_floor(out, 0.01)
    return [(out, f, "stone")]


def wall_segment():
    """Two courses of offset blocks plus capstones - reads as masonry.

    First attempt had visible gaps between the blocks (measured from the render:
    "not continuous, has gaps between the blocks"), so the blocks are now sized
    to overlap slightly and a mortar-course box fills the joints.
    """
    parts = []
    bw, bh, bd = 1.02, 0.46, 0.42          # was 0.92 wide with a 0.04 gap
    STEP = bw - 0.02                        # slight overlap, no daylight between
    for row in range(3):
        off = (bw / 2) if row % 2 else 0.0
        for i in range(5):
            cx = -2.0 + off + i * STEP
            parts.append(box(bw, bh, bd, cx=cx, cy=bh / 2 + row * (bh + 0.01), cz=0.0,
                             jitter=0.018, seed=100 + row * 10 + i))
    # a backing slab so the joints never show sky through the wall
    H = 3 * (bh + 0.01)
    parts.append(box(5.3, H, bd * 0.75, cx=0.02, cy=H / 2, cz=0.0, jitter=0.008, seed=250))
    for i in range(4):
        cx = -1.75 + i * (bw * 0.92)
        parts.append(box(bw * 0.92, 0.24, bd + 0.12, cx=cx, cy=H + 0.12, cz=0.0,
                         jitter=0.014, seed=200 + i))
    v, f = merge(*parts)
    return [(v, f, "stone")]


def pillar():
    """Octagonal tapered shaft with a base and a broken capital."""
    parts = [box(0.78, 0.26, 0.78, cy=0.13, jitter=0.012, seed=300)]
    shaft_v, shaft_f = cyl(0.30, 0.25, 2.30, seg=8, y0=0.26, twist=math.pi / 8, jitter=0.02)
    parts.append((shaft_v, shaft_f))
    parts.append(box(0.60, 0.22, 0.60, cy=2.56, jitter=0.03, seed=310))
    v, f = merge(*parts)
    return [(v, f, "stone")]


PROPS = {
    "tree_conifer": tree_conifer,
    "tree_dead": tree_dead,
    "rock_boulder": rock_boulder,
    "rock_small": rock_small,
    "wall_segment": wall_segment,
    "pillar": pillar,
}

MATERIALS = {
    # Same calibration as make_propset.py, measured in the assembled level: the
    # first values read 2x under the grass and every prop became a black
    # silhouette; these sit clearly above it so the form reads at a glance.
    "bark": (0.300, 0.235, 0.170),
    "stone": (0.460, 0.445, 0.415),
    "leaf": (0.170, 0.245, 0.120),
}
# which prop gets the foliage material for its canopy tiers
LEAFY = {"tree_conifer"}


def write_obj(name, verts, faces, mat, path):
    """Flat shaded: every triangle gets its own 3 verts and a face normal."""
    lines = ["# Dark Story prop: %s (generated by tools/make_props.py)" % name,
             "mtllib props.mtl", "o %s" % name]
    nrm, idx = [], []
    for (a, b, c) in faces:
        va, vb, vc = verts[a], verts[b], verts[c]
        nn = norm(cross(sub(vb, va), sub(vc, va)))
        # outward-facing check against the part's own centroid
        cen = ((va[0] + vb[0] + vc[0]) / 3, (va[1] + vb[1] + vc[1]) / 3, (va[2] + vb[2] + vc[2]) / 3)
        if nn[0] * cen[0] + nn[1] * (cen[1] - 1.0) + nn[2] * cen[2] < 0:
            nn = (-nn[0], -nn[1], -nn[2])
        base = len(idx) + 1
        for v in (va, vb, vc):
            lines.append("v %.5f %.5f %.5f" % v)
        nrm.append(nn)
        idx += [base, base + 1, base + 2]
    for nn in nrm:
        lines.append("vn %.5f %.5f %.5f" % nn)
    lines.append("usemtl %s" % mat)
    for i in range(0, len(idx), 3):
        q = i // 3 + 1
        lines.append("f %d//%d %d//%d %d//%d" % (idx[i], q, idx[i + 1], q, idx[i + 2], q))
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "props.mtl"), "w") as fh:
        for m, rgb in MATERIALS.items():
            fh.write("newmtl %s\nKd %.4f %.4f %.4f\nKa 0 0 0\nKs 0.05 0.05 0.05\nNs 8\n"
                     "illum 1\n\n" % (m, *rgb))
    total_tris = 0
    for name, fn in PROPS.items():
        res = fn()
        parts = res                          # always a list of (verts, faces, material)
        if name in LEAFY and len(parts) > 1:
            # each part already carries its own material - split by construction,
            # never by a height threshold (that broke when the trunk grew taller
            # than the first canopy tier).
            for i, (pv, pf, pmat) in enumerate(parts):
                tag = "trunk" if pmat == "bark" else "canopy" if i == 1 else "canopy%d" % i
                write_obj("%s_%s" % (name, tag), pv, pf, pmat,
                          os.path.join(OUT, "%s_%s.obj" % (name, tag)))
        else:
            pv, pf, pmat = parts[0]
            write_obj(name, pv, pf, pmat, os.path.join(OUT, name + ".obj"))
        tris = sum(len(p[1]) for p in parts)
        total_tris += tris
        allv = [v for p in parts for v in p[0]]
        xs = [v[0] for v in allv]
        ys = [v[1] for v in allv]
        zs = [v[2] for v in allv]
        print("  %-14s tris %4d  verts %4d  size %.2f x %.2f x %.2f m"
              % (name, tris, len(allv), max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)))
    print("PROPS_WRITTEN %d  total tris %d  -> %s" % (len(PROPS), total_tris, OUT))
    # Guard against the bug that shipped one geometry into every file: the loop
    # variable leaked from the LEAFY branch, so every prop after the tree wrote
    # the TREE's verts/faces (all 62 tris, all bbox 4.5 m tall). Compare the
    # written files' bounding boxes and fail loudly if any two are identical.
    import glob
    boxes = {}
    for f in sorted(glob.glob(os.path.join(OUT, "*.obj"))):
        vs = [tuple(map(float, l.split()[1:])) for l in open(f) if l.startswith("v ")]
        if not vs:
            continue
        key = tuple(round(v, 3) for v in
                    (min(v[0] for v in vs), max(v[0] for v in vs),
                     min(v[1] for v in vs), max(v[1] for v in vs),
                     min(v[2] for v in vs), max(v[2] for v in vs)))
        boxes.setdefault(key, []).append(os.path.basename(f))
    dupes = {k: v for k, v in boxes.items() if len(v) > 1}
    if dupes:
        print("PROPS_DUPLICATE_GEOMETRY %s" % dupes)
        return 1
    print("PROPS_ALL_DISTINCT true (%d files)" % len(boxes))
    return 0


if __name__ == "__main__":
    sys.exit(main())
