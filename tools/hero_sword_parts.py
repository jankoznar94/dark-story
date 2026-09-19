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
idx = acc(pr["indices"]).astype(int).ravel()
jname = [j["nodes"][k].get("name", "?") for k in j["skins"][0]["joints"]]
dom = np.array([jname[J[v][int(np.argmax(W[v]))]] for v in range(len(pos))])

hb = None
names = [n.get("name", "?") for n in j["nodes"]]


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


world = {}


def walk(i, Pm):
    M = Pm @ trs(j["nodes"][i])
    world[i] = M
    for c in j["nodes"][i].get("children", []):
        walk(c, M)


for r in j["scenes"][0]["nodes"]:
    walk(r, np.eye(4))
hand_o = world[names.index("DEF-hand.R")][:3, 3]
d_hand = np.linalg.norm(pos - hand_o, axis=1)

hand_ids = np.where(dom == "DEF-hand.R")[0]
fist = hand_ids[d_hand[hand_ids] <= 0.08]
sword = hand_ids[d_hand[hand_ids] > 0.08]
print("fist %d | sword %d" % (len(fist), len(sword)))

# topological components restricted to the sword vertices
sset = set(sword.tolist())
sub = [e for e in range(0, len(idx), 3)
       if idx[e] in sset and idx[e + 1] in sset and idx[e + 2] in sset]
par = {v: v for v in sset}


def f(x):
    while par[x] != x:
        par[x] = par[par[x]]
        x = par[x]
    return x


for e in sub:
    a, b, c = int(idx[e]), int(idx[e + 1]), int(idx[e + 2])
    for u, v in ((a, b), (b, c)):
        ru, rv = f(u), f(v)
        if ru != rv:
            par[ru] = rv

from collections import defaultdict  # noqa: E402

g = defaultdict(list)
for v in sset:
    g[f(v)].append(v)
pieces = sorted((np.array(v) for v in g.values()), key=len, reverse=True)
print("sword sub-islands: %d" % len(pieces))
rest = pos[sword]
print("\n%-5s %-24s %-22s %8s" % ("n", "centroid", "bbox span", "gap to other sword verts"))
for c in pieces:
    Q = pos[c]
    other = np.delete(rest, [list(sword).index(v) for v in c], axis=0) if False else None
    oidx = [k for k, v in enumerate(sword) if v not in set(c.tolist())]
    oth = rest[oidx]
    gap = float(np.sqrt(((Q[:, None, :] - oth[None, :, :]) ** 2).sum(-1).min()))
    print("%-5d %-24s %-22s %8.4f"
          % (len(c), str(np.round(Q.mean(0), 3)), str(np.round(Q.max(0) - Q.min(0), 3)), gap))

print("\n-- pieces whose gap to the rest of the sword exceeds 0.005 m --")
for c in pieces:
    Q = pos[c]
    oidx = [k for k, v in enumerate(sword) if v not in set(c.tolist())]
    oth = rest[oidx]
    gap = float(np.sqrt(((Q[:, None, :] - oth[None, :, :]) ** 2).sum(-1).min()))
    if gap > 0.005:
        print("   gap %6.4f m  n=%3d  centroid %s  dist to hand bone %.4f"
              % (gap, len(c), str(np.round(Q.mean(0), 3)),
                 float(np.linalg.norm(Q.mean(0) - hand_o))))
