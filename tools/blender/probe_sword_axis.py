# Dark Story - AXIAL PROFILE of the welded sword, in the REST pose, with the
# fingertips marked on it. This is the decisive diagnostic for "the grip looks
# wrong": a perpendicular distance alone does not say whether a fingertip is on
# the HANDLE, on the GUARD, or hanging past the pommel.
#
# Prints, per 1 cm slice along the sword's principal axis: the radial spread
# (min / median / max) and the vertex count, so the pommel, handle, guard and
# blade are all visible as structure, plus every fingertip's axial position and
# radial distance. The handle is the long thin run of small radial spread.
#
# Run: blender.exe -b --factory-startup -P tools/blender/probe_sword_axis.py
import math
import os

import bpy
import numpy as np
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

# REST POSE, guaranteed: reset every pose bone, do not trust the import state.
if arm.animation_data:
    arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.location = (0.0, 0.0, 0.0)
    pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
    pb.rotation_euler = (0.0, 0.0, 0.0)
    pb.scale = (1.0, 1.0, 1.0)
bpy.context.view_layer.update()

deps = bpy.context.evaluated_depsgraph_get()
me = mesh.evaluated_get(deps).to_mesh()
MW = mesh.matrix_world
co = [MW @ v.co for v in me.vertices]
gname = {g.index: g.name for g in mesh.vertex_groups}


def dom(i):
    v = mesh.data.vertices[i]
    if not v.groups:
        return None
    return gname.get(max(v.groups, key=lambda g: g.weight).group)


def wmax(i):
    v = mesh.data.vertices[i]
    return max(g.weight for g in v.groups) if v.groups else 0.0


hr = [i for i in range(len(co)) if dom(i) == "DEF-hand.R"]
hc = sum((co[i] for i in hr), Vector()) / len(hr)
hspan = max((co[i] - hc).length for i in hr)
print("DEF-hand.R dominant verts=%d  centroid=(%.3f, %.3f, %.3f)  max dist from centroid %.4f m"
      % (len(hr), hc.x, hc.y, hc.z, hspan))
print("max-weight distribution: " +
      " ".join("%.2f:%d" % (t / 10.0, sum(1 for i in hr if abs(wmax(i) - t / 10.0) < 0.05))
               for t in range(5, 11)))

sword = np.array([[co[i].x, co[i].y, co[i].z] for i in hr if (co[i] - hc).length > 0.12])
print("sword verts=%d  span=%.4f m" % (len(sword),
                                       float(np.linalg.norm(sword.max(0) - sword.min(0)))))
Sc = sword.mean(0)
_, sv, vt = np.linalg.svd(sword - Sc, full_matrices=False)
ax = vt[0]
if ax[2] < 0:
    ax = -ax                       # point the axis "up" (toward +Z) for readability
along = (sword - Sc) @ ax
perp = np.linalg.norm((sword - Sc) - np.outer(along, ax), axis=1)
print("sword axis=(%+.3f, %+.3f, %+.3f)  singular values %s"
      % (ax[0], ax[1], ax[2], [round(float(x), 3) for x in sv]))
print("axial range %.4f .. %.4f  (length %.4f m)"
      % (along.min(), along.max(), along.max() - along.min()))
print("")
print("AXIAL PROFILE   (1 cm slices; a 'handle' is a long run of small radius)")
print("  along[m]   n   r_min   r_med   r_max   what")
bins = np.arange(along.min(), along.max() + 0.01, 0.01)
for k in range(len(bins) - 1):
    sel = (along >= bins[k]) & (along < bins[k + 1])
    if sel.sum() == 0:
        print("   %+7.3f   0      -       -       -   (empty)")
        continue
    r = perp[sel]
    rmed = float(np.median(r))
    tag = ""
    if rmed < 0.035 and (bins[k + 1] - bins[k]) > 0:
        tag = "thin"
    if r.max() > 0.12:
        tag = "WIDE (guard?)"
    print("   %+7.3f  %3d  %6.4f  %6.4f  %6.4f   %s"
          % (bins[k], int(sel.sum()), float(r.min()), rmed, float(r.max()), tag))

print("")
print("FINGERTIPS against that axis (rest pose):")
FINGERS = ["DEF-thumb", "DEF-f_index", "DEF-f_middle", "DEF-f_ring", "DEF-f_pinky"]
pal = np.array([hc.x, hc.y, hc.z])
print("  palm centroid axial = %+.4f" % float((pal - Sc) @ ax))
tips_ax = {}
for f in FINGERS:
    idx = [i for i in range(len(co)) if dom(i) == "%s.03.R" % f]
    c = sum((co[i] for i in idx), Vector()) / len(idx)
    p = np.array([c.x, c.y, c.z])
    a = float((p - Sc) @ ax)
    rad = float(np.linalg.norm((p - Sc) - a * ax))
    # nearest sword vertex along the axis (which slice is the tip over?)
    nearest = int(np.argmin(np.abs(along - a)))
    tips_ax[f] = (a, rad)
    print("  %-14s axial %+.4f  radial %6.4f  -> sword slice at %+.3f has r_med %.4f"
          % (f, a, rad, along[nearest], float(np.median(
              perp[np.abs(along - along[nearest]) < 0.008]))))

# hand/finger geometry size, so "the hand is tiny" is a number too
print("")
for f in FINGERS:
    idx = [i for i in range(len(co)) if dom(i) == "%s.03.R" % f]
    if idx:
        span = max((co[i] - co[j]).length for i in idx for j in idx)
        print("  %-14s .03 verts %d  own span %.4f m" % (f, len(idx), span))
hidx = [i for i in range(len(co)) if dom(i) == "DEF-hand.R" and (co[i] - hc).length <= 0.12]
print("  hand (<=0.12 m from centroid) %d verts  span %.4f m"
      % (len(hidx), max((co[i] - co[j]).length for i in hidx for j in hidx)))
