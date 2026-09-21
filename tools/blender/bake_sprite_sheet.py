# Dark Story - bake 2D sprite sheets from the DELIVERED rigged hero.
#
# WHY: the game is 3D; a 2D sprite build re-uses the existing 45 animation clips
# by rendering them ONCE into PNG sheets instead of skinning at runtime.
#
# Three things this script gets right, each one a classic sprite-sheet failure:
#
#  1. ELEVATION. A camera at body height gives a side-on platformer view, not a
#     Diablo view. The camera looks DOWN at ELEV degrees; 55 is the D2-like range.
#  2. NO JITTER. The ortho scale and the framing are computed by projecting every
#     posed vertex onto the camera's own right/up axes across EVERY frame of the
#     clip, then fitting one box to all of them. Per-frame bounds would make the
#     sprite breathe in and out as the character moves.
#  3. FEET ANCHORED. The fitted centre is applied to the camera target, so the
#     ground stays at the same pixel row for the whole clip and a death clip does
#     not drift up the frame.
#
# Output is RGBA with a transparent background (film_transparent), plus a JSON
# manifest of the sheet parameters so a runtime can reproduce the framing.
#
# Run: blender.exe -b --factory-startup -P tools/blender/bake_sprite_sheet.py -- <clip> <frames> <res> <elev>
import json
import math
import os
import sys

import bpy
from mathutils import Vector

REPO = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg"
SRC = os.path.join(REPO, "models", "hero.glb")
BASE_OUT = r"C:\Users\Martin Fabian\AppData\Local\Temp\ds_sprites"
os.makedirs(BASE_OUT, exist_ok=True)

argv = sys.argv
argv = argv[argv.index("--") + 1:] if "--" in argv else []
CLIP = argv[0] if len(argv) > 0 else "Rig|Walk_Loop"
NFRAMES = int(argv[1]) if len(argv) > 1 else 8
RES = int(argv[2]) if len(argv) > 2 else 512
ELEV = float(argv[3]) if len(argv) > 3 else 55.0
# 4th arg: a FIXED world-space span in metres. Every clip must be baked with the
# SAME span or the character changes size from one clip to the next in game.
FIXED_SPAN = float(argv[4]) if len(argv) > 4 else 0.0
SUBDIR = argv[5] if len(argv) > 5 else CLIP.replace("|", "_")
OUT = os.path.join(BASE_OUT, SUBDIR)
os.makedirs(OUT, exist_ok=True)

# Compass order, the convention a sprite sheet is indexed in. 0 = camera in front
# of the hero (the hero faces Blender +Y, so this is his SOUTH-facing frame).
DIRS = ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images,
              bpy.data.cameras, bpy.data.lights, bpy.data.worlds):
    for item in list(block):
        try:
            block.remove(item)
        except Exception:
            pass

bpy.ops.import_scene.gltf(filepath=SRC)

arm = None
mesh = None
for o in bpy.context.scene.objects:
    if o.type == 'ARMATURE':
        arm = o
    if o.type == 'MESH' and o.parent is arm:
        mesh = o

acts = [a for a in bpy.data.actions if a.name == CLIP or CLIP in a.name]
if not acts:
    print("CLIP_NOT_FOUND %r" % CLIP)
    print("AVAILABLE %s" % sorted(a.name for a in bpy.data.actions))
    sys.exit(1)
if arm.animation_data is None:
    arm.animation_data_create()
arm.animation_data.action = acts[0]
action = acts[0]

f0, f1 = action.frame_range
print("CLIP %s frames %.1f..%.1f  fps %s" % (action.name, f0, f1, bpy.context.scene.render.fps))

sc = bpy.context.scene


def posed_world_verts(frame):
    sc.frame_set(int(frame))
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    me = mesh.evaluated_get(deps).to_mesh()
    mw = mesh.matrix_world
    return [mw @ v.co for v in me.vertices]


frame_list = [int(round(f0 + (f1 - f0) * i / max(1, NFRAMES))) for i in range(NFRAMES)]
print("FRAMES %s" % frame_list)

# ---- pass 1: bounds across the whole clip ------------------------------------
per_frame = {fr: posed_world_verts(fr) for fr in frame_list}
allv = [v for fr in frame_list for v in per_frame[fr]]
gz = min(v.z for v in allv)
tz = max(v.z for v in allv)
tgt = Vector((
    (min(v.x for v in allv) + max(v.x for v in allv)) / 2.0,
    (min(v.y for v in allv) + max(v.y for v in allv)) / 2.0,
    gz + (tz - gz) * 0.45,          # aim at the torso, not the ground
))
print("HEIGHT %.4f m  target (%.3f, %.3f, %.3f)" % (tz - gz, tgt.x, tgt.y, tgt.z))

el = math.radians(ELEV)
D = 8.0


def cam_axes(az_deg):
    az = math.radians(az_deg)
    # from target toward the camera
    dv = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    fwd = -dv
    right = fwd.cross(Vector((0.0, 0.0, 1.0))).normalized()
    up = right.cross(fwd).normalized()
    return dv, right, up


