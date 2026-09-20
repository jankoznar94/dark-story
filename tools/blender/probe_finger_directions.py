# Dark Story - FINGER DIRECTION PROBE + colour-coded diagram.
#
# Jan's report: "the biggest problem now is the fingers - they point in random
# directions." That is a DIRECTION defect, not a distance one, and it is measurable:
# take each finger's base (the .01 vertex-group centroid), its tip (.03 centroid) and
# its mid joint (.02), and report the direction of each segment in the frame of the
# palm itself. A hand that works has all four fingers close to PARALLEL and lying in
# the palm plane, converging slightly toward the tip; the failure is large, uneven
# angles between neighbouring fingers and segment directions leaving the palm plane.
#
# It also re-measures the same fingers in the REST pose, because if the two disagree
# the clips are pinning the fingers - which is exactly why an earlier finger-curl
# pass did nothing visible in the game.
#
# Renders a diagram with EVERY FINGER IN ITS OWN COLOUR, so "which finger is which"
# and "which way is it pointing" needs no trust in a description.
#
# Run: blender.exe -b --factory-startup -P tools/blender/probe_finger_directions.py
import math
import os
import shutil

import bpy
import numpy as np
from mathutils import Vector

GAME = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg\models\hero.glb"
OUT = r"C:\Users\Martin Fabian\AppData\Local\Temp\ds_fingers"
WSL = "/tmp/fingers"
for d in (OUT, WSL):
    os.makedirs(d, exist_ok=True)
CLIP, FRAME = "Rig|Sword_Idle", 10

FINGERS = ["DEF-thumb", "DEF-f_index", "DEF-f_middle", "DEF-f_ring", "DEF-f_pinky"]
SEGS = ("01", "02", "03")
FCOL = {
    "DEF-thumb":    (0.95, 0.15, 0.12),
    "DEF-f_index":  (0.20, 0.85, 0.20),
    "DEF-f_middle": (0.15, 0.40, 0.98),
    "DEF-f_ring":   (0.95, 0.85, 0.15),
    "DEF-f_pinky":  (0.80, 0.20, 0.85),
}

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images,
              bpy.data.cameras, bpy.data.lights):
    for it in list(block):
        try:
            block.remove(it)
        except Exception:
            pass

bpy.ops.import_scene.gltf(filepath=GAME)
body = next(x for x in bpy.context.scene.objects if x.type == 'MESH' and len(x.vertex_groups) > 20)
arm = next(x for x in bpy.context.scene.objects if x.type == 'ARMATURE')

Mi = (arm.matrix_world @ arm.data.bones["DEF-hand.R"].matrix_local).inverted()
vg = {g.index: g.name for g in body.vertex_groups}
DOM = [vg[max(v.groups, key=lambda g: g.weight).group] if v.groups else None
       for v in body.data.vertices]


def verts_of(name, co):
    idx = [i for i in range(len(co)) if DOM[i] == name]
    if not idx:
        return None, 0
    return sum((co[i] for i in idx), Vector()) / len(idx), len(idx)


def measure(co, label):
    print("=" * 78)
    print(label)
    # --- the palm's own plane ------------------------------------------------
    pal = [i for i in range(len(co)) if DOM[i] == "DEF-hand.R"]
    P = np.array([[co[i].x, co[i].y, co[i].z] for i in pal])
    Pc = P.mean(0)
    _, sv, vt = np.linalg.svd(P - Pc, full_matrices=False)
    pn = vt[2]                              # palm normal = smallest spread
    print("palm: %d verts, extent %s m" % (len(pal), [round(float(x), 3) for x in (P.max(0) - P.min(0))]))
    print("palm normal (world) = (%+.3f, %+.3f, %+.3f)   sv %s"
          % (pn[0], pn[1], pn[2], [round(float(x), 3) for x in sv]))

    cen = {}
    for f in FINGERS:
        c01, n01 = verts_of("%s.01.R" % f, co)
        c02, n02 = verts_of("%s.02.R" % f, co)
        c03, n03 = verts_of("%s.03.R" % f, co)
        cen[f] = (c01, c02, c03)
        if not all(cen[f]):
            continue
        A = np.array([c01.x, c01.y, c01.z])
        B = np.array([c02.x, c02.y, c02.z])
        C = np.array([c03.x, c03.y, c03.z])
        d01 = B - A
        d12 = C - B
        d_all = C - A
        ang_seg = math.degrees(math.acos(max(-1, min(1, float(
            d01.dot(d12) / max(1e-9, np.linalg.norm(d01) * np.linalg.norm(d12)))))))
        off_plane = 90.0 - math.degrees(math.acos(max(-1, min(1, abs(float(
            d_all.dot(pn) / max(1e-9, np.linalg.norm(d_all))))))))
        print("  %-14s base->tip %6.4f m   mid-joint bend %5.1f deg   "
              "off palm plane %5.1f deg" % (f, float(np.linalg.norm(d_all)), ang_seg, off_plane))
        print("        direction (world) = (%+.3f, %+.3f, %+.3f)"
              % tuple(d_all / np.linalg.norm(d_all)))

    # --- angles between neighbouring fingers, in the palm plane ---------------
    print("  neighbour spread (angle between finger directions, deg):")
    for a, b in zip(FINGERS[1:], FINGERS[2:]):
        if not (all(cen[a]) and all(cen[b])):
            continue
        da = np.array([cen[a][2].x - cen[a][0].x, cen[a][2].y - cen[a][0].y, cen[a][2].z - cen[a][0].z])
        db = np.array([cen[b][2].x - cen[b][0].x, cen[b][2].y - cen[b][0].y, cen[b][2].z - cen[b][0].z])
        ang = math.degrees(math.acos(max(-1, min(1, float(da.dot(db) /
                                                             (np.linalg.norm(da) * np.linalg.norm(db)))))))
        print("    %-14s vs %-14s %5.1f deg" % (a.replace("DEF-", ""), b.replace("DEF-", ""), ang))
    # spread across the whole hand and convergence
    if all(cen[f] for f in FINGERS[1:]):
        bases = np.array([[cen[f][0].x, cen[f][0].y, cen[f][0].z] for f in FINGERS[1:]])
        tips = np.array([[cen[f][2].x, cen[f][2].y, cen[f][2].z] for f in FINGERS[1:]])
        bb = np.linalg.norm(bases[0] - bases[-1])
        tt = np.linalg.norm(tips[0] - tips[-1])
        print("  index-to-pinky spread: bases %.4f m -> tips %.4f m  (%s)"
              % (bb, tt, "CONVERGING" if tt < bb else "DIVERGING/FANNING"))
    return cen, pn


