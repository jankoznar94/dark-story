# Verify the delivered hero.glb by EXACT identification: the weapon's 80 vertices
# are known in the source (material_index 1), and rigid binding to a single bone
# means the exporter preserves their BONE-LOCAL coordinates exactly. So rotate the
# source positions by the same R the build applied and match them one-to-one in the
# delivered file. That both identifies the weapon unambiguously and proves the
# rotation landed.
#
# This replaces two earlier attempts that were invalid:
#   * comparing bind-space mesh verts against POSED bone transforms (mixed frames)
#   * clustering "verts exclusively on DEF-hand.R" in the delivered file, where the
#     export splits the blade into 4-vert islands, so only a 0.54 m fragment was
#     measured and the gap read 0.62 m
import math

import bpy
from mathutils import Matrix, Vector

TMP = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_uv"
IN = TMP + r"\in.glb"
DELIVERED = TMP + r"\fixed\hero.glb"


def clear():
    for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
                  bpy.data.armatures, bpy.data.actions, bpy.data.images):
        for it in list(block):
            try:
                block.remove(it)
            except Exception:
                pass


def load(path):
    clear()
    bpy.ops.import_scene.gltf(filepath=path)
    body = [o for o in bpy.context.scene.objects
            if o.type == 'MESH' and o.name.lower().startswith("mannequin")][0]
    arm = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE'][0]
    return body, arm


# ---- source weapon, in bone-local space ---------------------------------------
body, arm = load(IN)
me = body.data
M = body.matrix_world
wl = set()
for p in me.polygons:
    if p.material_index == 1:
        for v in p.vertices:
            wl.add(v)
wl = sorted(wl)
hand = arm.data.bones["DEF-hand.R"]
Mhand = arm.matrix_world @ hand.matrix_local
Mh_inv = Mhand.inverted()
src_bone = [Mh_inv @ (M @ me.vertices[i].co) for i in wl]
print("SOURCE weapon verts %d, extent in bone space %s m"
      % (len(src_bone),
         [round(c, 4) for c in (Vector((max(v.x for v in src_bone) - min(v.x for v in src_bone),
                                        max(v.y for v in src_bone) - min(v.y for v in src_bone),
                                        max(v.z for v in src_bone) - min(v.z for v in src_bone))))]))

# ---- the same R the build applied ---------------------------------------------
# grip = weapon vert nearest the fist surface; recomputed identically here
vg = {g.index: g.name for g in body.vertex_groups}
fist = []
for vi in range(len(me.vertices)):
    if vi in set(wl):
        continue
    for ge in me.vertices[vi].groups:
        nm = vg[ge.group]
        if ge.weight > 0.5 and nm.endswith(".R") and (nm.startswith("DEF-hand")
                                                      or nm.startswith("DEF-f_")
                                                      or nm.startswith("DEF-thumb")):
            fist.append(Mh_inv @ (M @ me.vertices[vi].co))
            break
grip_i = min(range(len(src_bone)),
             key=lambda i: min((src_bone[i] - f).length for f in fist))
grip = src_bone[grip_i]
tip = max(src_bone, key=lambda p: (p - grip).length)
TARGET = Vector((0.0, 1.0, 0.0))
blade_before = (tip - grip).normalized()
R1 = blade_before.rotation_difference(TARGET).to_matrix().to_4x4()
backwards = (R1 @ blade_before).dot(TARGET) < 0.0
perp = TARGET.cross(Vector((0.0, 0.0, 1.0)))
if perp.length < 1e-6:
    perp = TARGET.cross(Vector((1.0, 0.0, 0.0)))
perp.normalize()
R = (Matrix.Rotation(math.pi, 4, perp) if backwards else Matrix.Identity(4)) @ R1
print("blade vs +Y BEFORE %.1f deg | flip applied: %s"
      % (math.degrees(blade_before.angle(TARGET)), backwards))
expected = [grip + (R @ (p - grip)) for p in src_bone]

# ---- match in the delivered file ---------------------------------------------
body2, arm2 = load(DELIVERED)
me2 = body2.data
M2 = body2.matrix_world
hand2 = arm2.data.bones["DEF-hand.R"]
Mhand2 = arm2.matrix_world @ hand2.matrix_local
Mh2_inv = Mhand2.inverted()
print("DELIVERED verts %d, matrices %d, animations %d"
      % (len(me2.vertices), len(me2.materials), len(bpy.data.actions)))
print("delivered hand.R matrix matches source: %s"
      % str(all(abs(Mhand[i][j] - Mhand2[i][j]) < 1e-4 for i in range(4) for j in range(4))))

delivered_bone = [Mh2_inv @ (M2 @ v.co) for v in me2.vertices]
matched = []
worst = 0.0
for i, exp in enumerate(expected):
    d = [(db - exp).length for db in delivered_bone]
    j = min(range(len(d)), key=lambda k: d[k])
    worst = max(worst, d[j])
    matched.append(j)
uniq = sorted(set(matched))
print("MATCHED %d of %d expected positions -> %d unique delivered verts, worst "
      "residual %.7f m" % (len(matched), len(expected), len(uniq), worst))
print("EXACT_IDENTIFICATION %s" % str(worst < 1e-4 and len(uniq) == len(expected)))

if worst < 1e-2:
    wb = [delivered_bone[j] for j in uniq]
    # grip in the delivered file = vert nearest the fist surface
    f_bone = []
    wset2 = set(uniq)
    for vi in range(len(me2.vertices)):
        if vi in wset2:
            continue
        for ge in me2.vertices[vi].groups:
            nm = vg.get(ge.group, "")
            if ge.weight > 0.5 and nm.endswith(".R") and (nm.startswith("DEF-hand")
                                                          or nm.startswith("DEF-f_")
                                                          or nm.startswith("DEF-thumb")):
                f_bone.append(delivered_bone[vi])
                break
    g2 = min(wb, key=lambda p: min((p - f).length for f in f_bone))
    t2 = max(wb, key=lambda p: (p - g2).length)
    blade2 = (t2 - g2).normalized()
    print("DELIVERED: blade length %.4f m" % (t2 - g2).length)
    print("DELIVERED: grip is %.6f m from the nearest fist vert"
          % min((g2 - f).length for f in f_bone))
    print("DELIVERED: blade vs hand bone +Y %.2f deg (signed %+.5f)"
          % (math.degrees(blade2.angle(TARGET)), blade2.dot(TARGET)))
    print("DELIVERED: blade points from the wrist toward the fingers: %s"
          % str(blade2.dot(TARGET) > 0.99))
    # vertical behaviour, relative to the hand, in bone space
    print("DELIVERED: in bone space the blade runs %s"
          % ("along the hand (blade extends the arm)"
             if abs(blade2.y) > 0.99 else "NOT along the hand"))
print("EXACT_VERIFY_DONE")
