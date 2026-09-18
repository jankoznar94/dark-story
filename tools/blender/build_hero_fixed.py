# Dark Story - ONE pass: fix the head projection AND re-orient the welded sword,
# then apply the atlas. Replaces the earlier multi-step chain whose intermediate
# files were the source of the space conversions going wrong.
#
# Inputs (all reproducible from git):
#   in.glb          = models/hero.glb at commit ff0618f (md5 01d39a0ee09f57...),
#                     the pre-atlas model. Its weapon is material_index 1.
#   hero_atlas.png  = the 1024x1024 sheet generated for that unwrap.
# Output: fixed hero.glb with one material, the face on the FRONT, and the blade
# running along the hand so it reads as a held sword.
#
# ---- the two bugs, both measured on the shipped file -------------------------
# 1. FACE ON THE BACK. Head projection used u = 0.5 + atan2(x,-y)/(2pi)*KU. The
#    character's front is +Y (toes at y +0.098..+0.206), so the front point
#    (x=0,y=+R) gave atan2(0,-R)=pi -> u=0.5+KU/2 = the far edge of the strip,
#    while the face is painted at u=0.5. Exactly 180 deg off.
#    Fix: u = 0.5 - atan2(x, y)/(2pi)*KU  -> front 0.5, seam at the back, and
#    NOT mirrored (the subject's own right, +X, lands below 0.5, which is where a
#    front-view portrait wants it). Covered u span is still KU, so the SAME atlas
#    fits and does not need regenerating.
# 2. SWORD HANGS POINT-DOWN OUT OF THE FIST. It is welded correctly (100% on
#    DEF-hand.R, 0.0000 m from the fist) but measured ~60 deg off the hand bone's
#    axis, hanging ~0.8 m down beside the leg -> reads as a slung rifle.
#    Fix: rotate the weapon in the HAND BONE's local space about its grip so the
#    blade lies along the bone (+Y, wrist->fingers). Rigid binding to one bone
#    makes this safe: no re-posing, no re-skinning, no animation edits.
#
# Run: blender.exe -b --factory-startup -P build_hero_fixed.py
import collections
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

KU = 0.5312          # head strip width; must match the atlas layout
HEAD_V1 = 0.25       # head owns atlas v 0.00..0.25

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
# A. FIX 1 - head projection
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
print("HEAD polys %d of %d" % (len(head_idx), len(me.polygons)))

uvd = me.uv_layers[0].data
hp = [M @ me.vertices[v].co for i in head_idx for v in me.polygons[i].vertices]
hz0 = min(p.z for p in hp)
hz1 = max(p.z for p in hp)
print("HEAD_Z %.4f..%.4f" % (hz0, hz1))

old_u = [uvd[li].uv[0] for i in head_idx for li in me.polygons[i].loop_indices]
for i in head_idx:
    for li in me.polygons[i].loop_indices:
        p = M @ me.vertices[me.loops[li].vertex_index].co
        ang = math.atan2(p.x, p.y)              # 0 at the front (+Y), pi/2 at +X
        u = 0.5 - ang / (2.0 * math.pi) * KU    # front -> 0.5, not mirrored
        v = (p.z - hz0) / max(1e-6, hz1 - hz0)
        uvd[li].uv = (u, v * HEAD_V1)
new_u = [uvd[li].uv[0] for i in head_idx for li in me.polygons[i].loop_indices]
print("HEAD u OLD %.4f..%.4f  ->  NEW %.4f..%.4f" % (min(old_u), max(old_u),
                                                    min(new_u), max(new_u)))
face_y = []
for i in head_idx:
    for li in me.polygons[i].loop_indices:
        if 0.44 < uvd[li].uv[0] < 0.56:
            face_y.append((M @ me.vertices[me.loops[li].vertex_index].co).y)
if face_y:
    mean_y = sum(face_y) / len(face_y)
    print("FACE patch mean Y %+.4f (+Y is the character's front)" % mean_y)
    print("FACE_ON_FRONT %s" % str(mean_y > 0.02))

