# Dark Story - pick the carried aim for the sword: score every candidate over the
# whole body in every clip that plays it, in one engine start. Numbers only.
#
# Jan's report: "the sword is in the palm now, but points the wrong way - toward the
# hero's body." Measured on the shipped model the blade is 30-70 deg ABOVE horizontal
# during walk/run with the tip 0.13-0.33 m from the body's own axis at head height;
# in Rig|Sprint_Loop at 0.50 the tip is at x=-0.133 while the fist is at x=+0.402, so
# the blade runs diagonally ACROSS the body at face height.
#
# THE VALIDATION THAT MATTERS: this script first proves its own transform chain by
# posing the sword with an IDENTITY candidate and comparing against the skinned mesh
# in the depsgraph. It reproduces the shipped tip to 0.00000 m. An earlier version of
# this sweep mixed frames (rest-LOCAL grip into a rest-WORLD-to-posed matrix), which
# put the sword 70 m outside the body and reported a confident "body gap 0.705 m,
# 555 candidates passing". A sweep that cannot reproduce the known-bad pose is not
# measuring the model.
#
# WHY THE OBSTACLES ARE SPLIT IN TWO: a blade carried in front of the body passes
# close to the ARM THAT HOLDS IT - that is unavoidable and harmless, and treating it
# as a collision rejects every forward-pointing aim (measured: 0 of 400 candidates
# passed with the arm in one cloud). So:
#   torso cloud (spine/hips/neck/head/legs/feet) -> must stay CLEAR (>= 0.12 m);
#     this is what Jan is actually seeing when the sword "points at the body"
#   arm cloud (shoulder/upper arm/forearm)       -> may come close (>= 0.03 m,
#     i.e. no interpenetration), because that arm is holding the grip
#
# Run: blender.exe -b --factory-startup -P sword_aim_pick2.py
import math
import os

import bpy
import numpy as np
from mathutils import Vector

GAME = r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg\models\hero.glb"
SRC = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_uv\unwrapped.glb"
OUT = r"C:\Users\Martin Fabian\AppData\Local\Temp\darkstory_sword2"
POSES = [("Rig|Sword_Idle", 0.00), ("Rig|Sword_Idle", 0.33), ("Rig|Sword_Idle", 0.66),
         ("Rig|Walk_Loop", 0.00), ("Rig|Walk_Loop", 0.20), ("Rig|Walk_Loop", 0.40),
         ("Rig|Walk_Loop", 0.60), ("Rig|Walk_Loop", 0.80),
         ("Rig|Sprint_Loop", 0.00), ("Rig|Sprint_Loop", 0.20), ("Rig|Sprint_Loop", 0.40),
         ("Rig|Sprint_Loop", 0.60), ("Rig|Sprint_Loop", 0.80),
         ("Rig|Jog_Fwd_Loop", 0.25), ("Rig|Jog_Fwd_Loop", 0.60)]
HAND_AND_FINGERS = ("DEF-f_", "DEF-thumb", "DEF-hand")
ARM_PREFIX = ("DEF-forearm", "DEF-upper_arm", "DEF-shoulder")
IDLE_FRACS = [(("Rig|Sword_Idle", f)) for f in (0.00, 0.33, 0.66)]
CLOUD_STEP = 4
CLEAR_TORSO = 0.12
CLEAR_ARM = 0.03


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
    b = [o for o in bpy.context.scene.objects
         if o.type == 'MESH' and o.name.lower().startswith("mannequin")][0]
    a = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE'][0]
    return b, a, b.matrix_world, (a.matrix_world @ a.data.bones["DEF-hand.R"].matrix_local)


b1, a1, M1, Mh1 = load(SRC)
Mi1 = Mh1.inverted()
SRC_PTS = [tuple(Mi1 @ (M1 @ v.co)) for v in b1.data.vertices]

