import json
import struct

import numpy as np

P = "/home/martin_fabian/godot-arpg/models/hero.glb"
d = open(P, 'rb').read()
jl = struct.unpack('<I', d[12:16])[0]
j = json.loads(d[20:20 + jl])
bo = 20 + jl + 8


def acc(i):
    a = j['accessors'][i]
    bv = j['bufferViews'][a['bufferView']]
    off = bo + bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    ct = {5126: 'f4', 5123: 'u2', 5121: 'u1', 5125: 'u4'}[a['componentType']]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
    return np.frombuffer(d, offset=off, count=a['count'] * n, dtype=ct).reshape(a['count'], n)


pr = j['meshes'][0]['primitives'][0]
pos = acc(pr['attributes']['POSITION']).astype(np.float64)
J = acc(pr['attributes']['JOINTS_0']).astype(int)
W = acc(pr['attributes']['WEIGHTS_0']).astype(float)
uv = acc(pr['attributes']['TEXCOORD_0']).astype(float)
idx = acc(pr['indices']).astype(int).ravel()
jname = [j['nodes'][k].get('name', '?') for k in j['skins'][0]['joints']]
dom = np.array([jname[J[v][int(np.argmax(W[v]))]] for v in range(len(pos))])

NV = len(pos)
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

# world rest transform of hand.R
def trs(n):
    t = n.get('translation', [0, 0, 0])
    r = n.get('rotation', [0, 0, 0, 1])
    s = n.get('scale', [1, 1, 1])
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
    M = Pm @ trs(j['nodes'][i])
    world[i] = M
    for c in j['nodes'][i].get('children', []):
        walk(c, M)


for r in j['scenes'][0]['nodes']:
    walk(r, np.eye(4))

names = [n.get('name', '?') for n in j['nodes']]
hb = world[names.index('DEF-hand.R')][:3, 3]

hs = [c for c in comp.values() if dom[np.array(c)].tolist().count('DEF-hand.R') /
      len(c) > 0.5 and np.bincount(np.array(c) * 0 + 0).sum() >= 0]
hs = [np.array(c) for c in comp.values()
      if max(set(dom[np.array(c)].tolist()), key=dom[np.array(c)].tolist().count) == 'DEF-hand.R']
hs.sort(key=lambda c: pos[c].mean(0)[1])
print("hand.R components: %d, verts %d" % (len(hs), sum(len(c) for c in hs)))
print("%5s %6s  %-25s %-22s %-20s" % ("n", "|c-hb|", "centroid", "span", "uv"))
for c in hs:
    Q = pos[c]
    cen = Q.mean(0)
    print("%5d %6.3f  %-25s %-22s %s" % (
        len(c), np.linalg.norm(cen - hb), str(np.round(cen, 3)),
        str(np.round(Q.max(0) - Q.min(0), 3)), str(np.round(uv[c].mean(0), 4))))

# how many hand.R verts are beyond 0.15 m of the bone
dist = np.linalg.norm(np.array([pos[i] for i in range(NV) if dom[i] == 'DEF-hand.R']) - hb, axis=1)
print("\nhand.R verts: %d | within 0.15 m: %d | beyond: %d"
      % (len(dist), int((dist <= 0.15).sum()), int((dist > 0.15).sum())))
