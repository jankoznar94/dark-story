# Independent check on the DELIVERED hero.glb (never trust the producing script).
#   1. the stray cluster is gone
#   2. the sword is in the fist, and WHERE its grip sits relative to the fist
#   3. the finger distance -> the fist radius that "fits" the sword
import json
import struct

import numpy as np

P = "/home/martin_fabian/godot-arpg/models/hero.glb"
d = open(P, "rb").read()
jl = struct.unpack("<I", d[12:16])[0]
j = json.loads(d[20:20 + jl])
bo = 20 + jl + 8


def acc(i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    off = bo + bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    ct = {5126: "f4", 5123: "u2", 5121: "u1", 5125: "u4"}[a["componentType"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
    return np.frombuffer(d, offset=off, count=a["count"] * n, dtype=ct).reshape(a["count"], n)


pr = j["meshes"][0]["primitives"][0]
pos = acc(pr["attributes"]["POSITION"]).astype(np.float64)
J = acc(pr["attributes"]["JOINTS_0"]).astype(int)
W = acc(pr["attributes"]["WEIGHTS_0"]).astype(float)
uv = acc(pr["attributes"]["TEXCOORD_0"]).astype(float)
jname = [j["nodes"][k].get("name", "?") for k in j["skins"][0]["joints"]]
dom = np.array([jname[J[v][int(np.argmax(W[v]))]] for v in range(len(pos))])
print("verts %d  materials %s" % (len(pos), [m.get("name") for m in j["materials"]]))


def trs(n):
    t = n.get("translation", [0, 0, 0])
    r = n.get("rotation", [0, 0, 0, 1])
    s = n.get("scale", [1, 1, 1])
    x, y, z, w = r
    R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    M = np.eye(4)
    M[:3, :3] = R * np.array(s)
    M[:3, 3] = t
    return M


names = [n.get("name", "?") for n in j["nodes"]]
world = {}


def walk(i, Pm):
    M = Pm @ trs(j["nodes"][i])
    world[i] = M
    for c in j["nodes"][i].get("children", []):
        walk(c, M)


for r in j["scenes"][0]["nodes"]:
    walk(r, np.eye(4))

hand_keys = [n for n in names if n.endswith(".R")
             and (n.startswith("DEF-hand") or n.startswith("DEF-f_"))]
hbw = np.array([world[names.index(k)][:3, 3] for k in hand_keys])
print("hand/finger bones %d" % len(hbw))

sel = np.where(dom == "DEF-hand.R")[0]
P_ = pos[sel]
d_nearest = np.array([np.min(np.linalg.norm(hbw - p, axis=1)) for p in P_])
print("\n1) stray cluster test on the delivered file")
print("   hand.R-dominant verts %d | nearest-bone distance: max %.4f m" % (len(sel), d_nearest.max()))
print("   verts beyond 0.35 m of EVERY hand/finger bone: %d  (was 24)"
      % int((d_nearest > 0.35).sum()))

# ---- 2) the sword: 80 verts on hand.R, everything else is the fist.
# find the split: sort by distance to the fist centroid, use the largest gap
cen = P_.mean(0)
d_cen = np.linalg.norm(P_ - cen, axis=1)
order = np.argsort(d_cen)
gaps = np.diff(d_cen[order])
k = int(np.argmax(gaps))
fist = sel[order[:k + 1]]
sword = sel[order[k + 1:]]
print("\n2) sword split by the largest distance gap: fist %d verts, candidate %d"
      % (len(fist), len(sword)))
for kk in (k - 1, k, k + 1):
    print("   boundary at %.4f m" % d_cen[order[kk]])
fist_c = pos[fist].mean(0)
sw = pos[sword]
print("   fist centre %s" % np.round(fist_c, 4))
dist_to_fist_c = np.linalg.norm(sw - fist_c, axis=1)
nearest_v = np.linalg.norm(sw[:, None, :] - pos[fist][None, :, :], axis=2).min()
print("   sword: nearest vert-to-fist-vert %.4f m | nearest to fist CENTRE %.4f m"
      % (nearest_v, dist_to_fist_c.min()))
print("   sword bbox %s .. %s" % (np.round(sw.min(0), 3), np.round(sw.max(0), 3)))

# ---- 3) what fist radius would fit the sword?
fist_all = np.array([pos[i] for i in range(len(pos))
                     if dom[i] == "DEF-hand.R"
                     and np.min(np.linalg.norm(hbw - pos[i], axis=1)) <= 0.15])
print("\n3) fist radius sensitivity (hand.R verts within R of the hand bone):")
for R in (0.10, 0.12, 0.14, 0.15, 0.17, 0.20):
    m = np.array([dom[i] == "DEF-hand.R"
                  and np.min(np.linalg.norm(hbw - pos[i], axis=1)) <= R
                  for i in range(len(pos))])
    Q = pos[m]
    if len(Q) == 0:
        continue
    c = Q.mean(0)
    print("   R=%.2f -> %4d verts, span %.4f m, centroid %s"
          % (R, len(Q), np.linalg.norm(Q.max(0) - Q.min(0)), np.round(c, 4)))
print("VERIFY_DONE")
