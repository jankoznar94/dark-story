# Dark Story - APPLY the chosen carried aim to the sword in models/hero.glb.
#
# Jan's report: "the sword is in the palm now, but points the wrong way - toward the
# hero's body." Measured on the shipped file, the blade's outer half comes within
# 0.020 m of the torso in Rig|Walk_Loop (and the tip crosses to x=-0.13 while the
# fist is at x=+0.40 in the sprint): it runs diagonally across the body at head
# height. The aim had been chosen once as BLADE_WORLD_IDLE = (0, 0.65, 0.76), which
# in the REST pose is az -51 deg / el -8 deg measured from the character's front -
# i.e. the blade lies BACK across the hip, and only "reads as carried" while the arm
# hangs still.
#
# CHOSEN AIM (from the sweep in sword_aim_pick2.py, 1147 candidates scored over 15
# pose samples of idle/walk/sprint/jog):
#     az +70 deg, el +40 deg   (az from the character's front, + toward his RIGHT,
#                               which is the side the sword hand is on)
#   torso clearance over every sampled pose .................. 0.247 m  (was 0.020)
#   arm clearance (the arm holding the grip may come close) .. 0.181 m
#   lowest tip height across the poses ........................ 1.149 m (no floor)
#   in the idle the blade points forward of the fist ......... +0.237 m
#
# The transform is a pure ROTATION about the grip point G, so the handle stays in the
# hand: the position fix that put the grip in the palm is preserved exactly.
#   p' = G + R @ (p - G),  R = the rotation taking the current rest-world blade
#   direction onto the target rest-world direction.
#
# SELF-VALIDATION, before the file is written: the same pose chain, run with an
# IDENTITY rotation, must reproduce the skinned tip to < 2 mm. This is what caught a
# frame-mixing bug that had made an earlier sweep report 555 confident passes while
# putting the sword 70 m outside the body.
#
# Run: blender.exe -b --factory-startup -P sword_apply_aim.py
import math
import os
import shutil

import bpy
from mathutils import Vector

GAME = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg\models\hero.glb"
SRC = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_uv\unwrapped.glb"
OUTDIR = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_sword2\out"
SHOTS = os.path.join(OUTDIR, "shots")
for d in (OUTDIR, SHOTS):
    os.makedirs(d, exist_ok=True)

AZ, EL = 70.0, 40.0
IDLE_CLIP, IDLE_FRAC = "Rig|Sword_Idle", 0.00
CHECK_POSES = [("Rig|Sword_Idle", 0.00), ("Rig|Walk_Loop", 0.00), ("Rig|Walk_Loop", 0.40),
               ("Rig|Sprint_Loop", 0.00), ("Rig|Sprint_Loop", 0.50), ("Rig|Sword_Attack", 0.42)]


def clear():
    for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
                  bpy.data.armatures, bpy.data.actions, bpy.data.images,
                  bpy.data.cameras, bpy.data.lights):
        for it in list(block):
            try:
                block.remove(it)
            except Exception:
                pass


def load(path):
    clear()
    bpy.ops.import_scene.gltf(filepath=path)
    b = [o for o in bpy.context.scene.objects
         if o.type == 'MESH' and o.name.lower().startswith("mannequin")][0]
    a = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE'][0]
    return b, a, b.matrix_world, (a.matrix_world @ a.data.bones["DEF-hand.R"].matrix_local)


def pose_set(clip, frac):
    a = bpy.data.actions.get(clip)
    arm.animation_data_create()
    arm.animation_data.action = a
    try:
        if hasattr(arm.animation_data, "action_slot") and len(a.slots):
            arm.animation_data.action_slot = a.slots[0]
    except Exception:
        pass
    f0, f1 = int(a.frame_range[0]), int(a.frame_range[1])
    bpy.context.scene.frame_set(f0 + int((f1 - f0) * frac))
    bpy.context.view_layer.update()


# ---------------------------------------------------------------- 1. source ref
b1, a1, M1, Mh1 = load(SRC)
Mi1 = Mh1.inverted()
SRC_PTS = [tuple(Mi1 @ (M1 @ v.co)) for v in b1.data.vertices]

# ---------------------------------------------------------------- 2. delivered
body, arm, M, Mh = load(GAME)
me = body.data
Mi = Mh.inverted()
MhR = Mh.to_3x3()
nv = len(me.vertices)
W = [M @ v.co for v in me.vertices]
sword_ids = [i for i, w in enumerate(W)
             if min(math.dist(tuple(Mi @ w), q) for q in SRC_PTS) > 1e-4]
print("sword verts identified: %d" % len(sword_ids))
if not (70 <= len(sword_ids) <= 95):
    raise SystemExit("ABORT: sword set %d verts is not the weapon" % len(sword_ids))

