#!/usr/bin/env python3
"""Prove the split-cache service worker actually saves bandwidth.

Simulates two consecutive deploys and asserts:
  1. a CODE-ONLY change keeps the wasm cache key -> the 39 MB is NOT refetched
  2. an ENGINE change (different wasm bytes) does change the wasm key
  3. a code change DOES change the code key, so small files do refresh
  4. the bytes a code-only deploy must transfer stay under 1 MB

Run: python3 tools/test_web_cache.py
"""
import hashlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJ = HERE.parent
PATCH = HERE / "patch_web_sw.py"

CODE_FILES = [
    "index.html", "index.js", "index.pck", "index.offline.html",
    "index.icon.png", "index.apple-touch-icon.png",
    "index.audio.worklet.js", "index.audio.position.worklet.js",
]


def sha(p: Path) -> str:
    h = hashlib.sha256()
    h.update(p.read_bytes())
    return h.hexdigest()[:16]


def build_worker(src: Path, dst: Path) -> tuple:
    """Copy a web build, patch its worker, return (code, wasm) versions."""
    dst.mkdir(parents=True, exist_ok=True)
    for f in src.iterdir():
        if f.is_file():
            shutil.copy2(f, dst / f.name)
    r = subprocess.run([sys.executable, str(PATCH), str(dst)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("patch failed:", r.stdout, r.stderr)
        sys.exit(1)
    txt = (dst / "index.service.worker.js").read_text()
    code = re.search(r"CODE_VERSION = '([^']+)'", txt).group(1)
    wasm = re.search(r"ASSET_VERSION = '([^']+)'", txt).group(1)
    return code, wasm


fails = []
def ok(label, cond, detail=""):
    print(("  OK   " if cond else "  FAIL ") + label + (("  " + detail) if detail else ""))
    if not cond:
        fails.append(label)


src = PROJ / "build" / "web"
if not (src / "index.wasm").exists():
    print("no web build found - run the export first")
    sys.exit(1)

print("== deploy 1: initial ==")
with tempfile.TemporaryDirectory() as td:
    d1 = Path(td) / "v1"
    c1, w1 = build_worker(src, d1)
    print(f"  code={c1} wasm={w1}")

    # --- deploy 2: a CODE-ONLY change (script edit changes index.pck only) ---
    d2 = Path(td) / "v2"
    d2.mkdir(parents=True)
    for f in d1.iterdir():
        if f.is_file():
            shutil.copy2(f, d2 / f.name)
    pck = d2 / "index.pck"
    pck.write_bytes(pck.read_bytes() + b"\x00CHANGED")
    # re-patch with the changed pck
    shutil.copy2(PATCH, d2 / "patch.py")
    r = subprocess.run([sys.executable, str(PATCH), str(d2)], capture_output=True, text=True)
    txt = (d2 / "index.service.worker.js").read_text()
    c2 = re.search(r"CODE_VERSION = '([^']+)'", txt).group(1)
    w2 = re.search(r"ASSET_VERSION = '([^']+)'", txt).group(1)

    print("== deploy 2: code-only change (index.pck edited) ==")
    print(f"  code={c2} wasm={w2}")
    ok("code cache key CHANGED (small files refresh)", c1 != c2)
    ok("wasm cache key UNCHANGED (39 MB not refetched)", w1 == w2,
       f"{w1} == {w2}")

    # --- deploy 3: the ENGINE changes (wasm bytes differ) ---
    d3 = Path(td) / "v3"
    d3.mkdir(parents=True)
    for f in d2.iterdir():
        if f.is_file():
            shutil.copy2(f, d3 / f.name)
    wasm = d3 / "index.wasm"
    wasm.write_bytes(wasm.read_bytes() + b"\x00ENGINEUPGRADE")
    r = subprocess.run([sys.executable, str(PATCH), str(d3)], capture_output=True, text=True)
    txt = (d3 / "index.service.worker.js").read_text()
    w3 = re.search(r"ASSET_VERSION = '([^']+)'", txt).group(1)
    print("== deploy 3: engine upgraded (index.wasm replaced) ==")
    print(f"  wasm={w3}")
    ok("wasm cache key DOES change when the engine changes", w3 != w2)

    # --- what a code-only deploy must transfer ---
    total = sum((d2 / f).stat().st_size for f in CODE_FILES if (d2 / f).exists())
    print(f"== bytes a code-only deploy must transfer ==")
    print(f"  {total} bytes = {total / 1048576:.2f} MB  (vs 37.7 MB wasm)")
    ok("code-only deploy transfers under 1 MB", total < 1048576, f"{total/1048576:.2f} MB")
    ok("saving is at least 20x", (37.7 * 1048576) / total > 20,
       f"{(37.7*1048576)/total:.0f}x")

print("")
if fails:
    for f in fails:
        print("FAIL:", f)
    print("WEB_CACHE_ALL_PASS=false")
    sys.exit(1)
print("WEB_CACHE_ALL_PASS=true")