# ---- 1. posed -----------------------------------------------------------------
arm.animation_data_create()
arm.animation_data.action = [a for a in bpy.data.actions if a.name == CLIP][0]
sc = bpy.context.scene
sc.frame_set(FRAME)
bpy.context.view_layer.update()
me = body.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
co_posed = [body.matrix_world @ v.co for v in me.vertices]
cen_posed, _ = measure(co_posed, "POSED  %s frame %d  (what the game shows)" % (CLIP, FRAME))

# ---- 2. rest ------------------------------------------------------------------
arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.location = (0.0, 0.0, 0.0)
    pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
    pb.rotation_euler = (0.0, 0.0, 0.0)
    pb.scale = (1.0, 1.0, 1.0)
bpy.context.view_layer.update()
me2 = body.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
co_rest = [body.matrix_world @ v.co for v in me2.vertices]
measure(co_rest, "REST (the bind pose; the clips OVERRIDE this)")

print("=" * 78)
print("finger tip travel rest -> posed (a big number = the clip moves that finger)")
for f in FINGERS:
    a, _ = verts_of("%s.03.R" % f, co_rest)
    b, _ = verts_of("%s.03.R" % f, co_posed)
    if a and b:
        print("  %-14s %.4f m" % (f, (a - b).length))

# ---- 3. the colour diagram ----------------------------------------------------
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
    m.diffuse_color = (*col, 1.0)      # Workbench reads THIS, not the nodes
    return m


body.data.materials.clear()
for f in FINGERS:
    body.data.materials.append(make(f, FCOL[f]))
body.data.materials.append(make("palm", (0.55, 0.55, 0.58)))
body.data.materials.append(make("sword", (0.97, 0.97, 0.97)))
body.data.materials.append(make("other", (0.16, 0.14, 0.12)))
FIDX = {f: i for i, f in enumerate(FINGERS)}
for p in body.data.polygons:
    d = DOM[list(p.vertices)[0]]
    if d and any(d.startswith(f) for f in FINGERS):
        p.material_index = FIDX[next(f for f in FINGERS if d.startswith(f))]
    elif d == "DEF-hand.R":
        p.material_index = 5
    elif d in ("DEF-forearm.R", "DEF-upper_arm.R"):
        p.material_index = 6
    else:
        p.material_index = 6

# the weapon: label by source match (material_index==1 is gone after the atlas)
arm.animation_data.action = [a for a in bpy.data.actions if a.name == CLIP][0]
sc.frame_set(FRAME)
bpy.context.view_layer.update()

sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'FLAT'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.background_type = 'VIEWPORT'
sc.display.shading.background_color = (0.08, 0.08, 0.10)
sc.display.shading.show_object_outline = True
sc.render.resolution_x = 950
sc.render.resolution_y = 950
sc.view_settings.view_transform = 'Standard'
cd = bpy.data.cameras.new("c")
cd.type = 'ORTHO'
cam = bpy.data.objects.new("c", cd)
sc.collection.objects.link(cam)
sc.camera = cam

deps = bpy.context.evaluated_depsgraph_get()
mev = body.evaluated_get(deps).to_mesh()
V = [body.matrix_world @ v.co for v in mev.vertices]
hand_idx = [i for i in range(len(V)) if DOM[i] and DOM[i].endswith(".R")
            and (DOM[i] == "DEF-hand.R" or DOM[i].startswith("DEF-f_") or DOM[i].startswith("DEF-thumb"))]
hc = sum((V[i] for i in hand_idx), Vector()) / len(hand_idx)
print("")
print("hand centre (%.3f, %.3f, %.3f)" % (hc.x, hc.y, hc.z))


def shot(az, el, scale, name):
    rr, ee = math.radians(az), math.radians(el)
    cam.location = hc + Vector((math.cos(ee) * math.sin(rr), -math.cos(ee) * math.cos(rr),
                                math.sin(ee))) * 4.0
    dd = (hc - cam.location).normalized()
    cam.rotation_mode = 'QUATERNION'
    cam.rotation_quaternion = (-dd).to_track_quat('Z', 'Y')
    cd.ortho_scale = scale
    sc.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)
    print("SHOT %s" % name)


for az in (0, 45, 90, 135, 180, 225, 270, 315):
    shot(az, 12, 0.34, "fingers_az%03d.png" % az)
shot(0, 80, 0.34, "fingers_top.png")
for f in os.listdir(OUT):
    shutil.copy2(os.path.join(OUT, f), os.path.join(WSL, f))
print("COPIED_TO %s" % WSL)
print("FINGER_PROBE_DONE")
