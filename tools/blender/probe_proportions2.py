# Dark Story - hero PROPORTIONS probe v2, DOMINANT weights.
# v1 took any nonzero weight, so the groups bled into each other (DEF-head came
# out 0.395 m tall on a 1.83 m body). Assign each vertex to its MAX-weight group.
# Run: blender.exe -b --factory-startup -P tools/blender/probe_proportions2.py

import bpy

SRC = r"\\wsl.localhost\Ubuntu\home\martin_fabian\tools\kaykit\candidates\quat_base_character.glb"

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images):
    for item in list(block):
        try:
            block.remove(item)
        except Exception:
            pass

bpy.ops.import_scene.gltf(filepath=SRC)

body = None
for o in bpy.context.scene.objects:
    if o.type == 'MESH' and len(o.vertex_groups) > 20:
        body = o
if body is None:
    raise SystemExit("no skinned mesh found")

mw = body.matrix_world
gname = {g.index: g.name for g in body.vertex_groups}
print("MESH %s verts=%d groups=%d scale=%.1f" %
      (body.name, len(body.data.vertices), len(body.vertex_groups), mw.to_scale().x))

groups = {}
for v in body.data.vertices:
    if not v.groups:
        continue
    best = max(v.groups, key=lambda g: g.weight)
    p = mw @ v.co
    groups.setdefault(gname.get(best.group, "?"), []).append((p.x, p.y, p.z))


def stat(n):
    pts = groups.get(n)
    if not pts:
        return None
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]; zs = [p[2] for p in pts]
    return dict(n=len(pts), zmin=min(zs), zmax=max(zs), xmin=min(xs), xmax=max(xs),
                ymin=min(ys), ymax=max(ys),
                z=sum(zs)/len(zs), x=sum(xs)/len(xs), y=sum(ys)/len(ys),
                len_=(max(zs)-min(zs)))


print("---- DOMINANT-GROUP SPANS (world metres)")
for name in sorted(groups):
    s = stat(name)
    print("  %-18s n=%-5d z %.3f..%.3f  x %.3f..%.3f  y %.3f..%.3f" %
          (name, s["n"], s["zmin"], s["zmax"], s["xmin"], s["xmax"], s["ymin"], s["ymax"]))

allz = [p[2] for pts in groups.values() for p in pts]
allx = [p[0] for pts in groups.values() for p in pts]
allo = [p[1] for pts in groups.values() for p in pts]
H = max(allz) - min(allz)
GROUND = min(allz)
print("---- TOTAL height=%.3f  span_x=%.3f  span_y=%.3f  ground=%.4f" %
      (H, max(allx)-min(allx), max(allo)-min(allo), GROUND))

# --- landmark z values from group centroids / extents -------------------------
head = stat("DEF-head")
neck = stat("DEF-neck")
hips = stat("DEF-hips")
thighL = stat("DEF-thigh.L"); shinL = stat("DEF-shin.L"); footL = stat("DEF-foot.L")
ua = stat("DEF-upper_arm.L"); fa = stat("DEF-forearm.L"); hd = stat("DEF-hand.L")
t3 = stat("DEF-spine.003"); t1 = stat("DEF-spine.001")

head_h = head["zmax"] - head["zmin"]
chin = head["zmin"]
print("HEAD   top=%.3f  chin=%.3f  height=%.3f m  -> %.2f heads tall, head/H=%.3f" %
      (head["zmax"], chin, head_h, H/head_h, head_h/H))

# shoulder joint x: innermost upper-arm vertex
print("SHOULDER joint x(L)=%.3f  arm reaches x=%.3f  -> arm length %.3f m (%.2f heads)" %
      (ua["xmax"], hd["xmin"], abs(hd["xmin"] - ua["xmax"]) + (ua["xmax"]-ua["xmin"]),
       (abs(hd["xmin"] - ua["xmax"]) + (ua["xmax"]-ua["xmin"]))/head_h))

# shoulder span from deltoid outer edges = outer x of upper arms at their top
print("SPAN   shoulders (upper arm outer edges)=%.3f m (%.2f heads, %.3f H)" %
      (ua["xmax"] - ua["xmin"] if False else abs(stat("DEF-upper_arm.R")["xmax"] - ua["xmin"]),
       abs(stat("DEF-upper_arm.R")["xmax"] - ua["xmin"])/head_h,
       abs(stat("DEF-upper_arm.R")["xmax"] - ua["xmin"])/H))

print("WAIST  hips group z %.3f..%.3f  centroid %.3f (%.3f H)  width=%.3f m" %
      (hips["zmin"], hips["zmax"], hips["z"], (hips["z"]-GROUND)/H,
       hips["xmax"]-hips["xmin"]))
print("CHEST  t3 z %.3f..%.3f  width=%.3f m  depth(y)=%.3f m" %
      (t3["zmin"], t3["zmax"], t3["xmax"]-t3["xmin"], t3["ymax"]-t3["ymin"]))
print("LOWER  t1 z %.3f..%.3f  width=%.3f m" % (t1["zmin"], t1["zmax"], t1["xmax"]-t1["xmin"]))
print("LEG    thigh z %.3f..%.3f  shin z %.3f..%.3f  foot z %.3f..%.3f" %
      (thighL["zmin"], thighL["zmax"], shinL["zmin"], shinL["zmax"],
       footL["zmin"], footL["zmax"]))
print("       crotch(hip joint)=%.3f (%.3f H)   thigh=%.3f  shin=%.3f  ankle=%.3f" %
      (hips["zmin"], (hips["zmin"]-GROUND)/H,
       hips["zmin"]-shinL["zmax"], shinL["zmax"]-footL["zmax"], footL["zmax"]-GROUND))
print("FOOT   length(y)=%.3f  width(x)=%.3f" %
      (footL["ymax"]-footL["ymin"], footL["xmax"]-footL["xmin"]))
print("---- FRACTION OF HEIGHT TABLE")
for k, v in (("head", head_h), ("neck", stat("DEF-neck")["zmax"]-stat("DEF-neck")["zmin"]),
             ("shoulder->crotch", stat("DEF-upper_arm.L")["z"]-hips["zmin"]),
             ("crotch->ground", hips["zmin"]-GROUND),
             ("arm", abs(hd["xmin"]-ua["xmax"]) + (ua["xmax"]-ua["xmin"]))):
    print("  %-18s %.3f H  = %.2f heads" % (k, v/H, v/head_h))

# ---- rest-pose arm direction check (T-pose?) --------------------------------
print("REST ARM  upper_arm.L x %.3f..%.3f  z %.3f..%.3f  -> %s" %
      (ua["xmin"], ua["xmax"], ua["zmin"], ua["zmax"],
       "HORIZONTAL (T-pose)" if (ua["xmax"]-ua["xmin"]) > (ua["zmax"]-ua["zmin"]) else "vertical"))
