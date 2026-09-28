#!/usr/bin/env bash
# Run every gate test in tools/test_*.gd and print one line per file.
# A headless run has no audio device and no motor, which is why only the DECISION layers are
# asserted — but every one of them must still come out green before a push.
cd "$(dirname "$0")/.." || exit 1
GODOT=${GODOT:-$HOME/tools/godot/godot4}
FAILED=0
for f in tools/test_*.gd; do
  OUT=$($GODOT --headless --path . --script "res://$f" 2>&1)
  VERDICT=$(echo "$OUT" | grep -oE "[A-Z_]+_ALL_PASS=(true|false)" | tail -1)
  if [ -z "$VERDICT" ]; then
    echo "NO VERDICT  $f"
    echo "$OUT" | grep -E "SCRIPT ERROR|Parse Error" | head -3
    FAILED=1
  elif [ "${VERDICT##*=}" != "true" ]; then
    echo "RED         $f  ($VERDICT)"
    echo "$OUT" | grep "FAIL:" | head -6
    FAILED=1
  else
    echo "green       $f"
  fi
done
echo "---"
[ "$FAILED" = "0" ] && echo "SUITE_ALL_PASS=true" || echo "SUITE_ALL_PASS=false"
