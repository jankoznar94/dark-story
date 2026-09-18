# DECISIVE check of the delivered hero.glb.
#
# The sword's 80 vertices are known exactly in the pre-atlas file (material_index
# == 1). Because the sword is rigidly bound to DEF-hand.R, the exporter preserves
# their BONE-LOCAL coordinates. So:
#   1. in in.glb, compute the 80 weapon verts in bone-local space
#   2. apply the same transform the build applies -> expected post-fix bone-local
#   3. in fixed/hero.glb, find verts whose bone-local coords equal those, one to one
#   4. report their WORLD positions relative to the fist
# Step 3 is what makes this independent: it does not trust the build's own maths,
# it re-derives the expectation from the source and locates the verts in the
# delivered file by coordinate identity.
import math

import bpy
import numpy as np
from mathutils import Matrix, Vector

TMP = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_uv"
BLADE_WORLD_IDLE = Vector((0.0, 0.65, 0.76)).normalized()
FIST_RADIUS_M = 0.15


def clear():
    for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
                  bpy.data.armatures, bpy.data.actions, bpy.data.images):
        for it in list(block):
            try:
                block.remove(it)
            except Exception:
                pass


def load(path):
    clear()
    bpy.ops.import_scene.gltf(filepath=path)
    body = [o for o in bpy.context.scene.objects
            if o.type == 'MESH' and o.name.lower().startswith("mannequin")][0]
    arm = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE'][0]
    return body, arm


# ---------------- 1. source ---------------------------------------------------
body, arm = load(TMP + r"\in.glb")
me = body.data
M = body.matrix_world
vg = {g.index: g.name for g in body.vertex_groups}
weapon_ids = sorted({v for p in me.polygons if p.material_index == 1 for v in p.vertices})
wset = set(weapon_ids)
hb = arm.data.bones["DEF-hand.R"]
Mhand = arm.matrix_world @ hb.matrix_local
Mi = Mhand.inverted()
hand_o = Mhand.translation
print("source: weapon verts %d, body scale %s" % (len(weapon_ids), str(M.to_scale())))

fist_ids = []
for vi in range(len(me.vertices)):
    if vi in wset:
        continue
    best, bw = None, 0.0
    for ge in me.vertices[vi].groups:
        if ge.weight > bw:
            bw, best = ge.weight, vg[ge.group]
    if best and best.startswith("DEF-hand") and best.endswith(".R"):
        if ((M @ me.vertices[vi].co) - hand_o).length <= FIST_RADIUS_M:
            fist_ids.append(vi)
f_world = [M @ me.vertices[i].co for i in fist_ids]
fist_c_world = Vector((sum(p.x for p in f_world) / len(f_world),
                       sum(p.y for p in f_world) / len(f_world),
                       sum(p.z for p in f_world) / len(f_world)))
fist_centre = Mi @ fist_c_world
print("source: fist %d verts, world centre %s, %.4f m from bone"
      % (len(fist_ids), [round(c, 3) for c in fist_c_world], (fist_c_world - hand_o).length))

w_local = [Mi @ (M @ me.vertices[i].co) for i in weapon_ids]
wi = min(range(len(w_local)), key=lambda i: (w_local[i] - fist_centre).length)
grip = w_local[wi]
tip = max(w_local, key=lambda p: (p - grip).length)
d_now = (tip - grip).normalized()
print("source PRE : grip-to-fist-centre %.4f bone-local | (x100 = %.3f m)"
      % ((grip - fist_centre).length, (grip - fist_centre).length * 100.0))

if arm.animation_data is None:
    arm.animation_data_create()
arm.animation_data.action = bpy.data.actions.get("Rig|Sword_Idle")
bpy.context.scene.frame_set(10)
bpy.context.view_layer.update()
mid = (arm.matrix_world @ arm.pose.bones["DEF-hand.R"].matrix).to_3x3()
arm.animation_data.action = None
D_local = (mid.inverted() @ BLADE_WORLD_IDLE).normalized()
R = d_now.rotation_difference(D_local).to_matrix().to_4x4()
expected = [fist_centre + (R @ (p - grip)) for p in w_local]
print("source POST: transform %.1f deg, expected grip at the fist centre"
      % math.degrees(d_now.angle(D_local)))
