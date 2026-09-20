# Dark Story - render the DELIVERED hero (models/hero.glb) in three orthographic
# views, POSED in a real clip, for side-by-side comparison with reference art.
#
# WHY posed: this rig's REST pose has the arms HORIZONTAL (measured: upper_arm.L
# x -0.470..-0.113, z 1.359..1.507 -> T-pose), so a rest-pose render is useless for
# comparing silhouette against a reference that stands with arms down.
# WHY Blender: --headless Godot cannot apply an animation; pose-dependent checks
# must run here with an action assigned and frame_set().
#
# Run: blender.exe -b --factory-startup -P tools/blender/render_hero_posed_views.py

import math
import os
import sys

import bpy
from mathutils import Vector

REPO = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg"
SRC = os.path.join(REPO, "models", "hero.glb")
OUT = r"C:\Users\Martin Fabian\AppData\Local\Temp\ds_hero_poses"
os.makedirs(OUT, exist_ok=True)

CLIP = "Rig|Sword_Idle"
FRAME = 10
RES = 720

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images,
              bpy.data.cameras, bpy.data.lights):
    for item in list(block):
        try:
            block.remove(item)
        except Exception:
            pass

bpy.ops.import_scene.gltf(filepath=SRC)

# ---- find the armature + its skinned mesh ------------------------------------
arm = None
mesh = None
for o in bpy.context.scene.objects:
    if o.type == 'ARMATURE':
        arm = o
    if o.type == 'MESH' and o.parent is arm:
        mesh = o
print("ARMATURE %s bones=%d   MESH %s verts=%d" %
      (arm.name, len(arm.data.bones), mesh.name, len(mesh.data.vertices)))

# ---- pose it -----------------------------------------------------------------
acts = [a for a in bpy.data.actions if CLIP in a.name or a.name == CLIP]
print("ACTIONS matching %r: %s" % (CLIP, [a.name for a in acts]))
if acts and arm.animation_data is None:
    arm.animation_data_create()
if acts:
    arm.animation_data.action = acts[0]
bpy.context.scene.frame_set(FRAME)
bpy.context.view_layer.update()

deps = bpy.context.evaluated_depsgraph_get()
me = mesh.evaluated_get(deps).to_mesh()
zs = [(mesh.matrix_world @ v.co).z for v in me.vertices]
GROUND, TOP = min(zs), max(zs)
HEIGHT = TOP - GROUND
print("POSED BOUNDS  ground=%.4f  top=%.4f  height=%.4f m" % (GROUND, TOP, HEIGHT))

# ---- grey studio background, matching the reference art ----------------------
world = bpy.data.worlds.new("W")
bpy.context.scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.30, 0.30, 0.32, 1.0)
bg.inputs[1].default_value = 1.0

key = bpy.data.lights.new("key", 'SUN')
key.energy = 3.0
key.color = (1.0, 0.95, 0.90)
ko = bpy.data.objects.new("key", key)
bpy.context.scene.collection.objects.link(ko)
ko.rotation_euler = (math.radians(58), 0.0, math.radians(-25))

fill = bpy.data.lights.new("fill", 'SUN')
fill.energy = 1.0
fill.color = (0.78, 0.82, 1.0)
fo = bpy.data.objects.new("fill", fill)
bpy.context.scene.collection.objects.link(fo)
fo.rotation_euler = (math.radians(75), 0.0, math.radians(160))

cam_data = bpy.data.cameras.new("cam")
cam_data.type = 'ORTHO'
cam_data.ortho_scale = HEIGHT * 1.14
cam = bpy.data.objects.new("cam", cam_data)
bpy.context.scene.collection.objects.link(cam)
bpy.context.scene.camera = cam

sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = RES
sc.render.resolution_y = RES
sc.render.film_transparent = False
sc.view_settings.view_transform = 'Standard'
sc.view_settings.look = 'None'
sc.render.image_settings.file_format = 'PNG'

MID = (GROUND + TOP) / 2.0
D = 6.0
# front is Blender +Y (toes span y +0.116..+0.206)
VIEWS = {
    "front": (Vector((0.0, D, MID)), Vector((0.0, 0.0, MID))),
    "back":  (Vector((0.0, -D, MID)), Vector((0.0, 0.0, MID))),
    "side":  (Vector((D, 0.0, MID)), Vector((0.0, 0.0, MID))),
}

for name, (loc, tgt) in VIEWS.items():
    cam.location = loc
    direction = (tgt - loc)
    cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = os.path.join(OUT, "hero_%s.png" % name)
    bpy.ops.render.render(write_still=True)
    print("RENDERED %s -> %s" % (name, sc.render.filepath))

print("OUT_DIR %s" % OUT)
