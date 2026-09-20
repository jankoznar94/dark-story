#!/usr/bin/env python3
"""Is a surface black because of its TEXTURE or its UVs? Answer without Blender.

Reads a .glb directly (glTF JSON chunk + bin chunk), samples the embedded atlas at
EVERY vertex's UV, and reports mean albedo luminance per body band. This is the
check that finds the "head fine, everything else black" defect, which is a degenerate
UV layer (many verts at one UV) and not a lighting or material problem.

Usage:
    python3 glb_uv_albedo_probe.py <model.glb> [--atlas <atlas.png>] [--gltf-v]

--atlas  sample an EXTERNAL png instead of the one embedded in the glb (use this to
         test whether a candidate source mesh pairs with the project atlas)
--gltf-v report the v-flipped alternative sample too (glTF/Godot put v=0 at the TOP
         row; Blender's Image.paste puts v=0 at the bottom, so the two conventions
         disagree and an off-by-100% flip is the usual first suspicion)

What to read from the output:
  * unique uvs << vertex count          -> degenerate unwrap, the real cause
  * body band luminance ~0, head ~40    -> the documented black-body signature
  * a candidate source at 55-58 mean    -> its UVs match the atlas
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

CT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2),
      5125: ("I", 4), 5126: ("f", 4)}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
LUMW = np.array([0.2126, 0.7152, 0.0722])


def load_glb(path):
    b = open(path, "rb").read()
    _, _, length = struct.unpack("<III", b[:12])
    off, chunks = 12, []
    while off < length:
        clen, ctype = struct.unpack("<II", b[off:off + 8])
        chunks.append((ctype, b[off + 8:off + 8 + clen]))
        off += 8 + clen
    js = json.loads(chunks[0][1].decode("utf-8"))
    return js, (chunks[1][1] if len(chunks) > 1 else b"")


def accessor(js, bin_, idx):
    a = js["accessors"][idx]
    bv = js["bufferViews"][a["bufferView"]]
    fmt, sz = CT[a["componentType"]]
    n = NC[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    count = a["count"]
    stride = bv.get("byteStride") or sz * n
    mv = memoryview(bin_)
    if stride == sz * n:
        raw = np.frombuffer(mv[start:start + count * sz * n], dtype=np.dtype("<" + fmt))
        arr = raw.reshape(count, n) if n > 1 else raw
    else:
        arr = np.stack([np.frombuffer(mv[start + k * stride:start + k * stride + sz * n],
                                      dtype=np.dtype("<" + fmt)) for k in range(count)])
    return np.asarray(arr, dtype=np.float64)


def embedded_image(js, bin_, index=0):
    img = js["images"][index]
    bv = js["bufferViews"][img["bufferView"]]
    s = bv.get("byteOffset", 0)
    return Image.open(io.BytesIO(bin_[s:s + bv["byteLength"]])).convert("RGB")


def sample(atlas, uv, size, flip):
    W, H = size
    px = np.clip((uv[:, 0] * (W - 1)).round().astype(int), 0, W - 1)
    vy = (1.0 - uv[:, 1]) if flip else uv[:, 1]
    py = np.clip((vy * (H - 1)).round().astype(int), 0, H - 1)
    return atlas[py, px] @ LUMW


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    model = sys.argv[1]
    js, bin_ = load_glb(model)
    atlas_path = None
    if "--atlas" in sys.argv:
        atlas_path = sys.argv[sys.argv.index("--atlas") + 1]
        A = np.array(Image.open(atlas_path).convert("RGB")).astype(np.float64)
    else:
        A = np.array(embedded_image(js, bin_)).astype(np.float64)
    H, W = A.shape[:2]
    print("MODEL  %s" % model)
    print("ATLAS  %s  %dx%d  mean lum %.1f"
          % (atlas_path or "<embedded images[0]>", W, H, (A @ LUMW).mean()))

    for mesh in js.get("meshes", []):
        for pi, pr in enumerate(mesh["primitives"]):
            if "TEXCOORD_0" not in pr["attributes"]:
                print("  prim %d: NO TEXCOORD_0 -> this surface cannot be textured" % pi)
                continue
            uv = accessor(js, bin_, pr["attributes"]["TEXCOORD_0"])
            pos = accessor(js, bin_, pr["attributes"]["POSITION"])
            uniq = len(np.unique(np.round(uv, 6), axis=0))
            # glTF is Y-up; fall back to Z if this export kept Blender axes
            axis = 1 if (pos[:, 1].max() - pos[:, 1].min()) > 0.5 else 2
            y = pos[:, axis]
            ymin, ymax = y.min(), y.max()
            step = (ymax - ymin)
            print("\n  prim %d mat %s  verts %d  unique uvs %d  (%.1f%% degenerate)"
                  % (pi, pr.get("material"), len(uv), uniq,
                     100.0 * (1.0 - uniq / max(1, len(uv)))))
            print("       uv u %.3f..%.3f  v %.3f..%.3f  |  height %.3f..%.3f"
                  % (uv[:, 0].min(), uv[:, 0].max(), uv[:, 1].min(), uv[:, 1].max(), ymin, ymax))
            if uniq <= 8:
                print("       *** DEGENERATE: %d unique UVs for %d verts - the surface "
                      "samples %d texel(s) ***" % (uniq, len(uv), uniq))
            bands = [("head/top    ", y > ymin + 0.80 * step),
                     ("chest       ", (y > ymin + 0.63 * step) & (y <= ymin + 0.80 * step)),
                     ("waist       ", (y > ymin + 0.49 * step) & (y <= ymin + 0.63 * step)),
                     ("legs        ", (y > ymin + 0.06 * step) & (y <= ymin + 0.49 * step)),
                     ("feet/bottom ", y <= ymin + 0.06 * step)]
            lum = sample(A, uv, (W, H), flip=False)
            for nm, m in bands:
                if m.sum():
                    print("       %s verts %5d  albedo lum %6.1f  frac<12 %5.1f%%  frac>30 %5.1f%%"
                          % (nm, m.sum(), lum[m].mean(),
                             100.0 * (lum[m] < 12).mean(), 100.0 * (lum[m] > 30).mean()))
            print("       WHOLE prim: lum %6.1f  frac<12 %5.1f%%"
                  % (lum.mean(), 100.0 * (lum < 12).mean()))
            if "--gltf-v" in sys.argv:
                lf = sample(A, uv, (W, H), flip=True)
                print("       v-flipped alt sampling: whole prim lum %6.1f  frac<12 %5.1f%%"
                      % (lf.mean(), 100.0 * (lf < 12).mean()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
