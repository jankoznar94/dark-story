# Did the finger curl actually land in the REST pose of the delivered file?
# Measures, with NO action assigned and an identity pose, the fingertip-to-palm
# distances. Curled must read ~0.03-0.09 m; the original open hand reads 0.12-0.17 m.
# Run: blender.exe -b --factory-startup -P tools/blender/probe_rest_hand.py -- <glb>

import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = argv[0] if argv else r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg\models\hero.glb"

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

# NO action, identity pose - this is the true rest state the game starts from
if arm.animation_data:
    arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.location = (0, 0, 0)
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.scale = (1, 1, 1)
bpy.context.view_layer.update()

gname = {g.index: g.name for g in mesh.vertex_groups}
DOM = [gname.get(max(v.groups, key=lambda g: g.weight).group) if v.groups else None
       for v in mesh.data.vertices]
me = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
co = [mesh.matrix_world @ v.co for v in me.vertices]


def cen(n):
    idx = [i for i in range(len(co)) if DOM[i] == n]
    return sum((co[i] for i in idx), Vector()) / len(idx) if idx else None


P = cen("DEF-hand.R")
print("FILE %s" % SRC)
print("palm (rest, no action) = (%.3f, %.3f, %.3f)" % (P.x, P.y, P.z))
tot = 0
for f in ["DEF-thumb", "DEF-f_index", "DEF-f_middle", "DEF-f_ring", "DEF-f_pinky"]:
    t = cen("%s.03.R" % f)
    d = (t - P).length
    tot += d
    print("   %-14s tip-palm %.4f m" % (f, d))
print("   SUM/5 = %.4f  -> %s" % (tot / 5, "CURLED" if tot / 5 < 0.12 else "OPEN (curl not baked)"))

# also: the armature's own rest matrix for a finger bone (does it differ from the source?)
b = arm.data.bones.get("DEF-f_middle.01.R")
print("rest bone matrix_local translation = (%.4f, %.4f, %.4f)"
      % (b.matrix_local.translation.x, b.matrix_local.translation.y, b.matrix_local.translation.z))
