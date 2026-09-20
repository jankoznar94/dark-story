# Dark Story - does the DELIVERED sword still have its handle? Compare its axial
# structure with the SOURCE rig's sword.
#
# Found by probe_hand_sword2.py: along the delivered sword's own axis the geometry
# runs blade (tip at one end, radius tapering 0.002 -> 0.037 m), then a WIDE feature
# (r_max 0.088 m, i.e. a 0.176 m cross-bar = the guard), then NOTHING for 0.13 m, then
# a small stub (r 0.028-0.036 m). The hand sits in the empty band.
#
# That is either (a) the sword never had a grip and the hand grips the guard, or
# (b) a previous fix deleted the grip. Only the SOURCE can say which, so this prints
# the same profile for the source rig's weapon, identified by material_index == 1
# (the reliable label on the pre-atlas mesh).
#
# Run: blender.exe -b --factory-startup -P tools/blender/probe_sword_source.py
import os

import bpy
import numpy as np

SRC = r"\\wsl.localhost\Ubuntu\home\martin_fabian\tools\kaykit\candidates\quat_base_character.glb"
MID = r"\\wsl.localhost\Ubuntu\home\martin_fabian\tools\kaykit\candidates\sword_base_character.glb"
CANDIDATES = [SRC, MID,
              r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg\models\hero.glb",
              r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_uv\unwrapped.glb",
              r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_uv\in.glb"]


def clear():
    for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
                  bpy.data.armatures, bpy.data.actions, bpy.data.images,
                  bpy.data.cameras, bpy.data.lights):
        for it in list(block):
            try:
                block.remove(it)
            except Exception:
                pass


for path in CANDIDATES:
    if not os.path.exists(path):
        print("MISSING %s" % path)
        continue
    clear()
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    print("=" * 78)
    print("%s" % path)
    for o in meshes:
        mats = [m.name if m else None for m in o.data.materials]
        print("  MESH %-22s verts=%-6d polys=%-6d mats=%s"
              % (o.name, len(o.data.vertices), len(o.data.polygons), mats))
    # weapon = material_index of the second slot, if there is one
    best = None
    for o in meshes:
        if len(o.data.materials) < 2:
            continue
        polys = [p for p in o.data.polygons if p.material_index == 1]
        if not polys:
            continue
        idx = sorted({v for p in polys for v in p.vertices})
        best = (o, idx)
    if best is None:
        print("  no two-material mesh with material_index==1 -> cannot label a weapon")
        continue
    o, idx = best
    mw = o.matrix_world
    S = np.array([[*(mw @ o.data.vertices[i].co)] for i in idx])
    span = float(np.linalg.norm(S.max(0) - S.min(0)))
    print("  WEAPON (material_index==1): %d verts, %d polys, span %.4f m"
          % (len(idx), sum(1 for p in o.data.polygons if p.material_index == 1), span))
    # sample the geometry along the edges so the profile is area-weighted
    ss = set(idx)
    edges = {tuple(sorted(e)) for p in o.data.polygons
             if set(p.vertices) <= ss for e in p.edge_keys}
    pts = []
    for a, b in edges:
        A = np.array([*(mw @ o.data.vertices[a].co)])
        B = np.array([*(mw @ o.data.vertices[b].co)])
        n = max(2, int(np.linalg.norm(B - A) / 0.004))
        for t in np.linspace(0, 1, n):
            pts.append(A + (B - A) * t)
    P = np.array(pts)
    C = P.mean(0)
    _, sv, vt = np.linalg.svd(P - C, full_matrices=False)
    ax = vt[0]
    along = (P - C) @ ax
    perp = np.linalg.norm((P - C) - np.outer(along, ax), axis=1)
    if perp[int(np.argmin(along))] > perp[int(np.argmax(along))]:
        ax, along = -ax, -along
    print("  edges sampled %d | axis len %.4f m | sv %s"
          % (len(pts), along.max() - along.min(), [round(float(x), 2) for x in sv]))
    print("  axial profile (0 = the sampled centroid):")
    bins = np.arange(along.min(), along.max() + 0.011, 0.01)
    for k in range(len(bins) - 1):
        sel = (along >= bins[k]) & (along < bins[k + 1])
        if sel.sum() == 0:
            continue
        r = perp[sel]
        print("   %+7.3f  n=%3d  r_med %6.4f  r_max %6.4f  |%s"
              % (bins[k], int(sel.sum()), float(np.median(r)), float(r.max()),
                 "#" * int(round(float(np.median(r)) * 150))))
    # vertices only, so thin geometry is not hidden by the edge sampling
    av = (S - C) @ ax
    print("  VERTEX axial histogram (all %d weapon verts):" % len(S))
    hist, edges2 = np.histogram(av, bins=np.arange(av.min(), av.max() + 0.011, 0.01))
    for h, e in zip(hist, edges2):
        print("   %+7.3f  %3d  %s" % (e, h, "#" * h))
