# Dark Story — the asset toolchain

Four tools that turn "make an asset" into one command. They exist because the same
analysis was being hand-written over and over during the hero work (nine separate
GLB probes, five separate render-statistics scripts, four copies of the atlas
builder), so results were not comparable between runs and could not be re-read.

**Everything is deterministic** (`--seed`, default `20260919`). A texture or prop is
*regenerated*, never hand-edited, so an asset can always be traced back to the
parameters that made it.

## Quick reference

```bash
# textures: one place, one recipe per surface, all verified on write
python3 tools/make_texture.py --list
python3 tools/make_texture.py --all                    # write every surface
python3 tools/make_texture.py ground_grass stone_wall  # just these
python3 tools/make_texture.py --all --dry-run          # metrics only, no files
python3 tools/make_texture.py bark --size 1024 --seed 7

# prop sets: whole families from one recipe
python3 tools/make_propset.py --list
python3 tools/make_propset.py --all                    # 16 variants, 5 families
python3 tools/make_propset.py fences --dry-run

# the original hand-built hero/prop set (still the reference for fidelity)
python3 tools/make_props.py

# render metrics + assertions (also checks a frame is not an empty capture)
python3 tools/render_metrics.py shots/*.png
python3 tools/render_metrics.py --compare before.png after.png
python3 tools/render_metrics.py --expect-range 20 --expect-green --expect-grass-share 50 \
    "$HOME/.local/share/godot/app_userdata/Dark Story/game_iso.png"

# render many lighting/param variants in ONE engine start, then fold to a sheet
~/tools/godot/godot4 --path . --rendering-driver opengl3 --resolution 480x270 \
    --script res://tools/sweep_render.gd -- --presets res://tools/lights_sweep_example.json \
    --out user://sweep
python3 tools/sweep_sheet.py "$HOME/.local/share/godot/app_userdata/Dark Story/sweep" \
    /tmp/sheet.png
```

## What each tool refuses to let you do

| tool | catches |
|---|---|
| `make_texture.py` | visible seams, a flat texture (std < 6), a green surface that reads brown (G−R ≤ 0), oversaturation |
| `make_propset.py` | degenerate geometry, one geometry written into every file, identical variants |
| `make_props.py` | two props sharing a bounding box (a leaked loop variable once shipped the tree into five other files) |
| `render_metrics.py` | an EMPTY capture reported as a render, a flat frame, a colour cast, clipped highlights |
| `sweep_render.gd` | the one-render-per-decision bottleneck (9 variants in ~6 s vs 9 engine starts) |

## Adding a surface

Add one function to `RECIPES` in `make_texture.py` returning an `HxWx3` uint8 array.
Seamless tiling, the checks and the reporting are all shared. Use `fbm`, `ridged`,
`lattice` and `mix` — every one of them is periodic, which is what makes the tile
seamless by construction rather than by a fix-up pass.

## Adding a prop family

Add one function to `SETS` in `make_propset.py` returning
`[(variant_name, [(verts, faces, material), ...]), ...]`. Material is assigned **by
construction**, never by a height threshold — a height threshold silently broke the
trunk/canopy split as soon as the trunk grew past the first canopy tier.

## Render probes (Godot, must NOT be `--headless`)

| script | purpose |
|---|---|
| `render_game.gd` | the real `main.tscn` — the frame the player sees |
| `sweep_render.gd` | N light/param variants from a JSON preset file, one engine start |
| `render_prop_grid.gd` | every `.obj` in `assets/props` on one grid |
| `render_props.gd` | the original seven props with a closer tree pass |
| `render_hero_views.gd` | the hero (front / face / hand / side) |

`grep` for `CAPTURED` in the output and run the file through `render_metrics.py`
with `--expect-fg` before trusting it: a camera move needs two settle frames, and a
blank frame is a bad capture rather than a missing model.
