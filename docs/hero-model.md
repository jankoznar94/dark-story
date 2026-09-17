# Hero model - how it was made and what to watch out for

## Source

**Quaternius "Animated Base Character"** (CC0, via poly.pizza). Chosen after
testing KayKit Adventurers first and rejecting it: KayKit is *chibi* (oversized
head, short legs) and does not match the brief of a tall, muscular warrior.
Quaternius is realistic-proportioned.

| | |
|---|---|
| Bones | 53 |
| Animations | 45 (Godot exposes 45 after import) |
| Triangles | ~13.7k |
| Height | 1.62 m |
| Licence | CC0 |

Cached at `~/tools/kaykit/candidates/quat_base_character.glb` (2.2 MB).

## The stray Icosphere - the trap that cost the most time

The GLB contains a second mesh: an **unparented 2 m `Icosphere`** centred on the
origin that encloses the lower body. It is not part of the character.

It was not obvious, because:
- a combined bounding box looked plausible (2.8 m tall, which read as "tall warrior")
- renders showed the mannequin *plus* a bright enclosing shell, which looked like
  a lighting or material problem rather than a second object
- it inflated every measurement

**Always delete it, and always measure per object rather than on a combined box.**
The real character is 1.62 m, not 2.8 m.

## Godot strips `_Loop` from clip names

The source GLB says `Rig|Walk_Loop`; Godot exposes **`Rig|Walk`**. Guessing clip
names in GDScript silently does nothing. Run `tools/list_anims.gd` instead - it
prints what Godot actually exposes.

| Want | Godot name | Length |
|---|---|---|
| combat idle | `Rig|Sword_Idle` | 1.67 s |
| walk | `Rig|Walk` | 1.33 s |
| light swing | `Rig|Sword_Attack` | 1.50 s |
| heavy swing | `Rig|Sword_Attack_RM` | 1.50 s |
| take a hit | `Rig|Hit_Chest` | 0.33 s |
| death | `Rig|Death01` | 2.38 s |
| cast | `Rig|Spell_Simple_Shoot` | 0.50 s |

## Attack timing is tuned to the animation

`Sword_Attack` is 1.50 s, played at 2x = 0.75 s. The player's committed window is
windup 0.30 + active 0.12 + recover 0.33 = **0.75 s**, so the blade lands with the
hit instead of still swinging afterwards. Changing one without the other will
desync the visual from the damage.

## Rendering previews - three things that mislead

1. **Measure the POSED mesh.** For a skinned mesh, `mesh.bound_box` is the *rest*
   pose. The camera framed a 1.08 m figure and cropped the head off the 1.62 m
   posed character. Evaluate the depsgraph and read the evaluated vertices.
2. **Filmic tonemapping turns a white backdrop grey.** The black-on-white
   silhouette test needs `view_settings.view_transform = 'Standard'`, otherwise a
   pixel test cannot separate figure from background.
3. **Lights tuned for a light grey mannequin make a dark palette look mid-grey.**
   When swapping in dark materials, cut the light energy to roughly a third.

## Palette

The source materials are saturated (orange `M_Main`, purple `M_Joints`) and carry
UVs but no textures, so they are safe to replace wholesale.

| Slot | Name | RGB | Metallic |
|---|---|---|---|
| 0 | `ds_dark_leather` | 0.200, 0.145, 0.100 | 0.0 |
| 1 | `ds_dark_steel` | 0.150, 0.150, 0.160 | 0.5 |

Measured result: figure mean luminance 114/255, 22 % of pixels below 90 - reads
dark without going black.

## Regenerate

```bash
"/mnt/c/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b --factory-startup \
  -P "C:\\Users\\Martin Fabian\\AppData\\Local\\Temp\\bl_final.py"
```

Then re-import in Godot, or the runtime will not see the new GLB:

```bash
~/tools/godot/godot4 --headless --path . --import
```

## Still to do

The model is a **featureless grey mannequin**. It is a correct, animated,
correctly-proportioned base to build on - not a finished hero. Next steps are
clothing/armour geometry, a face, and a hair/beard silhouette.