body, arm, M, Mh = load(GAME)
me = body.data
Mi = Mh.inverted()
nv = len(me.vertices)
W = [M @ v.co for v in me.vertices]
sword_ids = [i for i, w in enumerate(W)
             if min(math.dist(tuple(Mi @ w), q) for q in SRC_PTS) > 1e-4]
swset = set(sword_ids)
vg = {g.index: g.name for g in body.vertex_groups}
dom = [vg[max(v.groups, key=lambda g: g.weight).group] if v.groups else None for v in me.vertices]

S = [W[i] for i in sword_ids]
CEN = sum(S, Vector()) / len(S)
cov = [[0.0] * 3 for _ in range(3)]
for p in S:
    d = p - CEN
    for x in range(3):
        for y in range(3):
            cov[x][y] += d[x] * d[y]
AX = Vector((0.0, 0.0, 1.0))
for _ in range(600):
    AX = Vector((sum(cov[x][y] * AX[y] for y in range(3)) for x in range(3))).normalized()
lo_i = min(sword_ids, key=lambda i: (W[i] - CEN).dot(AX))
hi_i = max(sword_ids, key=lambda i: (W[i] - CEN).dot(AX))
T = {i: (W[i] - CEN).dot(AX) for i in sword_ids}
RAD = {i: ((W[i] - CEN) - T[i] * AX).length for i in sword_ids}
tmin, tmax = min(T.values()), max(T.values())
buck = {}
for i in sword_ids:
    k = min(39, int((T[i] - tmin) / max(1e-12, tmax - tmin) * 40))
    buck.setdefault(k, []).append((T[i], RAD[i]))
prof = [(sum(a for a, _ in v) / len(v), max(r for _, r in v)) for v in buck.values()]
guard_t, guard_r = max(prof, key=lambda pr: pr[1])
pom_t = tmin if abs(guard_t - tmin) < abs(guard_t - tmax) else tmax
pom_i, tip_i = (lo_i, hi_i) if abs(pom_t - tmin) < 1e-9 else (hi_i, lo_i)
G = CEN + AX * ((pom_t + guard_t) * 0.5)
POM_W = W[pom_i]
TIP_W = W[tip_i]
G_W = G
FIST_IDS = [i for i in range(nv) if i not in swset and dom[i] == "DEF-hand.R"
            and (W[i] - Mh.translation).length <= 0.08]
FC = sum((W[i] for i in FIST_IDS), Vector()) / len(FIST_IDS)
DNOW = (TIP_W - POM_W).normalized()
print("sword %d verts | tip %d | pommel %d | len %.4f m | G-fist %.4f m | guard %.4f m"
      % (len(sword_ids), tip_i, pom_i, (TIP_W - POM_W).length, (G_W - FC).length, guard_r))

torso = [i for i in range(nv) if i not in swset and dom[i]
         and not dom[i].startswith(HAND_AND_FINGERS)
         and not dom[i].startswith(ARM_PREFIX) and i % CLOUD_STEP == 0]
arms = [i for i in range(nv) if i not in swset and dom[i]
        and dom[i].startswith(ARM_PREFIX) and i % CLOUD_STEP == 0]
print("torso cloud %d | arm cloud %d" % (len(torso), len(arms)))

poses = []
for clip, frac in POSES:
    a = bpy.data.actions.get(clip)
    if a is None:
        continue
    arm.animation_data_create()
    arm.animation_data.action = a
    try:
        if hasattr(arm.animation_data, "action_slot") and len(a.slots):
            arm.animation_data.action_slot = a.slots[0]
    except Exception:
        pass
    f0, f1 = int(a.frame_range[0]), int(a.frame_range[1])
    bpy.context.scene.frame_set(f0 + int((f1 - f0) * frac))
    bpy.context.view_layer.update()
    Msw = (arm.matrix_world @ arm.pose.bones["DEF-hand.R"].matrix) @ Mi
    deps = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(deps)
    m2 = ev.to_mesh()
    T4 = np.array([list(ev.matrix_world @ m2.vertices[i].co) for i in torso], dtype=np.float64)
    A4 = np.array([list(ev.matrix_world @ m2.vertices[i].co) for i in arms], dtype=np.float64)
    ev.to_mesh_clear()
    M4 = np.array([[Msw[i][j] for j in range(4)] for i in range(4)], dtype=np.float64)
    poses.append((clip, frac, M4, T4, A4))
