# Dark Story - HAND + SWORD CLOSE-UP, with the two objects in contrasting flat
# colours so the defect is visible rather than inferred: is the weapon inside the
# closed fingers, and is there any geometry where a grip should be.
#
# WHY workbench + emission materials: a lit render of a low-poly model is an
# interpretation; two flat colours are a diagram. The sword is red, the hand and
# fingers are blue, the forearm grey, the rest of the body a dim brown.
#
# Run: blender.exe -b --factory-startup -P tools/blender/render_grip_truth.py
import math
import os
import shutil

import bpy
from mathutils import Vector

GAME = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg\models\hero.glb"
SRC = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_uv\in.glb"
OUT = r"C:\Users\Martin Fabian\AppData\Local\Temp\ds_grip_truth"
WSL = "/tmp/grip_truth"
os.makedirs(OUT, exist_ok=True)
os.makedirs(WSL, exist_ok=True)
CLIP, FRAME = "Rig|Sword_Idle", 10

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images,
              bpy.data.cameras, bpy.data.lights):
    for it in list(block):
        try:
            block.remove(it)
        except Exception:
            pass

# ---- the weapon label from the pre-atlas source, in hand-bone local space -----
bpy.ops.import_scene.gltf(filepath=SRC)
_s = next(x for x in bpy.context.scene.objects if x.type == 'MESH' and len(x.vertex_groups) > 20)
_sa = next(x for x in bpy.context.scene.objects if x.type == 'ARMATURE')
_Mi = (_sa.matrix_world @ _sa.data.bones["DEF-hand.R"].matrix_local).inverted()
SRC_LOCAL = [(*(_Mi @ (_s.matrix_world @ v.co)),) for v in _s.data.vertices]

for it in list(bpy.data.objects):
    bpy.data.objects.remove(it, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=GAME)
body = next(x for x in bpy.context.scene.objects if x.type == 'MESH' and len(x.vertex_groups) > 20)
arm = next(x for x in bpy.context.scene.objects if x.type == 'ARMATURE')

Mh = arm.matrix_world @ arm.data.bones["DEF-hand.R"].matrix_local
Mi = Mh.inverted()
W = [body.matrix_world @ v.co for v in body.data.vertices]
L = [tuple(Mi @ w) for w in W]
import numpy as np
SL = np.array(SRC_LOCAL)
D = np.min(((np.array(L)[:, None, :] - SL[None, :, :]) ** 2).sum(2), axis=1) ** 0.5
SWORD = set(i for i in range(len(W)) if D[i] > 1e-4)
print("weapon verts %d (expect 70..95)" % len(SWORD))
assert 70 <= len(SWORD) <= 95

vg = {g.index: g.name for g in body.vertex_groups}
DOM = [vg[max(v.groups, key=lambda g: g.weight).group] if v.groups else None
       for v in body.data.vertices]


def is_hand(i):
    d = DOM[i]
    return bool(d) and (d == "DEF-hand.R" or d.startswith("DEF-f_") or d.startswith("DEF-thumb"))


def is_hand_R(i):
    """right hand only - the LEFT hand is 1.5 m away and would drag the framed centre"""
    d = DOM[i]
    return bool(d) and d.endswith(".R") and (d == "DEF-hand.R" or d.startswith("DEF-f_")
                                            or d.startswith("DEF-thumb"))


# ---- materials ---------------------------------------------------------------
def flat(name, col):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type != 'OUTPUT_MATERIAL':
            nt.nodes.remove(n)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (*col, 1.0)
    nt.links.new(em.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    return m


body.data.materials.clear()
body.data.materials.append(flat("sword", (0.85, 0.10, 0.08)))     # 0 sword
body.data.materials.append(flat("hand", (0.10, 0.35, 0.85)))      # 1 hand+fingers
body.data.materials.append(flat("arm", (0.45, 0.45, 0.48)))       # 2 forearm/upper arm
body.data.materials.append(flat("torso", (0.28, 0.24, 0.20)))     # 3 everything else
for p in body.data.polygons:
    vs = list(p.vertices)
    if set(vs) <= SWORD:
        p.material_index = 0
    elif all(is_hand(v) for v in vs):
        p.material_index = 1
    elif DOM[vs[0]] in ("DEF-forearm.R", "DEF-upper_arm.R"):
        p.material_index = 2
    else:
        p.material_index = 3

# ---- pose --------------------------------------------------------------------
arm.animation_data_create()
arm.animation_data.action = [a for a in bpy.data.actions if a.name == CLIP][0]
sc = bpy.context.scene
sc.frame_set(FRAME)
bpy.context.view_layer.update()

deps = bpy.context.evaluated_depsgraph_get()
me = body.evaluated_get(deps).to_mesh()
V = [body.matrix_world @ v.co for v in me.vertices]
sw = [i for i in SWORD]
C = sum((V[i] for i in range(len(V)) if is_hand_R(i)), Vector()) / \
    sum(1 for i in range(len(V)) if is_hand_R(i))
# the sword's own centre, so the camera frames the whole relationship
SC = sum((V[i] for i in sw), Vector()) / len(sw)
mid = (C + SC) * 0.5
print("hand centre (%.3f, %.3f, %.3f)  sword centre (%.3f, %.3f, %.3f)  gap %.3f m"
      % (C.x, C.y, C.z, SC.x, SC.y, SC.z, (C - SC).length))
print("hand-to-sword nearest vertex pair:")
d = min((V[a] - V[b]).length for a in range(len(V)) if is_hand(a) for b in sw)
print("  min %.4f m" % d)

sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'FLAT'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.background_type = 'VIEWPORT'
sc.display.shading.background_color = (0.06, 0.06, 0.07)
sc.render.resolution_x = 800
sc.render.resolution_y = 800
sc.view_settings.view_transform = 'Standard'
cd = bpy.data.cameras.new("c")
cd.type = 'ORTHO'
cam = bpy.data.objects.new("c", cd)
sc.collection.objects.link(cam)
sc.camera = cam


def shot(target, az, el, scale, name):
    rr, ee = math.radians(az), math.radians(el)
    cam.location = target + Vector((math.cos(ee) * math.sin(rr), -math.cos(ee) * math.cos(rr),
                                    math.sin(ee))) * 4.0
    dd = (target - cam.location).normalized()
    cam.rotation_mode = 'QUATERNION'
    cam.rotation_quaternion = (-dd).to_track_quat('Z', 'Y')
    cd.ortho_scale = scale
    sc.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)
    print("SHOT %s" % name)


for az in (0, 90, 45, 180, 270):
    shot(Vector((mid.x, mid.y, mid.z)), az, 8, 0.75, "hand_az%03d.png" % az)
shot(Vector((mid.x, mid.y, 1.30)), 0, 8, 2.05, "figure_front.png")
shot(Vector((mid.x, mid.y, 1.30)), 90, 8, 2.05, "figure_side.png")
for f in os.listdir(OUT):
    shutil.copy2(os.path.join(OUT, f), os.path.join(WSL, f))
print("COPIED_TO %s" % WSL)
