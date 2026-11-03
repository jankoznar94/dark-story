#!/usr/bin/env python3
"""Stamp the Android export preset with the version this build really is.

Why: Android refuses to install an APK whose `versionCode` is LOWER than the one
already on the phone, and the version under the icon is the only way Jan can tell
which build he is running. A committed `version/code=1` would say "0.1.0" forever,
so CI writes the run number into the preset for the duration of the build.

The keystore is NOT handled here: Godot 4.7 reads `GODOT_ANDROID_KEYSTORE_RELEASE_*`
from the environment, so no secret ever has to be written into a tracked file.

    DR_ANDROID_VERSION_CODE  integer, e.g. ${{ github.run_number }}
    DR_ANDROID_VERSION_NAME  optional human string, e.g. "0.1.42"

Exit 0 also when there is nothing to do (no version in the env), so a local run
without CI variables is a no-op rather than an error.
"""

import os
import re
import sys

PRESET_NAME = "Android"
CFG = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "export_presets.cfg")


def main() -> int:
    code = os.environ.get("DR_ANDROID_VERSION_CODE", "").strip()
    name = os.environ.get("DR_ANDROID_VERSION_NAME", "").strip()
    if code == "":
        print("ci_android_version: DR_ANDROID_VERSION_CODE is not set -> nothing to do")
        return 0

    with open(CFG, "r", encoding="utf-8") as f:
        lines = f.readlines()

    index = None
    for i, line in enumerate(lines):
        if line.strip() == 'name="%s"' % PRESET_NAME:
            for j in range(i, -1, -1):
                m = re.match(r"\[preset\.(\d+)\]", lines[j].strip())
                if m:
                    index = m.group(1)
                    break
            break
    if index is None:
        print("ci_android_version: no %s preset in %s" % (PRESET_NAME, CFG), file=sys.stderr)
        return 1

    # ⚠️  The options live in the FLAT `[preset.N.options]` block. Godot 4.7 writes
    # sub-block sections (`[preset.N.options.keystore]`) but its loader only reads
    # `config->get_section_keys("preset.N.options")`, so a value written into a
    # sub-block is silently ignored — measured here as "Could not find release
    # keystore" with a correct-looking path in the file.
    start = None
    for i, line in enumerate(lines):
        if line.strip() == "[preset.%s.options]" % index:
            start = i
            break
    if start is None:
        print("ci_android_version: preset %s has no options block" % index, file=sys.stderr)
        return 1
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if lines[i].strip().startswith("["):
            end = i
            break

    def set_key(key, value):
        for i in range(start, end):
            if lines[i].startswith(key + "="):
                lines[i] = "%s=%s\n" % (key, value)
                return True
        return False

    if not set_key("version/code", code):
        print("ci_android_version: version/code missing from the preset", file=sys.stderr)
        return 1
    if name and not set_key("version/name", '"%s"' % name):
        print("ci_android_version: version/name missing from the preset", file=sys.stderr)
        return 1

    with open(CFG, "w", encoding="utf-8") as f:
        f.writelines(lines)

    # Also stamp the RUNNING build: `application/config/version` is baked into the pack, and
    # the Android build shows it under the update button. Without it the player cannot tell
    # "the update did nothing" from "I am running yesterday's build".
    if not _stamp_project_version(name or code):
        return 1

    print("ci_android_version: preset %s -> code %s name %s"
          % (index, code, name or "unchanged"))
    return 0


PROJECT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "project.godot")


def _stamp_project_version(version: str) -> bool:
    """Write `config/version` into project.godot's [application] block."""
    with open(PROJECT, "r", encoding="utf-8") as f:
        lines = f.readlines()
    start = None
    for i, line in enumerate(lines):
        if line.strip() == "[application]":
            start = i
            break
    if start is None:
        print("ci_android_version: no [application] block in project.godot", file=sys.stderr)
        return False
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if lines[i].strip().startswith("["):
            end = i
            break
    for i in range(start, end):
        if lines[i].startswith("config/version="):
            lines[i] = 'config/version="%s"\n' % version
            break
    else:
        lines.insert(start + 1, 'config/version="%s"\n' % version)
    with open(PROJECT, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print("ci_android_version: project version -> %s" % version)
    return True


if __name__ == "__main__":
    sys.exit(main())
