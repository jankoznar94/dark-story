# Dark Story - THE DECISIVE TABLE: every vertex of the weapon in axial order, with
# the hand's vertices in the same frame, plus an ASCII cross-section.
#
# WHY a raw table: the sword is only 80 vertices. Any statistic over it (median
# radius per 1 cm slice, "handle radius", centroid distances) averages away the very
# thing in question - whether geometry EXISTS where the hand is. 80 rows cannot hide
# anything, and they settle "is there a handle at all" in one look.
#
# Run: blender.exe -b --factory-startup -P tools/blender/probe_grip_table.py
import os

import bpy
import numpy as np

SRC = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_uv\in.glb"
GAME = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg\models\hero.glb"


def clear():
    for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
                  bpy.data.armatures, bpy.data.actions, bpy.data.images,
                  bpy.data.cameras, bpy.data.lights):
        for it in list(block):
            try:
                block.remove(it)
            except Exception:
                pass


def weapon_ids(o, mw, src_local=None):
    """material_index == 1 where the mesh still has two slots (the pre-atlas
    stages); otherwise the source-match label in DEF-hand.R rest-local space,
    which is the only label that survives the atlas collapse to one material."""
    polys = [p for p in o.data.polygons if p.material_index == 1]
    if polys:
        return sorted({v for p in polys for v in p.vertices}), "%d polys, material_index==1" % len(polys)
    if src_local is None:
        return None, "no label available"
    arm = next(x for x in bpy.context.scene.objects if x.type == 'ARMATURE')
    Mh = arm.matrix_world @ arm.data.bones["DEF-hand.R"].matrix_local
    Mi = Mh.inverted()
    L = np.array([[*(Mi @ (mw @ v.co))] for v in o.data.vertices])
    d = np.min(((L[:, None, :] - src_local[None, :, :]) ** 2).sum(2), axis=1) ** 0.5
    return [i for i in range(len(L)) if d[i] > 1e-4], "no source match in hand-local space"


def report(path, label, src_local=None):
    clear()
    bpy.ops.import_scene.gltf(filepath=path)
    o = next(x for x in bpy.context.scene.objects
             if x.type == 'MESH' and len(x.vertex_groups) > 20)
    mw = o.matrix_world
    idx, how = weapon_ids(o, mw, src_local)
    if idx is None:
        print("SKIP %s (%s)" % (path, how))
        return None
    print("=" * 80)
    print("%s   (%s)" % (label, path))
    print("weapon: %d verts  [labelled by: %s]" % (len(idx), how))
    S = np.array([[*(mw @ o.data.vertices[i].co)] for i in idx])
    C = S.mean(0)
    # the axis is the direction tip->pommel, taken from the two extreme verts
    d = ((S[:, None, :] - S[None, :, :]) ** 2).sum(2) ** 0.5
    i0, i1 = np.unravel_index(np.argmax(d), d.shape)
    ax = (S[i1] - S[i0]) / np.linalg.norm(S[i1] - S[i0])
    along = (S - C) @ ax
    perp = np.linalg.norm((S - C) - np.outer(along, ax), axis=1)
    if along[i0] > along[i1]:
        ax, along = -ax, -along
        i0, i1 = i1, i0
    print("axis = the longest vertex pair, %.4f m apart" % np.linalg.norm(S[i1] - S[i0]))
    print("  t+ = along the blade from the tip end. t=%.4f is the tip end." % along.min())
    print("")
    print("  #   t (along)   radius   |  x       y       z")
    order = np.argsort(along)
    for k, j in enumerate(order):
        print("  %3d  %+8.4f  %7.4f   | %+7.3f %+7.3f %+7.3f"
              % (k, along[j], perp[j], S[j][0], S[j][1], S[j][2]))
    # slice the t range into 20 bins and print the radius envelope
    print("")
    print("  radius envelope per 5 %% of the weapon's length (t as a fraction):")
    tmin, tmax = along.min(), along.max()
    for k in range(20):
        lo = tmin + (tmax - tmin) * k / 20
        hi = tmin + (tmax - tmin) * (k + 1) / 20
        sel = (along >= lo) & (along < hi)
        n = int(sel.sum())
        print("   %.2f-%.2f  n=%-3d  r_min %6.4f  r_max %6.4f  %s"
              % (k / 20, (k + 1) / 20, n,
                 float(perp[sel].min()) if n else -1,
                 float(perp[sel].max()) if n else -1,
                 "#" * int(round((float(perp[sel].max()) if n else 0) * 100))))
    return ax, C, along, perp, idx, o, mw


report(SRC, "SOURCE / PRE-ATLAS (in.glb)")
# the source label for the delivered file: the SAME pre-atlas mesh, in hand-local space
ax0, C0, along0, perp0, idx0, o0, mw0 = None, None, None, None, None, None, None
_ = None
clear()
bpy.ops.import_scene.gltf(filepath=SRC)
_o = next(x for x in bpy.context.scene.objects
          if x.type == 'MESH' and len(x.vertex_groups) > 20)
_a = next(x for x in bpy.context.scene.objects if x.type == 'ARMATURE')
_Mh = _a.matrix_world @ _a.data.bones["DEF-hand.R"].matrix_local
_Mi = _Mh.inverted()
SRC_LOCAL = np.array([[*(_Mi @ (_o.matrix_world @ v.co))] for v in _o.data.vertices])
out = report(GAME, "DELIVERED (models/hero.glb)", SRC_LOCAL)
if out is None:
    raise SystemExit("could not label the delivered weapon")
ax, C, along, perp, idx, o, mw = out

# ---- the hand, in the delivered weapon's frame ------------------------------
print("")
print("=" * 80)
print("THE HAND in the delivered file, in the SAME axial frame (t + radius):")
print("  (t is measured from the weapon's sampled centroid; the blade spans")
print("   %.3f .. %.3f)" % (along.min(), along.max()))
vg = {g.index: g.name for g in o.vertex_groups}
W = [mw @ v.co for v in o.data.vertices]
rows = {}
for i, v in enumerate(o.data.vertices):
    if not v.groups:
        continue
    g = vg[max(v.groups, key=lambda x: x.weight).group]
    if g and (g.startswith("DEF-f_") or g.startswith("DEF-thumb") or g == "DEF-hand.R"):
        p = np.array([W[i].x, W[i].y, W[i].z])
        rows.setdefault(g, []).append((float((p - C) @ ax), float(np.linalg.norm((p - C) - ((p - C) @ ax) * ax))))
for g in sorted(rows):
    ts = [t for t, r in rows[g]]
    rs = [r for t, r in rows[g]]
    print("  %-16s n=%-3d  t %+.3f .. %+.3f   radius %.4f .. %.4f   mean t %+.3f"
          % (g, len(ts), min(ts), max(ts), min(rs), max(rs), sum(ts) / len(ts)))
print("")
print("GRIP_TABLE_DONE")
