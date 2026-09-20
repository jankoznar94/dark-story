# Dark Story - verify the grip on the DELIVERED file: is each fingertip ON the
# handle? The decisive number is the PERPENDICULAR distance from the fingertip to
# the sword's long axis, compared against the handle's own radius - a tip-to-tip
# metric is misleading, because a correct opposed grip puts the thumb and the
# fingers on OPPOSITE sides of the handle (tip-to-tip then goes UP).
#
# Run: blender.exe -b --factory-startup -P tools/blender/verify_grip.py

import math
import os

import bpy
import numpy as np
from mathutils import Vector

REPO = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg"
SRC = os.environ.get("DS_HERO", os.path.join(REPO, "models", "hero.glb"))
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
N = len(mesh.data.vertices)


def dom_grp(i):
    v = mesh.data.vertices[i]
    if not v.groups:
        return None
    return gname.get(max(v.groups, key=lambda g: g.weight).group)


DOM = [dom_grp(i) for i in range(N)]


def cen(name, co):
    idx = [i for i in range(len(co)) if DOM[i] == name]
    return sum((co[i] for i in idx), Vector()) / len(idx) if idx else None


FINGERS = ["DEF-thumb", "DEF-f_index", "DEF-f_middle", "DEF-f_ring", "DEF-f_pinky"]

for clip, frame in CLIPS:
    acts = [a for a in bpy.data.actions if a.name == clip]
    if not acts:
        print("MISSING", clip)
        continue
    arm.animation_data.action = acts[0]
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    me = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    co = [mesh.matrix_world @ v.co for v in me.vertices]

    # the sword, from the hand group; the handle = the part nearest the palm
    hand = [i for i in range(len(co)) if DOM[i] == "DEF-hand.R"]
    hc = sum((co[i] for i in hand), Vector()) / len(hand)
    sword = [co[i] for i in hand if (co[i] - hc).length > 0.08]
    S = np.array([[p.x, p.y, p.z] for p in sword])
    Sc = S.mean(0)
    _, sv, vt = np.linalg.svd(S - Sc, full_matrices=False)
    ax = vt[0]
    palm_np = np.array([hc.x, hc.y, hc.z])
    along_all = (S - Sc) @ ax
    # the handle is the 12 cm of the sword nearest the palm (the grip region)
    grip_sel = np.abs(along_all - ((palm_np - Sc) @ ax)) < 0.06
    off = (S[grip_sel] - Sc) - np.outer(along_all[grip_sel], ax)
    HANDLE_R = float(np.percentile(np.linalg.norm(off, axis=1), 90))

    print("=" * 72)
    print("%s frame %d   sword span %.3f m   handle radius %.4f m"
          % (clip, frame, float(np.linalg.norm(S.max(0) - S.min(0))), HANDLE_R))

    for f in FINGERS:
        t = cen("%s.03.R" % f, co)
        tn = np.array([t.x, t.y, t.z])
        a = (tn - Sc) @ ax
        perp = float(np.linalg.norm((tn - Sc) - a * ax))
        print("   %-14s perpendicular to sword axis %.4f m   -> %s (handle r %.3f)"
              % (f, perp, "ON the handle" if abs(perp - HANDLE_R) < 0.035 else
                 ("too far off by %.3f m" % (perp - HANDLE_R)), HANDLE_R))

    tt = cen("DEF-thumb.03.R", co)
    # thumb side vs middle-finger side of the axis: a real grip opposes them
    m_t = cen("DEF-f_middle.03.R", co)
    sm = math.copysign(1.0, float((np.array([m_t.x, m_t.y, m_t.z]) - Sc) @ ax))
    sides = []
    for f in FINGERS:
        t = cen("%s.03.R" % f, co)
        tn = np.array([t.x, t.y, t.z])
        a = (tn - Sc) @ ax
        radial = (tn - Sc) - a * ax
        sides.append((f, float(np.linalg.norm(radial)),
                      float(np.dot(radial, (np.array([tt.x, tt.y, tt.z]) - Sc) -
                                   ((np.array([tt.x, tt.y, tt.z]) - Sc) @ ax) * ax))))
    print("   thumb vs fingers on the handle: %s"
          % ", ".join("%s %s" % (f.replace("DEF-", ""), "same side" if v > 0 else "OPPOSITE")
                      for f, _, v in sides))