print("posed samples %d" % len(poses))

R3_idle = None
for clip, frac, M4, T4, A4 in poses:
    if (clip, frac) == IDLE_FRACS[0]:
        R3_idle = M4[:3, :3].copy()

POM_L = np.array([POM_W.x, POM_W.y, POM_W.z])
TIP_L = np.array([TIP_W.x, TIP_W.y, TIP_W.z])
G_L = np.array([G_W.x, G_W.y, G_W.z])
DNOW_A = np.array([DNOW.x, DNOW.y, DNOW.z])
SAMPLES_T = np.array([0.40, 0.55, 0.70, 0.85, 1.00])


def rot_between(a, b):
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    s = float(np.linalg.norm(v))
    if s < 1e-9:
        return np.eye(3) if c > 0 else -np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * ((1 - c) / (s * s))


# ---- validation first --------------------------------------------------------
R_check = np.eye(3)
for clip, frac, M4, T4, A4 in poses:
    if (clip, frac) != IDLE_FRACS[0]:
        continue
    off = np.array([G_L[0] + (TIP_L - G_L)[0], G_L[1] + (TIP_L - G_L)[1],
                    G_L[2] + (TIP_L - G_L)[2], 1.0])
    pred = M4 @ off
    a = bpy.data.actions.get(clip)
    arm.animation_data.action = a
    f0, f1 = int(a.frame_range[0]), int(a.frame_range[1])
    bpy.context.scene.frame_set(f0 + int((f1 - f0) * frac))
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(deps)
    m2 = ev.to_mesh()
    tt = ev.matrix_world @ m2.vertices[tip_i].co
    ev.to_mesh_clear()
    err = float(np.linalg.norm(pred[:3] - np.array([tt.x, tt.y, tt.z])))
    print("")
    print("VALIDATION identity: predicted tip %+.3f %+.3f %+.3f vs skinned %+.3f %+.3f %+.3f | error %.5f m"
          % (pred[0], pred[1], pred[2], tt.x, tt.y, tt.z, err))
    if err > 0.002:
        raise SystemExit("ABORT: the pose chain does not reproduce the shipped sword")
    print("")

rows = []
for az in range(-180, 181, 10):
    for el in range(-80, 71, 5):
        r, e = math.radians(az), math.radians(el)
        aim = np.array([math.cos(e) * math.sin(r), math.cos(e) * math.cos(r), math.sin(e)])
        rest_aim = R3_idle.T @ aim
        d_loc = rest_aim / np.linalg.norm(rest_aim)
        R = rot_between(DNOW_A, d_loc)
        gap_t, gap_a, tipz = 9.9, 9.9, 9.9
        worst_t, worst_a = "", ""
        idle_fwd, idle_tip, idle_pom = 0.0, None, None
        for clip, frac, M4, T4, A4 in poses:
            o_p = np.array([G_L[0] + R[0] @ (POM_L - G_L), G_L[1] + R[1] @ (POM_L - G_L),
                            G_L[2] + R[2] @ (POM_L - G_L), 1.0])
            o_t = np.array([G_L[0] + R[0] @ (TIP_L - G_L), G_L[1] + R[1] @ (TIP_L - G_L),
                            G_L[2] + R[2] @ (TIP_L - G_L), 1.0])
            pom = M4 @ o_p
            tip = M4 @ o_t
            pts = np.array([pom[:3] + (tip[:3] - pom[:3]) * t for t in SAMPLES_T])
            dt = float(np.linalg.norm(T4[None, :, :] - pts[:, None, :], axis=2).min())
            if dt < gap_t:
                gap_t, worst_t = dt, "%s %.2f" % (clip, frac)
            da = float(np.linalg.norm(A4[None, :, :] - pts[:, None, :], axis=2).min())
            if da < gap_a:
                gap_a, worst_a = da, "%s %.2f" % (clip, frac)
            tipz = min(tipz, float(tip[2]))
            if (clip, frac) in IDLE_FRACS:
                idle_fwd = float(tip[1] - pom[1])
                idle_tip = tuple(float(x) for x in tip[:3])
                idle_pom = tuple(float(x) for x in pom[:3])
        rows.append(dict(t=gap_t, a=gap_a, az=az, el=el, tipz=tipz, fwd=idle_fwd,
                         wt=worst_t, wa=worst_a, tipxy=idle_tip, pomxy=idle_pom,
                         dloc=tuple(float(x) for x in d_loc)))

