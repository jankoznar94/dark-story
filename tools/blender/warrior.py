# Dark Story - procedural low-poly warrior, v2. Blender Python API, headless.
# Run:  blender.exe -b --factory-startup -P this_file.py
#
# v2 fixes, all caught by looking at the v1 renders:
#   * v1 read LANKY, not muscular  -> more mass everywhere, legs shortened,
#     chest/shoulders widened, arms and thighs thickened
#   * v1 sword FLOATED beside the hip -> now gripped in the right fist
#   * v1 had no readable hands -> proper fists
#   * v1 silhouette test silently did NOT apply (material_override ignored)
#     -> override every material to black instead
#   * feet were 1.7 cm above the ground -> origin exactly at z=0
#
# Art rules honoured: low poly, flat shaded, desaturated warm palette,
# no glow/emission, exaggerated old-Blizzard silhouette.

import math
import os

import bpy
from mathutils import Euler, Matrix, Vector

OUT = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_model"
os.makedirs(OUT, exist_ok=True)

PALETTE = {
    "skin":     (0.36, 0.27, 0.21),
    "skin_d":   (0.28, 0.20, 0.15),
    "steel":    (0.30, 0.30, 0.31),
    "steel_d":  (0.19, 0.19, 0.20),
    "leather":  (0.20, 0.14, 0.09),
    "leather_d": (0.13, 0.09, 0.06),
    "cloth":    (0.26, 0.10, 0.09),
    "hair":     (0.10, 0.08, 0.07),
    "bone":     (0.44, 0.40, 0.32),
}

# ---------------------------------------------------------------- proportions
# 1.88 m, 7.5 heads (heroic but not stretched). Wide chest, narrow waist,
# thick limbs. The V-taper and the shoulder width do all the silhouette work.
Z_TOTAL = 1.88
H = Z_TOTAL / 7.5                     # one head

Z_HEAD_BOT = Z_TOTAL - H              # 1.629
Z_SHOULDER = Z_HEAD_BOT - H * 0.72    # shoulder line
Z_CHEST_BOT = Z_TOTAL * 0.475         # 0.893 - bottom of ribcage
Z_WAIST = Z_TOTAL * 0.435             # 0.818
Z_PELVIS_BOT = Z_TOTAL * 0.365        # 0.686 - crotch
Z_KNEE = Z_TOTAL * 0.255              # 0.479
Z_ANKLE = Z_TOTAL * 0.048             # 0.090

SHOULDER_X = H * 1.15                 # half shoulder width (centre of deltoid)
                                      # 0.29 m each side -> ~0.84 m span, which is
                                      # what makes a heavy build read at a glance.

PARTS = []          # every part
BODY_PARTS = []     # body only (no weapon) - used for measurement
SWORD_PARTS = []    # weapon only
SWORD_MODE = [False]   # flipped to True just before the weapon is built;
                       # a list so the helper functions can read the flag


def wipe():
    for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
                  bpy.data.lights, bpy.data.cameras, bpy.data.armatures):
        for item in list(block):
            block.remove(item)


def mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    r, g, bl = PALETTE[name]
    b.inputs["Base Color"].default_value = (r, g, bl, 1.0)
    is_metal = name.startswith("steel")
    b.inputs["Metallic"].default_value = 0.6 if is_metal else 0.0
    b.inputs["Roughness"].default_value = 0.42 if is_metal else 0.9
    m.diffuse_color = (r, g, bl, 1.0)
    return m


def rot(pts, pivot, eul):
    if eul == (0, 0, 0):
        return pts
    m = Euler(eul).to_matrix()
    p = Vector(pivot)
    return [tuple(p + m @ (Vector(v) - p)) for v in pts]


def _mesh(name, verts, faces, material):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(mat(material))
    PARTS.append(o)
    return o


