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
NV = len(pos)
print("verts %d tris %d materials %s" % (NV, len(idx) // 3,
                                         [m.get("name") for m in j["materials"]]))

par = np.arange(NV)


def f(x):
    while par[x] != x:
        par[x] = par[par[x]]
        x = par[x]
    return x


for t in range(0, len(idx), 3):
    a, b, c = int(idx[t]), int(idx[t + 1]), int(idx[t + 2])
    for u, v in ((a, b), (b, c)):
        ru, rv = f(u), f(v)
        if ru != rv:
            par[ru] = rv

from collections import defaultdict  # noqa: E402

comp = defaultdict(list)
for i in range(NV):
    comp[f(i)].append(i)
comps = [np.array(v) for v in comp.values()]
print("components %d" % len(comps))

# For each component: span, centroid, and the gap to the nearest vertex that is
# NOT in it. A floating object is a component with a real gap.
rows = []
for c in comps:
    if len(c) < 3:
        continue
    Q = pos[c]
    cen = Q.mean(0)
    span = float(np.linalg.norm(Q.max(0) - Q.min(0)))
    other = np.delete(pos, c, axis=0)
    gap = float(np.sqrt(((Q[:, None, :] - other[None, :, :]) ** 2).sum(-1).min()))
    names, counts = np.unique(dom[c], return_counts=True)
    top = names[int(np.argmax(counts))]
    rows.append((gap, len(c), cen, span, top))
rows.sort(key=lambda r: -r[0])
print("\n-- top 12 components by GAP to the nearest other vertex --")
print("%8s %5s %8s  %-22s %s" % ("gap", "n", "span", "centroid", "bone"))
for gap, n, cen, span, top in rows[:12]:
    print("%7.4f %5d %8.3f  %-22s %s" % (gap, n, span, str(np.round(cen, 3)), top))

iso = [r for r in rows if r[0] > 0.01]
print("\nisolated components (gap > 0.01 m): %d, verts %d"
      % (len(iso), sum(r[1] for r in iso)))
for gap, n, cen, span, top in iso[:20]:
    print("  gap %6.4f n=%4d span %6.3f cen %s bone=%s"
          % (gap, n, span, str(np.round(cen, 3)), top))

# unweighted / odd-weight vertices
wsum = W.sum(1)
print("\nvertices with weight sum 0: %d | != 1: %d" % (int((wsum < 1e-6).sum()),
                                                       int((np.abs(wsum - 1) > 1e-3).sum())))
odd = np.where(np.abs(wsum - 1) > 1e-3)[0]
if len(odd):
    print("sample odd verts:", odd[:10].tolist())
    for v in odd[:10]:
        print("   v%d pos %s joints %s weights %s bone %s"
              % (v, np.round(pos[v], 3), J[v].tolist(), np.round(W[v], 3).tolist(), dom[v]))
