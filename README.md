# ARPG Proto

Slow-paced isometric 3D ARPG — *Diablo 1/2 feel, modern tech*.

Jan is the tester; Violet builds. Nothing in this repo should be edited by hand without
regenerating the input map (`tools/gen_input_map.gd`).

## Design rules these files encode

- **Attacks are commitments.** No move-cancel, no attack-cancel. `player.gd` blocks
  movement for the whole windup → active → recover window. This is the whole feel.
- **Melee is directional, never auto-target.** A swing raycasts a fan along `facing`.
  You can miss, and you can swing at empty air on purpose.
- **Four buttons, not seven.** `attack`, `skill_1`, `skill_2`, `potion`. Diablo Immortal
  ships seven targets because it is a fast game. We are not.
- **Everything is an Input Map action**, never a hardcoded key — that is what keeps
  touch, keyboard and gamepad on one code path.
- **Atmosphere lives in light, fog and sound**, not textures. Depth fog + tonemapping +
  low saturation are supported by every renderer, so a web export costs nothing there.
- **Landscape only.** `window/handheld/orientation=4` (sensor landscape).

## Renderer

| Target | Method |
|---|---|
| Desktop | `mobile` |
| Android | `mobile` |
| Web | `gl_compatibility` (mandatory — Godot web is WebGL 2) |

Set per-platform in `project.godot`. Mobile↔Compatibility differ only by CompositorEffects
vs SSAO; both lack SDFGI/volumetric fog/SSR, so we simply do not design around those.

**GDScript, not C#** — C#/.NET cannot be exported to web at all.

## Layout

```
scenes/     main.tscn (wiring), player.tscn
scripts/    player.gd (state machine), camera_rig.gd, hud.gd, main.gd, target_post.gd
tools/      gen_input_map.gd, test_attack.gd
```

## Dev commands (headless, no GPU)

```bash
# regenerate the input map after editing tools/gen_input_map.gd
~/tools/godot/godot4 --headless --path . --script res://tools/gen_input_map.gd

# gameplay sanity test — must print ALL_PASS=true
~/tools/godot/godot4 --headless --path . --script res://tools/test_attack.gd

# export
mkdir -p build/web build/windows build/android
~/tools/godot/godot4 --headless --path . --export-release "Web"
~/tools/godot/godot4 --headless --path . --export-release "Windows"
~/tools/godot/godot4 --headless --path . --export-release "Android"
```

## Getting a build to test

CI runs on every push: web goes to GitHub Pages, `.exe` and `.apk` go to Releases.
Telegram bots cannot send files over 50 MB, so downloads come as links, not attachments.
