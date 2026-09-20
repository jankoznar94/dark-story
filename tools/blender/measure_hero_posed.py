# Dark Story - measure the DELIVERED hero POSED in Rig|Sword_Idle, BODY ONLY.
# WHY posed: this rig's REST pose has the arms HORIZONTAL (a T-pose), so rest-pose
# proportions cannot be compared with a standing reference.
# WHY Blender: --headless Godot cannot apply an animation.
# WHY the sword is excluded explicitly: the atlas pass collapsed the mesh to ONE
# material, so material_index==1 no longer identifies the weapon, and the atlas
# unwrap split the mesh into 1060 islands so connectivity cannot either. The rule
# that survives is the old one - verts dominated by DEF-hand.R that are more than
# 0.12 m from the hand's own centroid are the weapon, not the hand.
# The LEFT arm gives arm length for the same reason: the sword is bound to
# DEF-hand.R.
#
# Run: blender.exe -b --factory-startup -P tools/blender/measure_hero_posed.py

import os

import bpy
from mathutils import Vector

REPO = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg"
SRC = os.path.join(REPO, "models", "hero.glb")
CLIP = "Rig|Sword_Idle"
FRAME = 10

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images,
              bpy.data.cameras, bpy.data.lights):
    for item in list(block):
        try:
            block.remove(item)
        except Exception:
            pass

bpy.ops.import_scene.gltf(filepath=SRC)

arm = mesh = None
for o in bpy.context.scene.objects:
    if o.type == 'ARMATURE':
        arm = o
    if o.type == 'MESH' and o.parent is arm:
        mesh = o

if arm.animation_data is None:
    arm.animation_data_create()
arm.animation_data.action = [a for a in bpy.data.actions if a.name == CLIP][0]
bpy.context.scene.frame_set(FRAME)
bpy.context.view_layer.update()
print("POSED %s frame %d" % (CLIP, FRAME))

deps = bpy.context.evaluated_depsgraph_get()
me = mesh.evaluated_get(deps).to_mesh()
MW = mesh.matrix_world
co = [MW @ v.co for v in me.vertices]

gname = {g.index: g.name for g in mesh.vertex_groups}

# ---- split the hand.R group into HAND vs WEAPON by distance from its centroid --
hand_r = [v.index for v in mesh.data.vertices
          if v.groups and gname.get(max(v.groups, key=lambda g: g.weight).group) == "DEF-hand.R"]
hc = sum((co[i] for i in hand_r), Vector()) / len(hand_r)
hand_set = {i for i in hand_r if (co[i] - hc).length <= 0.12}
weapon_set = {i for i in hand_r if (co[i] - hc).length > 0.12}
print("DEF-hand.R dominant verts=%d  -> HAND %d  WEAPON %d" %
      (len(hand_r), len(hand_set), len(weapon_set)))
if weapon_set:
    ws = [co[i] for i in weapon_set]
    print("  weapon span=%.3f m  (a real hand is ~0.13 m across, so a big number here is the weapon)"
          % max((a-b).length for a in ws for b in ws))

body_idx = [i for i in range(len(co)) if i not in weapon_set]
bz = [co[i].z for i in body_idx]
GROUND, TOP = min(bz), max(bz)
H = TOP - GROUND
print("BODY BOUNDS  ground=%.4f  top=%.4f  HEIGHT=%.4f m  (%d of %d verts)"
      % (GROUND, TOP, H, len(body_idx), len(co)))

groups = {}
for i in body_idx:
    v = mesh.data.vertices[i]
    if v.groups:
        groups.setdefault(gname.get(max(v.groups, key=lambda g: g.weight).group), []).append(co[i])


def ext(name):
    pts = groups.get(name)
    if not pts:
        return None
    zs = [p.z for p in pts]
    return dict(n=len(pts), zmin=min(zs), zmax=max(zs), zc=sum(zs)/len(zs),
                c=sum(pts, Vector())/len(pts))


X = lambda name: [p.x for p in groups[name]]


def frac(z):
    return (z - GROUND) / H


head, neck, hips = ext("DEF-head"), ext("DEF-neck"), ext("DEF-hips")
thigh, shin, foot = ext("DEF-thigh.L"), ext("DEF-shin.L"), ext("DEF-foot.L")
uaL, faL, haL = ext("DEF-upper_arm.L"), ext("DEF-forearm.L"), ext("DEF-hand.L")
ftip = ext("DEF-f_middle.03.L")

hh = head["zmax"] - head["zmin"]
print("")
print("HEAD     top %.3f  chin %.3f  length=%.3f m -> %.2f heads tall  head/H=%.3f"
      % (head["zmax"], head["zmin"], hh, H/hh, hh/H))
print("NECK     centroid z=%.3f (%.3f H)" % (neck["zc"], frac(neck["zc"])))
sh = Vector((max(X("DEF-upper_arm.L")), uaL["c"].y, uaL["zmax"]))
span = max(X("DEF-upper_arm.R")) - min(X("DEF-upper_arm.L"))
print("SHOULDER joint z=%.3f (%.3f H)   biacromial span=%.3f m (%.3f H)"
      % (uaL["zmax"], frac(uaL["zmax"]), span, span/H))
print("WRIST    z=%.3f (%.3f H)    FINGERTIP z=%.3f (%.3f H)"
      % (haL["zc"], frac(haL["zc"]), ftip["zmin"], frac(ftip["zmin"])))
print("ARM.L    shoulder->wrist     %.3f m (%.3f H)" % ((haL["c"]-sh).length, (haL["c"]-sh).length/H))
print("         shoulder->fingertip %.3f m (%.3f H)" % ((ftip["c"]-sh).length, (ftip["c"]-sh).length/H))
print("CROTCH   hips zmin=%.3f (%.3f H)   thigh top=%.3f (%.3f H)"
      % (hips["zmin"], frac(hips["zmin"]), thigh["zmax"], frac(thigh["zmax"])))
print("KNEE     z=%.3f (%.3f H)    ANKLE z=%.3f (%.3f H)"
      % (shin["zmax"], frac(shin["zmax"]), foot["zmax"], frac(foot["zmax"])))
print("")
print("---- TABLE, as fraction of total height (for comparison with a reference image)")
for k, v in (("head length", hh), ("shoulder line", uaL["zmax"]-GROUND),
             ("shoulder span", span), ("arm to wrist", (haL["c"]-sh).length),
             ("crotch", hips["zmin"]-GROUND), ("knee", shin["zmax"]-GROUND),
             ("ankle", foot["zmax"]-GROUND)):
    print("  %-16s %.3f H   (%.2f heads)" % (k, v/H, v/hh))
