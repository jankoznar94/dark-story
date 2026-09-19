#!/usr/bin/env python3
"""Force Godot to re-import every prop after a MATERIAL-only change.

THE TRAP: Godot's wavefront_obj import records its dependencies as the generated
.mesh file only, never the .mtl next to it:

    [deps]
    files=["res://.godot/imported/tree_dead.obj-<hash>.mesh"]

So editing props.mtl / proset.mtl changes NOTHING in the engine, and `--import`
and even `--import --force` both leave the OLD albedo in place. Measured: after
lifting every material in the source mtl, `probe_prop_material.gd` still reported
the old values (bark lum 24.3 instead of 50.8) and the props still rendered as
black silhouettes.

The fix is to re-import the MESH, not the material: the simplest reliable way is
to delete the .obj's cached .md5 so Godot sees it as changed, together with the
stale .mesh. This script does that for every .obj under assets/props.

    python3 tools/reimport_props.py            # report what it would do
    python3 tools/reimport_props.py --apply    # actually invalidate the caches
    python3 tools/reimport_props.py --apply --godot ~/tools/godot/godot4

Verify afterwards with:
    godot --headless --path . --script res://tools/probe_prop_material.gd
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--godot", default=os.path.expanduser("~/tools/godot/godot4"))
    ap.add_argument("--props", default=os.path.join(ROOT, "assets", "props"))
    args = ap.parse_args()

    objs = sorted(glob.glob(os.path.join(args.props, "*.obj")))
    imported = os.path.join(ROOT, ".godot", "imported")
    if not objs:
        print("no .obj files under %s" % args.props)
        return 1

    # the md5 filename embeds a hash of the SOURCE PATH, so match on the stem
    killed = []
    for o in objs:
        stem = os.path.basename(o)
        for ext in (".md5", ".mesh"):
            pat = os.path.join(imported, stem + "-*" + ext)
            for f in glob.glob(pat):
                if args.apply:
                    os.remove(f)
                killed.append(os.path.relpath(f, ROOT))

    print("props: %d .obj files" % len(objs))
    print("stale import artifacts %s: %d" % ("REMOVED" if args.apply else "found", len(killed)))
    for k in killed[:6]:
        print("  " + k)
    if len(killed) > 6:
        print("  ... and %d more" % (len(killed) - 6))

    if not args.apply:
        print("\ndry run - re-run with --apply to invalidate")
        return 0
    if not os.path.exists(args.godot):
        print("\ncannot find Godot at %s; run --import yourself" % args.godot)
        return 1
    print("\nre-importing...")
    r = subprocess.run([args.godot, "--headless", "--path", ROOT, "--import"],
                       capture_output=True, text=True, timeout=900)
    tail = [l for l in (r.stdout + r.stderr).splitlines() if "ERROR" in l or "reimport" in l]
    for l in tail[-8:]:
        print("  " + l)
    print("reimport exit %d" % r.returncode)
    print("\nnow verify the albedo actually changed:")
    print("  %s --headless --path . --script res://tools/probe_prop_material.gd" % args.godot)
    return 0


if __name__ == "__main__":
    sys.exit(main())
