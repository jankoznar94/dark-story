# Dark Story - prepare the rigged hero for the game. ONE clean pass.
# Run: blender.exe -b --factory-startup -P this.py
#
# Facts established by tools/blender probes (do not re-derive):
#   * the source GLB contains a stray 2 m Icosphere, unparented, no modifiers.
#     It is white, centred on the origin and encloses the lower body - it was
#     polluting every render and every bounds measurement. Delete it first.
#   * the real character (Mannequin) is ~1.62 m tall, 0.83 m wide,
#     8.5k verts, skinned to a 53-bone rig, with 45 animations.
#   * source materials are saturated (M_Main orange, M_Joints purple) and have
#     UVs but no textures - safe to replace wholesale with the project palette.
#
# ORDER MATTERS: delete stray -> palette -> assign action -> update depsgraph ->
# measure -> render. Measuring before the depsgraph update gave nonsense before.

import math
import os
import shutil

import bpy
from mathutils import Vector

SRC = r"C:\Users\Martin Fabian\AppData\Local\Temp\kaykit\Base.glb"
OUT = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_model"
GAME = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg\models"
os.makedirs(OUT, exist_ok=True)

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images):
    for item in list(block):
        try:
            block.remove(item)
        except Exception:
            pass

bpy.ops.import_scene.gltf(filepath=SRC)

# ---- 1. remove stray helper geometry ------------------------------------------
removed = []
for o in list(bpy.context.scene.objects):
    if o.type != 'MESH':
        continue
    if o.name.lower().startswith(("icosphere", "sphere", "cube", "helper")):
        removed.append("%s (%d verts, %s)"
                       % (o.name, len(o.data.vertices), "parented" if o.parent else "UNPARENTED"))
        bpy.data.objects.remove(o, do_unlink=True)
print("REMOVED_STRAY %s" % removed)

meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
arm = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE'][0]
body = meshes[0]
print("KEEPING meshes=%s armature=%s" % ([o.name for o in meshes], arm.name))

