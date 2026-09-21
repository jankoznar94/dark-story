# Dark Story - composite test: would a 2D sprite hero sit correctly in the REAL
# game scene (ground texture + the 3D prop set)?
#
# This reproduces the game's actual framing, taken from the source rather than
# guessed:
#   scripts/camera_rig.gd : offset (0, 12.5, 9.0), fov 32, look_height 0.6
#   scenes/main.tscn      : PlaneMesh floor, albedo assets/textures/ground_grass.png
#   levels/training_ground.json : prop placements (metres)
#
# Pass A renders the scene WITH the real 3D hero -> the reference.
# Pass B renders the SAME scene with no character -> the clean plate.
# The caller composites the baked 2D sprite onto pass B; comparing A against the
# composite answers "does a sprite sit right on this ground, among these props".
#
# The sprite's on-screen size is computed from the projection, not eyeballed:
#   px_per_m = (H/2) / (distance * tan(fov/2))
# and the 3D hero's measured bbox height in pass A is required to agree.
#
# Run: blender.exe -b --factory-startup -P tools/blender/render_2d_composite_test.py
import json
import math
import os
import sys

import bpy
from mathutils import Vector

REPO = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg"
HERO = os.path.join(REPO, "models", "hero.glb")
PROPS = os.path.join(REPO, "assets", "props")
GRASS = os.path.join(REPO, "assets", "textures", "ground_grass.png")
OUT = r"C:\Users\Martin Fabian\AppData\Local\Temp\ds_composite"
os.makedirs(OUT, exist_ok=True)

# ---- game camera, verbatim from camera_rig.gd --------------------------------
CAM_OFFSET = Vector((0.0, 12.5, 9.0))   # Blender: height -> Z, so (x, y, z)=(0,-?,..)
FOV_DEG = 32.0
LOOK_H = 0.6
RES_X, RES_Y = 960, 540
# Blender is Z-up; Godot is Y-up with the player's front at -Z. The camera sits
# BEHIND the player at Godot +Z, which in Blender is -Y.
CAM_POS = Vector((0.0, -CAM_OFFSET.z, CAM_OFFSET.y))
LOOK_AT = Vector((0.0, 0.0, LOOK_H))

HERO_FRAME = 4      # a mid-walk frame
CLIP = "Rig|Walk_Loop"

# prop placements, abbreviated from levels/training_ground.json
PLACE = [
    ("wall_segment",   (-8.0, 6.2, 0.0)),
    ("wall_segment",   (-2.6, 6.2, 0.0)),
    ("wall_segment",   (4.0, 6.2, 0.0)),
    ("ruin_stub_tall",  (-9.5, -1.0, 92.0)),
    ("ruin_stub_low",   (-7.4, 3.6, 104.0)),
    ("ruin_arch",       (7.5, -3.0, 0.0)),
    ("barrel",          (-4.2, 2.4, 0.0)),
    ("crate_large",     (5.2, 3.4, 25.0)),
    ("rock_boulder",    (2.4, -4.6, 0.0)),
    ("tree_dead",       (-11.8, 4.8, 0.0)),
    ("stump",           (6.4, 1.2, 0.0)),
    ("fence_run",       (-3.4, -5.4, 0.0)),
]

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images,
              bpy.data.cameras, bpy.data.lights, bpy.data.worlds):
    for item in list(block):
        try:
            block.remove(item)
        except Exception:
            pass


def import_obj(path):
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


# ---- the ground: a plane with the game's own grass texture -------------------
bpy.ops.mesh.primitive_plane_add(size=34.0, location=(0.0, 0.0, 0.0))
floor = bpy.context.active_object
floor.name = "Ground"
gmat = bpy.data.materials.new("GroundGrass")
gmat.use_nodes = True
nt = gmat.node_tree
bsdf = nt.nodes["Principled BSDF"]
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = bpy.data.images.load(GRASS)
mapping = nt.nodes.new("ShaderNodeMapping")
mapping.inputs["Scale"].default_value = (8.5, 8.5, 1.0)   # 34 m / 8.5 = 4 m per tile
uvn = nt.nodes.new("ShaderNodeTexCoord")
nt.links.new(uvn.outputs["UV"], mapping.inputs["Vector"])
nt.links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.95
bsdf.inputs["Specular IOR Level"].default_value = 0.05
floor.data.materials.append(gmat)

# ---- the prop set ------------------------------------------------------------
placed = 0
for name, (x, y, rot) in PLACE:
    p = os.path.join(PROPS, name + ".obj")
    if not os.path.exists(p):
        print("PROP_MISSING %s" % name)
        continue
    for o in import_obj(p):
        if o.type != 'MESH':
            continue
        o.location = (x, y, 0.0)
        o.rotation_euler = (0.0, 0.0, math.radians(rot))
        placed += 1
