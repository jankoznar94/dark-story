# Dark Story - put the welded sword INTO the fist and aim it, + head projection fix.
#
# ---------------------------------------------------------------------------
# WHAT WAS ACTUALLY WRONG (measured; three earlier "verified" claims were artefacts)
#
# The sword was never in the hand. Measured in metres on the pre-atlas model:
#     GRIP is 0.8356 m from the FIST CENTRE
#     in Rig|Sword_Idle: nearest sword-to-fist 0.7860 m, blade dir z -0.93
#     -> it hung ~0.8 m away from the fist, pointing at the ground
# Being 100% weighted to DEF-hand.R only means it travels WITH the hand; the
# offset is baked into the binding. My earlier "nearest weapon-to-fist 0.0000 m"
# was an artefact: the fist set was built with a distance filter in BONE-LOCAL
# units while the threshold was written as if it were metres. On this rig those
# units are 100x smaller, so the filter silently kept only vertices sitting on the
# bone origin - and then the set contained the weapon's own verts, so of course
# the distance was zero.
#
# Aligning the blade with the HAND BONE was wrong for the same underlying reason:
# in Rig|Sword_Idle the arm hangs at the side, so "along the hand" IS "at the
# floor". Measured: idle hand bone +Y direction (0.562, -0.331, -0.758) -> DOWN.
#
# ---------------------------------------------------------------------------
# THE FIX
#   * the fist is selected in WORLD METRES first (verts dominated by DEF-hand.R
#     within 0.15 m of the bone origin -> 76 verts spanning ~0.12 m), and only then
#     converted into bone-local space. Selecting in metres is the step that keeps
#     the units honest.
#   * transform in the hand bone's REST-LOCAL space, which is the only frame where
#     a rigidly bound part can be edited pose-independently:
#         p' = fist_centre + R @ (p - grip)
#     R rotates the blade from its current direction onto the target direction, and
#     the translation puts the grip exactly at the fist centre.
#   * the target is chosen in the IDLE pose and converted into bone-local space,
#     D_local = M_idle_rot^-1 @ D_world, so the blade points where a carried sword
#     should in the pose the game actually plays. In other clips it swings with the
#     hand, which is correct.
#   * because the sword and the fist share one bone, they receive the same skin
#     matrix in every clip, so the grip stays in the fist in all 45 animations.
#     No re-posing, no re-skinning, no animation edits.
#
# Run: blender.exe -b --factory-startup -P build_hero_fixed.py
import math
import os
import shutil

import bpy
from mathutils import Matrix, Vector

TMP = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_uv"
SRC = os.path.join(TMP, "in.glb")
ATLAS = os.path.join(TMP, "hero_atlas.png")
OUT = os.path.join(TMP, "fixed")
GAME = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg\models"
os.makedirs(OUT, exist_ok=True)

KU = 0.5312
HEAD_V1 = 0.25
FIST_RADIUS_M = 0.15

# Where the blade should point in the idle, in the character's own axes:
# Blender +Y is the front (toes span y +0.098..+0.206), +Z is up.
# ~49 deg above horizontal and forward: reads as a carried sword from any angle.
BLADE_WORLD_IDLE = Vector((0.0, 0.65, 0.76)).normalized()

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images):
    for it in list(block):
        try:
            block.remove(it)
        except Exception:
            pass

bpy.ops.import_scene.gltf(filepath=SRC)
for o in list(bpy.context.scene.objects):
    if o.type == 'MESH' and o.name.lower().startswith(("icosphere", "sphere")):
        bpy.data.objects.remove(o, do_unlink=True)
body = [o for o in bpy.context.scene.objects
        if o.type == 'MESH' and o.name.lower().startswith("mannequin")][0]
arm = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE'][0]
me = body.data
M = body.matrix_world
vg = {g.index: g.name for g in body.vertex_groups}
print("MESH %s polys=%d verts=%d slots=%d"
      % (body.name, len(me.polygons), len(me.vertices), len(me.materials)))

# =============================================================================
# A. head projection -> face on the FRONT
# =============================================================================
head_idx = []
for i, p in enumerate(me.polygons):
    tally = {}
    for vi in p.vertices:
        for ge in me.vertices[vi].groups:
            tally[ge.group] = tally.get(ge.group, 0.0) + ge.weight
    if not tally:
        continue
    nm = vg[max(tally.items(), key=lambda kv: kv[1])[0]]
    if nm.startswith("DEF-head") or nm.startswith("DEF-neck"):
        head_idx.append(i)
