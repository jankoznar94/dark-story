# Decisive: does the CLIP actually move the fingers in the delivered file?
# Prints RAW fingertip positions in three states, so a difference cannot hide
# behind a metric:
#   A) no action (rest)
#   B) action assigned, frame 1
#   C) action assigned, frame 10
# If A==B==C for every finger, the action is not being applied at all.
#
# Run: DS_HERO=<path> blender.exe -b --factory-startup -P tools/blender/probe_clip_applies.py

import os
import sys

import bpy
from mathutils import Vector

REPO = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg"
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = argv[0] if argv else os.path.join(REPO, "models", "hero.glb")

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
print("FILE %s" % SRC)
print("actions loaded: %d" % len(bpy.data.actions))
gname = {g.index: g.name for g in mesh.vertex_groups}
DOM = [gname.get(max(v.groups, key=lambda g: g.weight).group) if v.groups else None
       for v in mesh.data.vertices]


def snap(label):
    bpy.context.view_layer.update()
    me = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    co = [mesh.matrix_world @ v.co for v in me.vertices]
    out = {}
    for f in ["DEF-thumb", "DEF-f_index", "DEF-f_middle", "DEF-f_ring", "DEF-f_pinky"]:
        idx = [i for i in range(len(co)) if DOM[i] == "%s.03.R" % f]
        out[f] = sum((co[i] for i in idx), Vector()) / len(idx) if idx else None
    hand = [i for i in range(len(co)) if DOM[i] == "DEF-hand.R"]
    hp = sum((co[i] for i in hand), Vector()) / len(hand)
    print("  %-22s " % label + "  ".join(
        "%s=(%.3f,%.3f,%.3f)" % (f.replace("DEF-", ""), p.x, p.y, p.z) for f, p in out.items()))
    return out, hp


if arm.animation_data:
    arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.location = (0, 0, 0)
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.scale = (1, 1, 1)
A, hpA = snap("A) no action (rest)")

if arm.animation_data is None:
    arm.animation_data_create()
act = bpy.data.actions.get("Rig|Sword_Idle")
print("action found:", act is not None, " slots:", [(s.handle, s.name_display) for s in getattr(act, "slots", [])])
arm.animation_data.action = act
# Blender 5: an action slot may need an explicit assignment
try:
    if getattr(act, "slots", None):
        arm.animation_data.action_slot = act.slots[0]
        print("assigned action_slot ->", act.slots[0].name_display)
except Exception as e:
    print("action_slot assignment failed:", e)
bpy.context.scene.frame_set(1)
B, hpB = snap("B) action, frame 1")
bpy.context.scene.frame_set(10)
C, hpC = snap("C) action, frame 10")

print("")
print("hand centre: rest (%.3f,%.3f,%.3f)  f1 (%.3f,%.3f,%.3f)  f10 (%.3f,%.3f,%.3f)"
      % (hpA.x, hpA.y, hpA.z, hpB.x, hpB.y, hpB.z, hpC.x, hpC.y, hpC.z))
same = all((A[f] - C[f]).length < 1e-5 for f in A)
print("fingers identical between rest and frame 10: %s" % same)
print("fingers identical between frame 1 and frame 10: %s"
      % all((B[f] - C[f]).length < 1e-5 for f in B))
hpsame = (hpA - hpC).length < 1e-5
print("hand centre identical rest vs f10: %s" % hpsame)