def box(name, material, centre, size, taper=1.0, taper_front=1.0, eul=(0, 0, 0)):
    cx, cy, cz = centre
    sx, sy, sz = size
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    verts = []
    for zs in (-1, 1):
        t = taper if zs > 0 else 1.0
        tf = taper_front if zs > 0 else 1.0
        for xs, ys in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            verts.append((cx + xs * hx * t, cy + ys * hy * t * tf, cz + zs * hz))
    verts = rot(verts, centre, eul)
    faces = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1),
             (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    return _mesh(name, verts, faces, material)


def tube(name, material, p0, p1, r0, r1, sides=8):
    p0, p1 = Vector(p0), Vector(p1)
    axis = p1 - p0
    if axis.length < 1e-6:
        return None
    axis.normalize()
    up = Vector((0, 0, 1))
    if abs(axis.dot(up)) > 0.99:
        up = Vector((0, 1, 0))
    right = axis.cross(up).normalized()
    up2 = right.cross(axis).normalized()
    verts = []
    for centre, r in ((p0, r0), (p1, r1)):
        for s in range(sides):
            a = 2 * math.pi * s / sides
            verts.append(tuple(centre + right * (math.cos(a) * r) + up2 * (math.sin(a) * r)))
    faces = [(s, (s + 1) % sides, sides + (s + 1) % sides, sides + s) for s in range(sides)]
    faces.append(tuple(range(sides - 1, -1, -1)))
    faces.append(tuple(range(sides, sides * 2)))
    return _mesh(name, verts, faces, material)


def ball(name, material, centre, radius, scale=(1, 1, 1), segments=10, rings=6):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=rings, radius=radius, location=centre)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat(material))
    PARTS.append(o)
    return o


# ---------------------------------------------------------------- build
wipe()

# ---- head: thick bull neck, heavy jaw, small crown. No face detail: at the
# ARPG camera distance a face is noise, and the silhouette carries identity.
box("neck", "skin", (0, 0, Z_HEAD_BOT - H * 0.22), (H * 0.62, H * 0.60, H * 0.55), taper=0.9)
box("skull", "skin", (0, -0.01, Z_HEAD_BOT + H * 0.52), (H * 0.86, H * 0.92, H * 0.96),
    taper=0.86, taper_front=0.90)
box("jaw", "skin", (0, 0.02, Z_HEAD_BOT + H * 0.16), (H * 0.80, H * 0.82, H * 0.36), taper=0.92)
box("brow", "skin_d", (0, -H * 0.36, Z_HEAD_BOT + H * 0.60), (H * 0.80, H * 0.16, H * 0.16))
box("hair", "hair", (0, -0.012, Z_HEAD_BOT + H * 0.90), (H * 0.92, H * 1.0, H * 0.46), taper=0.84)

# ---- trapezius: the wedge that makes a heavy build read from BEHIND
box("trap", "skin", (0, 0.02, Z_SHOULDER + H * 0.06),
    (SHOULDER_X * 1.72, H * 0.66, H * 0.52), taper=2.4)

# ---- torso: strong V. Chest wide and deep, waist pulled in hard.
Z_RIB_TOP = Z_SHOULDER - H * 0.10
box("chest", "skin", (0, 0, (Z_RIB_TOP + Z_CHEST_BOT) / 2),
    (H * 2.35, H * 1.18, Z_RIB_TOP - Z_CHEST_BOT), taper=0.54, taper_front=0.86)
# pectorals: two slabs, not one, so the front reads as muscle not a wall
for side in (-1, 1):
    box("pec_%d" % side, "skin",
        (side * H * 0.44, -H * 0.42, Z_RIB_TOP - H * 0.34),
        (H * 0.80, H * 0.30, H * 0.52), taper=0.88, taper_front=0.7)
# latissimus: widens the back
for side in (-1, 1):
    box("lat_%d" % side, "skin", (side * H * 0.80, H * 0.10, Z_RIB_TOP - H * 0.60),
        (H * 0.42, H * 0.78, H * 0.78), taper=0.6)
box("abs", "skin", (0, 0, (Z_CHEST_BOT + Z_WAIST) / 2),
    (H * 1.42, H * 0.94, Z_CHEST_BOT - Z_WAIST), taper=0.80)
# obliques flare slightly - a heavy man is not a rectangle
for side in (-1, 1):
    box("obl_%d" % side, "skin", (side * H * 0.70, 0, (Z_WAIST + Z_PELVIS_BOT) / 2),
        (H * 0.30, H * 0.86, (Z_WAIST - Z_PELVIS_BOT) * 1.15), taper=0.85)