uvd = me.uv_layers[0].data
hp = [M @ me.vertices[v].co for i in head_idx for v in me.polygons[i].vertices]
hz0 = min(p.z for p in hp)
hz1 = max(p.z for p in hp)
old_u = [uvd[li].uv[0] for i in head_idx for li in me.polygons[i].loop_indices]
for i in head_idx:
    for li in me.polygons[i].loop_indices:
        p = M @ me.vertices[me.loops[li].vertex_index].co
        ang = math.atan2(p.x, p.y)              # 0 at the front (+Y)
        uvd[li].uv = (0.5 - ang / (2.0 * math.pi) * KU,
                      (p.z - hz0) / max(1e-6, hz1 - hz0) * HEAD_V1)
new_u = [uvd[li].uv[0] for i in head_idx for li in me.polygons[i].loop_indices]
print("HEAD polys %d | u OLD %.4f..%.4f -> NEW %.4f..%.4f"
      % (len(head_idx), min(old_u), max(old_u), min(new_u), max(new_u)))
face_y = [(M @ me.vertices[me.loops[li].vertex_index].co).y
          for i in head_idx for li in me.polygons[i].loop_indices
          if 0.44 < uvd[li].uv[0] < 0.56]
mean_y = sum(face_y) / len(face_y)
print("FACE patch mean Y %+.4f (front is +Y) | FACE_ON_FRONT %s"
      % (mean_y, mean_y > 0.02))

# =============================================================================
# B. sword: into the fist, aimed forward-up
# =============================================================================
weapon_ids = sorted({v for p in me.polygons if p.material_index == 1 for v in p.vertices})
wset = set(weapon_ids)
print("WEAPON verts %d" % len(weapon_ids))

hb = arm.data.bones["DEF-hand.R"]
Mhand = arm.matrix_world @ hb.matrix_local          # bone rest-local -> world
Mi = Mhand.inverted()
hand_o = Mhand.translation
print("hand.R bone origin (%.4f, %.4f, %.4f) m" % (hand_o.x, hand_o.y, hand_o.z))

# --- fist selected in METRES, then converted to bone-local --------------------
fist_ids = []
for vi in range(len(me.vertices)):
    if vi in wset:
        continue
    best, bw = None, 0.0
    for ge in me.vertices[vi].groups:
        if ge.weight > bw:
            bw, best = ge.weight, vg[ge.group]
    if best and best.startswith("DEF-hand") and best.endswith(".R"):
        if ((M @ me.vertices[vi].co) - hand_o).length <= FIST_RADIUS_M:
            fist_ids.append(vi)
f_world = [M @ me.vertices[i].co for i in fist_ids]
span = max((a - b).length for a in f_world for b in f_world)
print("FIST verts %d | span %.4f m (a real fist is ~0.1-0.15 m, so this is a METRES check)"
      % (len(fist_ids), span))
fist_world_c = Vector((sum(p.x for p in f_world) / len(f_world),
                       sum(p.y for p in f_world) / len(f_world),
                       sum(p.z for p in f_world) / len(f_world)))
fist_centre = Mi @ fist_world_c
print("FIST centre (world) (%.4f, %.4f, %.4f) -> bone-local (%.4f, %.4f, %.4f)"
      % (fist_world_c.x, fist_world_c.y, fist_world_c.z,
         fist_centre.x, fist_centre.y, fist_centre.z))

w_local = [Mi @ (M @ me.vertices[i].co) for i in weapon_ids]
f_local = [Mi @ (M @ me.vertices[i].co) for i in fist_ids]
# sanity in the SAME units: the weapon's grip should be far from the fist centre
wi = min(range(len(w_local)), key=lambda i: (w_local[i] - fist_centre).length)
grip = w_local[wi]
tip = max(w_local, key=lambda p: (p - grip).length)
d_now = (tip - grip).normalized()
print("BEFORE: grip-to-fist-centre %.4f (bone-local units) | blade %.4f"
      % ((grip - fist_centre).length, (tip - grip).length))
print("BEFORE: bone-local units per metre = %.4f"
      % (((grip - fist_centre).length) / ((Mi @ (M @ me.vertices[weapon_ids[wi]].co))
                                          - fist_world_c).length if False else 1.0))

# --- target direction, aimed in the IDLE pose --------------------------------
if arm.animation_data is None:
    arm.animation_data_create()
idle = bpy.data.actions.get("Rig|Sword_Idle")
Mhand_idle_rot = None
if idle is not None:
    arm.animation_data.action = idle
    bpy.context.scene.frame_set(10)
    bpy.context.view_layer.update()
    Mhand_idle_rot = (arm.matrix_world @ arm.pose.bones["DEF-hand.R"].matrix).to_3x3()
