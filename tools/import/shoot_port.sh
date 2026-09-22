#!/usr/bin/env bash
# Shoot the port's screens into tools/reference/port2/ — the other half of every diff.
#
#   tools/import/shoot_port.sh                 # all screens
#   tools/import/shoot_port.sh town chest      # only these
#
# `inventory`, `talents` and `hero` are the three TABS of one modal in the PWA, so they
# are shot as `character@<tab>` (see capture_screen.gd). The port needs a REAL renderer:
# --headless waits on RenderingServer.frame_post_draw, which never fires there.
#
# EVERY CAPTURE GETS A TIMEOUT. The renderer is llvmpipe (software), so a frame takes
# ~1.5s of CPU; a capture that has not finished in a minute is not slow, it is stuck —
# and without `timeout` it holds the whole batch forever while the files on disk look
# untouched, which reads as "the tool does nothing".
set -u
cd "$(dirname "$0")/../.." || exit 1

GODOT="${GODOT:-$HOME/tools/godot/godot4}"
OUT=tools/reference/port2
LIMIT="${LIMIT:-90}"
mkdir -p "$OUT"

# reference name -> --screen value
declare -A SCREENS=(
  [town]=town [map]=map [chest]=chest [shop]=shop [gamble]=gamble [craft]=craft
  [bestiary]=bestiary [spellbook]=spellbook
  [inventory]=character@inventory [talents]=character@skills [hero]=character@stats
)

if [ "$#" -gt 0 ]; then
  keys=("$@")
else
  keys=(town map chest shop gamble craft bestiary spellbook inventory talents hero)
fi

fail=0
for key in "${keys[@]}"; do
  screen="${SCREENS[$key]:-}"
  if [ -z "$screen" ]; then
    echo "unknown screen: $key" >&2
    fail=1
    continue
  fi
  rm -f "$OUT/$key.png"
  timeout "$LIMIT" "$GODOT" --path . --rendering-driver opengl3 \
      --script res://tools/capture_screen.gd -- \
      --screen "$screen" --out "$OUT/$key.png" --frames 60 >/dev/null 2>&1
  rc=$?
  if [ ! -s "$OUT/$key.png" ]; then
    echo "$key: NO FRAME (exit $rc)" >&2
    fail=1
  else
    echo "$key: $screen -> $OUT/$key.png"
  fi
done
exit $fail