# ---- shoulders + pauldrons
for side, s in ((-1, "L"), (1, "R")):
    sx = side * SHOULDER_X
    ball("delt_" + s, "skin", (sx, 0, Z_SHOULDER - H * 0.22), H * 0.52,
         scale=(1.05, 1.0, 1.05))
    box("pauldron_" + s, "steel", (side * SHOULDER_X * 1.30, 0, Z_SHOULDER - H * 0.10),
        (H * 0.66, H * 1.00, H * 0.78), taper=0.62, taper_front=0.86)
    box("pauldron_lip_" + s, "steel_d",
        (side * SHOULDER_X * 1.52, 0, Z_SHOULDER - H * 0.44),
        (H * 0.34, H * 0.94, H * 0.26), taper=0.88)
    box("pauldron_stud_" + s, "bone",
        (side * SHOULDER_X * 1.24, 0, Z_SHOULDER + H * 0.30),
        (H * 0.34, H * 0.34, H * 0.30), taper=0.7)

    # ---- arm. Forearm THICKER than the upper arm: a brawler, not a fencer.
    ax = side * SHOULDER_X * 1.06
    Z_ELBOW = Z_SHOULDER - H * 1.55
    Z_WRIST = Z_SHOULDER - H * 2.72
    tube("upper_arm_" + s, "skin", (ax, 0, Z_SHOULDER - H * 0.55),
         (ax + side * H * 0.10, 0, Z_ELBOW), H * 0.46, H * 0.36, sides=8)
    ball("bicep_" + s, "skin", (ax + side * H * 0.02, -H * 0.06, Z_SHOULDER - H * 0.95),
         H * 0.34, scale=(1.0, 1.25, 1.15))
    ball("elbow_" + s, "skin", (ax + side * H * 0.10, 0, Z_ELBOW), H * 0.34)
    tube("forearm_" + s, "skin", (ax + side * H * 0.10, 0, Z_ELBOW),
         (ax + side * H * 0.06, 0, Z_WRIST), H * 0.44, H * 0.30, sides=8)
    tube("bracer_" + s, "leather", (ax + side * H * 0.09, 0, Z_ELBOW - H * 0.08),
         (ax + side * H * 0.06, 0, Z_WRIST + H * 0.06), H * 0.42, H * 0.34, sides=8)
    # fist: big and blocky, so "gripping" reads instantly
    box("fist_" + s, "skin_d", (ax + side * H * 0.06, -H * 0.02, Z_WRIST - H * 0.28),
        (H * 0.48, H * 0.52, H * 0.52), taper=0.94)
    box("knuckles_" + s, "skin", (ax + side * H * 0.06, -H * 0.20, Z_WRIST - H * 0.26),
        (H * 0.44, H * 0.18, H * 0.40), taper=0.96)

    # ---- leg
    lx = side * H * 0.68
    tube("thigh_" + s, "skin", (lx, 0, Z_PELVIS_BOT + H * 0.22), (lx, 0, Z_KNEE + H * 0.06),
         H * 0.60, H * 0.42, sides=8)
    # quad slab on the front
    box("quad_" + s, "skin", (lx, -H * 0.34, Z_PELVIS_BOT - H * 0.30),
        (H * 0.62, H * 0.34, H * 0.90), taper=0.92, eul=(math.radians(-4), 0, 0))
    ball("knee_" + s, "steel", (lx, -H * 0.14, Z_KNEE + H * 0.10), H * 0.30)
    tube("calf_" + s, "skin", (lx, 0, Z_KNEE), (lx, 0, Z_ANKLE + H * 0.04),
         H * 0.44, H * 0.26, sides=8)
    ball("calf_muscle_" + s, "skin", (lx, H * 0.14, Z_KNEE - H * 0.34), H * 0.26,
         scale=(1.0, 1.3, 1.35))
    box("greave_" + s, "steel", (lx, -H * 0.16, Z_KNEE - H * 0.50),
        (H * 0.52, H * 0.54, H * 0.62), taper=0.88)
    # boot centred so its underside sits exactly on z=0
    box("boot_" + s, "leather_d", (lx, H * 0.10, H * 0.18),
        (H * 0.54, H * 1.10, H * 0.36), taper=0.96)

# ---- belt, tassets, chest strap
Z_BELT = Z_WAIST - H * 0.10
box("belt", "leather", (0, 0, Z_BELT), (H * 1.60, H * 1.00, H * 0.30))
box("buckle", "bone", (0, -H * 0.54, Z_BELT), (H * 0.38, H * 0.16, H * 0.26))
for i, off in enumerate((-0.60, 0.0, 0.60)):
    box("tasset_%d" % i, "cloth", (off * H * 1.42, 0, Z_PELVIS_BOT - H * 0.12),
        (H * 0.62, H * 0.96, H * 0.70), taper=0.86)
box("strap", "leather", (H * 0.34, -H * 0.50, Z_RIB_TOP - H * 0.85),
    (H * 0.26, H * 0.18, H * 1.60))
box("strap_back", "leather", (-H * 0.30, H * 0.50, Z_RIB_TOP - H * 0.85),
    (H * 0.24, H * 0.18, H * 1.60))

# everything built so far is body, everything after this is weapon
for _o in PARTS:
    BODY_PARTS.append(_o)
SWORD_MODE[0] = True   # without this the sword parts get tagged as body and
                       # SWORD_PARTS stays empty

