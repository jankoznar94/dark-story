#!/usr/bin/env python3
"""Replace the exported service worker with the split-cache version.

Godot's stock worker keys ONE cache by a build timestamp, so every deploy
invalidates everything - including the 39 MB index.wasm, which is byte-identical
across code-only deploys. That burns mobile data for nothing.

This rewrites it to use:
  * a CODE cache keyed by the combined hash of the small files
  * a WASM cache keyed by the CONTENT HASH of index.wasm

so a code-only deploy refetches ~0.3 MB instead of ~39 MB.

Run after `--export-release "Web"`:
    python3 tools/patch_web_sw.py build/web
"""
import hashlib
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE.parent / "web_sw.js"

CODE_FILES = [
    "index.html", "index.js", "index.pck", "index.offline.html",
    "index.icon.png", "index.apple-touch-icon.png",
    "index.audio.worklet.js", "index.audio.position.worklet.js",
]
ASSET_FILES = ["index.wasm"]


def sha(path: Path, limit: int = 0) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        while True:
            chunk = fh.read(1 << 20)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()[:16]


def main() -> int:
    web = Path(sys.argv[1] if len(sys.argv) > 1 else "build/web")
    sw = web / "index.service.worker.js"
    if not sw.exists():
        print(f"patch_web_sw: {sw} not found", file=sys.stderr)
        return 1

    # code version: changes whenever any small file changes
    code_h = hashlib.sha256()
    for name in CODE_FILES:
        p = web / name
        if p.exists():
            code_h.update(name.encode())
            code_h.update(sha(p).encode())
    code_version = code_h.hexdigest()[:16]

    # asset version: changes ONLY when the wasm bytes change
    wasm = web / "index.wasm"
    if not wasm.exists():
        print(f"patch_web_sw: {wasm} not found", file=sys.stderr)
        return 1
    asset_version = sha(wasm)

    tpl = TEMPLATE.read_text()
    out = tpl.replace("__CODE_VERSION__", code_version).replace("__ASSET_VERSION__", asset_version)
    sw.write_text(out)

    print(f"patch_web_sw: code={code_version} wasm={asset_version}")
    print(f"  wasm size {wasm.stat().st_size / 1048576:.1f} MB is now cached separately")
    return 0


if __name__ == "__main__":
    sys.exit(main())
