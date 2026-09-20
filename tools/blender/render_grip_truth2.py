# Dark Story - TRUTH RENDER of the hand and the sword, in contrasting flat colours.
#
# WHY THIS SCRIPT EXISTS: the first version assigned colours through emission NODES,
# and Blender's WORKBENCH engine in MATERIAL shading mode reads
# `material.diffuse_color` (the viewport display colour), NOT the node tree. Every
# surface therefore rendered as the default grey and the "diagram" was a single grey
# blob - the render was useless and the defect invisible. Set BOTH: diffuse_color for
# Workbench, and the node tree for anything else. The script now also ASSERTS that
# each colour is actually present in the output, so a monochrome result fails loudly
# instead of being shipped as evidence.
#
# Run: blender.exe -b --factory-startup -P tools/blender/render_grip_truth2.py
import math
import os
import shutil

import bpy
import numpy as np
from mathutils import Vector

GAME = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg\models\hero.glb"
SRC = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_uv\in.glb"
OUT = r"C:\Users\Martin Fabian\AppData\Local\Temp\ds_grip2"
WSL = "/tmp/grip2"
for d in (OUT, WSL):
    os.makedirs(d, exist_ok=True)
CLIP, FRAME = "Rig|Sword_Idle", 10

COLS = {
    "sword":  (0.95, 0.22, 0.12),
    "hand":   (0.15, 0.50, 0.98),
    "arm":    (0.62, 0.62, 0.66),
    "body":   (0.20, 0.17, 0.14),
}


def clear():
    for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
                  bpy.data.armatures, bpy.data.actions, bpy.data.images,
                  bpy.data.cameras, bpy.data.lights):
        for it in list(block):
            try:
                block.remove(it)
            except Exception:
                pass


# ---- the weapon label from the pre-atlas source, in hand-bone local space -----
clear()
bpy.ops.import_scene.gltf(filepath=SRC)
_s = next(x for x in bpy.context.scene.objects if x.type == 'MESH' and len(x.vertex_groups) > 20)
_sa = next(x for x in bpy.context.scene.objects if x.type == 'ARMATURE')
_Mi = (_sa.matrix_world @ _sa.data.bones["DEF-hand.R"].matrix_local).inverted()
SRC_LOCAL = np.array([[*(_Mi @ (_s.matrix_world @ v.co))] for v in _s.data.vertices])

clear()
bpy.ops.import_scene.gltf(filepath=GAME)
body = next(x for x in bpy.context.scene.objects if x.type == 'MESH' and len(x.vertex_groups) > 20)
arm = next(x for x in bpy.context.scene.objects if x.type == 'ARMATURE')

Mi = (arm.matrix_world @ arm.data.bones["DEF-hand.R"].matrix_local).inverted()
W = [body.matrix_world @ v.co for v in body.data.vertices]
L = np.array([[*(Mi @ w)] for w in W])
D = np.min(((L[:, None, :] - SRC_LOCAL[None, :, :]) ** 2).sum(2), axis=1) ** 0.5
SWORD = set(i for i in range(len(W)) if D[i] > 1e-4)
print("weapon verts %d (expect 70..95)" % len(SWORD))
assert 70 <= len(SWORD) <= 95

vg = {g.index: g.name for g in body.vertex_groups}
DOM = [vg[max(v.groups, key=lambda g: g.weight).group] if v.groups else None
       for v in body.data.vertices]


def is_hand_R(i):
    d = DOM[i]
    return bool(d) and d.endswith(".R") and (d == "DEF-hand.R" or d.startswith("DEF-f_")
                                             or d.startswith("DEF-thumb"))


def make(name, col):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type != 'OUTPUT_MATERIAL':
            nt.nodes.remove(n)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (*col, 1.0)
    nt.links.new(em.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    m.diffuse_color = (*col, 1.0)          # <- THIS is what Workbench/MATERIAL reads
    return m


body.data.materials.clear()
body.data.materials.append(make("sword", COLS["sword"]))
body.data.materials.append(make("hand", COLS["hand"]))
body.data.materials.append(make("arm", COLS["arm"]))
body.data.materials.append(make("body", COLS["body"]))
for p in body.data.polygons:
    vs = list(p.vertices)
    if set(vs) <= SWORD:
        p.material_index = 0
    elif all(is_hand_R(v) for v in vs):
        p.material_index = 1
    elif DOM[vs[0]] in ("DEF-forearm.R", "DEF-upper_arm.R"):
        p.material_index = 2
    else:
        p.material_index = 3
print("polygon material counts: %s"
      % {k: sum(1 for p in body.data.polygons if p.material_index == k)
         for k in range(4)})

# ---- pose --------------------------------------------------------------------
arm.animation_data_create()
arm.animation_data.action = [a for a in bpy.data.actions if a.name == CLIP][0]
sc = bpy.context.scene
sc.frame_set(FRAME)
bpy.context.view_layer.update()

deps = bpy.context.evaluated_depsgraph_get()
me = body.evaluated_get(deps).to_mesh()
V = [body.matrix_world @ v.co for v in me.vertices]
hr = [i for i in range(len(V)) if is_hand_R(i)]
sw = [i for i in SWORD]
hcen = sum((V[i] for i in hr), Vector()) / len(hr)
scen = sum((V[i] for i in sw), Vector()) / len(sw)
mid = (hcen + scen) * 0.5
print("hand centre (%.3f, %.3f, %.3f) | sword centre (%.3f, %.3f, %.3f) | gap %.3f m"
      % (hcen.x, hcen.y, hcen.z, scen.x, scen.y, scen.z, (hcen - scen).length))

sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'FLAT'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.background_type = 'VIEWPORT'
sc.display.shading.background_color = (0.10, 0.10, 0.12)
sc.display.shading.show_object_outline = True
sc.render.resolution_x = 900
sc.render.resolution_y = 900
sc.render.film_transparent = False
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
    return os.path.join(OUT, name)


shots = []
for az in (0, 45, 90, 135, 180, 225, 270, 315):
    shots.append((shot(Vector((mid.x, mid.y, mid.z)), az, 15, 0.62, "h%03d.png" % az), az))
shots.append((shot(Vector((mid.x, mid.y, mid.z)), 0, 80, 0.62, "h_top.png"), 999))
shots.append((shot(Vector((scen.x, scen.y, 1.30)), 0, 8, 2.10, "body_front.png"), 998))
shots.append((shot(Vector((scen.x, scen.y, 1.30)), 90, 8, 2.10, "body_side.png"), 997))

# ---- ASSERT the colours are really in the output -----------------------------
print("")
print("COLOUR CHECK per frame (share of foreground pixels within 0.18 of each colour):")
ok = True
for path, az in shots:
    p = path.replace("\\", "/").replace("C:", "/mnt/c")
    from PIL import Image
    a = np.array(Image.open(p).convert("RGB")).astype(float) / 255.0
    bgc = np.array(sc.display.shading.background_color)
    fg = np.abs(a - bgc).sum(2) > 0.10
    tot = int(fg.sum())
    parts = []
    for k, c in COLS.items():
        share = float((np.abs(a - np.array(c)).sum(2) < 0.35)[fg].mean()) if tot else 0.0
        parts.append("%s %.3f" % (k, share))
    print("  %-16s fg %6d  %s" % (path.split("\\")[-1], tot, "  ".join(parts)))
    if tot < 3000:
        ok = False
if not ok:
    raise SystemExit("ASSERT FAILED: a frame is nearly empty or monochrome")

for f in os.listdir(OUT):
    shutil.copy2(os.path.join(OUT, f), os.path.join(WSL, f))
print("COPIED_TO %s" % WSL)
