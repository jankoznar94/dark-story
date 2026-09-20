# Dark Story - THE HAND+SWORD PROBE (one authoritative tool).
#
# Replaces a run of ad-hoc probes that each answered a slightly different question
# with a different notion of "the hand" and "the sword", which is how a build got
# declared correct against numbers that did not describe it.
#
# It fixes three things the earlier probes got wrong:
#  1. THE SWORD IS IDENTIFIED BY THE SOURCE RIG, not by a distance from a centroid.
#     A distance split cuts across the object (the welded sword is 0.85 m long and
#     bound to the same bone as the hand) and can leave the probe comparing the
#     hand against HALF of the sword. The validated label is the one
#     sword_apply_aim.py uses: take every vertex's position in DEF-hand.R's
#     REST-LOCAL frame, and call a delivered vertex "weapon" when it does not
#     match ANY source vertex. The source rig is the clean base character.
#  2. THE GRIP IS MEASURED AS A CROSS-SECTION, not as a radius. The blade tapers to
#     a 0.0016 m point, so a single "handle radius" is meaningless - what matters is
#     the radius of the shaft where the hand actually is. This prints the profile.
#  3. FINGERS ARE MEASURED BY THEIR OWN BONES (.01/.02/.03 per finger) in the bone's
#     REST-LOCAL frame, so the answer is pose-invariant and needs no clip sweep.
#
# Run: blender.exe -b --factory-startup -P tools/blender/probe_hand_sword2.py
import math
import os

import bpy
import numpy as np
from mathutils import Vector

REPO = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg"
GAME = os.path.join(REPO, "models", "hero.glb")
SRC = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_uv\unwrapped.glb"
CLIP, FRAME = "Rig|Sword_Idle", 10

FINGERS = ["DEF-thumb", "DEF-f_index", "DEF-f_middle", "DEF-f_ring", "DEF-f_pinky"]
SEGS = ("01", "02", "03")


def clear():
    for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
                  bpy.data.armatures, bpy.data.actions, bpy.data.images,
                  bpy.data.cameras, bpy.data.lights):
        for it in list(block):
            try:
                block.remove(it)
            except Exception:
                pass


def load(path):
    clear()
    bpy.ops.import_scene.gltf(filepath=path)
    mesh = next(o for o in bpy.context.scene.objects
                if o.type == 'MESH' and len(o.vertex_groups) > 20)
    arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    return mesh, arm


# ---------------------------------------------------------------- source rig ----
sm, sa = load(SRC)
Mh_src = sa.matrix_world @ sa.data.bones["DEF-hand.R"].matrix_local
Mi_src = Mh_src.inverted()
SRC_LOCAL = np.array([[*(Mi_src @ (sm.matrix_world @ v.co))] for v in sm.data.vertices])
SRC_NAMES = list(sm.vertex_groups)


def src_groups(local_pts):
    """dominant source group per delivered vertex, matched by rest-local position"""
    out = []
    for p in local_pts:
        j = int(np.argmin(((SRC_LOCAL - p) ** 2).sum(1)))
        d = float(np.linalg.norm(SRC_LOCAL[j] - p))
        out.append((SRC_NAMES[max(sm.data.vertices[j].groups,
                                  key=lambda g: g.weight).group], d))
    return out


# ---------------------------------------------------------------- delivered -----
body, arm = load(GAME)
me = body.data
M = body.matrix_world
Mh = arm.matrix_world @ arm.data.bones["DEF-hand.R"].matrix_local
Mi = Mh.inverted()
W = [M @ v.co for v in me.vertices]
LOCAL = np.array([[*(Mi @ w)] for w in W])

