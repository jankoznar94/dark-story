# Dark Story - GROUND TRUTH on "the sword floats outside the hand".
#
# The question "is the sword gripped?" answered from GEOMETRY, not from a render
# and not from vision (vision called the same render both "open hand" and "closed
# fist", and invented a beard and a scar on a flat face).
#
# Three traps this script is built to avoid:
#   * The fist radius must be TIGHT - 0.08 m. At 0.15 m the set swallows the
#     sword's own grip verts and its span jumps 0.10 -> 0.36 m, which is how a
#     meaningless "grip-to-fist 0.0000 m" gets printed. The set's own SPAN is
#     printed as proof: a real fist is ~0.10-0.13 m across.
#   * A minimum distance can read zero by construction (one vertex sitting on
#     the centroid). So the perpendicular distance from the fist centre to the
#     sword's LONG AXIS is measured too, plus the angle between the two axes.
#   * A render is an interpretation. An ASCII projection rasterised straight
#     from the vertex positions is not - it is the geometry itself.
#
# Run: blender.exe -b --factory-startup -P tools/blender/truth_hand_sword.py

import os

import bpy
import numpy as np
from mathutils import Vector

REPO = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg"
SRC = os.path.join(REPO, "models", "hero.glb")
OUT = r"C:\Users\Martin Fabian\AppData\Local\Temp\ds_truth"
os.makedirs(OUT, exist_ok=True)

CLIPS = [("Rig|Sword_Idle", 10), ("Rig|Sword_Attack", 12), ("Rig|Walk_Loop", 16)]

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images,
              bpy.data.cameras, bpy.data.lights):
    for item in list(block):
        try:
            block.remove(item)
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


def dom(i):
    v = mesh.data.vertices[i]
    if not v.groups:
        return None
    return gname.get(max(v.groups, key=lambda g: g.weight).group)


DIV = "=" * 78
for clip, frame in CLIPS:
    acts = [a for a in bpy.data.actions if a.name == clip]
    if not acts:
        print("MISSING CLIP", clip)
        continue
    arm.animation_data.action = acts[0]
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    me = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    MW = mesh.matrix_world
    co = [MW @ v.co for v in me.vertices]

    # ---- the fist: TIGHT radius, and print the span as proof -----------------
    hand = [i for i in range(len(co)) if dom(i) == "DEF-hand.R"]
    hc = sum((co[i] for i in hand), Vector()) / len(hand)

    print(DIV)
    print("CLIP %s   frame %d" % (clip, frame))
    print("DEF-hand.R dominant verts = %d   centroid=(%.3f, %.3f, %.3f)"
          % (len(hand), hc.x, hc.y, hc.z))

    for R in (0.06, 0.08, 0.12, 0.20):
        sel = [i for i in hand if (co[i] - hc).length <= R]
        if len(sel) < 3:
            continue
        pts = [co[i] for i in sel]
        span = max((a - b).length for a in pts for b in pts)
        print("   radius %.2f m -> %3d verts, span %.3f m %s"
              % (R, len(sel), span,
                 "<- plausible FIST" if 0.08 <= span <= 0.16 else ""))

    FIST_R = 0.08
    fist = [i for i in hand if (co[i] - hc).length <= FIST_R]
    sword = [i for i in hand if (co[i] - hc).length > FIST_R]
    fs = [co[i] for i in fist]
    ss = [co[i] for i in sword]
    fspan = max((a - b).length for a in fs for b in fs)
    sspan = max((a - b).length for a in ss for b in ss)
    fc = sum(fs, Vector()) / len(fs)
    sc = sum(ss, Vector()) / len(ss)
    print("FIST %d verts span=%.3f m | SWORD %d verts span=%.3f m" %
          (len(fist), fspan, len(sword), sspan))

    def pca(pts):
        P = np.array([[p.x, p.y, p.z] for p in pts])
        P = P - P.mean(0)
        _, s, vt = np.linalg.svd(P, full_matrices=False)
        return Vector(vt[0]), s

    saxis, ssv = pca(ss)
    fax, fsv = pca(fs)
    d = sc - fc
    perp = (d - d.dot(saxis) * saxis).length
    import math
    ang = math.degrees(math.acos(max(-1.0, min(1.0, abs(saxis.dot(fax))))))
    near = min((a - b).length for a in ss for b in fs)
    print("   min sword<->fist vertex distance : %.4f m" % near)
    print("   perp. fist centre -> sword AXIS  : %.4f m   (seated grip = a few mm)" % perp)
    print("   angle sword axis <-> fist axis   : %.1f deg  (gripped = roughly aligned)" % ang)
    print("   fist axis singular values        : %s" %
          [round(float(x), 3) for x in fsv])

    # ---- ASCII projection: geometry, not a render ----------------------------
    for label, ax_u, ax_v, ax_w in (("view along +X (from the character's right)",
                                     'y', 'z', 'x'),
                                    ("view along -Y (from the FRONT)", 'x', 'z', 'y')):
        pts = [(getattr(p, ax_u), getattr(p, ax_v), p) for p in fs + ss]
        us = [p[0] for p in pts]
        vs = [p[1] for p in pts]
        ctr = Vector((sum((p[2].x for p in pts)) / len(pts),
                      sum((p[2].y for p in pts)) / len(pts),
                      sum((p[2].z for p in pts)) / len(pts)))
        u0, u1 = min(us), max(us)
        v0, v1 = min(vs), max(vs)
        scale = max(u1 - u0, v1 - v0)
        u0 -= (scale - (u1 - u0)) / 2
        v0 -= (scale - (v1 - v0)) / 2
        GW, GH = 58, 40
        grid = [[" "] * GW for _ in range(GH)]
        nf = len(fs)
        order = [('S', p) for p in ss] + [('F', p) for p in fs]
        for tag, p in order:
            gu = int((getattr(p, ax_u) - u0) / scale * (GW - 1))
            gv = int((getattr(p, ax_v) - v0) / scale * (GH - 1))
            if 0 <= gu < GW and 0 <= gv < GH:
                cur = grid[GH - 1 - gv][gu]
                if cur == " " or cur == ".":
                    grid[GH - 1 - gv][gu] = tag
                elif cur == "F" and tag == "S":
                    grid[GH - 1 - gv][gu] = "X"   # overlap: sword INSIDE the fist
        print("   %s   [F=fist  S=sword  X=overlap]" % label)
        for row in grid:
            print("      |" + "".join(row) + "|")

    # ---- how open is the hand? ----------------------------------------------
    def cen(g):
        idx = [i for i in range(len(co)) if dom(i) == g]
        return sum((co[i] for i in idx), Vector()) / len(idx) if idx else None

    tt, mt = cen("DEF-thumb.03.R"), cen("DEF-f_middle.03.R")
    if tt and mt:
        print("   thumb tip <-> middle fingertip     : %.4f m  (0.078 open, 0.001 closed)"
              % (tt - mt).length)