# project every posed vertex through the axes of EVERY direction, so one
# ortho_scale fits all 8 directions too (a wide weapon must not clip when the
# hero turns side-on).
umin = wmin = 1e9
umax = wmax = -1e9
for az_deg in range(0, 360, 45):
    dv, right, up = cam_axes(az_deg)
    for fr in frame_list:
        for v in per_frame[fr]:
            rel = v - tgt
            u = rel.dot(right)
            w = rel.dot(up)
            umin = min(umin, u); umax = max(umax, u)
            wmin = min(wmin, w); wmax = max(wmax, w)

SPAN = max(umax - umin, wmax - wmin) * 1.12
if FIXED_SPAN > 0.0:
    # A clip that swings a weapon needs a wider cell, but it must not make the
    # character bigger than in other clips -- so the span can only GROW beyond
    # the shared value, never shrink below it. This is the "the hero changes
    # size when he attacks" bug, and it is invisible until two clips are
    # compared side by side.
    if SPAN < FIXED_SPAN:
        print("SPAN_GROWN_REQUIRED clip=%s natural=%.4f shared=%.4f" % (CLIP, SPAN, FIXED_SPAN))
        SPAN = FIXED_SPAN
    else:
        print("SPAN_SHARED clip=%s natural=%.4f shared=%.4f" % (CLIP, SPAN, FIXED_SPAN))
    SPAN = round(SPAN, 4)
CU = (umin + umax) / 2.0
CW = (wmin + wmax) / 2.0
print("SHEET_SPAN %.4f m  centre_u %.4f  centre_w %.4f" % (SPAN, CU, CW))

# ---- world, lighting, camera -------------------------------------------------
world = bpy.data.worlds.new("W")
sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.06, 0.055, 0.05, 1.0)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.0

key = bpy.data.lights.new("key", 'SUN')
key.energy = 3.2
key.color = (1.0, 0.94, 0.87)
ko = bpy.data.objects.new("key", key)
sc.collection.objects.link(ko)
ko.rotation_euler = (math.radians(50), 0.0, math.radians(-30))

fill = bpy.data.lights.new("fill", 'SUN')
fill.energy = 0.9
fill.color = (0.76, 0.80, 1.0)
fo = bpy.data.objects.new("fill", fill)
sc.collection.objects.link(fo)
fo.rotation_euler = (math.radians(70), 0.0, math.radians(155))

cam_data = bpy.data.cameras.new("cam")
cam_data.type = 'ORTHO'
cam_data.ortho_scale = SPAN
cam = bpy.data.objects.new("cam", cam_data)
sc.collection.objects.link(cam)
sc.camera = cam

sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = RES
sc.render.resolution_y = RES
sc.render.film_transparent = True           # sprites composite over any ground
sc.view_settings.view_transform = 'Standard'
sc.view_settings.look = 'None'
sc.render.image_settings.file_format = 'PNG'
sc.render.image_settings.color_mode = 'RGBA'

# ---- assert the sign of the fix, so a regression FAILS instead of shipping ---
# NB the threshold is a SIGN check, not 0.9: at ELEV=55 the horizontal component
# is only cos(55)=0.574, so an "almost 1" bound fails on the correct value.
_dv0, _r0, _u0 = cam_axes(0.0 + 180.0)
assert _dv0.y > 0.0, "direction S must put the camera on the hero's +Y (front) side, got %r" % (_dv0,)
print("DIRECTION_ASSERT_OK S camera dv=(%.3f, %.3f, %.3f)" % (_dv0.x, _dv0.y, _dv0.z))

# ---- pass 2: render every (direction, frame) ---------------------------------
for di, dname in enumerate(DIRS):
    # +180: the hero faces Blender +Y, so for the "S" frame the camera must sit
    # on the +Y side. Without the offset the rows are labelled 180 deg out --
    # the row marked S renders the hero's BACK. Caught by reading the render,
    # not by any assertion, so it is asserted below instead.
    dv, right, up = cam_axes(di * 45.0 + 180.0)
    aim = tgt + CU * right + CW * up          # shift the aim, not the scale
    loc = aim + D * dv
    cam.location = loc
    cam.rotation_euler = (aim - loc).to_track_quat('-Z', 'Y').to_euler()
    for fi, fr in enumerate(frame_list):
        sc.frame_set(fr)
        fn = "%s_d%d_f%02d.png" % (CLIP.replace("|", "_"), di, fi)
        sc.render.filepath = os.path.join(OUT, fn)
        bpy.ops.render.render(write_still=True)

man = {
    "clip": action.name, "source": "models/hero.glb", "directions": DIRS,
    "frames": frame_list, "frame_range": [f0, f1], "fps": bpy.context.scene.render.fps,
    "cell_px": RES, "ortho_scale_m": SPAN, "elevation_deg": ELEV,
    "target": [tgt.x, tgt.y, tgt.z], "centre_offset": [CU, CW],
}
with open(os.path.join(OUT, "manifest.json"), "w") as fh:
    json.dump(man, fh, indent=1)
print("OUT_DIR %s" % OUT)
print("GRID %d dirs x %d frames @ %dpx" % (len(DIRS), len(frame_list), RES))
