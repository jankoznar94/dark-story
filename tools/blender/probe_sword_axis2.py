# Dark Story - SWORD AXIAL PROFILE, sampled along the GEOMETRY (edges), not along
# the vertices. WHY: the welded sword is low-poly and most of its vertices sit at
# the pommel end, so a vertex-based axial histogram is empty everywhere in between
# and a vertex CENTROID anchors the PCA axis line at the wrong end of the blade.
# Sampling every polygon edge at a fixed step gives a profile proportional to
# surface area, which is what actually identifies pommel / grip / guard / blade.
#
# Prints the sword's axial structure, then every fingertip's perpendicular
# distance to the GRIP segment and to the handle's own radius.
#
# Run: blender.exe -b --factory-startup -P tools/blender/probe_sword_axis2.py
import math
import os

import bpy
import numpy as np
from mathutils import Vector

REPO = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg"
SRC = os.path.join(REPO, "models", "hero.glb")
CLIP = "Rig|Sword_Idle"
FRAME = 10

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images,
              bpy.data.cameras, bpy.data.lights):
    for it in list(block):
        try:
            block.remove(it)
        except Exception:
            pass

bpy.ops.import_scene.gltf(filepath=SRC)

arm = mesh = None
for o in bpy.context.scene.objects:
    if o.type == 'ARMATURE':
        arm = o
    if o.type == 'MESH' and o.parent is arm:
        mesh = o

gname = {g.index: g.name for g in mesh.vertex_groups}


def dom(i):
    v = mesh.data.vertices[i]
    if not v.groups:
        return None
    return gname.get(max(v.groups, key=lambda g: g.weight).group)


DOM = [dom(i) for i in range(len(mesh.data.vertices))]
# polygons whose vertices all belong to the hand.R group = the rigidly bound part
HAND_POLYS = [p for p in mesh.data.polygons
              if all(DOM[v] == "DEF-hand.R" for v in p.vertices)]
print("hand.R polygons: %d of %d" % (len(HAND_POLYS), len(mesh.data.polygons)))


def measure(clip, frame):
    if arm.animation_data is None:
        arm.animation_data_create()
    if clip is None:
        arm.animation_data.action = None
        for pb in arm.pose.bones:
            pb.location = (0.0, 0.0, 0.0)
            pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
            pb.rotation_euler = (0.0, 0.0, 0.0)
            pb.scale = (1.0, 1.0, 1.0)
        label = "REST"
    else:
        arm.animation_data.action = [a for a in bpy.data.actions if a.name == clip][0]
        bpy.context.scene.frame_set(frame)
        label = "%s f%d" % (clip, frame)
    bpy.context.view_layer.update()
    me = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    MW = mesh.matrix_world
    co = [MW @ v.co for v in me.vertices]
    return label, co, me


