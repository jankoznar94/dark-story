# Dark Story - precise grip check on the delivered file.
# The earlier version reported a "handle radius" of 0.096 m because the band
# around the grip also caught the 0.17 m GUARD. The handle is a 0.038 x 0.032 m
# shaft, so its cross-section radius is ~0.02 m - measuring the guard instead
# makes every fingertip look "inside the handle".
#
# This prints, per fingertip: the perpendicular distance to the sword's long axis
# AND the axial offset (is the tip even at the handle's position along the blade?),
# plus an ASCII section of the sword perpendicular to the handle at the grip.
#
# Run: DS_HERO=<path> blender.exe -b --factory-startup -P tools/blender/verify_grip2.py

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

REPO = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg"
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = argv[0] if argv else os.path.join(REPO, "models", "hero.glb")
CLIPS = [("Rig|Sword_Idle", 10), ("Rig|Sword_Attack", 12), ("Rig|Walk_Loop", 16)]

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images):
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
if arm.animation_data is None:
    arm.animation_data_create()
gname = {g.index: g.name for g in mesh.vertex_groups}
DOM = [gname.get(max(v.groups, key=lambda g: g.weight).group) if v.groups else None
       for v in mesh.data.vertices]

FINGERS = ["DEF-thumb", "DEF-f_index", "DEF-f_middle", "DEF-f_ring", "DEF-f_pinky"]


def cen(name, co):
    idx = [i for i in range(len(co)) if DOM[i] == name]
    return sum((co[i] for i in idx), Vector()) / len(idx) if idx else None


for clip, frame in CLIPS:
    acts = [a for a in bpy.data.actions if a.name == clip]
    if not acts:
        continue
    arm.animation_data.action = acts[0]
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    me = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    co = [mesh.matrix_world @ v.co for v in me.vertices]

    hand = [i for i in range(len(co)) if DOM[i] == "DEF-hand.R"]
    hc = sum((co[i] for i in hand), Vector()) / len(hand)
    sword = np.array([[co[i].x, co[i].y, co[i].z] for i in hand
                      if (co[i] - hc).length > 0.08])
    Sc = sword.mean(0)
    _, sv, vt = np.linalg.svd(sword - Sc, full_matrices=False)
    ax = vt[0]
    palm = np.array([hc.x, hc.y, hc.z])
    along = (sword - Sc) @ ax
    perp_all = np.linalg.norm((sword - Sc) - np.outer(along, ax), axis=1)

    # the HANDLE = the shaft of small cross-section. Find the axial band where the
    # perpendicular spread is smallest and narrow (the guard is a wide spike).
    a_palm = float((palm - Sc) @ ax)
    band = np.abs(along - a_palm) < 0.05
    # within the band, the handle is the tight cluster at small radius
    tight = band & (perp_all < np.percentile(perp_all[band], 45))
    HR = float(np.percentile(perp_all[tight], 85))
    h_lo, h_hi = float(along[tight].min()), float(along[tight].max())

    print("=" * 74)
    print("%s f%d   handle cross-section r=%.4f m   axial extent %.4f .. %.4f (palm at %.4f)"
          % (clip, frame, HR, h_lo, h_hi, a_palm))

    tips = {}
    for f in FINGERS:
        t = cen("%s.03.R" % f, co)
        tn = np.array([t.x, t.y, t.z])
        a = float((tn - Sc) @ ax)
        radial = (tn - Sc) - a * ax
        perp = float(np.linalg.norm(radial))
        tips[f] = (tn, radial, perp, a)
        print("   %-14s perp %.4f m (handle r %.4f)  axial %.4f  %s"
              % (f, perp, HR, a,
                 "AT the handle" if h_lo - 0.04 <= a <= h_hi + 0.04 else "off the handle's length"))
    print("   tip vs grip surface: %s"
          % ", ".join("%s %+.3f m" % (f.replace("DEF-", ""), tips[f][2] - HR) for f in FINGERS))

    # opposition: the angle between the thumb's radial direction and the fingers'
    tdir = tips["DEF-thumb"][1] / max(1e-9, np.linalg.norm(tips["DEF-thumb"][1]))
    for f in FINGERS[1:]:
        fd = tips[f][1] / max(1e-9, np.linalg.norm(tips[f][1]))
        ang = math.degrees(math.acos(max(-1.0, min(1.0, float(tdir @ fd)))))
        print("   thumb vs %-14s radial angle %.0f deg  (%s)"
              % (f.replace("DEF-", ""), ang, "OPPOSED" if ang > 110 else "same side"))

    # ASCII section perpendicular to the handle, at the grip
    W, H = 54, 22
    sel = np.abs(along - a_palm) < 0.035
    sub = sword[sel] - Sc - np.outer(along[sel], ax)   # radial coords
    sub = sub - np.outer((sub @ ax), ax)
    # basis in the plane
    u = np.array([1.0, 0, 0]) - ax * ax[0]
    u /= np.linalg.norm(u)
    v = np.cross(ax, u)
    pts = []
    for p in sub:
        pts.append((float(p @ u), float(p @ v), "S"))
    for f in FINGERS:
        tn, radial, perp, a = tips[f]
        if abs(a - a_palm) < 0.12:
            pts.append((float(radial @ u), float(radial @ v), "F"))
    cu = sum(p[0] for p in pts) / len(pts)
    cv = sum(p[1] for p in pts) / len(pts)
    span = max(max(abs(p[0] - cu), abs(p[1] - cv)) for p in pts) * 1.15 or 0.05
    grid = [[" "] * W for _ in range(H)]
    for x, y, tag in pts:
        gx = int((x - cu) / span * (W / 2 - 1) + W / 2)
        gy = int((y - cv) / span * (H / 2 - 1) + H / 2)
        if 0 <= gx < W and 0 <= gy < H:
            cur = grid[H - 1 - gy][gx]
            grid[H - 1 - gy][gx] = "X" if cur != " " and cur != tag else tag
    print("   section at the grip  [S=sword  F=fingertip  X=both]")
    for row in grid:
        print("      |" + "".join(row) + "|")
