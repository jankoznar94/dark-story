# Dark Story - CLOSE-UP diagnosis: is the sword in the fist, and what does the
# head read as? Two reports from Jan on the delivered hero.glb:
#   "it looks like a hood"  and  "a sword floating outside the hand".
#
# Renders close-ups (head front, head 3/4, sword hand) AND prints the numbers
# that decide the sword question. A centroid distance alone can read 0.0000 on a
# sword that is NOT held (a single vertex sitting on the centroid returns zero by
# construction), so this prints three independent things:
#   * min distance sword-vert -> hand-vert
#   * PERPENDICULAR distance from the fist centre to the sword's long axis
#   * ANGLE between the sword's principal axis and the fist's principal axis
# plus the hand-openness metric (thumb tip <-> middle fingertip).
#
# Run: blender.exe -b --factory-startup -P tools/blender/diag_hand_head.py

import math
import os

import bpy
import numpy as np
from mathutils import Vector

REPO = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg"
SRC = os.path.join(REPO, "models", "hero.glb")
CLIP = "Rig|Sword_Idle"
FRAME = 10
OUT = r"C:\Users\Martin Fabian\AppData\Local\Temp\ds_diag"
os.makedirs(OUT, exist_ok=True)

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
arm.animation_data.action = [a for a in bpy.data.actions if a.name == CLIP][0]
bpy.context.scene.frame_set(FRAME)
bpy.context.view_layer.update()

deps = bpy.context.evaluated_depsgraph_get()
me = mesh.evaluated_get(deps).to_mesh()
MW = mesh.matrix_world
co = [MW @ v.co for v in me.vertices]
gname = {g.index: g.name for g in mesh.vertex_groups}


def dom(i):
    v = mesh.data.vertices[i]
    if not v.groups:
        return None
    return gname.get(max(v.groups, key=lambda g: g.weight).group)


print("=" * 70)
print("CLIP %s  frame %d" % (CLIP, FRAME))

# ---------------------------------------------------------------- the fist ----
hr = [i for i in range(len(co)) if dom(i) == "DEF-hand.R"]
hc = sum((co[i] for i in hr), Vector()) / len(hr)
fist = [i for i in hr if (co[i] - hc).length <= 0.12]
sword = [i for i in hr if (co[i] - hc).length > 0.12]
fs = [co[i] for i in fist]
ss = [co[i] for i in sword]
fspan = max((a - b).length for a in fs for b in fs) if fs else 0
sspan = max((a - b).length for a in ss for b in ss) if ss else 0
print("hand.R-dominant=%d -> FIST %d (span %.3f m)  |  SWORD %d (span %.3f m)"
      % (len(hr), len(fist), fspan, len(sword), sspan))

fc = sum(fs, Vector()) / len(fs)
sc = sum(ss, Vector()) / len(ss)

# min distance sword -> hand
mind = min((a - b).length for a in ss for b in fs)
print("1) min sword-vert -> fist-vert distance      : %.4f m" % mind)
print("   grip(sword centroid) -> fist centroid     : %.4f m" % (sc - fc).length)


def pca(points):
    P = np.array([[p.x, p.y, p.z] for p in points])
    P = P - P.mean(0)
    u, s, vt = np.linalg.svd(P, full_matrices=False)
    return Vector(vt[0]), list(s)


saxis, ssv = pca(ss)
faxis, fsv = pca(fs)
print("2) sword principal axis %s   (singular values %s)"
      % (tuple(round(x, 3) for x in saxis), [round(x, 3) for x in ssv]))
print("   fist  principal axis %s   (singular values %s)"
      % (tuple(round(x, 3) for x in faxis), [round(x, 3) for x in fsv]))

# perpendicular distance from fist centre to the sword's long axis
d = sc - fc
perp = (d - d.dot(saxis) * saxis).length
print("3) PERPENDICULAR fist-centre -> sword axis   : %.4f m  (a seated grip is a few mm)"
      % perp)
ang = math.degrees(math.acos(max(-1.0, min(1.0, abs(saxis.dot(faxis))))))
print("4) ANGLE sword axis <-> fist axis            : %.1f deg" % ang)

# ------------------------------------------------- hand open or closed? -------
def tip(g):
    idx = [i for i in range(len(co)) if dom(i) == g]
    return sum((co[i] for i in idx), Vector()) / len(idx) if idx else None


tt = tip("DEF-thumb.03.R")
mt = tip("DEF-f_middle.03.R")
if tt and mt:
    print("5) thumb tip <-> middle fingertip            : %.4f m   (0.078 = OPEN hand, 0.001 = CLOSED)"
          % (tt - mt).length)

# --------------------------------------------------------------- rendering ----
world = bpy.data.worlds.new("W")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.30, 0.30, 0.32, 1.0)

key = bpy.data.lights.new("k", 'SUN')
key.energy = 3.0
ko = bpy.data.objects.new("k", key)
bpy.context.scene.collection.objects.link(ko)
ko.rotation_euler = (math.radians(58), 0.0, math.radians(-25))
fill = bpy.data.lights.new("f", 'SUN')
fill.energy = 1.0
fill.color = (0.78, 0.82, 1.0)
fo = bpy.data.objects.new("f", fill)
bpy.context.scene.collection.objects.link(fo)
fo.rotation_euler = (math.radians(75), 0.0, math.radians(160))

cd = bpy.data.cameras.new("c")
cd.type = 'ORTHO'
cam = bpy.data.objects.new("c", cd)
bpy.context.scene.collection.objects.link(cam)
bpy.context.scene.camera = cam

sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = 640
sc.render.resolution_y = 640
sc.view_settings.view_transform = 'Standard'
sc.render.image_settings.file_format = 'PNG'


def shoot(name, target, size, direction):
    cd.ortho_scale = size
    cam.location = target + direction.normalized() * 4.0
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("RENDER %s -> %s" % (name, sc.render.filepath))


# front is Blender +Y
head = sum((co[i] for i in range(len(co)) if dom(i) == "DEF-head"),
           Vector()) / max(1, len([1 for i in range(len(co)) if dom(i) == "DEF-head"]))
shoot("head_front", head, 0.62, Vector((0, 1, 0)))
shoot("head_34", head, 0.62, Vector((0.6, 0.8, 0.25)))
shoot("head_side", head, 0.62, Vector((1, 0, 0)))
shoot("hand_front", hc, 1.5, Vector((0.15, 1, 0.1)))
shoot("hand_34", hc, 1.5, Vector((0.8, 0.7, 0.2)))
shoot("hand_top", hc, 1.5, Vector((0.1, 0.2, 1)))
print("OUT %s" % OUT)