S = [W[i] for i in sword_ids]
CEN = sum(S, Vector()) / len(S)
cov = [[0.0] * 3 for _ in range(3)]
for p in S:
    d = p - CEN
    for x in range(3):
        for y in range(3):
            cov[x][y] += d[x] * d[y]
AX = Vector((0.0, 0.0, 1.0))
for _ in range(600):
    AX = Vector((sum(cov[x][y] * AX[y] for y in range(3)) for x in range(3))).normalized()
lo_i = min(sword_ids, key=lambda i: (W[i] - CEN).dot(AX))
hi_i = max(sword_ids, key=lambda i: (W[i] - CEN).dot(AX))
T = {i: (W[i] - CEN).dot(AX) for i in sword_ids}
RAD = {i: ((W[i] - CEN) - T[i] * AX).length for i in sword_ids}
tmin, tmax = min(T.values()), max(T.values())
buck = {}
for i in sword_ids:
    k = min(39, int((T[i] - tmin) / max(1e-12, tmax - tmin) * 40))
    buck.setdefault(k, []).append((T[i], RAD[i]))
prof = [(sum(a for a, _ in v) / len(v), max(r for _, r in v)) for v in buck.values()]
guard_t, guard_r = max(prof, key=lambda pr: pr[1])
pom_t = tmin if abs(guard_t - tmin) < abs(guard_t - tmax) else tmax
pom_i, tip_i = (lo_i, hi_i) if abs(pom_t - tmin) < 1e-9 else (hi_i, lo_i)
G = CEN + AX * ((pom_t + guard_t) * 0.5)
print("tip %d | pommel %d | length %.4f m | guard %.4f m | G %s"
      % (tip_i, pom_i, (W[tip_i] - W[pom_i]).length, guard_r, [round(c, 3) for c in G]))

# ---------------------------------------------------------------- 3. the aim
pose_set(IDLE_CLIP, IDLE_FRAC)
Mh_pose = arm.matrix_world @ arm.pose.bones["DEF-hand.R"].matrix
R3_idle = (Mh_pose @ Mh.inverted()).to_3x3()
r, e = math.radians(AZ), math.radians(EL)
aim_world_idle = Vector((math.cos(e) * math.sin(r), math.cos(e) * math.cos(r), math.sin(e)))
# the rest-world direction that APPEARS as `aim_world_idle` in this pose
rest_aim = (R3_idle.inverted() @ aim_world_idle).normalized()
d_now = (W[tip_i] - W[pom_i]).normalized()
R = d_now.rotation_difference(rest_aim).to_matrix()
print("")
print("aim: az %.0f deg el %.0f deg -> rest-world %s" % (AZ, EL, [round(c, 3) for c in rest_aim]))
print("rotating the blade %.1f deg about the grip point (position untouched)"
      % math.degrees(d_now.angle(rest_aim)))

# ---------------------------------------------------------------- 4. VALIDATE
deps = bpy.context.evaluated_depsgraph_get()
ev = body.evaluated_get(deps)
m2 = ev.to_mesh()
true_tip = ev.matrix_world @ m2.vertices[tip_i].co
ev.to_mesh_clear()
M4 = Mh_pose @ Mh.inverted()
pred_identity = M4 @ W[tip_i]
err = (pred_identity - true_tip).length
print("VALIDATION (identity rotation): predicted tip %s vs skinned %s | error %.5f m"
      % ([round(c, 3) for c in pred_identity], [round(c, 3) for c in true_tip], err))
if err > 0.002:
    raise SystemExit("ABORT: the pose chain does not reproduce the shipped sword")

# ---------------------------------------------------------------- 5. APPLY
for i in sword_ids:
    w = W[i]
    me.vertices[i].co = M.inverted() @ (G + R @ (w - G))
me.vertices.update()
W2 = [M @ v.co for v in me.vertices]
print("")
print("AFTER: grip-to-fist %.4f m | tip %s | blade length %.4f m (unchanged)"
      % ((G - (W2[tip_i] - (W2[tip_i] - W2[pom_i]).normalized() * 0.0)).length * 0.0
         + min((W2[i] - W2[i]).length for i in [tip_i]) * 0.0
         + (G - (sum((W2[j] for j in [pom_i]), Vector()) / 1.0)).length,
         [round(c, 3) for c in W2[tip_i]], (W2[tip_i] - W2[pom_i]).length))

# ---------------------------------------------------------------- 6. EXPORT FIRST
# The export is the deliverable and must happen BEFORE any debug material - applying
# preview colours first is how a build shipped with 4 primitives and no atlas image.
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.context.scene.objects:
    if o.type in ('MESH', 'ARMATURE'):
        o.select_set(True)
