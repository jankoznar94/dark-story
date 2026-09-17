1|# Hero model - how it was made and what to watch out for
2|
3|## Source
4|
5|**Quaternius "Animated Base Character"** (CC0, via poly.pizza). Chosen after
6|testing KayKit Adventurers first and rejecting it: KayKit is *chibi* (oversized
7|head, short legs) and does not match the brief of a tall, muscular warrior.
8|Quaternius is realistic-proportioned.
9|
10|| | |
11||---|---|
12|| Bones | 53 |
13|| Animations | 45 (Godot exposes 45 after import) |
14|| Triangles | ~13.7k |
15|| Height | 1.62 m |
16|| Licence | CC0 |
17|
18|Cached at `~/tools/kaykit/candidates/quat_base_character.glb` (2.2 MB).
19|
20|## The stray Icosphere - the trap that cost the most time
21|
22|The GLB contains a second mesh: an **unparented 2 m `Icosphere`** centred on the
23|origin that encloses the lower body. It is not part of the character.
24|
25|It was not obvious, because:
26|- a combined bounding box looked plausible (2.8 m tall, which read as "tall warrior")
27|- renders showed the mannequin *plus* a bright enclosing shell, which looked like
28|  a lighting or material problem rather than a second object
29|- it inflated every measurement
30|
31|**Always delete it, and always measure per object rather than on a combined box.**
32|The real character is 1.62 m, not 2.8 m.
33|
34|## Godot strips `_Loop` from clip names
35|
36|The source GLB says `Rig|Walk_Loop`; Godot exposes **`Rig|Walk`**. Guessing clip
37|names in GDScript silently does nothing. Run `tools/list_anims.gd` instead - it
38|prints what Godot actually exposes.
39|
40|| Want | Godot name | Length |
41||---|---|---|
42|| combat idle | `Rig|Sword_Idle` | 1.67 s |
43|| walk | `Rig|Walk` | 1.33 s |
44|| light swing | `Rig|Sword_Attack` | 1.50 s |
45|| heavy swing | `Rig|Sword_Attack_RM` | 1.50 s |
46|| take a hit | `Rig|Hit_Chest` | 0.33 s |
47|| death | `Rig|Death01` | 2.38 s |
48|| cast | `Rig|Spell_Simple_Shoot` | 0.50 s |
49|
50|## Attack timing is tuned to the animation
51|
52|`Sword_Attack` is 1.50 s, played at 2x = 0.75 s. The player's committed window is
53|windup 0.30 + active 0.12 + recover 0.33 = **0.75 s**, so the blade lands with the
54|hit instead of still swinging afterwards. Changing one without the other will
55|desync the visual from the damage.
56|
57|## Rendering previews - three things that mislead
58|
59|1. **Measure the POSED mesh.** For a skinned mesh, `mesh.bound_box` is the *rest*
60|   pose. The camera framed a 1.08 m figure and cropped the head off the 1.62 m
61|   posed character. Evaluate the depsgraph and read the evaluated vertices.
62|2. **Filmic tonemapping turns a white backdrop grey.** The black-on-white
63|   silhouette test needs `view_settings.view_transform = 'Standard'`, otherwise a
64|   pixel test cannot separate figure from background.
65|3. **Lights tuned for a light grey mannequin make a dark palette look mid-grey.**
66|   When swapping in dark materials, cut the light energy to roughly a third.
67|
68|## Palette
69|
70|The source materials are saturated (orange `M_Main`, purple `M_Joints`) and carry
71|UVs but no textures, so they are safe to replace wholesale.
72|
73|| Slot | Name | RGB | Metallic |
74||---|---|---|---|
75|| 0 | `ds_dark_leather` | 0.200, 0.145, 0.100 | 0.0 |
76|| 1 | `ds_dark_steel` | 0.150, 0.150, 0.160 | 0.5 |
77|
78|Measured result: figure mean luminance 114/255, 22 % of pixels below 90 - reads
79|dark without going black.
80|
81|## Regenerate
82|
83|```bash
84|"/mnt/c/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b --factory-startup \
85|  -P "C:\\Users\\Martin Fabian\\AppData\\Local\\Temp\\bl_final.py"
86|```
87|
88|Then re-import in Godot, or the runtime will not see the new GLB:
89|
90|```bash
91|~/tools/godot/godot4 --headless --path . --import
92|```
93|
## Still to do

