#!/usr/bin/env bash
# Run every headless test the CI gate runs, and print one line each.
set -u
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-$HOME/tools/godot/godot4}"
# ⚠️  THE TESTS GET THEIR OWN `user://`, NOT THE MEASUREMENT ONE. Several tests build a
# save and write it (`test_equip_and_town`, `test_shop_and_craft`), and Godot resolves
# `user://` through `XDG_DATA_HOME` — so running the suite under the same isolated tree the
# parity harness seeds DELETES the loadout a probe is halfway through measuring. That
# happened once and made a correct frame measure as "the doll is 4px high and the bag is
# empty". Separate trees, no shared state.
export XDG_DATA_HOME="${DR_TEST_DATA:-/tmp/dr_godot_tests}"
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
