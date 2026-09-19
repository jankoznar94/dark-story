# Dark Story - build the test enemy model: models/enemy.glb
#
# Same rigged base character as the hero (CC0, Quaternius "Animated Base
# Character"), minus the welded sword. WHY the same source: the hero's sword is
# welded into the fist in models/hero.glb, so an enemy built from THAT file would
# carry a sword while the punch clips play. The source GLB is the clean copy.
#
# Two edits only, both deliberate:
#   1. delete the stray 2 m Icosphere (see docs/hero-model.md - it is not part of
#      the character and it inflates every bounds reading)
#   2. replace the saturated source materials (M_Main orange, M_Joints purple)
#      with one flat desaturated material, matching the project's palette rule
#      (dark, warm, no glow)
#
# No UV work, no atlas, no welding. The runtime tints it further per monster type
# via material_override, so this file stays a plain neutral body.
#
# Run: blender.exe -b --factory-startup -P tools/blender/build_enemy.py

import os
import shutil

import bpy

SRC = r"\\wsl.localhost\Ubuntu\home\martin_fabian\tools\kaykit\candidates\quat_base_character.glb"
GAME = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg\models"
OUT = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_enemy"

os.makedirs(OUT, exist_ok=True)

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images):
    for item in list(block):
        try:
            block.remove(item)
        except Exception:
            pass

bpy.ops.import_scene.gltf(filepath=SRC)

# ---- 1. stray helper geometry -------------------------------------------------
for o in list(bpy.context.scene.objects):
    if o.type == 'MESH' and o.name.lower().startswith(("icosphere", "sphere")):
        print("REMOVED_STRAY %s (%d verts)" % (o.name, len(o.data.vertices)))
        bpy.data.objects.remove(o, do_unlink=True)

body = [o for o in bpy.context.scene.objects
        if o.type == 'MESH' and o.name.lower().startswith("mannequin")][0]
arm = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE'][0]
me = body.data
print("MESH %s verts=%d materials=%s" % (body.name, len(me.vertices),
                                         [m.name for m in me.materials]))
print("RIG %s bones=%d" % (arm.name, len(arm.data.bones)))

# ---- 2. one flat desaturated material ----------------------------------------
# Measured palette intent: the hero's atlas averages skin 74 / leather 46 / steel
# 61 luminance. The enemy sits slightly warmer and darker than the hero so the two
# read apart at a glance in an isometric camera without any glow.
mat = bpy.data.materials.new("ds_enemy_hide")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.30, 0.18, 0.14, 1.0)
for k in ("Roughness", "Metallic"):
    if k in bsdf.inputs:
        bsdf.inputs[k].default_value = 0.9 if k == "Roughness" else 0.0
me.materials.clear()
me.materials.append(mat)
for p in me.polygons:
    p.material_index = 0
print("MATERIAL %s applied to every polygon" % mat.name)

# ---- 3. export ---------------------------------------------------------------
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.context.scene.objects:
    if o.type in ('MESH', 'ARMATURE'):
        o.select_set(True)
bpy.context.view_layer.objects.active = body
glb = os.path.join(OUT, "enemy.glb")
bpy.ops.export_scene.gltf(
    filepath=glb, export_format='GLB', use_selection=True,
    export_animations=True, export_animation_mode='ACTIONS',
    export_apply=False, export_yup=True,
)
print("EXPORTED %s (%.1f KB)" % (glb, os.path.getsize(glb) / 1024.0))

n_anim = 0
try:
    n_anim = len(bpy.data.actions)
except Exception:
    pass
print("ACTIONS_EXPORTED %d" % n_anim)

os.makedirs(GAME, exist_ok=True)
dest = os.path.join(GAME, "enemy.glb")
shutil.copy2(glb, dest)
print("COPIED_TO_GAME %s (%.1f KB)" % (dest, os.path.getsize(dest) / 1024.0))
print("BUILD_ENEMY_DONE")