# --- the weapon label, from the source ---------------------------------------
dist_to_src = np.min(((LOCAL[:, None, :] - SRC_LOCAL[None, :, :]) ** 2).sum(2), axis=1) ** 0.5
SWORD = [i for i in range(len(W)) if dist_to_src[i] > 1e-4]
print("weapon verts (no source match in hand-local space): %d" % len(SWORD))
if not (70 <= len(SWORD) <= 95):
    print("  !! outside the expected 70..95 - the label is untrustworthy, stopping")
    print("  match distances: p50 %.5f p90 %.5f max %.5f"
          % tuple(np.percentile(dist_to_src, [50, 90, 100])))
    raise SystemExit(1)
print("  match distances: matched verts p99 %.6f | weapon verts min %.5f"
      % (np.percentile(dist_to_src, 99), dist_to_src[SWORD].min() if SWORD else -1))

vg = {g.index: g.name for g in body.vertex_groups}
DOM = [vg[max(v.groups, key=lambda g: g.weight).group] if v.groups else None
       for v in me.vertices]

# --- is the sword one piece? -------------------------------------------------
parent = list(range(len(W)))


def find(a):
    while parent[a] != a:
        parent[a] = parent[parent[a]]
        a = parent[a]
    return a


for p in me.polygons:
    vs = list(p.vertices)
    for k in range(1, len(vs)):
        ra, rb = find(vs[0]), find(vs[k])
        if ra != rb:
            parent[rb] = ra
sw = set(SWORD)
comp = {}
for i in SWORD:
    comp.setdefault(find(i), []).append(i)
print("")
print("WEAPON COMPONENTS: %d  sizes %s" % (len(comp), sorted((len(v) for v in comp.values()),
                                                             reverse=True)))
for root, idxs in sorted(comp.items(), key=lambda kv: -len(kv[1])):
    if len(idxs) < 8:
        continue
    pts = np.array([[W[i].x, W[i].y, W[i].z] for i in idxs])
    span = float(np.linalg.norm(pts.max(0) - pts.min(0)))
    print("  component %-5d %3d verts  span %.4f m  centroid (%.3f, %.3f, %.3f)"
          % (root, len(idxs), span, *pts.mean(0)))

# --- axis + area-weighted axial profile --------------------------------------
def profile(idxs, tag):
    idxs = set(idxs)
    edges = {tuple(sorted(e)) for p in me.polygons
             if all(v in idxs for v in p.vertices) for e in p.edge_keys}
    pts = []
    for a, b in edges:
        A, B = W[a], W[b]
        n = max(2, int((B - A).length / 0.004))
        for t in np.linspace(0.0, 1.0, n):
            pts.append(A.lerp(B, float(t)))
    P = np.array([[p.x, p.y, p.z] for p in pts])
    C = P.mean(0)
    _, sv, vt = np.linalg.svd(P - C, full_matrices=False)
    ax = vt[0]
    along = (P - C) @ ax
    perp = np.linalg.norm((P - C) - np.outer(along, ax), axis=1)
    if along[int(np.argmax(perp))] < along.mean():
        ax, along = -ax, -along               # point the axis toward the wide end
    print("")
    print("=== %s : %d verts, %d edge samples" % (tag, len(idxs), len(pts)))
    print("  axis (%+.3f, %+.3f, %+.3f)  sv %s  length %.4f m"
          % (ax[0], ax[1], ax[2], [round(float(x), 2) for x in sv],
             along.max() - along.min()))
    print("  axial profile: t is the ABSOLUTE axial coordinate, 0 = the point the")
    print("  centroid plane cuts; the widest slice is the guard/cross-bar")
    bins = np.arange(along.min(), along.max() + 0.011, 0.01)
    for k in range(len(bins) - 1):
        sel = (along >= bins[k]) & (along < bins[k + 1])
        if sel.sum() == 0:
            continue
        r = perp[sel]
        print("   %+7.3f  n=%3d  r_med %6.4f  r_max %6.4f  |%s"
              % (bins[k], int(sel.sum()), float(np.median(r)), float(r.max()),
                 "#" * int(round(float(np.median(r)) * 150))))
    return C, ax, along, perp


