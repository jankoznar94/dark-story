# Dark Story - measure the animation FACTS the game code needs, on the shipped
# models/hero.glb (not on the source GLB), because that is what the game plays.
#
# Two things are measured, both so the code stops guessing:
#
#  1. GROUND SPEED PER LOCOMOTION CLIP. The walk clip was retimed once already
#     (0.963 m per cycle, toe-contact method). Run/Sprint need the same number or
#     the feet will slide at the new speed.
#
#  2. THE CONTACT FRAME OF EACH SWORD CLIP. The hit currently fires at
#     windup+active = 0.42 s on a 0.75 s swing, which Jan reports as too fast /
#     not readable. The right anchor is where the blade actually passes through
#     the front, so that is measured here too.
#
# Run: blender.exe -b --factory-startup -P measure_gait.py

import bpy
from mathutils import Vector

GAME = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg\models\hero.glb"

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images):
    for item in list(block):
        try:
            block.remove(item)
        except Exception:
            pass

bpy.ops.import_scene.gltf(filepath=GAME)

arm = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE'][0]
body = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
deps = bpy.context.evaluated_depsgraph_get()

print("BODY=%s verts=%d  arm=%s bones=%d" % (body.name, len(body.data.vertices),
                                              arm.name, len(arm.data.bones)))
scl = body.matrix_world.to_scale()
print("body.matrix_world scale = %.3f (this rig is 100x; absolute lengths need it)"
      % scl.x)


def act(name):
    a = bpy.data.actions.get(name)
    if a is None:
        for x in bpy.data.actions:
            if x.name.replace("_Loop", "") == name.replace("_Loop", ""):
                return x
    return a


def bone_world(bone_name, frame):
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    pb = arm.pose.bones.get(bone_name)
    if pb is None:
        return None
    return arm.matrix_world @ pb.matrix @ Vector((0.0, 0.0, 0.0))


def sample(clip, bone_names, step=1):
    a = act(clip)
    if a is None:
        print("  MISSING ACTION %s" % clip)
        return []
    arm.animation_data_create()
    arm.animation_data.action = a
    # Blender 5: slots
    try:
        if hasattr(arm.animation_data, "action_slot") and len(a.slots):
            arm.animation_data.action_slot = a.slots[0]
    except Exception as e:
        print("  slot assign skipped:", e)
    f0, f1 = int(a.frame_range[0]), int(a.frame_range[1])
    rows = []
    for f in range(f0, f1 + 1, step):
        rec = {"frame": f}
        for bn in bone_names:
            p = bone_world(bn, f)
            rec[bn] = p
        rows.append(rec)
    return rows


def clip_stats(clip):
    a = act(clip)
    if a is None:
        return None
    f0, f1 = int(a.frame_range[0]), int(a.frame_range[1])
    frames = f1 - f0
    return {"len_s": frames / 24.0, "frames": frames, "f0": f0, "f1": f1}


print("")
print("=== 1. LOCOMOTION GROUND SPEED (toe-contact) ===")
for clip in ["Rig|Walk_Loop", "Rig|Jog_Fwd_Loop", "Rig|Sprint_Loop"]:
    st = clip_stats(clip)
    if st is None:
        print("%-20s  MISSING" % clip)
        continue
    rows = sample(clip, ["DEF-toe.L", "DEF-toe.R"])
    if not rows:
        continue
    # distance travelled per step = how far the foot moves forward while it is
    # planted (its lowest point). Two feet -> two steps per cycle.
    total = 0.0
    detail = []
    for key in ["DEF-toe.L", "DEF-toe.R"]:
        zs = [r[key].z for r in rows]
        zmin = min(zs)
        contact = [r for r in rows if r[key].z < zmin + 0.03]
        if len(contact) < 2:
            detail.append("%s: no contact window" % key)
            continue
        # contiguous window: use the first run of contact frames
        ys = [r[key].y for r in contact]
        step_len = abs(max(ys) - min(ys))
        total += step_len
        detail.append("%s: %d contact frames, step %.3f m" % (key, len(contact), step_len))
    speed = total / st["len_s"] if st["len_s"] > 0 else 0.0
    print("%-20s len=%.3fs frames=%d  cycle=%.3f m  -> %.3f m/s at 1x"
          % (clip, st["len_s"], st["frames"], total, speed))
    for d in detail:
        print("      ", d)

print("")
print("=== 2. SWORD CLIP CONTACT FRAME ===")
# blade tip = the vertex bound to DEF-hand.R that is FARTHEST from that bone, in
# world metres. (The shipped GLB has one material, so material_index cannot pick
# the weapon out any more - the docs say so.)
hand_rest = arm.data.bones["DEF-hand.R"].head_local.copy()
best = None
best_d = -1.0
for v in body.data.vertices:
    if len(v.groups) == 0:
        continue
    g = max(v.groups, key=lambda x: x.weight)
    if body.vertex_groups[g.group].name != "DEF-hand.R":
        continue
    d = (v.co - hand_rest).length
    if d > best_d:
        best_d = d
        best = v.index
print("blade tip vertex index %s, %.4f m from the hand bone head (mesh units)"
      % (best, best_d))


def tip_world(frame):
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    p = ev.matrix_world @ me.vertices[best].co
    ev.to_mesh_clear()
    return p


for clip in ["Rig|Sword_Attack", "Rig|Sword_Attack_RM"]:
    st = clip_stats(clip)
    if st is None:
        print("%-20s MISSING" % clip)
        continue
    arm.animation_data_create()
    a = act(clip)
    arm.animation_data.action = a
    try:
        if hasattr(arm.animation_data, "action_slot") and len(a.slots):
            arm.animation_data.action_slot = a.slots[0]
    except Exception:
        pass
    print("-- %s  (%.3f s, %d frames)" % (clip, st["len_s"], st["frames"]))
    prev = None
    rows = []
    for f in range(st["f0"], st["f1"] + 1):
        p = tip_world(f)
        hand = bone_world("DEF-hand.R", f)
        # direction of the blade as a bearing around Z, 0 = front (+Y in Blender)
        d = p - hand
        import math
        bearing = math.degrees(math.atan2(d.x, d.y))
        speed = 0.0 if prev is None else (p - prev).length
        rows.append((f, p, bearing, speed))
        prev = p
    tmax = max(rows, key=lambda r: r[3])
    # frontmost bearing closest to 0 within the first 70 % of the clip: that is
    # the moment the blade sweeps through the target in front of the character
    first = [r for r in rows if r[0] <= st["f0"] + int(st["frames"] * 0.7)]
    front = min(first, key=lambda r: abs(r[2]))
    t = lambda r: (r[0] - st["f0"]) / 24.0
    print("   peak tip speed  at frame %3d  t=%.2fs (%.0f%% of clip)"
          % (tmax[0], t(tmax), 100.0 * (tmax[0] - st["f0"]) / max(1, st["frames"])))
    print("   frontmost blade at frame %3d  t=%.2fs (%.0f%% of clip)  bearing %.1f deg"
          % (front[0], t(front), 100.0 * (front[0] - st["f0"]) / max(1, st["frames"]),
             front[2]))
    for f, p, bearing, speed in rows:
        if f % 2 == 0:
            print("     f%02d t=%.3f  tip=(%.3f %.3f %.3f)  bearing %+7.1f  tipv %.3f"
                  % (f, (f - st["f0"]) / 24.0, p.x, p.y, p.z, bearing, speed))

print("DONE")
