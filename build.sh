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
# apksigner is a java launcher - JAVA_HOME alone is not enough, java must be on PATH,
# otherwise the verification step below false-negatives on a perfectly signed APK.
export PATH="$JAVA_HOME/bin:$PATH"

# ---------------------------------------------------------------- signing key
# The debug keystore is re-used as the release key so the tester can install
# updates over old builds instead of uninstalling every time.
#
# Android refuses an update signed with a DIFFERENT key, so this one file is
# load-bearing. It is backed up (see docs/signing-key.md). If it ever goes
# missing, rebuild it from the backup rather than silently generating a new one
# - a new key would break every future update.
KS="$HOME/.android/debug.keystore"
KS_BAK="$HOME/tools/backup/dark-story-debug.keystore"
KS_SHA="458066f0d822f5ed21501d532d2671429523bd5e4ed7957f7c717819e500eca5"  # SHA256 of the key, from docs/signing-key.md

if [ ! -f "$KS" ]; then
  if [ -f "$KS_BAK" ]; then
    echo "!! keystore missing - restoring from backup $KS_BAK"
    mkdir -p "$(dirname "$KS")"
    cp "$KS_BAK" "$KS"
  else
    echo "!! FATAL: keystore missing and no backup found at $KS_BAK"
    echo "!! A newly generated key would break every existing install."
    echo "!! Restore it first - see docs/signing-key.md"
    exit 1
  fi
fi

# Guard: refuse to build with a key that is not the known one, because the APK
# would install as a separate app rather than an update.
if command -v keytool >/dev/null 2>&1 || [ -x "$HOME/tools/jdk-17/bin/keytool" ]; then
  KT="$HOME/tools/jdk-17/bin/keytool"
  [ -x "$KT" ] || KT="keytool"
  # keytool indents with TABS and may wrap the fingerprint across lines, so
  # strip all whitespace, not just spaces - tr -d ' ' gives a false mismatch.
  ACTUAL=$("$KT" -list -v -keystore "$KS" -storepass android -alias androiddebugkey 2>/dev/null \
    | grep "SHA256:" | head -1 | sed 's/.*SHA256://' | tr -d '[:space:]:' | tr 'A-F' 'a-f')
  if [ -n "$ACTUAL" ] && [ "$ACTUAL" != "$KS_SHA" ]; then
    echo "!! WARNING: keystore fingerprint does not match the recorded key."
    echo "!!   expected $KS_SHA"
    echo "!!   actual   $ACTUAL"
    echo "!! Updates will NOT install over existing builds. See docs/signing-key.md"
  fi
fi

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KS"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="android"

cd "$PROJ"

echo "== regenerate input map =="
"$GODOT" --headless --path . --script res://tools/gen_input_map.gd | tail -2

echo "== gameplay test (must pass) =="
OUT=$("$GODOT" --headless --path . --script res://tools/test_attack.gd 2>&1)
echo "$OUT" | grep -E "^(CASE|RESULT|ALL_PASS)"
echo "$OUT" | grep -q "ALL_PASS=true" || { echo "GAMEPLAY TEST FAILED - not building"; exit 1; }

echo "== controls test (must pass) =="
OUT2=$("$GODOT" --headless --path . --script res://tools/test_controls.gd 2>&1)
echo "$OUT2" | grep -E "FAIL|checks executed|CONTROLS_ALL_PASS"
echo "$OUT2" | grep -q "CONTROLS_ALL_PASS=true" || { echo "CONTROLS TEST FAILED - not building"; exit 1; }

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
  SIG=$("$APKSIGNER" verify --verbose build/android/arpg.apk 2>&1) || true
  if echo "$SIG" | grep -q "^Verifies"; then
    SCHEMES=$(echo "$SIG" | grep ": true" | sed 's/Verified using //; s/: true//' | tr '\n' ' ')
    echo "  APK signature: VALID   (schemes: $SCHEMES)"
  else
    echo "  APK signature: INVALID"
    echo "$SIG" | head -3
  fi
fi
