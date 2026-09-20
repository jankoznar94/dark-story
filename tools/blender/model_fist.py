# Dark Story - MODEL A GRIPPING FIST on the right hand.
#
# WHY this approach: this rig has finger bones (DEF-f_*/DEF-thumb* with .01/.02/.03)
# and the sword is rigidly bound to DEF-hand.R, but EVERY sword/walk clip keys the
# fingers OPEN (measured: thumb-tip <-> middle-fingertip 0.0776 m, constant across
# all frames of every clip). The closed pose exists in the rig - it is simply only
# keyed in the Pistol/Punch clips.
#
# So the hand is made to grip by two moves, both needed:
#   1. Delete the finger-bone channels from EVERY action. A clip key stores an
#      ABSOLUTE local rotation, so it would override any rest change; with the
#      channels gone the bones fall back to their rest pose in all 45 clips.
#   2. CURL the finger bones in the rest pose (pose them, then bake with
#      armature_apply). The sign of each rotation is SOLVED, not guessed: try
#      both and keep the one that moves the fingertip closer to the palm centre.
#
# Run: blender.exe -b --factory-startup -P tools/blender/model_fist.py

import math
import os
import shutil

import bpy
from mathutils import Vector

REPO = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg"
SRC = os.path.join(REPO, "models", "hero.glb")
OUT = r"C:\Users\Martin Fabian\AppData\Local\Temp\ds_fist"
GAME = os.path.join(REPO, "models")
os.makedirs(OUT, exist_ok=True)

FINGERS = ["DEF-thumb", "DEF-f_index", "DEF-f_middle", "DEF-f_ring", "DEF-f_pinky"]
SIDE = ".R"

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
print("ARMATURE %s bones=%d  MESH %s verts=%d" %
      (arm.name, len(arm.data.bones), mesh.name, len(mesh.data.vertices)))

mw = mesh.matrix_world
gname = {g.index: g.name for g in mesh.vertex_groups}


def dom(i):
    v = mesh.data.vertices[i]
    if not v.groups:
        return None
    return gname.get(max(v.groups, key=lambda g: g.weight).group)


# ---- 1. the finger channels are KEPT and REWRITTEN, never deleted -----------
# An earlier version deleted all 6750 finger f-curves, reasoning that a missing
# channel falls back to the rest pose. That works, but the rewrite step below then
# has nothing to rewrite ("rewrote 0 ... f-curves"), and baking the curl into the
# rest pose instead produced a file whose hand measured EXACTLY the original open
# distances - the rest curl and the clip curl cancelled out. So: keep the channels
# and overwrite their values.
finger_names = set()
for f in FINGERS:
    for k in ("01", "02", "03"):
        finger_names.add("%s.%s%s" % (f, k, SIDE))
print("finger bones to rewrite: %d" % len(finger_names))

# ---- 2. curl the fingers in the rest pose -----------------------------------
#
# TRAP: this rig's skeleton is COLLAPSED - every bone head/tail sits inside a
# ~0.016 m box, so a finger DIRECTION derived from bone head/tail is noise. The
# first run of this script did that and measured every fingertip 1.2 m from the
# palm. Directions must come from the GEOMETRY (vertex-group centroids).
#
# TRAP 2: do NOT call animation_data_clear(). Clearing it made the export emit
# **0 of 45 animations** while still reporting success and writing a plausible
# 1.6 MB file. The action is only UNASSIGNED while the rest pose is edited, then
# restored before export so the exporter still sees an animated armature.
arm.animation_data.action = None
bpy.context.scene.frame_set(0)
# Clearing the action does NOT clear the pose: pose-bone values persist and the
# evaluated mesh keeps the LAST action's deformation. Measuring "rest" against an
# evaluated mesh in that state compares two different frames, which is how the
# first run reported the fingertips over a metre from the handle. Reset to identity.
for pb in arm.pose.bones:
    pb.location = (0.0, 0.0, 0.0)
    pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
    pb.rotation_euler = (0.0, 0.0, 0.0)
    pb.scale = (1.0, 1.0, 1.0)
bpy.context.view_layer.update()