# ---- sword, GRIPPED IN THE RIGHT FIST (v1 had it floating beside the hip).
RX = SHOULDER_X * 1.06 + H * 0.06
Z_FIST = (Z_SHOULDER - H * 2.72) - H * 0.28
GRIP = (RX, -H * 0.02, Z_FIST)
# negative Y rotation swings the blade OUTWARD on the right-hand side
TILT = (math.radians(13), math.radians(-38), 0.0)


def _tag(o):
    (SWORD_PARTS if SWORD_MODE[0] else BODY_PARTS).append(o)
    return o


def sbox(name, material, off, size, taper=1.0, taper_front=1.0):
    """A sword part positioned relative to the grip, sharing the sword's tilt."""
    c = (GRIP[0] + off[0], GRIP[1] + off[1], GRIP[2] + off[2])
    return _tag(box(name, material, c, size, taper=taper, taper_front=taper_front, eul=TILT))


def stube(name, material, a, b, r0, r1, sides=6):
    """Tube between two points, both offset from the grip and tilted with it."""
    m = Euler(TILT).to_matrix()
    pa = Vector(GRIP) + m @ Vector(a)
    pb = Vector(GRIP) + m @ Vector(b)
    return _tag(tube(name, material, tuple(pa), tuple(pb), r0, r1, sides=sides))


# A hanging arm sits at ~0.74 m; a full-length sword pointing straight down
# would go through the floor. Tilt it outward (negative Y rotation swings the
# blade away from the body on the right side) and keep the blade short enough
# that the tip stops just above the ground.
stube("grip", "leather", (0, 0, 0.16), (0, 0, -0.12), H * 0.11, H * 0.10)
sbox("pommel", "bone", (0, 0, 0.24), (H * 0.26, H * 0.26, H * 0.20))
sbox("guard", "steel", (0, 0, -0.10), (H * 1.00, H * 0.26, H * 0.18))
BLADE_LEN = H * 2.20
sbox("blade", "steel", (0, 0, -0.10 - BLADE_LEN * 0.5), (H * 0.30, H * 0.08, BLADE_LEN),
     taper=0.45, taper_front=0.30)
sbox("blade_tip", "steel", (0, 0, -0.10 - BLADE_LEN - 0.05), (H * 0.13, H * 0.08, H * 0.14),
     taper=0.1)
# report where the tip lands so this cannot silently break again
_m = Euler(TILT).to_matrix()
_tip = Vector(GRIP) + _m @ Vector((0, 0, -0.10 - BLADE_LEN - 0.12))
print("  sword tip z = %.4f  (must be > 0, feet are at 0)" % _tip.z)

# ---------------------------------------------------------------- join + clean
# The sword is joined SEPARATELY so the body can be measured on its own. Merging
# them first made the bounding box meaningless (a hanging blade adds ~1.7 m of
# "height" and a lot of useless width).
bpy.ops.object.select_all(action='DESELECT')
for o in SWORD_PARTS:
    o.select_set(True)
bpy.context.view_layer.objects.active = SWORD_PARTS[0]
bpy.ops.object.join()
sword = bpy.context.active_object
sword.name = "Sword"

bpy.ops.object.select_all(action='DESELECT')
for o in BODY_PARTS:
    o.select_set(True)
bpy.context.view_layer.objects.active = BODY_PARTS[0]
bpy.ops.object.join()
body = bpy.context.active_object
body.name = "Body"
bpy.ops.object.shade_flat()

# consistent outward normals - hand-built faces get the winding wrong otherwise
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode='OBJECT')

# Feet are placed at z=0 by construction, so NO auto-shift is applied. The old
# "shift by the lowest vertex" approach used a blade vertex as the reference and
# buried the character 24 cm underground.
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

body_low = min(p.co.z for p in body.data.vertices)
sword_low = min(p.co.z for p in sword.data.vertices) if sword.data.vertices else 0.0
print("  body lowest z  = %.4f  (must be ~0, feet)" % body_low)
print("  sword lowest z = %.4f  (must be > 0, no floor clipping)" % sword_low)

v = body.data.vertices
xs = [p.co.x for p in v]
ys = [p.co.y for p in v]
zs = [p.co.z for p in v]
tris = sum(len(f.vertices) - 2 for f in body.data.polygons)
height = max(zs) - min(zs)
width = max(xs) - min(xs)

print("BUILD_STATS")
print("  vertices : %d" % len(v))
print("  polygons : %d" % len(body.data.polygons))
print("  triangles: %d" % tris)
print("  materials: %d %s" % (len(body.data.materials), [m.name for m in body.data.materials]))
print("  height   : %.3f m" % height)
print("  width    : %.3f m   (shoulder span / height = %.3f)" % (width, width / height))
print("  depth    : %.3f m" % (max(ys) - min(ys)))
print("  min z    : %.5f (must be 0)" % min(zs))
# a heavy warrior should be roughly half as wide as he is tall, including pauldrons
print("  MASS CHECK width/height %.3f  (target 0.42-0.58)" % (width / height))

