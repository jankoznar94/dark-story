# Dark Story - render the WEAPON ALONE (material_index == 1) from the pre-atlas
# source, four orthographic views, with a 1 cm grid of axial ticks.
#
# WHY: the axial profiles kept disagreeing about whether the sword has a grip at all,
# because a low-poly blade is two long quads - so a vertex histogram shows empty
# bands where there IS surface, and an edge-sampled profile shows surface where the
# faces are only corner-to-corner. Neither number settles "is there a handle". A
# picture of the object alone settles it instantly, for the human too.
#
# Run: blender.exe -b --factory-startup -P tools/blender/render_sword_alone.py
import math
import os
import shutil

import bpy
import numpy as np
from mathutils import Vector

SRC = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_uv\in.glb"
OUT = r"C:\Users\Martin Fabian\AppData\Local\Temp\ds_sword_alone"
WSL = "/tmp/sword_alone"
for d in (OUT, WSL):
    os.makedirs(d, exist_ok=True)

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images,
              bpy.data.cameras, bpy.data.lights):
    for it in list(block):
        try:
            block.remove(it)
        except Exception:
            pass

bpy.ops.import_scene.gltf(filepath=SRC)
body = next(x for x in bpy.context.scene.objects if x.type == 'MESH' and len(x.vertex_groups) > 20)

polys = [p for p in body.data.polygons if p.material_index == 1]
idx = sorted({v for p in polys for v in p.vertices})
print("weapon verts %d  polys %d" % (len(idx), len(polys)))
W = [body.matrix_world @ v.co for v in body.data.vertices]

# ---- axis from the longest vertex pair --------------------------------------
P = np.array([[W[i].x, W[i].y, W[i].z] for i in idx])
d = ((P[:, None, :] - P[None, :, :]) ** 2).sum(2) ** 0.5
i0, i1 = np.unravel_index(np.argmax(d), d.shape)
ax = (P[i1] - P[i0]) / np.linalg.norm(P[i1] - P[i0])
C = P.mean(0)
along = (P - C) @ ax
if along[i0] > along[i1]:
    ax, along = -ax, -along
    i0, i1 = i1, i0
print("axis len %.4f m; t of the two extreme verts: %.4f / %.4f" % (d[i0, i1], along.min(), along.max()))

# ---- per-polygon table, the decisive structure ------------------------------
print("")
print("EACH POLYGON: centroid t, area, and its vertices' t values")
print("  #   t_cen   area[m2]  n  vertex t values")
rows = []
for p in polys:
    ts = [float(along[idx.index(v)] if v in idx else 0.0) for v in p.vertices]
    tc = sum(ts) / len(ts)
    rows.append((tc, p.area, len(p.vertices), sorted(ts)))
for k, (tc, ar, n, ts) in enumerate(sorted(rows)):
    print("  %3d  %+7.3f  %7.5f  %d  %s" % (k, tc, ar, n, ["%+.3f" % t for t in ts]))
print("")
print("total area %.4f m2   span %.4f m" % (sum(r[1] for r in rows), along.max() - along.min()))

# ---- isolate the weapon into its own object, keep everything, hide the rest --
body.data.materials.clear()
m = bpy.data.materials.new("sw")
m.use_nodes = True
em = m.node_tree.nodes.new("ShaderNodeEmission")
em.inputs[0].default_value = (0.85, 0.83, 0.78, 1.0)
m.node_tree.links.new(em.outputs[0], m.node_tree.nodes["Material Output"].inputs["Surface"])
body.data.materials.append(m)

# ticks: a small sphere every 5 cm along the axis, alternating size so the scale shows
tick_mat = bpy.data.materials.new("tick")
tick_mat.use_nodes = True
tem = tick_mat.node_tree.nodes.new("ShaderNodeEmission")
tem.inputs[0].default_value = (0.8, 0.1, 0.1, 1.0)
tick_mat.node_tree.links.new(tem.outputs[0], tick_mat.node_tree.nodes["Material Output"].inputs["Surface"])
for k in range(int((along.max() - along.min()) / 0.05) + 1):
    t = along.min() + k * 0.05
    pos = C + ax * t
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.006 if k % 2 else 0.010,
                                         location=(pos[0], pos[1], pos[2]), segments=12, ring_count=6)
    ob = bpy.context.active_object
    ob.data.materials.clear()
    ob.data.materials.append(tick_mat)

sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'FLAT'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.background_type = 'VIEWPORT'
sc.display.shading.background_color = (0.07, 0.07, 0.08)
sc.render.resolution_x = 1100
sc.render.resolution_y = 460
sc.view_settings.view_transform = 'Standard'
cd = bpy.data.cameras.new("c")
cd.type = 'ORTHO'
cam = bpy.data.objects.new("c", cd)
sc.collection.objects.link(cam)
sc.camera = cam
mid = Vector((C[0], C[1], C[2]))


def shot(az, el, scale, name):
    rr, ee = math.radians(az), math.radians(el)
    cam.location = mid + Vector((math.cos(ee) * math.sin(rr), -math.cos(ee) * math.cos(rr),
                                 math.sin(ee))) * 4.0
    dd = (mid - cam.location).normalized()
    cam.rotation_mode = 'QUATERNION'
    cam.rotation_quaternion = (-dd).to_track_quat('Z', 'Y')
    cd.ortho_scale = scale
    sc.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)
    print("SHOT %s" % name)


# align the camera with the blade: azimuth of the axis in the XY plane
baz = math.degrees(math.atan2(ax[0], ax[1]))
print("blade azimuth %.1f deg" % baz)
shot(baz + 90, 0, 1.05, "sword_broadside.png")
shot(baz, 0, 1.05, "sword_edge_on.png")
shot(baz + 90, 25, 1.05, "sword_broadside_hi.png")
shot(baz + 45, 15, 1.05, "sword_iso.png")
for f in os.listdir(OUT):
    shutil.copy2(os.path.join(OUT, f), os.path.join(WSL, f))
print("COPIED_TO %s" % WSL)
