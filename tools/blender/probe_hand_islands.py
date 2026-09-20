# Dark Story - HAND-REGION STRUCTURE: every connected ISLAND of the body mesh
# that touches the right hand or its fingers, with its size, extent, dominant
# bones and position relative to the palm.
#
# WHY this and not another distance metric: "the hand and the grip look wrong" is
# a question about what GEOMETRY EXISTS there. Distance probes cannot tell whether
# the handle is a real piece of mesh, whether the sword is one continuous object,
# or whether the fingers are separate pieces at all. Islands answer all three.
#
# Run: blender.exe -b --factory-startup -P tools/blender/probe_hand_islands.py
import json
import os

import bpy
from mathutils import Vector

REPO = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg"
SRC = os.path.join(REPO, "models", "hero.glb")

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images,
              bpy.data.cameras, bpy.data.lights):
    for it in list(block):
        try:
            block.remove(it)
        except Exception:
            pass

bpy.ops.import_scene.gltf(filepath=SRC)
arm = mesh = None
for o in bpy.context.scene.objects:
    if o.type == 'ARMATURE':
        arm = o
    if o.type == 'MESH' and o.parent is arm:
        mesh = o

if arm.animation_data:
    arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.location = (0.0, 0.0, 0.0)
    pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
    pb.rotation_euler = (0.0, 0.0, 0.0)
    pb.scale = (1.0, 1.0, 1.0)
bpy.context.view_layer.update()

mw = mesh.matrix_world
me = mesh.data
co = [mw @ v.co for v in me.vertices]
gname = {g.index: g.name for g in mesh.vertex_groups}
DOM = []
for v in me.vertices:
    DOM.append(gname.get(max(v.groups, key=lambda g: g.weight).group) if v.groups else None)

# ---- union-find over shared edges -------------------------------------------
parent = list(range(len(me.vertices)))


def find(a):
    while parent[a] != a:
        parent[a] = parent[parent[a]]
        a = parent[a]
    return a


def union(a, b):
    ra, rb = find(a), find(b)
    if ra != rb:
        parent[rb] = ra


for p in me.polygons:
    vs = list(p.vertices)
    for k in range(1, len(vs)):
        union(vs[0], vs[k])

isl = {}
for i in range(len(me.vertices)):
    isl.setdefault(find(i), []).append(i)

HANDY = {"DEF-hand.R", "DEF-hand.L"} | {"%s.%s.%s" % (f, k, s) for f in
         ("DEF-thumb", "DEF-f_index", "DEF-f_middle", "DEF-f_ring", "DEF-f_pinky")
         for k in ("01", "02", "03") for s in ("R", "L")}
FOREARM_R = {"DEF-hand.R", "DEF-forearm.R"} | {"%s.%s.R" % (f, k) for f in
              ("DEF-thumb", "DEF-f_index", "DEF-f_middle", "DEF-f_ring", "DEF-f_pinky")
              for k in ("01", "02", "03")}

# palm centre = centroid of verts dominated by DEF-hand.R that are within 0.08 m
hr = [i for i in range(len(co)) if DOM[i] == "DEF-hand.R"]
hc = sum((co[i] for i in hr), Vector()) / len(hr)
hpalm = [i for i in hr if (co[i] - hc).length <= 0.08]
pc = sum((co[i] for i in hpalm), Vector()) / len(hpalm)
print("DEF-hand.R verts %d   palm(<=0.08) %d   palm centre (%.3f, %.3f, %.3f)"
      % (len(hr), len(hpalm), pc.x, pc.y, pc.z))
print("distance of every hand.R vert from that centroid: max %.4f m" %
      max((co[i] - hc).length for i in hr))

print("")
print("ISLANDS (all %d of them); listing any island that contains a right-hand or finger vertex"
      % len(isl))
print("  id    verts  faces   span[m]  dist(palm)  dominant groups (top 3, with counts)   centroid")
rows = []
for root, idxs in isl.items():
    doms = [DOM[i] for i in idxs if DOM[i]]
    if not any(d in FOREARM_R for d in doms):
        continue
    s = set(idxs)
    span = max((co[a] - co[b]).length for a in idxs for b in idxs)
    d = min((co[i] - pc).length for i in idxs)
    c = sum((co[i] for i in idxs), Vector()) / len(idxs)
    faces = sum(1 for p in me.polygons if all(v in s for v in p.vertices))
    cnt = {}
    for dd in doms:
        cnt[dd] = cnt.get(dd, 0) + 1
    top = sorted(cnt.items(), key=lambda kv: -kv[1])[:3]
    rows.append((d, root, idxs, span, c, faces, top))

for d, root, idxs, span, c, faces, top in sorted(rows):
    print("  %-6d %5d  %5d  %7.4f  %9.4f  %-44s (%.3f, %.3f, %.3f)"
          % (root, len(idxs), faces, span, d,
             ", ".join("%s:%d" % t for t in top), c.x, c.y, c.z))

print("")
print("BIG PICTURE: %d islands in the whole mesh, %d touch the right arm/hand"
      % (len(isl), len(rows)))
sizes = sorted((len(v) for v in isl.values()), reverse=True)
print("largest island sizes: %s" % sizes[:12])
hand_verts = sum(r[2].__len__() for r in rows)
print("verts inside hand-touching islands: %d of %d (%.2f %%)"
      % (hand_verts, len(me.vertices), 100.0 * hand_verts / len(me.vertices)))