The model is a **featureless grey mannequin**. It is a correct, animated,
correctly-proportioned base to build on - not a finished hero. Next steps are
clothing/armour geometry, a face, and a hair/beard silhouette.

---

## Textured: the generated atlas (Sept 2026)

The mannequin now has a painted face and per-zone materials, all from one
**1024x1024 atlas generated with Lemonade** (`Flux-2-Klein-4B`, 256x256 source
tiles) and composited in PIL. `hero.glb` has **one material, one surface**; the
atlas is embedded in the GLB.

### The blocker that had to be solved first

The source mesh's usable UV layer had real coordinates on the **hands only** -
every body polygon (torso, head, arms, legs, weapon) was collapsed onto
`u=v=0`. No texture could land on the body at all. The mesh had to be
re-unwrapped before any of this meant anything.

### UV layout it was replaced with

| Atlas region | Contents |
|---|---|
| `v 0.00..0.25` | head + neck, **cylindrical projection around Z** |
| `v 0.25..1.00` | everything else, smart-projected and packed |

The head projection is analytic, not packed: `u = 0.5 + atan2(x, -y)/(2*pi) * KU`
puts the character's front at `u = 0.5` and `v` increases upward, so a painted
face lands predictably.

### Pitfalls that cost real time here

- **`pack_islands` overrides an explicit mapping.** It was run *after* the head
  was mapped, repacked the head too, and destroyed it - `corr(analytic_u,
  actual_u)` fell to **0.198**. Order matters: pack first, then overwrite the
  head loops **last**.
- **A UV layer reference goes invalid after `pack_islands`.** Calling
  `.name` on the stale handle raised `UnicodeDecodeError: invalid start byte`.
  Re-read `me.uv_layers[0]` after packing.
- **Anisotropy must be checked as a density ratio, not a pixel ratio.** The head
  wrap spans `KU*1024` px, so anisotropy is
  `(256/H) / (KU*1024/C)` - not `1024/C`. Using the wrong formula produced a
  bogus "7.9x" reading and a wrong `KU`, leaving a real **1.49x** error that made
  a square portrait render 0.234 m wide instead of 0.16 m.
  Correct value for this head: **`KU = 0.5312`**
  (`C = 0.7252 m` perimeter, `H = 0.3413 m`, 750 px/m both ways).
