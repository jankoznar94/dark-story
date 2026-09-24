#!/usr/bin/env bash
# Run every headless test the CI gate runs, and print one line each.
set -u
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-$HOME/tools/godot/godot4}"
TESTS=$(grep -oE "res://tools/test_[a-z_]+\.gd" .github/workflows/build.yml | sort -u)
fail=0
for t in $TESTS; do
  OUT=$(timeout 240 "$GODOT" --headless --path . --script "$t" 2>&1)
  if echo "$OUT" | grep -qE "_ALL_PASS=true"; then
    echo "PASS  $t"
  else
    echo "FAIL  $t"
    echo "$OUT" | grep -E "FAIL|ERROR" | grep -v "RID\|resources still\|RID alloc" | head -5
    fail=1
  fi
done
exit $fail