# ---- 2. dark desaturated palette ----------------------------------------------
PALETTE = [
    ("dark_leather", (0.200, 0.145, 0.100), 0.0, 0.88),
    ("dark_steel",   (0.150, 0.150, 0.160), 0.50, 0.48),
    ("skin_warm",    (0.330, 0.245, 0.190), 0.0, 0.90),
    ("hair_dark",    (0.095, 0.078, 0.068), 0.0, 0.92),
]
new_mats = []
for i in range(len(body.data.materials)):
    name, rgb, metal, rough = PALETTE[i % len(PALETTE)]
    m = bpy.data.materials.new("ds_" + name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    for k in ("Specular IOR Level", "Specular"):
        if k in b.inputs:
            b.inputs[k].default_value = 0.25
    m.diffuse_color = (*rgb, 1.0)
    new_mats.append(m)
body.data.materials.clear()
for m in new_mats:
    body.data.materials.append(m)

print("PALETTE_APPLIED")
for i, m in enumerate(body.data.materials):
    b = m.node_tree.nodes.get("Principled BSDF")
    c = b.inputs["Base Color"].default_value
    print("  slot%d %-14s rgb=%.3f,%.3f,%.3f" % (i, m.name, c[0], c[1], c[2]))

# ---- 3. pose ---------------------------------------------------------------
if arm.animation_data is None:
    arm.animation_data_create()
act = bpy.data.actions.get("Rig|Sword_Idle") or bpy.data.actions.get("Rig|Idle_Loop")
arm.animation_data.action = act
bpy.context.scene.frame_set(10)
print("POSED action=%s frame=10" % (act.name if act else "NONE"))

# force the depsgraph to actually evaluate before measuring
bpy.context.view_layer.update()
deps = bpy.context.evaluated_depsgraph_get()

# ---- 4. measure PER OBJECT (a combined box hides which object is which) ------
print("BOUNDS_PER_OBJECT")
per = {}
for o in bpy.context.scene.objects:
    if o.type != 'MESH':
        continue
    ev = o.evaluated_get(deps)
    me = ev.to_mesh()
    pts = [ev.matrix_world @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    xs = [p.x for p in pts]
    ys = [p.y for p in pts]
    zs = [p.z for p in pts]
    per[o.name] = (min(xs), max(xs), min(zs), max(zs))
    print("  %-12s x %.3f..%.3f  z %.3f..%.3f  height %.3f"
          % (o.name, min(xs), max(xs), min(zs), max(zs), max(zs) - min(zs)))

body_zmin = min(v[2] for v in per.values())
body_zmax = max(v[3] for v in per.values())
HEIGHT = body_zmax - body_zmin
BOTTOM = body_zmin
print("CHARACTER height=%.4f m  bottom z=%.4f (%s)"
      % (HEIGHT, BOTTOM, "on the floor" if abs(BOTTOM) < 0.05 else "OFF THE FLOOR"))

# ---- 5. render -------------------------------------------------------------
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 24
scene.cycles.use_denoising = False
scene.render.resolution_x = 600
scene.render.resolution_y = 900
scene.view_settings.view_transform = 'Filmic'

world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
BG = world.node_tree.nodes["Background"]
BG.inputs[0].default_value = (0.030, 0.026, 0.023, 1.0)


def add_light(name, loc, euler, energy, size, colour=(1.0, 0.94, 0.86)):
    d = bpy.data.lights.new(name, 'AREA')
    d.energy = energy
    d.size = size
    d.color = colour
    o = bpy.data.objects.new(name, d)
    o.location = loc
    o.rotation_euler = euler
    bpy.context.collection.objects.link(o)


add_light("key", (-2.4, -2.8, 3.0), (math.radians(50), 0, math.radians(-40)), 520, 2.6)
add_light("fill", (2.8, -2.2, 1.7), (math.radians(76), 0, math.radians(54)), 130, 3.5,
          (0.78, 0.82, 1.0))
add_light("rim", (0.8, 3.0, 2.6), (math.radians(120), 0, math.radians(162)), 340, 1.8,
          (0.96, 0.86, 0.76))

bpy.ops.mesh.primitive_plane_add(size=16, location=(0, 0, 0))
ground = bpy.context.active_object
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.024, 0.021, 0.019, 1)
gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
ground.data.materials.append(gm)

cam_data = bpy.data.cameras.new("cam")
cam_data.type = 'ORTHO'
SPAN = HEIGHT * 1.25                    # 25 % headroom + footroom
cam_data.ortho_scale = SPAN
cam = bpy.data.objects.new("cam", cam_data)
bpy.context.collection.objects.link(cam)
scene.camera = cam

TARGET = Vector((0, 0, (body_zmin + body_zmax) / 2))
DIST = 8.0
top = TARGET.z + SPAN * 0.5
bot = TARGET.z - SPAN * 0.5
print("FRAMING span=%.3f  frame z %.3f..%.3f  character z %.3f..%.3f"
      % (SPAN, bot, top, body_zmin, body_zmax))
print("HEADROOM %.3f m above the head" % (top - body_zmax))
print("FOOTROOM %.3f m below the feet" % (body_zmin - bot))


def look_from(angle_deg, elev_deg=3.0):
    a, e = math.radians(angle_deg), math.radians(elev_deg)
    cam.location = TARGET + Vector((math.sin(a) * math.cos(e) * DIST,
                                    -math.cos(a) * math.cos(e) * DIST,
                                    math.sin(e) * DIST))
    cam.rotation_euler = (TARGET - cam.location).to_track_quat('-Z', 'Y').to_euler()


for name, ang in (("front", 0.0), ("side", 90.0), ("back", 180.0), ("threequarter", 40.0)):
    look_from(ang)
    scene.render.filepath = os.path.join(OUT, "final_%s.png" % name)
    bpy.ops.render.render(write_still=True)
    print("RENDERED %s" % scene.render.filepath)

# ---- 6. silhouette proof ---------------------------------------------------
# Use Standard view transform for this one, otherwise Filmic turns the white
# backdrop grey and a pixel test cannot tell figure from background.
scene.view_settings.view_transform = 'Standard'
for m in body.data.materials:
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1)
    b.inputs["Metallic"].default_value = 0.0
    for k in ("Specular IOR Level", "Specular"):
        if k in b.inputs:
            b.inputs[k].default_value = 0.0
BG.inputs[0].default_value = (1.0, 1.0, 1.0, 1.0)
ground.hide_render = True
look_from(0.0, 0.0)
scene.render.filepath = os.path.join(OUT, "final_silhouette.png")
bpy.ops.render.render(write_still=True)
print("RENDERED %s" % scene.render.filepath)

# ---- 7. export -------------------------------------------------------------
glb_local = os.path.join(OUT, "hero.glb")
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.context.scene.objects:
    if o.type in ('MESH', 'ARMATURE') and o.name != ground.name:
        o.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.export_scene.gltf(
    filepath=glb_local,
    export_format='GLB',
    use_selection=True,
    export_animations=True,
    export_animation_mode='ACTIONS',
    export_apply=False,
    export_yup=True,
)
print("EXPORTED %s (%.1f KB)" % (glb_local, os.path.getsize(glb_local) / 1024.0))

try:
    os.makedirs(GAME, exist_ok=True)
    dest = os.path.join(GAME, "hero.glb")
    shutil.copy2(glb_local, dest)
    print("COPIED_TO_GAME %s (%.1f KB)" % (dest, os.path.getsize(dest) / 1024.0))
except Exception as e:
    print("COPY_FAILED %s" % e)

print("DONE")