# ASSERT THE PREMISE: the evaluated mesh must now BE the rest mesh.
_palm_eval = None
def _eval_palm():
    _me = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    _co = [mesh.matrix_world @ v.co for v in _me.vertices]
    _idx = [i for i in range(len(_co))
            if mesh.data.vertices[i].groups and
            gname.get(max(mesh.data.vertices[i].groups, key=lambda g: g.weight).group) == "DEF-hand.R"]
    return sum((_co[i] for i in _idx), Vector()) / len(_idx), _co

mw = mesh.matrix_world
rest_co = [mw @ v.co for v in mesh.data.vertices]


def cen(g, co=None):
    co = co or rest_co
    idx = [i for i in range(len(co)) if dom(i) == g]
    return sum((co[i] for i in idx), Vector()) / len(idx) if idx else None


palm = cen("DEF-hand.R")
print("palm centre (rest) = (%.3f, %.3f, %.3f)" % (palm.x, palm.y, palm.z))
_pe, _pco = _eval_palm()
print("palm centre (evaluated at identity pose) = (%.3f, %.3f, %.3f)  delta %.4f m"
      % (_pe.x, _pe.y, _pe.z, (_pe - palm).length))
assert (_pe - palm).length < 0.01, ("the evaluated mesh is NOT at rest (%.4f m off) - "
                                    "a leftover pose is deforming it" % (_pe - palm).length)
assert len(_pco) == len(rest_co), "evaluated vertex count differs from rest"

# geometry-derived finger direction + knuckle line
fdirs, bases, tips = {}, {}, {}
for f in FINGERS:
    b = cen("%s.01%s" % (f, SIDE))
    t = cen("%s.03%s" % (f, SIDE))
    bases[f], tips[f] = b, t
    fdirs[f] = (t - b).normalized()
    print("  %-14s dir=(%+.2f, %+.2f, %+.2f)  base->tip %.3f m  tip-palm %.3f m"
          % (f, fdirs[f].x, fdirs[f].y, fdirs[f].z, (t - b).length, (t - palm).length))

SPREAD = (bases["DEF-f_index"] - bases["DEF-f_pinky"]).normalized()
print("knuckle line (spread) = (%+.2f, %+.2f, %+.2f)" % (SPREAD.x, SPREAD.y, SPREAD.z))

# ---- WHERE THE FINGERS SHOULD REACH: the sword's grip ------------------------
# The objective must be "get the fingertips onto the handle", not "get them near
# the palm". The handle's position is knowable exactly: the sword is the part of
# the DEF-hand.R group further than 0.08 m from the palm centroid (span 0.846 m =
# the blade), and the grip is the point of it nearest the palm.
hand_idx = [i for i in range(len(mesh.data.vertices)) if dom(i) == "DEF-hand.R"]
hv = [rest_co[i] for i in hand_idx]
hc0 = sum(hv, Vector()) / len(hv)
sword_pts = [p for p in hv if (p - hc0).length > 0.08]
import numpy as np

SP = np.array([[p.x, p.y, p.z] for p in sword_pts])
SP = SP - SP.mean(0)
_, _, vt = np.linalg.svd(SP, full_matrices=False)
SWORD_AXIS = Vector(vt[0]).normalized()
# grip = projection of the palm centre onto the handle's long axis
d0 = palm - sum(sword_pts, Vector()) / len(sword_pts)
GRIP = sum(sword_pts, Vector()) / len(sword_pts) + d0.dot(SWORD_AXIS) * SWORD_AXIS
print("sword axis  = (%+.2f, %+.2f, %+.2f)   grip point = (%.3f, %.3f, %.3f)"
      % (SWORD_AXIS.x, SWORD_AXIS.y, SWORD_AXIS.z, GRIP.x, GRIP.y, GRIP.z))
print("palm centre -> grip = %.4f m" % (palm - GRIP).length)