# The component split is INFORMATIVE, not a selection rule: a hard-surface low-poly
# export hard-edges every face, so the sword arrives as ~27 disconnected 2-4 vertex
# faces. Profiling the "largest component" therefore measures one blade quad (0.05 m),
# which is how a probe can report a 5 cm sword. Always profile the WHOLE labelled set.
C, ax, along, perp = profile(SWORD, "THE WEAPON (%d verts, %d loose faces)"
                             % (len(SWORD), len(comp)))

# --- landmark: the grip. The grip is the LOW-radius run nearest the hand ------
band = None
print("")
print("AXIAL PROFILE of the SHAFT (slices with r_med < 0.030 m):")
small = [(float(np.median(perp[(along >= b) & (along < b + 0.01)])), b)
         for b in np.arange(along.min(), along.max(), 0.01)
         if ((along >= b) & (along < b + 0.01)).sum() > 0]
runs, cur = [], []
for r, b in small:
    if r > 0.030:
        if cur:
            runs.append(cur)
        cur = []
        continue
    if cur and abs(b - cur[-1][1] - 0.01) > 1e-6:
        runs.append(cur)
        cur = []
    cur.append((r, b))
if cur:
    runs.append(cur)
for run in runs:
    print("  shaft run axial %.3f .. %.3f  (%.3f m)  mean r %.4f  -> grip candidate"
          % (run[0][1], run[-1][1] + 0.01, run[-1][1] + 0.01 - run[0][1],
             float(np.mean([r for r, _ in run]))))

# --- the hand, in the same axial frame ---------------------------------------
print("")
print("HAND vs SHAFT (all in the sword's own axial frame; radial = perpendicular")
print("distance from the shaft's axis, so a fingertip ON the shaft reads ~0 + r_handle)")
SW = np.array([[W[i].x, W[i].y, W[i].z] for i in SWORD])
print("  sword: %d verts   axial %.3f .. %.3f" % (len(SWORD), along.min(), along.max()))
for f in FINGERS:
    for seg in SEGS:
        name = "%s.%s.R" % (f, seg)
        idx = [i for i in range(len(W)) if DOM[i] == name]
        if not idx:
            continue
        c = np.array([sum(W[i][k] for i in idx) / len(idx) for k in range(3)])
        a = float((c - C) @ ax)
        rad = float(np.linalg.norm((c - C) - a * ax))
        print("  %-16s axial %+7.3f  radial %6.4f m" % (name, a, rad))

pal_idx = [i for i in range(len(W)) if DOM[i] == "DEF-hand.R" and i not in sw]
P = np.array([[W[i].x, W[i].y, W[i].z] for i in pal_idx])
pc = P.mean(0)
a_palm = float((pc - C) @ ax)
print("  %-16s axial %+7.3f  radial %6.4f m   (%d verts)"
      % ("DEF-hand.R(hand)", a_palm, float(np.linalg.norm((pc - C) - a_palm * ax)),
         len(P)))
print("  hand cloud extent: %s" % [round(float(x), 3) for x in (P.max(0) - P.min(0))])
# where is the hand's nearest approach to the shaft?
d = np.linalg.norm(P[:, None, :] - np.array([[W[i].x, W[i].y, W[i].z] for i in SWORD])[None, :, :], axis=2)
jj = np.unravel_index(np.argmin(d), d.shape)
print("  nearest hand vert -> nearest weapon vert: %.4f m" % float(d[jj]))
print("  that weapon vertex is at axial %+.3f, radial %.4f m"
      % (float((np.array([W[SWORD[jj[1]]].x, W[SWORD[jj[1]]].y, W[SWORD[jj[1]]].z]) - C) @ ax),
         float(np.linalg.norm((np.array([W[SWORD[jj[1]]].x, W[SWORD[jj[1]]].y, W[SWORD[jj[1]]].z]) - C)
                              - ((np.array([W[SWORD[jj[1]]].x, W[SWORD[jj[1]]].y, W[SWORD[jj[1]]].z]) - C) @ ax) * ax))))
print("")
print("HAND_SWORD_PROBE_DONE")
