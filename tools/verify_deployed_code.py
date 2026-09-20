#!/usr/bin/env python3
"""Prove the DEPLOYED gh-pages build carries the new systems.

TWO METHODS WERE TRIED AND ONE OF THEM LIES, which is why this file documents both:

  * grepping the pck for SCRIPT TEXT ("Tělo", "dress_corpse", "spawn_body") is
    worthless: a web-export pck stores GDScript zlib-compressed, and measured hits
    were 0 even for strings provably in the build. The pck header's directory-offset
    field also gave a nonsense value (3381523799 on a 4.6 MB file), so a parser built
    on it fails.
  * the FILE TABLE is stored UNCOMPRESSED (the REL_FILE_BASE region), so script
    PATHS are reliably findable by a plain byte scan. That is the method used below.

And the decisive evidence for a BEHAVIOUR fix is not this script at all - it is that
`tools/test_panels.gd` is a CI step that runs BEFORE the gh-pages publish and fails
the job. Since the publish happened, the deployed build passed the assertion that a
panel's rect covers the viewport - i.e. a tap has somewhere to land.

Usage: python3 tools/verify_deployed_code.py
"""
import subprocess
import sys

REPO = "."

# Script PATHS that only exist in the fixed build.
PRESENT = [
    "scripts/loot_body.gd",     # the corpse system
    "scripts/loot_panel.gd",    # the loot window
    "scripts/input_gate.gd",    # the pause flag every gameplay read goes through
]
# The deleted ground-item system. A hit here means a STALE build.
ABSENT = ["scripts/loot_drop.gd"]
# Calibration: scripts that have been in the build all along.
CALIBRATION = ["scripts/main.gd", "scripts/player.gd"]


def main() -> int:
    subprocess.run(["git", "fetch", "origin", "gh-pages", "-q"], cwd=REPO, check=False)
    blob = subprocess.run(["git", "show", "origin/gh-pages:index.pck"],
                          cwd=REPO, capture_output=True, check=True).stdout
    print("deployed index.pck: %d bytes" % len(blob))

    # CALIBRATION FIRST: without it, every "MISSING" below would be a claim about
    # the search rather than about the build.
    calib = [n for n in CALIBRATION if n.encode() in blob]
    print("calibration (must be found): %s" % calib)
    if len(calib) != len(CALIBRATION):
        print("FAIL: known-present script paths were not found - the search is broken, "
              "so no verdict below would mean anything")
        return 1

    ok = True
    for n in PRESENT:
        hit = n.encode() in blob
        print("  %-26s %s" % (n, "present" if hit else "MISSING"))
        ok = ok and hit
    for n in ABSENT:
        hit = n.encode() in blob
        print("  %-26s %s" % (n, "PRESENT (stale build!)" if hit else "absent"))
        ok = ok and not hit

    print("DEPLOYED_PATHS_OK=%s" % str(ok).lower())
    print("")
    print("Behaviour proof (the part this script cannot give): the gh-pages publish "
          "runs AFTER the headless suites, so a deploy that landed means "
          "PANELS_ALL_PASS (rect covers the viewport, a real tap lands inside it) "
          "and INVENTORY_ALL_PASS passed on these exact sources.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