- **A square portrait pasted into a 2.35:1 rect stretches.** Crop to the subject
  and fit preserving aspect (pad, don't stretch).
- **`export_uv`/`uv.export_layout` needs a GPU** and fails in background Blender
  (`GPU functions for drawing are not available in background mode`). Rasterise
  the UV polygons in PIL from a dumped JSON instead.
- **Godot extracts embedded glTF textures next to the `.glb`** on import
  (`gltf/embedded_image_handling=1`), so `models/hero_hero_atlas.png` appears as
  a build product. It is gitignored - do not hand-copy the atlas into `models/`
  as well, or the same 830 KB ships twice.

### Palette, measured on the atlas

Warm, dark, desaturated, flat - no glow. `KHR_materials_specular` is the only
extension; metallic is 0 because a metal response needs specular highlights.

| Zone | Mean luminance |
|---|---|
| skin (head + hands) | 74 |
| leather (torso, limbs) | 46 |
| steel (sword) | 61 |

The untextured head initially read as a bright **"white hood"** because skin sat
at 131-137 against body leather at 45 - a 3x jump. That is what the grading fixes.

### The face patch was checked numerically, not by eye

Vision reported a "hard rectangular edge" around the face on **four** separate
renders. Measurement says otherwise and vision is the one that is wrong:

- max gradient **on** the patch border: **6.5**
- 99th-percentile gradient **inside** the patch: **55.7**
- luminance straight across the border: `74, 75, 74, 75, 73 | 75, 76, 75, 75, 73`

An edge far smoother than the texture's own detail is not a visible seam. This is
the same trap the Dark Story notes already warn about - **do not treat a vision
"hard edge" finding as a defect without a pixel measurement behind it.**

### Verification of the shipped GLB

- texture embedded: `images[0] = hero_atlas, image/png`; 1 material, 1 primitive,
  `TEXCOORD_0` present
- **0 unweighted vertices** of 13,289; 240 verts bound to `DEF-hand.R`, so the
  welded sword still follows the arm
- `test_weapon.gd` reworked for the 1-surface design (it used to assert 2
  surfaces) and asserts the atlas material + size instead: **20/20 OK**

## The weapon is welded into the hand (and why that mattered)

Two symptoms Jan reported, with **two different causes** - both confirmed by
measurement:

**"The bar is in his crotch."** `player.tscn` carried a procedural `Pivot` +
`Blade` bar (a 1.15 m box) at hip height on the player body, rotated by
`player.gd::_animate_weapon()`. It rotated independently of the animation, so as
soon as the character leaned forward the bar sat between his legs. It was never
part of the model and is now **deleted**, along with `_animate_weapon()`.

**"He swings his arms but the bar is not in them."** The source rig does **not
animate the fingers** in the sword/walk clips, so the hand stays wide open:

| Clip | thumb-tip <-> middle-fingertip |
|---|---|
| `Rig|Sword_Idle` | 0.0776 m (constant, all frames) |
| `Rig|Sword_Attack` | 0.0776 m |
| `Rig|Sword_Attack_RM` | 0.0776 m |
| `Rig|Walk_Loop` | 0.0776 m |
| `Rig|Pistol_Idle_Loop` | **0.0009 m (closed!) ** |
| `Rig|Punch_Cross` | 0.0009 m |

The same value comes back from the mesh and from the skeleton, so it is not a
mesh artefact - the clips genuinely leave the hand open. The closed-hand pose
**exists in the rig**, it is just only keyed in the pistol/punch clips.

The fix bakes that closed-hand pose into the clips the game ships
(`Sword_Idle`, `Walk_Loop`, `Sword_Attack`, `Sword_Attack_RM`, `Hit_Chest`) and
welds a purpose-built sword into the same GLB, 100 % weighted to `DEF-hand.R`.

## The weapon itself

Authored in Blender as plain boxes (no asset download needed), origin = **grip
centre**, blade along local **+Z**:

| Part | Size |
|---|---|
| grip | 0.038 x 0.032 x 0.150 m |
| pommel | 0.052 x 0.044 x 0.030 m |
| guard | 0.170 x 0.036 x 0.030 m |
| blade | 0.635 m long, tapered, 0.074 m wide at the base |
| total | 0.845 m (proportionate to a 1.62 m figure) |

33 verts / 27 faces. It becomes surface 1 of the body mesh, so `hero.glb` still
has one skinned mesh with two surfaces (`ds_dark_leather`, `ds_dark_steel`).

**Attach transform (order matters):** rotate the blade onto the hand bone axis
first, *then* translate the grip centre onto the fist. `R @ T` instead of
`T @ R` put the grip 0.198 m off in the idle and 1.12 m off at the strike frame.

**Which axis:** the blade runs along the hand **bone** axis, so in the idle it is
2.8 deg off the forearm - i.e. the blade is the extension of the arm. The
alternative mapping (blade perpendicular to the bone) measured **0.14 m below the
floor** at the swing and put the tip behind the body: rejected.

Measured on the final model, per frame:

| Frame | tip height | blade vs forearm | clearance to torso+legs |
|---|---|---|---|
| idle f10 | +0.256 m | 2.8 deg | 0.036 m |
| windup f4 | +1.137 m | 9.9 deg | 0.036 m |
| strike f12 | +0.320 m | 70.0 deg | 0.036 m |
| follow f24 | +1.000 m | 5.4 deg | 0.036 m |

Grip-to-fist distance is 0.0000 m on every frame.

## Pitfalls hit while doing this

- **A GDScript lambda captures by value.** `_count(n, func(_x): count += 1)` left
  `count` at 0. Pass an array instead.
- **A comment before `[gd_scene]` breaks the scene file.** Godot reported
  `player.tscn:1 - Parse Error: Expected '['`, which then cascaded into
  "Node not found: Player" in every test.
- **Bone poses come back in the Skeleton3D's own space**, which the glTF importer
  scaled by 100 relative to world space. A metre-based threshold on raw bone
  coordinates is wrong by 100x; multiply by
  `skel.global_transform.basis.get_scale()` first.
- **The 100x scale on the `Rig` node is in the original asset too**, not
  something the weapon pass introduced. Verified against the committed GLB.
- **Re-deriving the skin matrix by hand is not worth it.** A skinned
  MeshInstance3D ignores its own transform; `skel.global_transform * pose *
  rest.affine_inverse()` gave a 193 m tall figure. So blade-vs-floor and
  blade-vs-body are asserted in Blender on the source data
  (`tools/test_weapon.gd` documents this and checks what Godot can measure
  correctly: binding, closed fist, hand travel, overall scale).