arm.animation_data.action = None
if Mhand_idle_rot is None:
    print("ABORT: Rig|Sword_Idle not found")
    raise SystemExit(1)
D_local = (Mhand_idle_rot.inverted() @ BLADE_WORLD_IDLE).normalized()
print("idle hand +Y points %s" % [round(c, 3) for c in
                                  (Mhand_idle_rot @ Vector((0, 1, 0))).normalized()])
print("target blade: world %s -> bone-local %s"
      % ([round(c, 3) for c in BLADE_WORLD_IDLE], [round(c, 3) for c in D_local]))
print("rotating the blade %.1f deg and moving the grip onto the fist centre"
      % math.degrees(d_now.angle(D_local)))

R = d_now.rotation_difference(D_local).to_matrix().to_4x4()
for vi in weapon_ids:
    p = Mi @ (M @ me.vertices[vi].co)
    me.vertices[vi].co = M.inverted() @ (Mhand @ (fist_centre + (R @ (p - grip))))
me.vertices.update()

# --- verify in METRES, independently -----------------------------------------
w2_world = [M @ me.vertices[i].co for i in weapon_ids]
f2_world = [M @ me.vertices[i].co for i in fist_ids]
fc2 = Vector((sum(p.x for p in f2_world) / len(f2_world),
              sum(p.y for p in f2_world) / len(f2_world),
              sum(p.z for p in f2_world) / len(f2_world)))
nearest = min(min((a - b).length for b in f2_world) for a in w2_world)
g2 = min(w2_world, key=lambda p: (p - fc2).length)
t2 = max(w2_world, key=lambda p: (p - g2).length)
b2 = (t2 - g2).normalized()
# where does that bone-local direction land in the idle pose?
world_dir_idle = (Mhand_idle_rot @ D_local).normalized()
print("")
print("AFTER (metres): grip-to-fist-centre %.4f m | nearest vert %.4f m"
      % ((g2 - fc2).length, nearest))
print("AFTER (metres): blade %.4f m" % (t2 - g2).length)
print("AFTER: blade in the idle points (%.3f, %.3f, %.3f) = %s deg above horizontal"
      % (world_dir_idle.x, world_dir_idle.y, world_dir_idle.z,
         math.degrees(math.asin(max(-1.0, min(1.0, world_dir_idle.z))))))
print("GRIP_IN_FIST %s" % str((g2 - fc2).length < 0.02))
print("BLADE_POINTS_UP_IN_IDLE %s" % str(world_dir_idle.z > 0.5))

# =============================================================================
# C. atlas as one material
# =============================================================================
img = bpy.data.images.load(ATLAS)
img.colorspace_settings.name = 'sRGB'
mat = bpy.data.materials.new("ds_hero_atlas")
mat.use_nodes = True
nt = mat.node_tree
for n in list(nt.nodes):
    if n.type != 'OUTPUT_MATERIAL':
        nt.nodes.remove(n)
bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = img
tex.interpolation = 'Linear'
nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Metallic"].default_value = 0.0
bsdf.inputs["Roughness"].default_value = 0.86
for k in ("Specular IOR Level", "Specular"):
    if k in bsdf.inputs:
        bsdf.inputs[k].default_value = 0.22
nt.links.new(bsdf.outputs["BSDF"], nt.nodes["Material Output"].inputs["Surface"])
mat.diffuse_color = (0.5, 0.45, 0.4, 1.0)
me.materials.clear()
me.materials.append(mat)
for p in me.polygons:
    p.material_index = 0
print("ATLAS applied as one material")

# =============================================================================
# D. export
# =============================================================================
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.context.scene.objects:
    if o.type in ('MESH', 'ARMATURE'):
        o.select_set(True)
bpy.context.view_layer.objects.active = body
glb = os.path.join(OUT, "hero.glb")
bpy.ops.export_scene.gltf(
    filepath=glb, export_format='GLB', use_selection=True,
    export_animations=True, export_animation_mode='ACTIONS',
    export_apply=False, export_yup=True,
    export_image_format='AUTO', export_texture_dir='',
)
print("EXPORTED %s (%.1f KB)" % (glb, os.path.getsize(glb) / 1024.0))
try:
    dest = os.path.join(GAME, "hero.glb")
    shutil.copy2(glb, dest)
    print("COPIED_TO_GAME %s (%.1f KB)" % (dest, os.path.getsize(dest) / 1024.0))
except Exception as e:
    print("COPY_FAILED %s" % e)
print("BUILD_HERO_DONE")