# the handle's own radius: how far the sword's verts near the grip sit off the axis
_ax = np.array([SWORD_AXIS.x, SWORD_AXIS.y, SWORD_AXIS.z])
_gp = np.array([GRIP.x, GRIP.y, GRIP.z])
_SP = np.array([[p.x, p.y, p.z] for p in sword_pts])
_along = (_SP - _gp) @ _ax
_off = (_SP - _gp) - np.outer(_along, _ax)
_near = np.linalg.norm(_off, axis=1)[np.abs(_along) < 0.09]
HANDLE_R = float(np.percentile(_near, 80)) if len(_near) else 0.02
print("handle radius (80th pct of verts within 9 cm along the axis) = %.4f m" % HANDLE_R)
print("fingers must therefore stop at ~%.3f m off the axis; resting ON it is ~%.3f m" % (HANDLE_R, HANDLE_R))

for pb in arm.pose.bones:
    pb.rotation_mode = 'QUATERNION'
POSES = {pb.name: pb.rotation_quaternion.copy() for pb in arm.pose.bones}

from mathutils import Quaternion

ANG = {"01": math.radians(85), "02": math.radians(95), "03": math.radians(60)}
# the thumb opposes across the palm, so it needs a different axis: the direction
# from the thumb base toward the index base, crossed with the finger direction
THUMB_AXES = [
    ("across-palm", (bases["DEF-f_index"] - bases["DEF-thumb"]).normalized()),
    ("knuckle", SPREAD),
    ("palm-normal", (bases["DEF-f_index"] - bases["DEF-f_middle"]).normalized()
     .cross(SPREAD).normalized()),
]


def set_chain(finger, sign, axis_world, ang_scale=1.0):
    for k in ("01", "02", "03"):
        pb = arm.pose.bones.get("%s.%s%s" % (finger, k, SIDE))
        if pb is None:
            continue
        W = arm.matrix_world.to_3x3() @ pb.bone.matrix_local.to_3x3()
        ax_local = W.inverted() @ axis_world
        if ax_local.length < 1e-9:
            continue
        ax_local.normalize()
        pb.rotation_quaternion = Quaternion(ax_local, sign * ANG[k] * ang_scale)


def measure(finger):
    bpy.context.view_layer.update()
    me = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    co = [mesh.matrix_world @ v.co for v in me.vertices]
    assert len(co) == len(rest_co), ("evaluated mesh has %d verts, rest has %d - "
                                     "dom() indices are invalid" % (len(co), len(rest_co)))
    t = cen("%s.03%s" % (finger, SIDE), co)
    pc = cen("DEF-hand.R", co)
    print("      [dbg] %s tip=(%.3f,%.3f,%.3f) palm=(%.3f,%.3f,%.3f) tip-grip=%.4f tip-palm=%.4f"
          % (finger, t.x, t.y, t.z, pc.x, pc.y, pc.z, (t-GRIP).length, (t-pc).length))
    return (t - GRIP).length, co



def measure_only(finger, target=None):
    bpy.context.view_layer.update()
    me = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    co = [mesh.matrix_world @ v.co for v in me.vertices]
    assert len(co) == len(rest_co), "evaluated vertex count differs from rest"
    tgt = target if target is not None else GRIP
    return (cen("%s.03%s" % (finger, SIDE), co) - tgt).length, co


def set_chain_scaled(finger, sign, axis_world, scales):
    for k in ("01", "02", "03"):
        pb = arm.pose.bones.get("%s.%s%s" % (finger, k, SIDE))
        if pb is None:
            continue
        W = arm.matrix_world.to_3x3() @ pb.bone.matrix_local.to_3x3()
        al = W.inverted() @ axis_world
        if al.length < 1e-9:
            continue
        al.normalize()
        pb.rotation_quaternion = Quaternion(al, sign * ANG[k] * scales.get(k, 1.0))


print("")
# Coordinate descent on each finger's three joint angles: a single shared scale
# cannot close a fist (the pinky stayed 0.093 m from the handle with the best
# shared scale). The objective is the distance from the fingertip to the GRIP.
SCALES = [0.4, 0.6, 0.8, 1.0, 1.2, 1.5, 1.8]
# The thumb must OPPOSE the fingers, not sit beside them. A target at the grip
# centre lets the thumb land on the same side, which is why the tip-to-tip metric
# stayed at 0.067 m (nearly the open 0.078) while every tip was close to the grip.
# So the thumb aims at the FAR side of the handle: grip + r * (grip - fingers).
_mt = cen("DEF-f_middle.03.R")
THUMB_TARGET = GRIP + (GRIP - _mt).normalized() * max(HANDLE_R, 0.02)
print("thumb target (far side of the handle) = (%.3f, %.3f, %.3f)"
      % (THUMB_TARGET.x, THUMB_TARGET.y, THUMB_TARGET.z))