def analyse(label, co, me):
    print("=" * 78)
    print(label)
    # --- the hand's own vertices, and the welded weapon among them -----------
    hr = [i for i in range(len(co)) if DOM[i] == "DEF-hand.R"]
    hc = sum((co[i] for i in hr), Vector()) / len(hr)
    # the weapon = the polygons of hand.R whose distance from the palm side is
    # large. Palm side = verts within 0.08 m of the hand bone's own vertex cloud
    # centroid; the split is per FACE so a face straddling the split is dropped.
    fist = [i for i in hr if (co[i] - hc).length <= 0.12]
    fc = sum((co[i] for i in fist), Vector()) / len(fist)
    sword_v = sorted({vi for p in HAND_POLYS
                      if min((co[vi] - hc).length for vi in p.vertices) > 0.12
                      for vi in p.vertices})
    sv = set(sword_v)
    print("hand.R verts %d | hand cloud (<=0.12 m) %d | weapon verts %d"
          % (len(hr), len(fist), len(sword_v)))

    # --- sample the weapon's GEOMETRY along its edges ------------------------
    pts = []
    edges = {tuple(sorted(e)) for p in HAND_POLYS for e in p.edge_keys}
    for a, b in edges:
        if a in sv and b in sv:
            A, B = co[a], co[b]
            L = (B - A).length
            n = max(2, int(L / 0.005))          # a sample every 5 mm
            for t in np.linspace(0.0, 1.0, n):
                pts.append(A.lerp(B, float(t)))
    P = np.array([[p.x, p.y, p.z] for p in pts])
    print("weapon edge samples %d (from %d interior edges)"
          % (len(P), sum(1 for a, b in edges if a in sv and b in sv)))
    C = P.mean(0)
    _, svv, vt = np.linalg.svd(P - C, full_matrices=False)
    ax = vt[0]
    if ax[2] < 0:
        ax = -ax
    along = (P - C) @ ax
    perp = np.linalg.norm((P - C) - np.outer(along, ax), axis=1)
    print("axis=(%+.3f, %+.3f, %+.3f)  sv=%s  axial %.4f..%.4f (len %.4f m)"
          % (ax[0], ax[1], ax[2], [round(float(x), 3) for x in svv],
             along.min(), along.max(), along.max() - along.min()))

    # --- axial profile, area-weighted ---------------------------------------
    print("  along[m]  n   r_min   r_med   r_max  |  bar (radius)")
    bins = np.arange(along.min(), along.max() + 0.011, 0.01)
    prof = []
    for k in range(len(bins) - 1):
        sel = (along >= bins[k]) & (along < bins[k + 1])
        n = int(sel.sum())
        if n == 0:
            print("   %+7.3f   0      -       -       -  |" % bins[k])
            prof.append(None)
            continue
        r = perp[sel]
        prof.append((bins[k], n, float(np.median(r)), float(r.max())))
        print("   %+7.3f %3d  %6.4f  %6.4f  %6.4f  | %s"
              % (bins[k], n, float(r.min()), float(np.median(r)), float(r.max()),
                 "#" * int(round(float(np.median(r)) * 120))))

    # --- the GRIP = the longest axial run whose median radius is small -------
    small = [i for i, v in enumerate(prof) if v and v[2] < 0.045]
    runs, cur = [], []
    for i in small:
        if cur and i != cur[-1] + 1:
            runs.append(cur)
            cur = []
        cur.append(i)
    if cur:
        runs.append(cur)
    grip_lo = grip_hi = None
    if runs:
        best = max(runs, key=len)
        grip_lo = prof[best[0]][0]
        grip_hi = prof[best[-1]][0] + 0.01
        print("GRIP (longest run with r_med < 0.045 m): axial %.4f .. %.4f  (%.4f m long)"
              % (grip_lo, grip_hi, grip_hi - grip_lo))
        band = (along >= grip_lo) & (along <= grip_hi)
        print("  grip band radius: median %.4f  p85 %.4f  p95 %.4f m"
              % (float(np.median(perp[band])), float(np.percentile(perp[band], 85)),
                 float(np.percentile(perp[band], 95))))
    return ax, C, grip_lo, grip_hi, co, hc, fc


# ---- run it in BOTH frames, because the sword is rigid to DEF-hand.R ----------
res = {}
for clip, frame in ((None, 0), (CLIP, FRAME)):
    label, co, me = measure(clip, frame)
    res[label] = analyse(label, co, me)

for label, (ax, C, glo, ghi, co, hc, fc) in res.items():
    print("=" * 78)
    print("FINGERTIPS, %s" % label)
    FINGERS = ["DEF-thumb", "DEF-f_index", "DEF-f_middle", "DEF-f_ring", "DEF-f_pinky"]
    for f in FINGERS:
        idx = [i for i in range(len(co)) if DOM[i] == "%s.03.R" % f]
        c = sum((co[i] for i in idx), Vector()) / len(idx)
        p = np.array([c.x, c.y, c.z])
        a = float((p - C) @ ax)
        rad = float(np.linalg.norm((p - C) - a * ax))
        if glo is not None:
            inb = glo - 0.02 <= a <= ghi + 0.02
            print("  %-14s axial %+.4f  perp-to-axis %6.4f m  %s"
                  % (f, a, rad, "OVER THE GRIP" if inb else "OFF the grip length"))
        else:
            print("  %-14s axial %+.4f  perp-to-axis %6.4f m" % (f, a, rad))
    a_palm = float((np.array([hc.x, hc.y, hc.z]) - C) @ ax)
    print("  palm centroid axial %+.4f  perp %.4f m"
          % (a_palm, float(np.linalg.norm((np.array([hc.x, hc.y, hc.z]) - C)
                                          - a_palm * ax))))