print("PROPS_PLACED %d" % placed)


def add_hero():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=HERO)
    new = [o for o in bpy.data.objects if o not in before]
    arm = next((o for o in new if o.type == 'ARMATURE'), None)
    mesh = next((o for o in new if o.type == 'MESH' and o.parent is arm), None)
    acts = [a for a in bpy.data.actions if a.name == CLIP or CLIP in a.name]
    if arm and acts:
        if arm.animation_data is None:
            arm.animation_data_create()
        arm.animation_data.action = acts[0]
        bpy.context.scene.frame_set(HERO_FRAME)
        bpy.context.view_layer.update()
    return new, arm, mesh


# ---- world + game-like lighting (main.gd: light lives in atmosphere) ---------
sc = bpy.context.scene
world = bpy.data.worlds.new("W")
sc.world = world
world.use_nodes = True
bgn = world.node_tree.nodes["Background"]
bgn.inputs[0].default_value = (0.16, 0.15, 0.145, 1.0)
bgn.inputs[1].default_value = 0.55

sun = bpy.data.lights.new("sun", 'SUN')
sun.energy = 2.6
sun.color = (1.0, 0.93, 0.84)
so = bpy.data.objects.new("sun", sun)
sc.collection.objects.link(so)
so.rotation_euler = (math.radians(52), 0.0, math.radians(-34))

fill = bpy.data.lights.new("fill", 'SUN')
fill.energy = 0.5
fill.color = (0.72, 0.78, 1.0)
fo = bpy.data.objects.new("fill", fill)
sc.collection.objects.link(fo)
fo.rotation_euler = (math.radians(72), 0.0, math.radians(150))

# ---- camera exactly as the game has it ---------------------------------------
cam_data = bpy.data.cameras.new("cam")
cam_data.type = 'PERSP'
cam_data.sensor_fit = 'VERTICAL'
cam_data.angle_y = math.radians(FOV_DEG)
cam = bpy.data.objects.new("cam", cam_data)
sc.collection.objects.link(cam)
sc.camera = cam
cam.location = CAM_POS
cam.rotation_euler = (LOOK_AT - CAM_POS).to_track_quat('-Z', 'Y').to_euler()

sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = RES_X
sc.render.resolution_y = RES_Y
sc.render.film_transparent = False
sc.view_settings.view_transform = 'Standard'
sc.render.image_settings.file_format = 'PNG'
sc.render.image_settings.color_mode = 'RGB'

DIST = (CAM_POS - Vector((0.0, 0.0, 0.9))).length
PPM = (RES_Y / 2.0) / (DIST * math.tan(math.radians(FOV_DEG) / 2.0))
print("CAMERA dist=%.4f m  fov=%.1f  px_per_metre=%.3f" % (DIST, FOV_DEG, PPM))
print("HERO_PROJECTED_HEIGHT_PX %.1f" % (1.838 * PPM))

# ---- pass A: with the real 3D hero -------------------------------------------
hero_objs, arm, hmesh = add_hero()
sc.render.filepath = os.path.join(OUT, "scene_3d_hero.png")
bpy.ops.render.render(write_still=True)

# measure the hero's on-screen height so the composite can be checked against it
deps = bpy.context.evaluated_depsgraph_get()
me = hmesh.evaluated_get(deps).to_mesh()
mw = hmesh.matrix_world
from bpy_extras.object_utils import world_to_camera_view
zs = []
for v in me.vertices:
    co = world_to_camera_view(sc, cam, mw @ v.co)
    zs.append(co.y)
lo, hi = min(zs), max(zs)
print("HERO_SCREEN_BBOX_Y %.4f..%.4f  -> height %.1f px" % (lo, hi, (hi - lo) * RES_Y))

# ---- pass B: clean plate, no character ---------------------------------------
for o in hero_objs:
    try:
        bpy.data.objects.remove(o, do_unlink=True)
    except Exception:
        pass
sc.render.filepath = os.path.join(OUT, "scene_clean_plate.png")
bpy.ops.render.render(write_still=True)

man = {
    "camera_pos": list(CAM_POS), "look_at": list(LOOK_AT), "fov_deg": FOV_DEG,
    "res": [RES_X, RES_Y], "px_per_metre": PPM, "clip": CLIP, "frame": HERO_FRAME,
    "hero_height_m": 1.838, "hero_screen_height_px": (hi - lo) * RES_Y,
}
with open(os.path.join(OUT, "composite_manifest.json"), "w") as fh:
    json.dump(man, fh, indent=1)
print("OUT_DIR %s" % OUT)