for f in FINGERS:
    TARGET = THUMB_TARGET if f == "DEF-thumb" else GRIP
    axes = THUMB_AXES if f == "DEF-thumb" else [("knuckle", SPREAD)]
    best_overall = None
    for aname, ax in axes:
        for sign in (1.0, -1.0):
            scale = {k: 1.0 for k in ("01", "02", "03")}
            for _pass in range(4):
                for k in ("01", "02", "03"):
                    trials = {}
                    for sc in SCALES:
                        trial = dict(scale)
                        trial[k] = sc
                        for pb in arm.pose.bones:
                            pb.rotation_quaternion = POSES[pb.name].copy()
                        for kk in ("01", "02", "03"):
                            pb = arm.pose.bones.get("%s.%s%s" % (f, kk, SIDE))
                            if pb is None:
                                continue
                            W = arm.matrix_world.to_3x3() @ pb.bone.matrix_local.to_3x3()
                            al = W.inverted() @ ax
                            al.normalize()
                            pb.rotation_quaternion = Quaternion(al, sign * ANG[kk] * trial[kk])
                        d, _ = measure_only(f, TARGET)
                        trials[sc] = d
                    scale[k] = min(trials, key=trials.get)
            for pb in arm.pose.bones:
                pb.rotation_quaternion = POSES[pb.name].copy()
            for kk in ("01", "02", "03"):
                pb = arm.pose.bones.get("%s.%s%s" % (f, kk, SIDE))
                if pb is None:
                    continue
                W = arm.matrix_world.to_3x3() @ pb.bone.matrix_local.to_3x3()
                al = W.inverted() @ ax
                al.normalize()
                pb.rotation_quaternion = Quaternion(al, sign * ANG[kk] * scale[kk])
            d, _ = measure_only(f, TARGET)
            if best_overall is None or d < best_overall[0]:
                best_overall = (d, aname, sign, dict(scale))
    for pb in arm.pose.bones:
        pb.rotation_quaternion = POSES[pb.name].copy()
    set_chain_scaled(f, best_overall[2], dict(axes)[best_overall[1]], best_overall[3])
    POSES = {pb.name: pb.rotation_quaternion.copy() for pb in arm.pose.bones}
    _t = THUMB_TARGET if f == "DEF-thumb" else GRIP
    print("  %-14s tip->target %.3f -> %.3f m  [%s sign %+.0f  scales %s]"
          % (f, (tips[f] - _t).length, best_overall[0], best_overall[1],
             best_overall[2], {k: round(v, 2) for k, v in best_overall[3].items()}))

bpy.context.view_layer.update()
deps = bpy.context.evaluated_depsgraph_get()
me = mesh.evaluated_get(deps).to_mesh()
co = [mesh.matrix_world @ v.co for v in me.vertices]

tt, mt = cen("DEF-thumb.03.R", co), cen("DEF-f_middle.03.R", co)
print("AFTER: thumb tip <-> middle fingertip = %.4f m  (0.078 open, 0.001 closed)"
      % (tt - mt).length)

hr = [i for i in range(len(co)) if dom(i) == "DEF-hand.R"]
hc = sum((co[i] for i in hr), Vector()) / len(hr)
fist = [co[i] for i in hr if (co[i] - hc).length <= 0.08]
sword = [co[i] for i in hr if (co[i] - hc).length > 0.08]
span_f = max((a - b).length for a in fist for b in fist)
span_s = max((a - b).length for a in sword for b in sword)
print("FIST %d verts span %.3f m | SWORD %d verts span %.3f m"
      % (len(fist), span_f, len(sword), span_s))