bpy.ops.object.select_all(action='DESELECT')
body.select_set(True)
sword.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
final = bpy.context.active_object
final.name = "Warrior"
print("  FINAL: %d verts, %d tris, %d materials"
      % (len(final.data.vertices),
         sum(len(f.vertices) - 2 for f in final.data.polygons),
         len(final.data.materials)))
final_low = min(p.co.z for p in final.data.vertices)
print("  FINAL lowest z = %.4f (>= 0 means nothing is under the floor)" % final_low)

glb = os.path.join(OUT, "warrior.glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB',
                          use_selection=True, export_apply=True)
print("EXPORTED %s (%.1f KB)" % (glb, os.path.getsize(glb) / 1024.0))

# ---------------------------------------------------------------- render
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 28
scene.cycles.use_denoising = False
scene.render.resolution_x = 620
scene.render.resolution_y = 900
scene.view_settings.view_transform = 'Filmic'

world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
BG = world.node_tree.nodes["Background"]
BG.inputs[0].default_value = (0.035, 0.030, 0.026, 1.0)


def add_light(name, loc, euler, energy, size, colour=(1.0, 0.94, 0.86)):
    d = bpy.data.lights.new(name, 'AREA')
    d.energy = energy
    d.size = size
    d.color = colour
    o = bpy.data.objects.new(name, d)
    o.location = loc
    o.rotation_euler = euler
    bpy.context.collection.objects.link(o)


add_light("key", (-2.8, -3.2, 3.4), (math.radians(50), 0, math.radians(-40)), 1100, 2.6)
add_light("fill", (3.2, -2.6, 1.8), (math.radians(74), 0, math.radians(54)), 320, 3.5,
          (0.78, 0.82, 1.0))
add_light("rim", (1.0, 3.4, 2.8), (math.radians(118), 0, math.radians(162)), 700, 1.8,
          (0.96, 0.86, 0.76))

bpy.ops.mesh.primitive_plane_add(size=14, location=(0, 0, 0))
ground = bpy.context.active_object
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.05, 0.045, 0.04, 1)
gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
ground.data.materials.append(gm)

cam_data = bpy.data.cameras.new("cam")
cam_data.type = 'ORTHO'
cam_data.ortho_scale = 2.25
cam = bpy.data.objects.new("cam", cam_data)
bpy.context.collection.objects.link(cam)
scene.camera = cam

TARGET = Vector((0, 0, 1.0))
DIST = 7.0


def look_from(angle_deg, elev_deg=5.0):
    a, e = math.radians(angle_deg), math.radians(elev_deg)
    cam.location = TARGET + Vector((math.sin(a) * math.cos(e) * DIST,
                                    -math.cos(a) * math.cos(e) * DIST,
                                    math.sin(e) * DIST))
    cam.rotation_euler = (TARGET - cam.location).to_track_quat('-Z', 'Y').to_euler()


for name, ang in (("front", 0.0), ("side", 90.0), ("back", 180.0),
                  ("threequarter", 35.0), ("hero", 210.0)):
    look_from(ang)
    scene.render.filepath = os.path.join(OUT, "v4_%s.png" % name)
    bpy.ops.render.render(write_still=True)
    print("RENDERED %s" % scene.render.filepath)

# ---------------------------------------------------------------- silhouette test
# Highest-leverage check there is: if the shape is not identifiable as a solid
# black blob, colour will not save it. v1's attempt silently did nothing because
# material_override was ignored, so override every material directly instead.
saved = {m.name: m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value[:3]
         for m in final.data.materials}
for m in final.data.materials:
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0, 0, 0, 1)
    m.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.0
BG.inputs[0].default_value = (1.0, 1.0, 1.0, 1.0)
ground.hide_render = True
look_from(0.0, 0.0)
scene.render.filepath = os.path.join(OUT, "v4_silhouette_front.png")
bpy.ops.render.render(write_still=True)
print("RENDERED %s" % scene.render.filepath)

look_from(35.0, 0.0)
scene.render.filepath = os.path.join(OUT, "v4_silhouette_34.png")
bpy.ops.render.render(write_still=True)
print("RENDERED %s" % scene.render.filepath)

for m in final.data.materials:
    r, g, b = saved[m.name]
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (r, g, b, 1)

print("DONE %s" % OUT)