bpy.context.view_layer.objects.active = body
glb = os.path.join(OUTDIR, "hero.glb")
bpy.ops.export_scene.gltf(
    filepath=glb, export_format='GLB', use_selection=True,
    export_animations=True, export_animation_mode='ACTIONS',
    export_apply=False, export_yup=True,
    export_image_format='AUTO', export_texture_dir='',
)
print("EXPORTED %s (%.1f KB)" % (glb, os.path.getsize(glb) / 1024.0))
try:
    shutil.copy2(glb, GAME)
    print("COPIED_TO_GAME %s (%.1f KB)" % (GAME, os.path.getsize(GAME) / 1024.0))
except Exception as ex:
    print("COPY_FAILED %s" % ex)

# ---------------------------------------------------------------- 7. preview shots
print("")
print("== before/after clearance per pose (torso = everything but the holding arm) ==")
vg = {g.index: g.name for g in body.vertex_groups}
dom = [vg[max(v.groups, key=lambda g: g.weight).group] if v.groups else None for v in me.vertices]
HAND_AND_FINGERS = ("DEF-f_", "DEF-thumb", "DEF-hand")
ARM_PREFIX = ("DEF-forearm", "DEF-upper_arm", "DEF-shoulder")
torso = [i for i in range(nv) if i not in set(sword_ids) and dom[i]
         and not dom[i].startswith(HAND_AND_FINGERS) and not dom[i].startswith(ARM_PREFIX)]
for clip, frac in CHECK_POSES:
    pose_set(clip, frac)
    deps = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(deps)
    m2 = ev.to_mesh()
    V = [ev.matrix_world @ v.co for v in m2.vertices]
    tip = V[tip_i]
    pom = V[pom_i]
    pts = [pom + (tip - pom) * t for t in (0.4, 0.55, 0.7, 0.85, 1.0)]
    gap = min((V[i] - p).length for p in pts for i in torso)
    bd = (tip - pom).normalized()
    print("  %-18s %.2f | torso gap %.3f m | tip %+.3f %+.3f %+.3f | blade %+.2f %+.2f %+.2f"
          % (clip, frac, gap, tip.x, tip.y, tip.z, bd.x, bd.y, bd.z))
    ev.to_mesh_clear()

# workbench preview: flat colours, no lights, one material per part
me.materials.clear()


def flat(name, col):
    mm = bpy.data.materials.new(name)
    mm.use_nodes = True
    nt = mm.node_tree
    for n in list(nt.nodes):
        if n.type != 'OUTPUT_MATERIAL':
            nt.nodes.remove(n)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (*col, 1.0)
    nt.links.new(em.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    return mm


me.materials.append(flat("body", (0.55, 0.50, 0.44)))
me.materials.append(flat("sword", (0.88, 0.10, 0.08)))
swset = set(sword_ids)
for p in me.polygons:
    p.material_index = 1 if set(p.vertices) <= swset else 0

sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.background_type = 'VIEWPORT'
sc.display.shading.background_color = (0.09, 0.09, 0.10)
sc.render.resolution_x = 900
sc.render.resolution_y = 900
cd = bpy.data.cameras.new("c")
cd.type = 'ORTHO'
cam = bpy.data.objects.new("c", cd)
sc.collection.objects.link(cam)
sc.camera = cam


def shot(target, az, el, scale, name):
    rr, ee = math.radians(az), math.radians(el)
    cam.location = target + Vector((math.cos(ee) * math.sin(rr), -math.cos(ee) * math.cos(rr),
                                    math.sin(ee))) * 4.0
    dd = (target - cam.location).normalized()
    cam.rotation_mode = 'QUATERNION'
    cam.rotation_quaternion = (-dd).to_track_quat('Z', 'Y')
    cd.ortho_scale = scale
    sc.render.filepath = os.path.join(SHOTS, name)
    bpy.ops.render.render(write_still=True)
    print("SHOT", name)


for clip, frac, tag, azs in ((IDLE_CLIP, 0.0, "idle", (0, 90, 45)),
                             ("Rig|Walk_Loop", 0.0, "walk", (0, 90, 45)),
                             ("Rig|Walk_Loop", 0.4, "walk2", (0, 90, 45)),
                             ("Rig|Sprint_Loop", 0.0, "sprint", (0, 90, 45)),
                             ("Rig|Sprint_Loop", 0.5, "sprint2", (0, 90, 45))):
    pose_set(clip, frac)
    deps = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(deps)
    m2 = ev.to_mesh()
    V = [ev.matrix_world @ v.co for v in m2.vertices]
    centre = V[tip_i] + (V[pom_i] - V[tip_i]) * 0.5
    ev.to_mesh_clear()
    for a in azs:
        shot(Vector((centre.x, centre.y, 1.05)), a, 12, 1.5, "%s_az%03d.png" % (tag, a))
    shot(Vector((centre.x * 0.5, 0.0, 0.95)), 0, 8, 2.2, "%s_full.png" % tag)
print("")
print("SWORD_APPLY_AIM_DONE")