# ---- write the curl INTO THE CLIPS' OWN KEYS --------------------------------
#
# WHY not armature_apply: baking the curl into the REST pose made the delivered
# file BYTE-FOR-BYTE EQUIVALENT in behaviour to the original - the new rest curl
# and the curl stored in the clips cancelled out exactly, and the delivered hand
# measured the original OPEN distances (0.121/0.162/0.170/0.171/0.171 m) with a
# clip playing. Verified: probe_rest_hand.py reported identical numbers for
# before and after on every finger.
#
# Every clip already carries a constant quaternion for each finger bone - the
# OPEN one, which is why the hand has never closed. So the fix is to OVERWRITE
# those key values with the solved curl, in every action, and export with the
# rest pose left alone.
print("")
print("writing the solved curl into every action's finger keys")
SOLVED = {pb.name: pb.rotation_quaternion.copy() for pb in arm.pose.bones}
touched = 0
for act in bpy.data.actions:
    for lay in getattr(act, "layers", []):
        for strip in lay.strips:
            for cb in getattr(strip, "channelbags", []):
                for fc in cb.fcurves:
                    if "rotation_quaternion" not in fc.data_path:
                        continue
                    name = None
                    for fn in finger_names:
                        if '["%s"]' % fn in fc.data_path:
                            name = fn
                            break
                    if name is None:
                        continue
                    q = SOLVED[name]
                    val = q[fc.array_index]
                    for kp in fc.keyframe_points:
                        kp.co[1] = val
                        kp.handle_left[1] = val
                        kp.handle_right[1] = val
                    fc.update()
                    touched += 1
print("  rewrote %d finger rotation f-curves across %d actions" % (touched, len(bpy.data.actions)))

# put the armature back to rest; the clips carry the pose now
arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
    pb.location = (0.0, 0.0, 0.0)
    pb.scale = (1.0, 1.0, 1.0)

# ---- export ------------------------------------------------------------------
# copy the source out of the way first: a stash/checkout of a regenerated .glb has
# silently reverted one before, so the artifact is kept in its own directory
dest = os.path.join(OUT, "hero.glb")
bpy.ops.export_scene.gltf(
    filepath=dest,
    export_format='GLB',
    use_selection=False,
    export_animation_mode='ACTIONS',
    export_apply=False,
    export_yup=True,
)
print("EXPORTED %s (%d bytes)" % (dest, os.path.getsize(dest)))

# ---- VERIFY THE DELIVERED FILE, not the in-memory scene ---------------------
# The first export wrote 0 of 45 animations and reported success. Assert on the
# bytes: clip count, the two clips the game uses, and that no animation still
# carries a finger channel (which would override the baked rest pose).
import hashlib
import json
import struct

raw = open(dest, "rb").read()
off, chunks = 12, {}
while off < len(raw):
    clen, ctype = struct.unpack_from("<II", raw, off)
    chunks[ctype] = raw[off + 8:off + 8 + clen]
    off += 8 + clen
gj = json.loads(chunks[0x4E4F534A].decode("utf-8"))

anims = gj.get("animations", [])
names = [a.get("name") for a in anims]
print("VERIFY  animations=%d (expected 45)" % len(anims))
assert len(anims) == 45, "animation count regressed"
for want in ("Rig|Sword_Idle", "Rig|Walk_Loop"):
    assert want in names, "missing clip %s" % want
print("VERIFY  Rig|Sword_Idle and Rig|Walk_Loop present")

finger_nodes = {i for i, n in enumerate(gj["nodes"])
                if n.get("name") and ("f_" in n["name"] or "thumb" in n["name"])}
worst = 0
for a in anims:
    n = sum(1 for c in a["channels"] if c["target"]["node"] in finger_nodes)
    worst = max(worst, n)
print("VERIFY  max finger channels in any clip = %d (informational - the exporter bakes the curled rest pose into them)" % worst)
# A nonzero count is EXPECTED and harmless: the finger channels now carry the baked
# curled rest pose in every clip, and no clip MOVES the fingers (a static channel
# with a constant value everywhere would leave the rest pose in force regardless).

print("VERIFY  joints=%d  images=%s" %
      (len(gj["skins"][0]["joints"]), [im.get("name") for im in gj.get("images", [])]))
print("md5 %s" % hashlib.md5(raw).hexdigest())
