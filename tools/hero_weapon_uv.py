import json
from collections import Counter

import numpy as np
from PIL import Image

W = "/mnt/c/Users/Martin Fabian/AppData/Local/Temp/darkstory_uv/"
J = json.load(open(W + "atlas_src2.json"))
polys = J["polys"]
print("polys", len(polys))
print(Counter(p["z"] for p in polys))
wp = [p for p in polys if p["z"] == "weapon"]
print("weapon polys", len(wp), "with material slot 1:",
      sum(1 for p in wp if p["m"] == 1))
uv = np.array([[u, v] for p in wp for u, v in p["uv"]])
print("weapon UV u %.4f..%.4f  v %.4f..%.4f" % (uv[:, 0].min(), uv[:, 0].max(),
                                                uv[:, 1].min(), uv[:, 1].max()))
c = np.array([p["c"] for p in wp])
print("weapon poly centroid mean (Blender m)", np.round(c.mean(0), 3))
print("weapon bbox (Blender m)", np.round(c.min(0), 3), np.round(c.max(0), 3))


def area(p):
    P = np.array(p["uv"])
    x = P[:, 0]
    y = P[:, 1]
    return 0.5 * abs((x * np.roll(y, 1) - np.roll(x, 1) * y).sum())


A = sum(area(p) for p in wp)
print("weapon UV area %.6f of the atlas = %.0f px^2 at 1024" % (A, A * 1024 * 1024))

im = Image.open(W + "hero_atlas.png").convert("RGB")
a = np.asarray(im).astype(float)
print("atlas", im.size)
u0, u1 = uv[:, 0].min(), uv[:, 0].max()
v0, v1 = uv[:, 1].min(), uv[:, 1].max()
x0, x1 = int(u0 * 1024), int(np.ceil(u1 * 1024))
y0, y1 = int((1 - v1) * 1024), int(np.ceil((1 - v0) * 1024))
sub = a[y0:y1, x0:x1]
lum = (sub * np.array([0.2126, 0.7152, 0.0722])).sum(-1)
print("steel rect px x %d..%d y %d..%d  mean lum %.1f p10 %.1f p90 %.1f"
      % (x0, x1, y0, y1, lum.mean(), np.percentile(lum, 10), np.percentile(lum, 90)))

# whole-atlas check of the same rect measured through the DELIVERED glb UVs
P = "/home/martin_fabian/godot-arpg/models/hero.glb"
d = open(P, "rb").read()
import struct

jl = struct.unpack("<I", d[12:16])[0]
j = json.loads(d[20:20 + jl])
bo = 20 + jl + 8


def acc(i):
    ac = j["accessors"][i]
    bv = j["bufferViews"][ac["bufferView"]]
    off = bo + bv.get("byteOffset", 0) + ac.get("byteOffset", 0)
    ct = {5126: "f4", 5123: "u2", 5121: "u1", 5125: "u4"}[ac["componentType"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[ac["type"]]
    return np.frombuffer(d, offset=off, count=ac["count"] * n, dtype=ct).reshape(ac["count"], n)


pr = j["meshes"][0]["primitives"][0]
pos = acc(pr["attributes"]["POSITION"]).astype(float)
uvd = acc(pr["attributes"]["TEXCOORD_0"]).astype(float)
inside = ((uvd[:, 0] >= u0) & (uvd[:, 0] <= u1) & (uvd[:, 1] >= v0) & (uvd[:, 1] <= v1))
print("delivered verts whose UV falls in the weapon rect: %d" % inside.sum())
if inside.sum():
    print("their glTF position bbox", np.round(pos[inside].min(0), 3), np.round(pos[inside].max(0), 3))
    print("their centroid", np.round(pos[inside].mean(0), 3))
