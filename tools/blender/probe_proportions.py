# Dark Story - hero PROPORTIONS probe (reference comparison).
# Measures per-landmark proportions of the rigged base character in METRES,
# from VERTEX GROUPS (this rig's skeleton is COLLAPSED - bone rest origins all
# sit within a ~0.016 m box, so bone transforms carry no limb lengths).
# Run: blender.exe -b --factory-startup -P tools/blender/probe_proportions.py

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
scale = mw.to_scale()
print("MESH %s  verts=%d  groups=%d  matrix_scale=%.3f" %
      (body.name, len(body.data.vertices), len(body.vertex_groups), scale.x))

# group index -> name
gname = {g.index: g.name for g in body.vertex_groups}

# world-metre vertex positions per group (verts with weight on that group)
gverts = {}
for v in body.data.vertices:
    p = mw @ v.co
    for g in v.groups:
        if g.weight <= 0.0:
            continue
        gverts.setdefault(gname.get(g.group, "?"), []).append((p.x, p.y, p.z))


def span(group):
    pts = gverts.get(group, [])
    if not pts:
        return None
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    zs = [p[2] for p in pts]
    return {
        "n": len(pts),
        "zmin": min(zs), "zmax": max(zs),
        "xmin": min(xs), "xmax": max(xs),
        "zmean": sum(zs) / len(zs),
        "xmean": sum(xs) / len(xs),
        "ymean": sum(ys) / len(ys),
    }


WANT = ["DEF-head", "DEF-neck", "DEF-spine.003", "DEF-spine.002", "DEF-spine.001",
        "DEF-hips", "DEF-shoulder.L", "DEF-shoulder.R",
        "DEF-upper_arm.L", "DEF-upper_arm.R",
        "DEF-forearm.L", "DEF-forearm.R", "DEF-hand.L", "DEF-hand.R",
        "DEF-thigh.L", "DEF-thigh.R", "DEF-shin.L", "DEF-shin.R",
        "DEF-foot.L", "DEF-foot.R", "DEF-toe.L", "DEF-toe.R"]

print("---- GROUPS (world metres)")
stats = {}
for name in WANT:
    s = span(name)
    stats[name] = s
    if s is None:
        print("  %-18s MISSING" % name)
    else:
        print("  %-18s n=%-5d z %.3f..%.3f  x %.3f..%.3f  width=%.3f" %
              (name, s["n"], s["zmin"], s["zmax"], s["xmin"], s["xmax"],
               s["xmax"] - s["xmin"]))

# ---- proportions -------------------------------------------------------------
allz = [p[2] for pts in gverts.values() for p in pts]
allx = [p[0] for pts in gverts.values() for p in pts]
total_h = max(allz) - min(allz)
print("---- TOTAL  height=%.3f m  xrange=%.3f m  ground_z=%.4f" %
      (total_h, max(allx) - min(allx), min(allz)))

head = stats.get("DEF-head")
if head:
    head_h = head["zmax"] - head["zmin"]
    print("HEAD       length=%.3f m  top=%.3f  bottom=%.3f  ->  %.2f heads tall" %
          (head_h, head["zmax"], head["zmin"], total_h / head_h if head_h else 0))
    print("           head/height = %.3f" % (head_h / total_h))

# shoulder span: outermost upper-arm verts, left vs right
ua_l, ua_r = stats.get("DEF-upper_arm.L"), stats.get("DEF-upper_arm.R")
if ua_l and ua_r:
    print("SHOULDER   span=%.3f m  (%.2f x head)   at z=%.3f (%.2f of height)" %
          (ua_r["xmax"] - ua_l["xmin"], (ua_r["xmax"] - ua_l["xmin"]) / head_h,
           (ua_l["zmean"] + ua_r["zmean"]) / 2,
           ((ua_l["zmean"] + ua_r["zmean"]) / 2 - min(allz)) / total_h))

hips = stats.get("DEF-hips")
if hips:
    print("HIPS       z=%.3f  -> leg length %.3f m (%.2f of height)" %
          (hips["zmean"], hips["zmean"] - min(allz),
           (hips["zmean"] - min(allz)) / total_h))

arm = None
if stats.get("DEF-upper_arm.L") and stats.get("DEF-forearm.L") and stats.get("DEF-hand.L"):
    u, f, h = stats["DEF-upper_arm.L"], stats["DEF-forearm.L"], stats["DEF-hand.L"]
    upper = abs(u["zmean"] - f["zmean"])
    fore = abs(f["zmean"] - h["zmean"])
    hand = h["zmax"] - h["zmin"]
    arm = upper + fore + hand
    print("ARM.L      upper~%.3f  fore~%.3f  hand=%.3f  total~%.3f m (%.2f heads)" %
          (upper, fore, hand, arm, arm / head_h if head_h else 0))

th = stats.get("DEF-thigh.L")
sh = stats.get("DEF-shin.L")
if th and sh and hips:
    print("LEG.L      thigh~%.3f  shin~%.3f  ground=%.3f" %
          (abs(th["zmean"] - sh["zmean"]), abs(sh["zmean"] - min(allz)), min(allz)))

print("---- HEAD-UNIT TABLE (everything in head lengths, 1 head = %.3f m)" % head_h)
for label, val in (("total height", total_h),
                   ("shoulder span", (ua_r["xmax"] - ua_l["xmin"]) if ua_l and ua_r else 0),
                   ("arm length", arm or 0),
                   ("leg length", (hips["zmean"] - min(allz)) if hips else 0)):
    print("  %-16s %.2f heads" % (label, val / head_h if head_h else 0))
