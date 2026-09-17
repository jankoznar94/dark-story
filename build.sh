#!/usr/bin/env bash
# Build all three targets headlessly. No GPU, no GUI.
#
# The keystore env vars are REQUIRED: without them Godot refuses to sign a
# release APK ("Could not find release keystore, unable to export") and leaves
# an UNSIGNED apk behind that Android will reject.
set -euo pipefail

GODOT="${GODOT:-$HOME/tools/godot/godot4}"
PROJ="$(cd "$(dirname "$0")" && pwd)"

# Android toolchain (user-local install, see docs/android-setup.md)
export JAVA_HOME="$HOME/tools/jdk-17"
export ANDROID_HOME="$HOME/tools/android-sdk"

# Signing. The debug keystore is re-used as the release key so the tester can
# install updates over old builds instead of uninstalling every time.
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$HOME/.android/debug.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="android"

cd "$PROJ"

echo "== regenerate input map =="
"$GODOT" --headless --path . --script res://tools/gen_input_map.gd | tail -2

echo "== gameplay test (must pass) =="
OUT=$("$GODOT" --headless --path . --script res://tools/test_attack.gd 2>&1)
echo "$OUT" | grep -E "^(CASE|RESULT|ALL_PASS)"
echo "$OUT" | grep -q "ALL_PASS=true" || { echo "GAMEPLAY TEST FAILED - not building"; exit 1; }

rm -rf build
mkdir -p build/web build/windows build/android

for target in Web Windows Android; do
  echo "== export $target =="
  "$GODOT" --headless --path . --export-release "$target" 2>&1 | grep -iE "^ERROR|Signed" || true
done

echo
echo "== artifacts =="
for f in build/web/index.html build/web/index.wasm build/windows/arpg.exe build/android/arpg.apk; do
  if [ -f "$f" ]; then printf "  OK   %-8s %s\n" "$(du -h "$f" | cut -f1)" "$f"
  else printf "  MISS ---     %s\n" "$f"; fi
done

APKSIGNER="$ANDROID_HOME/build-tools/35.0.0/apksigner"
if [ -x "$APKSIGNER" ]; then
  "$APKSIGNER" verify build/android/arpg.apk >/dev/null 2>&1 \
    && echo "  APK signature: VALID" || echo "  APK signature: INVALID"
fi