# how many of the 80 expected positions are distinct?
uniqpos = len({(round(p.x, 5), round(p.y, 5), round(p.z, 5)) for p in expected})
print("source POST: %d expected positions, %d distinct" % (len(expected), uniqpos))

# ---------------- 2. delivered ------------------------------------------------
body2, arm2 = load(TMP + r"\fixed\hero.glb")
me2 = body2.data
M2 = body2.matrix_world
vg2 = {g.index: g.name for g in body2.vertex_groups}
hb2 = arm2.data.bones["DEF-hand.R"]
Mhand2 = arm2.matrix_world @ hb2.matrix_local
Mi2 = Mhand2.inverted()
hand_o2 = Mhand2.translation
print("")
print("delivered: %d verts, materials %d, animations %d"
      % (len(me2.vertices), len(me2.materials), len(bpy.data.actions)))
print("delivered: bone matrix equals source: %s"
      % str(all(abs(Mhand[i][j] - Mhand2[i][j]) < 1e-4 for i in range(4) for j in range(4))))
print("delivered: body matrix equals source: %s"
      % str(all(abs(M[i][j] - M2[i][j]) < 1e-4 for i in range(4) for j in range(4))))

d_local_all = [Mi2 @ (M2 @ v.co) for v in me2.vertices]
hits = []
worst = 0.0
for exp in expected:
    j = min(range(len(d_local_all)), key=lambda k: (d_local_all[k] - exp).length)
    worst = max(worst, (d_local_all[j] - exp).length)
    hits.append(j)
uniq = sorted(set(hits))
print("delivered: matched %d refs -> %d distinct verts, worst residual %.7f (bone-local)"
      % (len(hits), len(uniq), worst))

if worst < 1e-5:
    wpos = [M2 @ me2.vertices[j].co for j in uniq]
    # the delivered fist, from the same rule
    fist2 = []
    for vi in range(len(me2.vertices)):
        if vi in set(uniq):
            continue
        best, bw = None, 0.0
        for ge in me2.vertices[vi].groups:
            if ge.weight > bw:
                bw, best = ge.weight, vg2[ge.group]
        if best and best.startswith("DEF-hand") and best.endswith(".R"):
            if ((M2 @ me2.vertices[vi].co) - hand_o2).length <= FIST_RADIUS_M:
                fist2.append(vi)
    f2p = [M2 @ me2.vertices[i].co for i in fist2]
    fc2 = Vector((sum(p.x for p in f2p) / len(f2p), sum(p.y for p in f2p) / len(f2p),
                  sum(p.z for p in f2p) / len(f2p)))
    print("delivered: fist %d verts, centre %s" % (len(fist2),
                                                   [round(c, 3) for c in fc2]))
    dmin = min((p - q).length for p in wpos for q in f2p)
    g2 = min(wpos, key=lambda p: (p - fc2).length)
    t2 = max(wpos, key=lambda p: (p - g2).length)
    b2 = (t2 - g2).normalized()
    print("")
    print("DELIVERED (world metres): nearest sword-vert to fist %.4f m" % dmin)
    print("DELIVERED: grip-to-fist-centre %.4f m (bone-local x100)" % ((g2 - fc2).length))
    print("DELIVERED: blade length %.4f m" % (t2 - g2).length)
    print("DELIVERED: rest blade dir (%.3f, %.3f, %.3f)" % (b2.x, b2.y, b2.z))
    # what that direction becomes in the idle pose
    widle = (mid @ D_local).normalized()
    print("DELIVERED: blade in the IDLE pose points (%.3f, %.3f, %.3f) = %+.1f deg above "
          "horizontal" % (widle.x, widle.y, widle.z,
                          math.degrees(math.asin(max(-1.0, min(1.0, widle.z))))))
    print("DELIVERED: sword is IN the fist: %s" % str(dmin < 0.06))
    print("DELIVERED: blade no longer at the ground: %s" % str(widle.z > 0.3))
print("DECISIVE_DONE")
