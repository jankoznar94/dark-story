# Dark Story - DETERMINISTIC head projection, v2 (order fixed).
#
# v1 bug: pack_islands was run AFTER the head was mapped analytically, and it
# repacked the head island too - the mapping was destroyed (corr analytic vs
# actual u dropped to 0.198). Order must be:
#   1. pack everything (body + head) normally
#   2. reslot the BODY into the upper region
#   3. THEN overwrite the HEAD loops with the analytic cylindrical mapping,
#      into a strip nothing else can occupy
# so the head mapping is the last thing written.

import collections
import json
import math
import os

import bmesh
import bpy

SRC = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_uv\in.glb"
OUT = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_uv"
os.makedirs(OUT, exist_ok=True)

HEAD_V1 = 0.25          # head owns v 0.00..0.25, body v 0.25..1.00
BODY_V0 = 0.25
# Isotropic head mapping. Measured head cross-section is 0.213 m wide x 0.248 m
# deep -> ellipse perimeter C = 0.7252 m, and the head strip gives 256 px for
# 0.3413 m (750 px/m). The u wrap spans KU of the 1024 px atlas, so for the
# horizontal density to equal 750 px/m:  KU = C * (256/H) / 1024 = 0.5312.
# NOTE: an earlier value of 0.3564 came from dividing the FULL 1024 px by the
# covered metres, which is wrong (the wrap only uses KU*1024 px) and left the
# head 1.49x anisotropic, so a pasted face came out 0.234 m wide instead of
# 0.16 m. Verify anisotropy as (256/H) / (KU*1024/C), not 1024/C.
KU = 0.5312

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
me = body.data
M = body.matrix_world

VG2ZONE = [
    (("DEF-head", "DEF-neck"), "head"),
    (("DEF-spine", "DEF-hips"), "torso"),
    (("DEF-shoulder",), "shoulder"),
    (("DEF-upper_arm", "DEF-forearm"), "arm"),
    (("DEF-hand", "DEF-f_", "DEF-thumb"), "hand"),
    (("DEF-thigh",), "thigh"),
    (("DEF-shin",), "shin"),
    (("DEF-foot", "DEF-toe"), "foot"),
]


def zone_of(p) -> str:
    if p.material_index == 1:
        return "weapon"
    tally = {}
    for vi in p.vertices:
        for ge in me.vertices[vi].groups:
            tally[ge.group] = tally.get(ge.group, 0.0) + ge.weight
    if not tally:
        return "torso"
    name = body.vertex_groups[max(tally.items(), key=lambda kv: kv[1])[0]].name
    for pref, z in VG2ZONE:
        if name.startswith(pref):
            return z
    return "torso"


zones = [zone_of(p) for p in me.polygons]
print("ZONES", dict(collections.Counter(zones)))

# single usable uv layer
layers = [l.name for l in me.uv_layers]


def spread(name):
    d = me.uv_layers[name].data
    us = [q.uv[0] for q in d]
    return max(us) - min(us) if us else 0.0


keep = max(layers, key=spread)
for l in list(me.uv_layers):
    if l.name != keep:
        me.uv_layers.remove(l)
me.uv_layers.active_index = 0
print("UV_LAYER", me.uv_layers[0].name, "from", layers)

head_idx = set(i for i, z in enumerate(zones) if z == "head")
rest_idx = [i for i in range(len(me.polygons)) if i not in head_idx]

# ---- 1. unwrap + pack EVERYTHING (head included, just to get it placed) -----
bpy.context.view_layer.objects.active = body
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.002,
                         correct_aspect=True, scale_to_bounds=False)
bpy.ops.uv.pack_islands(rotate=False, margin=0.002, scale=True)
print("PACKED_ALL")
bpy.ops.object.mode_set(mode='OBJECT')

# ---- 2. reslot the body into the upper region --------------------------------
uvd = me.uv_layers[0].data
for i in rest_idx:
    for li in me.polygons[i].loop_indices:
        u, v = uvd[li].uv
        uvd[li].uv = (u, BODY_V0 + v * (1.0 - BODY_V0))
print("BODY_RESLOTTED")

# ---- 3. head LAST: analytic cylindrical map into the reserved strip ----------
hp = [M @ me.vertices[v].co for i in head_idx for v in me.polygons[i].vertices]
hz0 = min(p.z for p in hp)
hz1 = max(p.z for p in hp)
print("HEAD_Z %.4f..%.4f" % (hz0, hz1))

for i in head_idx:
    for li in me.polygons[i].loop_indices:
        p = M @ me.vertices[me.loops[li].vertex_index].co
        ang = math.atan2(p.x, -p.y)              # 0 in front, +pi/2 at +X
        # iso: shrink the angular span so texels stay square (see KU above)
        u = 0.5 + ang / (2.0 * math.pi) * KU
        v = (p.z - hz0) / max(1e-6, hz1 - hz0)
        uvd[li].uv = (u, v * HEAD_V1)
print("HEAD_MAPPED_LAST polys=%d  (u span %.3f)" % (len(head_idx), KU))

# ---- dump --------------------------------------------------------------------
polys = []
for i, p in enumerate(me.polygons):
    c = M @ p.center
    n = (M.to_3x3() @ p.normal).normalized()
    polys.append({
        "z": zones[i], "m": p.material_index,
        "c": [round(c.x, 4), round(c.y, 4), round(c.z, 4)],
        "n": [round(n.x, 3), round(n.y, 3), round(n.z, 3)],
        "uv": [[round(uvd[li].uv[0], 5), round(uvd[li].uv[1], 5)]
               for li in p.loop_indices],
    })
with open(os.path.join(OUT, "atlas_src2.json"), "w") as f:
    json.dump({"uv_layer": me.uv_layers[0].name, "polys": polys}, f)

hu = [q[0] for p in polys if p["z"] == "head" for q in p["uv"]]
hv = [q[1] for p in polys if p["z"] == "head" for q in p["uv"]]
bu = [q[0] for p in polys if p["z"] != "head" for q in p["uv"]]
bv = [q[1] for p in polys if p["z"] != "head" for q in p["uv"]]
print("HEAD_UV u %.4f..%.4f v %.4f..%.4f" % (min(hu), max(hu), min(hv), max(hv)))
print("BODY_UV u %.4f..%.4f v %.4f..%.4f" % (min(bu), max(bu), min(bv), max(bv)))

# ---- export ------------------------------------------------------------------
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.context.scene.objects:
    if o.type in ('MESH', 'ARMATURE'):
        o.select_set(True)
bpy.context.view_layer.objects.active = body
glb = os.path.join(OUT, "unwrapped.glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=True,
                          export_animations=True, export_animation_mode='ACTIONS',
                          export_apply=False, export_yup=True)
print("EXPORTED %s (%.1f KB)" % (glb, os.path.getsize(glb) / 1024.0))
print("REMAP_DONE")