print("candidates %d" % len(rows))
print("")
print("== aims the blade FORWARD in the idle (tip in front of the pommel), best torso clearance first ==")
fwdrows = sorted([r for r in rows if r["fwd"] >= 0.20], key=lambda r: -r["t"])
print("%5s %5s | torso gap | arm gap | tip z min | idle fwd | idle tip xyz"
      % ("az", "el"))
for r in fwdrows[:16]:
    print("%5d %5d | %.3f m   | %.3f m  | %.3f m    | %+.3f   | %+.2f %+.2f %+.2f"
          % (r["az"], r["el"], r["t"], r["a"], r["tipz"], r["fwd"],
             r["tipxy"][0], r["tipxy"][1], r["tipxy"][2]))
if not fwdrows:
    print("  none - no candidate points the blade forward")
print("")
print("== where does the SHIPPED aim sit (az/el of the current blade in the idle)? ==")
cur = DNOW_A
cur_az = math.degrees(math.atan2(cur[0], cur[1]))
cur_el = math.degrees(math.asin(max(-1.0, min(1.0, cur[2]))))
print("  shipped aim in the idle: az %.0f deg, el %.0f deg (az measured from the front)"
      % (cur_az, cur_el))
for r in rows:
    if abs(r["az"] - round(cur_az)) <= 10 and abs(r["el"] - round(cur_el)) <= 5:
        print("  shipped-ish candidate: az %d el %d -> torso gap %.3f m, arm gap %.3f m, worst torso %s"
              % (r["az"], r["el"], r["t"], r["a"], r["wt"]))
        break

passing = [r for r in rows if r["t"] >= CLEAR_TORSO and r["a"] >= CLEAR_ARM and r["tipz"] >= 0.30]
passing_fwd = sorted([r for r in passing if r["fwd"] >= 0.20], key=lambda r: -r["t"])
print("")
print("passing (torso >= %.2f, arm >= %.2f, tip z >= 0.30): %d of %d | of those pointing forward: %d"
      % (CLEAR_TORSO, CLEAR_ARM, len(passing), len(rows), len(passing_fwd)))
for r in passing_fwd[:6]:
    print("  az %d el %d | torso %.3f | arm %.3f | tip z %.3f | idle fwd %+.3f | worst torso %s"
          % (r["az"], r["el"], r["t"], r["a"], r["tipz"], r["fwd"], r["wt"]))
with open(os.path.join(OUT, "aim_candidates.txt"), "w") as fh:
    for r in (passing_fwd if passing_fwd else fwdrows[:10]):
        fh.write("az %d el %d torso %.4f arm %.4f tipz %.4f fwd %.4f dloc %s\n"
                 % (r["az"], r["el"], r["t"], r["a"], r["tipz"], r["fwd"], repr(r["dloc"])))
print("written to aim_candidates.txt")
arm.animation_data.action = None
print("\nSWORD_AIM_PICK2_DONE")