# =============================================================================
# B. FIX 2 - sword orientation
# =============================================================================
weapon_ids = set()
for p in me.polygons:
    if p.material_index == 1:
        for v in p.vertices:
            weapon_ids.add(v)
weapon_ids = sorted(weapon_ids)
print("WEAPON verts %d (material_index 1)" % len(weapon_ids))

# rigid-binding proof: every weapon vert is 100% on DEF-hand.R
bad = 0
for vi in weapon_ids:
    gs = [(vg[ge.group], ge.weight) for ge in me.vertices[vi].groups]
    if len(gs) != 1 or gs[0][0] != "DEF-hand.R" or gs[0][1] < 0.99:
        bad += 1
print("WEAPON verts NOT 100%% on DEF-hand.R: %d (must be 0)" % bad)

hand = arm.data.bones["DEF-hand.R"]
Mhand = arm.matrix_world @ hand.matrix_local
Mhand_inv = Mhand.inverted()
TARGET = Vector((0.0, 1.0, 0.0))

# grip = weapon vertex nearest the nearest fist vertex, all in bone space
fist_ids = []
wset = set(weapon_ids)
for vi in range(len(me.vertices)):
    if vi in wset:
        continue
    for ge in me.vertices[vi].groups:
        nm = vg[ge.group]
        if ge.weight > 0.5 and nm.endswith(".R") and (
                nm.startswith("DEF-hand") or nm.startswith("DEF-f_")
                or nm.startswith("DEF-thumb")):
            fist_ids.append(vi)
            break


def to_bone(co):
    return Mhand_inv @ (M @ co)


def to_raw(p):
    return M.inverted() @ (Mhand @ p)


w_bone = [to_bone(me.vertices[vi].co) for vi in weapon_ids]
f_bone = [to_bone(me.vertices[vi].co) for vi in fist_ids]
print("FIST verts %d" % len(fist_ids))
grip_i = min(range(len(w_bone)),
             key=lambda i: min((w_bone[i] - f).length for f in f_bone))
grip = w_bone[grip_i]
tip = max(w_bone, key=lambda p: (p - grip).length)
blade = (tip - grip)
print("blade length %.4f m | grip is %.4f m from the nearest fist vert"
      % (blade.length, min((grip - f).length for f in f_bone)))
print("blade vs hand bone +Y BEFORE %.1f deg" % math.degrees(blade.normalized().angle(TARGET)))

R1 = blade.normalized().rotation_difference(TARGET).to_matrix().to_4x4()
backwards = (R1 @ blade.normalized()).dot(TARGET) < 0.0
perp = TARGET.cross(Vector((0.0, 0.0, 1.0)))
if perp.length < 1e-6:
    perp = TARGET.cross(Vector((1.0, 0.0, 0.0)))
perp.normalize()
R = (Matrix.Rotation(math.pi, 4, perp) if backwards else Matrix.Identity(4)) @ R1
print("rotating the blade %.1f deg about the grip%s"
      % (math.degrees(blade.normalized().angle(TARGET)),
         " plus a 180 deg flip so the point leads" if backwards else ""))

for vi in weapon_ids:
    p = to_bone(me.vertices[vi].co)
    me.vertices[vi].co = to_raw(grip + (R @ (p - grip)))
me.vertices.update()

w2 = [to_bone(me.vertices[vi].co) for vi in weapon_ids]
grip2 = min(w2, key=lambda p: min((p - f).length for f in f_bone))
tip2 = max(w2, key=lambda p: (p - grip2).length)
blade2 = (tip2 - grip2).normalized()
print("grip moved %.6f m | blade %.4f m" % ((grip2 - grip).length, (tip2 - grip2).length))
print("blade vs hand bone +Y AFTER %.1f deg (signed %+.4f)"
      % (math.degrees(blade2.angle(TARGET)), blade2.dot(TARGET)))
print("nearest weapon-to-fist AFTER %.6f m" % min((grip2 - f).length for f in f_bone))
print("BLADE_EXTENDS_HAND %s" % str(blade2.dot(TARGET) > 0.99))

# =============================================================================
# C. apply the atlas as one material
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
print("ATLAS applied as one material, atlas=%s" % os.path.basename(ATLAS))

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
