extends Control
class_name SurvivorScreen
## SurvivorScreen — the RENDERER half of the new fight (see `survivor_run.gd` for the rules).
##
## The arena is drawn, not composed out of nodes: one Control paints the ground, the props,
## the walking portraits, the loot and the HUD in `_draw()`. On a 390x844 phone that is a
## handful of draw calls per frame, and it keeps every position in ONE coordinate system
## (world pixels, camera subtracted), which is what stops the "the figure is 12px off its
## own shadow" class of bug that a tree of Container nodes invites.
##
## Controls, per Jan's decisions: the MOVEMENT is a FLOATING stick on the RIGHT — it appears
## wherever the thumb lands — and the ACTION WHEEL is FIXED in the bottom-LEFT and drawn all the
## time (a disc with six wedges), so the hand that walks is the other one. Only the ATTACK is HELD:
## while its wedge is under the thumb the RULES pick a target in the direction the hero looks and
## walk him into it (see `survivor_run._pick_target`). A spell or a potion is ARMED by dragging into
## its wedge and fires when the thumb LIFTS (Jan: "až puštění kontaktu bude považováno za aktivaci").
##
## ⚠️  One finger arrives TWICE on this engine (`Input` synthesises a mouse event from every
## touch), so the press/release pair goes through `_pointer_down`: the first event of the
## pair starts the gesture and the second is ignored. Motion is never gated — a finger DRAG
## delivers `ScreenDrag` and no `MouseMotion` at all, so a motion gate breaks dragging on
## the phone.

signal leave_requested
signal run_finished(outcome: String)
## The hero walked into the zone's EXIT: the act continues one zone deeper. The screen does
## not know what "deeper" means — `Main` owns the act's chain (`ActRun`).
signal zone_exited
## The waypoint was tapped: go to town and come back to this zone later. The act's record
## keeps this zone as the checkpoint, so nothing is lost.
signal waypoint_requested
## The town-portal scroll was used FROM THE ZONE: a portal opens where the hero stands and he
## steps through it into town. `Main` spends the scroll, freezes the zone and stores the exact
## spot, so the town's portal button brings him back onto it (Diablo's own behaviour).
signal portal_requested
## The character modal (Inventory / Skills / Stats) asked for FROM the fight. Jan, Nov 2026:
## "Inventář a staty hrdiny by měly být dostupné i při souboji. Aby hráč mohl hned obléct to co
## našel nebo si vybrat skilly." The screen only says "the player wants his hero"; MAIN pauses the
## run and opens the dialog — the run rules have no business knowing a modal exists.
signal hero_requested

const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")
const ActionWheel := preload("res://scripts/combat/action_wheel.gd")
const RunSpells := preload("res://scripts/combat/run_spells.gd")
const TownPortal := preload("res://scripts/items/town_portal.gd")
const UIKit := preload("res://scripts/ui/ui_kit.gd")
const UIFonts := preload("res://scripts/ui/ui_fonts.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")

const STEP := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 6

const TOP_BAR := 54.0
const STICK_RADIUS := 58.0
const STICK_DEADZONE := 9.0
## THE ACTION WHEEL (left thumb). Jan, Nov 2026, second pass: the wheel is PERMANENT — drawn all the
## time in the bottom-left, sectors and all — and each bound action is a whole WEDGE of an outer
## ring around the joystick-like disc, so the thumb never has to find an icon:
## "kolem ovládacího levého kruhu bude vnější větší kruh s akcemi, rozdělený na X výsečí".
##
## `WHEEL_INNER` is the resting disc: a thumb inside it runs nothing. `WHEEL_OUTER` is the ring's
## edge. A thumb landing ON the wheel (or just outside it) owns it; anything else in the left half
## is not an action, because the sectors are fixed and a stray thumb must not arm one.
##
## ⚠️  THE RADII ARE DERIVED FROM THE CANVAS, and they are deliberately SMALL: Jan, after the
## landscape pass came back to portrait — "zmenšíme oblast pro akce. Teď je zbytečně moc velká."
## `wheel_outer()` is a tenth of the canvas height (84 px on 844), the resting disc 55 % of that
## (46 px), and the icons 15 px. The old 106 / 58 pair ate a quarter of the screen and left the
## whole lower-left unplayable.
const WHEEL_OUTER_MAX := 88.0
const WHEEL_OUTER_MIN := 52.0
const WHEEL_ICON_RADIUS := 15.0
## The wheel's distance from the screen's left edge, and its centre's clearance above the bottom
## (the HP/mana bars own the last 40 px and the loot tally sits at `size.y - 6`).
const WHEEL_MARGIN := 12.0
const WHEEL_BOTTOM_PAD := 52.0
## The bind panel's rows. A thumb needs 52 px of height at the very least; the slot rows get more
## because they carry two lines (direction + action).
const BIND_ROW_H := 74.0
const BIND_PICK_ROW_H := 52.0
const BIND_GAP := 10.0
const BIND_PAD := 14.0
const BIND_BACK_H := 46.0
## The Whirlwind row: the duel's `ps_*.png` symbols, drawn as a body of their own. 26 px matches
## the spell buttons so the thumb does not have to relearn a size mid-fight.
const WW_BUTTON_RADIUS := 26.0
const WW_ROW_Y := 150.0
const WW_KEYS := ["tri", "circle", "cross", "square"]
const WW_KEY_BORDERS := {
	"tri": "#2ecc71", "circle": "#e74c3c", "cross": "#e67e22", "square": "#f1c40f",
}
## One disc diameter for every actor: the hero is a walking portrait too (Jan), and a single
## size is what makes the collision radius (BODY_RADIUS 31 = DISC_DIA / 2) true on screen.
const DISC_DIA := 62.0

const GRASS_PATH := "res://assets/ground/grass.png"
const ZoneThemeData := preload("res://scripts/ui/zone_theme.gd")
## The zone's own look lives in `scripts/ui/zone_theme.gd` (`class_name ZoneTheme`): ground tile,
## palette, wall material, cover and landmarks. `_ready()` loads the default; `setup()` replaces
## both once the run knows its act and zone.

const C_TEXT := Color("#e8e0d0")
const C_DIM := Color("#b0a48e")
const C_GOLD := Color("#d8b876")
const C_RED := Color("#d4524a")
const C_BAR_BG := Color(0, 0, 0, 0.55)

var run = null
var _state
var _find_item: Callable

var _accum := 0.0
var _grass: Texture2D = null
## The zone's palette and ground tile. Set by `_apply_theme()` from `setup()`; until then both
## fall back to the shipped look, so a screen built before a run exists still paints.
var _theme: Dictionary = {}
var _ground: Texture2D = null
## The current prop's own ground point in canvas space, so a landmark can place its parts
## relative to itself (`_set_prop_offset`).
var _prop_base := Vector2.ZERO
var _disc_cache: Dictionary = {}
## The fog of war as ONE texture: a (COLS+1)x(ROWS+1) grid of CORNER alphas, resampled
## bilinearly over the whole world. The per-cell polygon pass it replaces was one draw call
## per veiled cell — measured 180 of the frame's 623 draw calls and ~4.2 ms of a 24.5 ms
## frame at device resolution — and it drew the same bilinear ramp the texture's own
## filtering produces for free.
var _fog_tex: ImageTexture = null
var _fog_version := -1

## Camera, in world pixels (top-left of the view).
var _cam := Vector2.ZERO

## Floating stick. `_stick_origin` is where the thumb landed; `_stick_vec` is 0..1.
## `_stick_index` is WHICH finger owns the stick (a touch's index, 0 for a mouse). Jan: "kouzla
## musí jít vykouzlit i za běhu" — so a second finger has to be able to press a spell button
## while the first one holds the stick, which a single `_pointer_down` flag could not express:
## the second press was swallowed as a duplicate and the spell never fired.
var _pointer_down := false
var _stick_index := -1
## Has a TOUCH ever arrived? If yes, every mouse event this engine synthesises from a touch is
## ignored — that is the duplicate that used to be filtered by the single flag.
var _touch_seen := false
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _pointer_kind := ""

## The EXIT and the wheel's BIND button, both fixed in the TOP bar (the only fixed controls left in
## the fight — everything a thumb plays is on the two wheels).
var _exit_rect := Rect2()
var _bind_rect := Rect2()
## The TOWN PORTAL button. It exists only while a scroll is carried, and it sits UNDER the top
## bar on the same right edge as `Konec` — inside the bar there is no free rectangle left: the
## second row already carries "Oblasti" and the kill counter, and a button drawn over them was
## measured hiding the timer once already.
var _portal_rect := Rect2()
## The HERO button — the door to the character modal from inside the fight. It shares the second
## row with the portal (the portal is only there while a scroll is carried), so the bar never has
## two controls in one rectangle.
var _hero_rect := Rect2()
## Set while the character modal is open over the fight. `stop()` already halts the clock, but a
## VISIBILITY change must not silently resume a paused run — that would let the monsters walk
## while the player reads his inventory.
var _paused := false

## THE ACTION WHEEL (left thumb). It is FIXED in the bottom-left and always drawn; the wedge the
## thumb is pushed into is the action. `_wheel_slot` is the wedge under the thumb right now (-1 =
## inside the resting disc, i.e. nothing), and `_wheel_slots` is what each wedge is bound to.
var _wheel_index := -1
var _wheel_vec := Vector2.ZERO
var _wheel_slot := -1
var _wheel_slots: Array = []
## The attack / held-spell state the RUN reads. Written from the wheel's active sector, never from
## a button: the wheel IS the input.
var _attack_held := false
var _held_spell := ""

## The bind panel: the wheel's editor, drawn by this screen like everything else. `_bind_pick` is
## -1 while it lists the slots and the slot index while it lists the actions for that slot.
var _bind_open := false
var _bind_pick := -1
var _bind_rects: Array = []
var _bind_back_rect := Rect2()
## The Whirlwind reaction row (four PS symbols). Only live during a flurry.
var _ww_buttons: Array = []
var _spell_tex_cache: Dictionary = {}
var _toast := ""
var _toast_ticks := 0.0
var _flash := 0.0
var _death_reported := false
## One exit report per zone: the gate must not fire every frame the hero stands in it.
var _zone_exited := false

## Seeded decorations: they are DATA so a re-layout cannot move the cover the fight uses.
var _props: Array = []
var _patches: Array = []


## ⚠️  THE STATIC WORLD RENDERS AT `WORLD_RENDER_SCALE`, THE REST AT NATIVE RESOLUTION.
## Jan, Nov 2026: "Takhle graficky primitivní hra se nesmí sekat ani ve snu." The ground, rock,
## river, deck and baked props cover every pixel of the screen and never change; the monsters, the
## fog and the HUD are a small fraction of the pixels and must stay sharp (measured: at 2.8x
## upscale the small HUD text goes visibly soft, which is why the whole frame is NOT scaled).
## 0.5 = a quarter of the fill for the world half.
const WORLD_RENDER_SCALE := 0.5
var _world_vp: SubViewport = null
var _world_layer: Node2D = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_grass = UIKit.load_texture(GRASS_PATH)
	_ground = _grass
	_theme = ZoneThemeData.for_zone(-1, -1)
	_make_world_viewport()


## Build the world's own framebuffer: a SubViewport at `WORLD_RENDER_SCALE` holding the static
## painters (`static_world.gd`). It is sized to the WHOLE ZONE and painted once per zone, so the
## frame only blits a window of it (see `_draw`).
func _make_world_viewport() -> void:
	if _world_vp != null:
		return
	_world_vp = SubViewport.new()
	_world_vp.disable_3d = true
	_world_vp.transparent_bg = false
	# ⚠️  NOT `UPDATE_ALWAYS`. The texture is world-fixed (no camera inside it), so it is repainted
	# only when the zone's meshes change — `_rebake_world()` sets this after `_bake_props()`.
	# `UPDATE_ALWAYS` re-emitted the whole static pass every frame and measured exactly nothing:
	# 390x844 went from 7.2 ms to 16.3 ms, 1080x2340 from 20.8 to 20.6 ms.
	_world_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_world_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(_world_vp)
	var layer := Node2D.new()
	layer.name = "StaticWorld"
	layer.set_script(load("res://scripts/ui/static_world.gd"))
	layer.screen = self
	layer.render_scale = WORLD_RENDER_SCALE
	layer.bake_world = true
	_world_vp.add_child(layer)
	_world_layer = layer
	_size_world_viewport()


## The zone's static texture size: the WHOLE world at the zoom, downscaled by the render scale.
## 2460 x 5940 world px -> 1009 x 2436 px, ~9.8 MB — one texture instead of ~70 draw calls a frame.
func _size_world_viewport() -> void:
	if _world_vp == null:
		return
	var px := SurvivorRun.WORLD * ZOOM * WORLD_RENDER_SCALE
	_world_vp.size = Vector2i(maxi(int(ceil(px.x)), 1), maxi(int(ceil(px.y)), 1))


## Repaint the static texture after the zone changed: ground tint, rock mesh and prop mesh are all
## read at paint time, so one update is enough. Called from `setup()` after `_bake_props()`.
func _rebake_world() -> void:
	if _world_vp == null:
		return
	if _world_layer != null:
		_world_layer.queue_redraw()
	_world_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## Stop the clock. The run object is KEPT (the payout is read from it when the screen hands the
## player back), but nothing advances it any more.
func stop() -> void:
	set_process(false)
	_pointer_down = false
	_stick_index = -1
	_stick_vec = Vector2.ZERO
	_wheel_index = -1
	_wheel_vec = Vector2.ZERO
	_wheel_slot = -1
	_attack_held = false
	_held_spell = ""
	if run != null:
		run.attack_held = false
		run.held_spell = ""
	_accum = 0.0


func setup(state, find_item: Callable, loot_system, act_id: int,
		seed_value: int = 0, zone: int = 0, resume: Dictionary = {}) -> void:
	_state = state
	_find_item = find_item
	run = SurvivorRun.new()
	run.setup(state, find_item, loot_system, act_id, seed_value, zone)
	# The zone's look is resolved BEFORE `_build_decoration()` reads it, and before `restore()`:
	# the ground and the props are the same zone the save was walked in, not the act's default.
	_apply_theme(act_id, zone)
	_prop_mesh = null
	# A zone the player already walked is put back from memory BEFORE the screen builds anything
	# that depends on it: the fog cache is keyed on `explored_version` and the camera is placed
	# on `player_pos`, so restoring afterwards would show a map that only catches up a frame
	# later (or not at all, for the fog).
	run.restore(resume)
	_accum = 0.0
	_death_reported = false
	_zone_exited = false
	_paused = false
	set_process(true)
	_toast = ""
	_toast_ticks = 0.0
	_flash = 0.0
	_stick_vec = Vector2.ZERO
	_pointer_down = false
	_stick_index = -1
	_wheel_index = -1
	_wheel_vec = Vector2.ZERO
	_wheel_slot = -1
	_attack_held = false
	_held_spell = ""
	_bind_open = false
	_bind_pick = -1
	# A fresh run has a fresh fog; the cache must not survive into it.
	_fog_tex = null
	_fog_version = -1
	_wheel_slots = _resolve_wheel()
	_build_decoration()
	# The props are static, so they are baked into ONE mesh here — once per zone, never per frame.
	_bake_props()
	_place_camera()
	_layout_buttons()
	queue_redraw()


## Resolve the zone's theme and its ground tile. A missing tile falls back to the shipped grass
## rather than to a flat colour: a zone whose art failed to load must still look like a place.
func _apply_theme(act_id: int, zone: int) -> void:
	_theme = ZoneThemeData.for_zone(act_id, zone)
	var tex := UIKit.load_texture(str(_theme.get("ground_path", GRASS_PATH)))
	_ground = tex if tex != null else _grass


## The "procedurally generated environment": a handful of rules over one seed, not a map.
## Dirt patches break the grass into places; boulders and dead bushes give the eye something
## to run past. Every entry is world-space data and is drawn only when it is on screen.
##
## ⚠️  The props follow the CORRIDOR now, not a rectangle. The wall used to be two rings of rock
## standing on the world's inset border — with the area carved out of a cell grid, that ring would
## stand in the middle of solid rock and the corridor's own turns would have no edge at all. So:
## every FLOOR cell that touches rock gets a boulder, and the interior cover is scattered on floor
## only. The player runs into the same thing that stopped him.
func _build_decoration() -> void:
	_props.clear()
	_patches.clear()
	if run == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	# Dirt patches: only on floor, and never on the wall line.
	for _i in 26:
		var c := Vector2i(rng.randi_range(0, SurvivorRun.COLS - 1), rng.randi_range(0, SurvivorRun.ROWS - 1))
		if not run.is_floor_cell(c.x, c.y):
			continue
		_patches.append({
			"pos": run.cell_centre(c.x, c.y)
				+ Vector2(rng.randf_range(-24, 24), rng.randf_range(-24, 24)),
			"rx": rng.randf_range(38, 96), "ry": rng.randf_range(28, 66),
		})
	# THE WALL. One prop per floor cell that touches rock, pushed a little toward the rock so the
	# rock line the rules stop the hero at is the line the boulders stand on.
	#
	# The KIND comes from the zone's theme (pines, menhirs, masonry, dead trees…), and the wall
	# positions are kept as CANDIDATES for the landmarks: a landmark belongs in the rock beyond
	# the path, which is where the wall cells already look.
	var along := 0
	var wall_spots: Array = []
	for cy in SurvivorRun.ROWS:
		for cx in SurvivorRun.COLS:
			if not run.is_floor_cell(cx, cy):
				continue
			var to_rock := _rock_direction(cx, cy)
			if to_rock == Vector2i.ZERO:
				continue
			var centre: Vector2 = run.cell_centre(cx, cy)
			var pos := centre + Vector2(to_rock) * (SurvivorRun.TILE * 0.5 - 14.0) \
				+ Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7))
			wall_spots.append({"pos": pos, "dir": to_rock})
			# Every other cell only: a boulder per 120 px reads as a wall, one per 60 as a hedge.
			if (cx + cy) % 2 == 1 and rng.randf() < 0.6:
				continue
			_props.append(_wall_prop(pos, along, rng))
			along += 1
	# Interior cover. Sparse on purpose: it is something to run past, and a pack has to be
	# readable from a distance instead of hiding behind a bush.
	#
	# ⚠️  DRY GROUND ONLY. In a bog the walkable cells are PLANKS — a bush growing out of a walkway
	# is a bush standing on a road, and a rock on a bridge is a lie about the collision.
	for _i in 26:
		var c := Vector2i(rng.randi_range(0, SurvivorRun.COLS - 1), rng.randi_range(0, SurvivorRun.ROWS - 1))
		if run.cell_kind_at(c.x, c.y) != SurvivorRun.KIND_GROUND:
			continue
		if _rock_direction(c.x, c.y) != Vector2i.ZERO:
			continue
		var pos: Vector2 = run.cell_centre(c.x, c.y) \
			+ Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20))
		var kind: String = ZoneThemeData.pick_cover(_theme, rng)
		_props.append({
			"pos": pos,
			"kind": kind,
			"size": ZoneThemeData.base_size(kind, rng, false),
			"seed": rng.randf() * 10.0,
		})
	# THE SHORE. Everything that stands in the water along the walkway: reeds in the bog, boulders
	# and rubble on a river bank. Without this the water is an empty colour and the walkway floats
	# in nothing — Jan's "vypadá to pořád stejně" applied to a new surface.
	var shore_kinds: Array = _theme.get("shore", [])
	if not shore_kinds.is_empty():
		for cy in SurvivorRun.ROWS:
			for cx in SurvivorRun.COLS:
				if not run.is_deck_cell(cx, cy):
					continue
				var to_water := _water_direction(cx, cy)
				if to_water == Vector2i.ZERO or rng.randf() > 0.55:
					continue
				var centre: Vector2 = run.cell_centre(cx, cy)
				var kind: String = ZoneThemeData.pick_shore(_theme, rng)
				_props.append({
					"pos": centre + Vector2(to_water) * (SurvivorRun.TILE * 0.62),
					"kind": kind,
					"size": ZoneThemeData.base_size(kind, rng, false),
					"seed": rng.randf() * 10.0,
				})
	_build_landmarks(wall_spots, rng)
	# Nothing may stand on the hero's first step.
	_props = _props.filter(func(p): return (p["pos"] as Vector2).distance_to(run.player_pos) > 70.0)


## The zone's SIGNATURE, placed in the rock beyond the path. One at the hero's arrival (so the
## first frame of the zone already tells him where he is) and the rest spaced along the walk —
## a landmark seen from across the map is what makes two corridors feel like two places.
##
## ⚠️  The spot is chosen from the WALL cells, i.e. from floor cells that touch rock, and then
## pushed a further 46 px INTO the rock: a landmark standing on the path would be a shape the
## hero walks through, and props carry no collision.
func _build_landmarks(wall_spots: Array, rng: RandomNumberGenerator) -> void:
	var marks: Array = _theme.get("marks", [])
	if marks.is_empty() or wall_spots.is_empty():
		return
	# Depths relative to the hero's arrival: just ahead of the clearing, then two thirds of the
	# way along the map. The third entry covers a long zone without crowding the start.
	var targets := [
		run.player_pos + Vector2(0.0, -420.0),
		run.player_pos + Vector2(0.0, -700.0),
		run.player_pos + Vector2(0.0, 520.0),
	]
	# ⚠️  A landmark on a SIDE wall is invisible at the hero's own spawn: the corridor is 7 cells
	# (420 px) wide and a 390x844 portrait phone shows 475 world px, so a side wall lands on the
	# very edge of the frame — measured, the stone circle stood at x = 496 against a hero at 750
	# and never appeared in a capture at all. Only walls the player looks DOWN THE CORRIDOR at
	# (a vertical rock face at a turn or the end of a room) put a landmark in the middle of the
	# screen, so those are the only candidates unless the zone has none.
	var forward: Array = []
	for j in wall_spots.size():
		var d: Vector2i = wall_spots[j]["dir"]
		if d.y != 0:
			forward.append(j)
	if forward.is_empty():
		forward = range(wall_spots.size())
	var used: Array = []
	for i in marks.size():
		var target: Vector2 = targets[i % targets.size()]
		var best := -1
		var best_gap := INF
		# The FIRST landmark is placed by a RAY from the hero, not from the wall list: the wall
		# list only contains floor cells, so a corridor that runs straight ahead has no wall
		# within reach and its landmark ends up 900 px away. A ray finds the rock the corridor
		# actually ENDS at, which is the line the player looks at on arrival.
		if i == 0:
			var spot0 := _landmark_spot(380.0)
			if not spot0.is_empty():
				_props.append({
					"pos": spot0["pos"] as Vector2,
					"kind": str(marks[0]),
					"size": 122.0,
					"seed": rng.randf() * 10.0,
				})
				continue
		for j in forward:
			if used.has(j):
				continue
			var spot: Vector2 = (wall_spots[j]["pos"] as Vector2)
			var crowded := false
			for taken in used:
				if (wall_spots[taken]["pos"] as Vector2).distance_to(spot) < 260.0:
					crowded = true
					break
			if crowded:
				continue
			var gap := spot.distance_to(target) + absf(spot.x - target.x) * 2.0
			if gap < best_gap:
				best_gap = gap
				best = j
		if best < 0:
			continue
		used.append(best)
		var spot: Dictionary = wall_spots[best]
		var face: Vector2i = spot["dir"]
		var out := Vector2(face) * 22.0
		_props.append({
			"pos": (spot["pos"] as Vector2) + out,
			"kind": str(marks[i]),
			"size": 130.0,
			"seed": rng.randf() * 10.0,
		})


## Where the zone's SIGNATURE stands, so the player sees it on the arrival frame. Three rules,
## each of them a measured correction of a placement that looked wrong in a capture:
##
##  1. A landmark in the rock beyond the corridor is the best reading ("the tower is past the
##     path"), but only when the rock is BETWEEN 150 and 700 px ahead — further and the shape is
##     off screen, nearer and it is a prop at his feet;
##  2. When the corridor simply runs on (measured on zone 0: 900 px of open path, no rock), the
##     landmark stands ON the floor of the clearing. A stone circle in a glade is exactly what
##     the painting shows, and props carry no collision, so the hero walks through the ring
##     instead of being stopped by a monument that is only scenery;
##  3. DOWN is the last resort: the bottom of a portrait screen is the HUD, and a landmark placed
##     there is one nobody sees (the circle landed under the joystick).
func _landmark_spot(want: float) -> Dictionary:
	var up := Vector2(0, -1)
	var hit := _ray_hit(up, 900.0)
	if hit > 0.0 and hit <= 700.0:
		return {"pos": run.player_pos + up * (hit + 26.0)}
	var floor_spot := _floor_spot_ahead(up, want)
	if not floor_spot.is_empty():
		return floor_spot
	for dir in [Vector2(1, 0), Vector2(-1, 0)]:
		var side := _ray_hit(dir, 900.0)
		if side > 0.0:
			return {"pos": run.player_pos + dir * (side + 26.0)}
	return {}


## Distance to the first rock cell along `dir`, or -1 when the path is open further than `limit`.
func _ray_hit(dir: Vector2, limit: float) -> float:
	var t := 0.0
	while t < limit:
		t += 20.0
		var c: Vector2i = run.cell_of(run.player_pos + dir * t)
		if not run.is_floor_cell(c.x, c.y):
			return t
	return -1.0


## A point `want` px ahead along `dir` that is FLOOR with floor all round it, so a landmark there
## stands in a clearing instead of hanging over the wall line.
func _floor_spot_ahead(dir: Vector2, want: float) -> Dictionary:
	for step in [0.0, -40.0, 40.0, -80.0, 80.0, -120.0, 120.0]:
		var p: Vector2 = run.player_pos + dir * (want + step)
		var c: Vector2i = run.cell_of(p)
		var ok := true
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if not run.is_floor_cell(c.x + dx, c.y + dy):
					ok = false
		if ok:
			return {"pos": p}
	return {}


## The direction from a floor cell to the ROCK next to it, or ZERO if the cell is interior.
## ⚠️  ROCK ONLY, not "anything that is not floor": water is not a place a pine grows out of, and
## a wall prop on the edge of a river would stand in mid-air over the water.
func _rock_direction(cx: int, cy: int) -> Vector2i:
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if run.cell_kind_at(cx + d.x, cy + d.y) == SurvivorRun.KIND_ROCK:
			return d
	return Vector2i.ZERO


## The direction from a WALKABLE cell to the water next to it, or ZERO. The shore pass reads this.
func _water_direction(cx: int, cy: int) -> Vector2i:
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if run.is_water_cell(cx + d.x, cy + d.y):
			return d
	return Vector2i.ZERO


## One piece of the wall. Bigger and darker than interior cover: at a glance it has to read as
## "the area ends here", not as one more rock to walk around. The MATERIAL is the zone's own —
## a pine wood is edged with pines, the ruined tower with rubble, the bog with dead trees — which
## is the cheapest way for two zones to stop looking like the same place.
func _wall_prop(pos: Vector2, index: int, rng: RandomNumberGenerator) -> Dictionary:
	var kind: String = ZoneThemeData.wall_kind(_theme, index)
	return {
		"pos": pos,
		"kind": kind,
		"size": ZoneThemeData.base_size(kind, rng, true),
		"seed": rng.randf() * 10.0,
	}


## The hero's medallion is the SAME portrait his stat page shows: `hero.face` ->
## `assets/monsters/<face>.png`, the one route the stats panel uses. No second art source.
func _hero_face() -> String:
	if _state == null:
		return "hero"
	return str(_state.hero().get("face", "hero"))


# ============================================================================ input

func _gui_input(event: InputEvent) -> void:
	# TWO FINGERS, TWO JOBS. The stick is owned by ONE touch index; a second finger may press a
	# spell button, the potion or the flurry row at the same time. The old code gated everything
	# on a single `_pointer_down` flag, so the second press was read as the duplicate this
	# engine synthesises and dropped — a spell could not be cast while running.
	if event is InputEventScreenTouch:
		_touch_seen = true
		if event.pressed:
			_on_press(event.position, event.index)
		else:
			_on_release(event.index)
		accept_event()
		return

	if event is InputEventMouseButton:
		if _touch_seen:
			# The synthetic mouse event of a touch. Ignoring ALL of them (not just the second)
			# is what keeps a two-finger gesture from turning into a phantom press.
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_on_press(event.position, 0)
		else:
			_on_release(0)
		accept_event()
		return

	if event is InputEventScreenDrag:
		_on_drag(event.position, event.index)
		accept_event()
		return
	if event is InputEventMouseMotion:
		if _touch_seen:
			return
		# ⚠️  Motion is never gated on a press: a finger DRAG emits no MouseMotion at all, so a
		# motion gate breaks dragging on the phone — but a motion from the index that does not
		# own the stick must be dropped (`_on_drag` checks it).
		_on_drag(event.position, 0)


func _on_press(pos: Vector2, index: int = 0) -> void:
	# The bind panel owns every press while it is open: it is a modal over a live fight.
	if _bind_open:
		_bind_press(pos)
		return
	# A running flurry OWNS the input: its four symbols are the only thing a press may hit, or an
	# action would fire with the thumb that was about to answer the press.
	if run != null and run.whirlwind_open():
		for b in _ww_buttons:
			if (b["centre"] as Vector2).distance_to(pos) <= WW_BUTTON_RADIUS + 8.0:
				_tap_whirlwind(str(b["key"]))
				return
		return
	if _exit_rect.has_point(pos):
		leave_requested.emit()
		return
	# The scroll's own button. Checked BEFORE the world tap, because the portal is a fixed
	# control and a thumb aimed at it must never start a walk instead.
	if _has_portal_scroll() and _portal_rect.has_point(pos):
		portal_requested.emit()
		return
	if _bind_rect.has_point(pos):
		_open_bind()
		return
	# The HERO button, on the second row beside the portal. Checked here (below the `TOP_BAR`
	# guard's y) because it hangs UNDER the bar, over the world.
	if _hero_rect.has_point(pos):
		hero_requested.emit()
		return
	if pos.y < TOP_BAR:
		return
	# The WAYPOINT owns its own tap: it is the only world object a press may use, and it sits
	# in the middle of the map where the walk thumb also lands. Checked before the stick arms
	# so a tap on the stone goes to town instead of starting a walk.
	if run != null and _world_at(pos).distance_to(run.waypoint_point) <= WAYPOINT_RADIUS:
		waypoint_requested.emit()
		return
	# TWO THUMBS, TWO WHEELS, split down the middle of the screen: the LEFT one is the action
	# wheel, the RIGHT one walks. The action wheel is FIXED and permanently drawn, so only a thumb
	# that lands on it (or just outside its ring) owns it — a stray thumb elsewhere in the left half
	# must not arm an action whose wedge it never aimed at.
	if pos.x < size.x * 0.5:
		if _wheel_index >= 0:
			return
		if pos.distance_to(wheel_centre()) > wheel_outer() + wheel_press_slack():
			return
		_wheel_index = index
		_wheel_vec = (pos - wheel_centre()).limit_length(wheel_outer())
		_set_wheel_slot(_wheel_slot_for(pos - wheel_centre()))
		queue_redraw()
		return
	if _stick_index >= 0:
		return
	_stick_index = index
	_pointer_down = true
	_stick_origin = pos
	_stick_vec = Vector2.ZERO
	queue_redraw()


## Screen -> world. The world half is drawn as `(world - _cam) * ZOOM`, so this is its inverse
## and the ONLY place that arithmetic lives.
func _world_at(pos: Vector2) -> Vector2:
	return pos / ZOOM + _cam


func _on_drag(pos: Vector2, index: int = 0) -> void:
	if index == _wheel_index:
		var offset := pos - wheel_centre()
		_wheel_vec = offset.limit_length(wheel_outer())
		# Nothing counts inside the resting disc (Jan): a thumb sitting on the wheel must not run
		# an action. Past it, whichever WEDGE it is in is the action.
		_set_wheel_slot(_wheel_slot_for(offset))
		queue_redraw()
		return
	if index != _stick_index:
		return
	var delta := pos - _stick_origin
	if delta.length() < STICK_DEADZONE:
		_stick_vec = Vector2.ZERO
	else:
		_stick_vec = delta.limit_length(STICK_RADIUS) / STICK_RADIUS
	queue_redraw()


## Where the wheel lives: FIXED in the bottom-left, because Jan wants it permanently visible — "i s
## výsečemi". A fixed wheel is also what makes the wedges learnable: the same action is in the same
## place in every fight, so the player can build muscle memory instead of aiming at an icon.
func wheel_outer() -> float:
	return clampf(size.y * 0.10, WHEEL_OUTER_MIN, WHEEL_OUTER_MAX)


func wheel_inner() -> float:
	return wheel_outer() * 0.55


func wheel_centre() -> Vector2:
	var r := wheel_outer()
	return Vector2(r + WHEEL_MARGIN, size.y - r - WHEEL_BOTTOM_PAD)


## A thumb landing this far outside the ring still owns the wheel — the sectors are BIG, and a
## thumb that lands just past the rim clearly meant to play a wedge.
func wheel_press_slack() -> float:
	return wheel_outer() * 0.28


## Which wedge a thumb offset from the centre points into: -1 inside the resting disc, else the
## sector. One place, so the press, the drag and the release can never disagree.
func _wheel_slot_for(offset: Vector2) -> int:
	if offset.length() < wheel_inner():
		return -1
	return ActionWheel.sector_at(offset)


## Enter (or leave) a wedge. Only the ATTACK is a HOLD, and it is the only thing that starts here;
## a spell or a potion is merely ARMED by being under the thumb and fires on RELEASE, so a drifted
## thumb cannot cast it and one gesture cannot fire it twice.
func _set_wheel_slot(slot: int) -> void:
	if slot == _wheel_slot:
		return
	_wheel_slot = slot
	var action := wheel_action(slot)
	var hold_attack := action == ActionWheel.ATTACK
	_attack_held = hold_attack
	# No spell is held any more (Jan: only the attack holds). The run still understands
	# `held_spell`, but the wheel never sets it — one source of truth, and it is empty.
	_held_spell = ""
	if run != null:
		run.attack_held = hold_attack
		run.held_spell = ""


## What a sector is bound to, or EMPTY.
func wheel_action(slot: int) -> String:
	if slot < 0 or slot >= _wheel_slots.size():
		return ActionWheel.EMPTY
	return str(_wheel_slots[slot])


## A one-shot action. A refused cast still SAYS why (the toast over the arena) — a trigger that
## silently does nothing is indistinguishable from a binding that is wrong.
func _fire_action(action: String) -> void:
	if action == ActionWheel.POTION:
		_drink_potion()
		return
	_cast_spell(action)


func _on_release(index: int = 0) -> void:
	if index == _wheel_index:
		# RELEASE IS THE ACTIVATION for everything but the attack (Jan): "musí do dané výseče
		# vyjet prstem a pak prst pustit/sundat". Read the wedge BEFORE clearing it, then lift:
		# a thumb that drifts back into the resting disc first fires nothing.
		var action := wheel_action(_wheel_slot)
		_wheel_index = -1
		_wheel_vec = Vector2.ZERO
		_set_wheel_slot(-1)
		if action != ActionWheel.EMPTY and not ActionWheel.is_hold(action, RunSpells):
			_fire_action(action)
		queue_redraw()
		return
	# Only the finger that OWNS the stick may stop it; lifting the action thumb must not.
	if index != _stick_index:
		return
	_stick_index = -1
	_pointer_down = false
	_stick_vec = Vector2.ZERO
	queue_redraw()


func _move_vector() -> Vector2:
	if _pointer_down:
		return _stick_vec
	# Desktop/keyboard fallback so the same build can be driven in a browser with WASD.
	return Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")


func _drink_potion() -> void:
	var belt: Array = _state.equip().get("beltPotionSlots", [])
	var used := false
	for id in belt:
		if str(id) == "":
			continue
		if int(_state.consume_potion(str(id))) > 0:
			used = true
			break
	if not used:
		_say("Žádný lektvar v pásu")
		return
	run.hp = mini(run.max_hp, run.hp + int(round(float(run.max_hp) * 0.35)))
	_add_ring()
	Sfx.play_global(Sfx.CUE_POTION)


func _add_ring() -> void:
	run.numbers.append({"pos": run.player_pos + Vector2(0, -40), "text": "Lektvar",
		"kind": "item", "age": 0.0})


func _say(text: String) -> void:
	_toast = text
	_toast_ticks = 2.2


# ============================================================================ loop

func _process(delta: float) -> void:
	if run == null:
		return
	# The gesture state IS the rule's input. Written every frame, because a release can be lost
	# (the phone hands us no event at all when the app is backgrounded mid-hold) and a stale
	# `true` would leave the hero swinging on his own.
	run.attack_held = _attack_held
	run.held_spell = _held_spell
	_accum += minf(delta, 0.25)
	var steps := 0
	while _accum >= STEP and steps < MAX_STEPS_PER_FRAME:
		run.step(STEP, _move_vector())
		_accum -= STEP
		steps += 1
	if _toast_ticks > 0.0:
		_toast_ticks = maxf(0.0, _toast_ticks - delta)
	_flash = maxf(0.0, _flash - delta * 3.0)
	_play_events()
	_whirlwind_feedback()
	# ONE report per run, and the only thing that ends a run is DEATH: an emptied area no longer
	# ends anything (Jan, Nov 2026), so "cleared" is not an outcome the screen can hear.
	if run.finished and run.outcome != "" and not _death_reported:
		_death_reported = true
		stop()
		run_finished.emit(run.outcome)
	# The EXIT gate. Reaching the far end of the zone hands the player one zone deeper; the
	# act's chain is not the screen's business, so this only reports it once.
	if not _zone_exited and run.player_pos.distance_to(run.exit_point) <= EXIT_RADIUS:
		_zone_exited = true
		stop()
		zone_exited.emit()
	_place_camera()
	queue_redraw()


## The RULES decide what a fight sounded like; the screen only plays it. Drained every
## frame so a cue cannot be heard twice, which is the same contract `battle.gd` has.
func _play_events() -> void:
	for cue in run.drain_events():
		match str(cue):
			"hit":
				Sfx.play_global(Sfx.CUE_MELEE_HIT)
				# The phone's half of "something happened". A buzz is a bonus, never the
				# message: on an iPhone or in a desktop browser there is no motor at all.
				Juice.haptic_hit()
			"crit":
				Sfx.play_global(Sfx.CUE_MELEE_CRIT)
				Juice.haptic_crit()
			"kill":
				Sfx.play_global(Sfx.CUE_BLUNT_HIT)
			"hurt":
				Sfx.play_global(Sfx.CUE_HURT)
				_flash = 1.0
				# Being hit buzzes too, and LONGER than the hero's own blow: the player has to
				# be able to tell "I hit it" from "it hit me" without looking.
				Juice.haptic_crit()
			"gold":
				Sfx.play_global(Sfx.CUE_TREASURE)
			"item":
				Sfx.play_global(Sfx.CUE_TREASURE)
			"bagfull":
				_say("Batoh je plný — předmět zůstal na zemi")
			"dead":
				Sfx.play_global(Sfx.CUE_HURT)
			"orb":
				# The throw itself. A caster that fires silently reads as a bug in the hero's
				# health bar, so the cue is part of the feature, not decoration.
				Sfx.play_global(Sfx.CUE_ENEMY_CAST)
			"pack":
				# A pack waking is the beat the whole area model exists for: the player has to
				# HEAR that walking into the next cell started something.
				Sfx.play_global(Sfx.CUE_SHOUT)
			"pack_champion":
				# A champion cell is the same beat DEEPER: a different shout, plus the word, so
				# the player knows the four bodies he just woke are not four strays.
				Sfx.play_global(Sfx.CUE_STRONG_STRIKE)
				_say("Šampionská skupina")
			"pack_elite":
				Sfx.play_global(Sfx.CUE_THUNDER_CLAP)
				_say("Elita se svými otroky")
			"zone":
				_say("Oblast vyčištěna")
			"cleared":
				# NO victory sting: an emptied corridor is not a win any more, it is QUIET, and
				# the player's next move is the exit — say that instead of congratulating him.
				_say("Oblast je prázdná — jdi k východu")
			_:
				# A spell's own cue (thunder_clap, thunder_bolt, shout, dodge, strong_strike,
				# melee_hit …). The rules append the MIXER's name for a spell rather than
				# inventing an event per spell, so the screen plays any cue it knows — the same
				# contract `battle.sound()` has, and the reason a new spell needs no screen code.
				var named := str(cue)
				if Sfx.is_known(named):
					Sfx.play_global(named)


## The flurry's verdict, drained once: a completed flurry says so, a broken one says that
## instead. One call so the word and the strike count can never disagree.
func _whirlwind_feedback() -> void:
	if run == null:
		return
	var res: Dictionary = run.take_whirlwind_result()
	var word := str(res.get("feedback", ""))
	if word == "":
		return
	if word == "complete":
		_say("Whirlwind: %d úderů" % int(res.get("landed", 0)))
	else:
		_say("Whirlwind přerušen")


## The zoom the WHOLE fight is drawn at. Jan: "zmenšíme celkový zoom v souboji. Vše je zbytečně
## velké a blízko. Trochu bych to celé vzdálil a ono to pomůže pocitově i s tím prostorem."
##
## Applied as ONE `draw_set_transform` around the world half of `_draw()`, not as a factor in the
## fifty `pos - _cam` expressions: the camera is computed in world units already (`_cam` is a world
## point), the transform maps that to the screen, and the HUD is drawn after a reset so text and
## bars keep their measured pixel sizes. Everything in the world — tiles, portraits, reach rings,
## damage numbers — shrinks together, which is what "vzdálit" means.
const ZOOM := 0.82
## How close the hero has to get to the zone's exit for the gate to open, in WORLD px. Wide
## enough that a thumb does not have to hit a pixel, narrow enough that walking past the far
## room's edge is not a teleport.
const EXIT_RADIUS := 66.0
## The waypoint's tap radius, in WORLD px (converted from the screen by `_world_at`).
const WAYPOINT_RADIUS := 60.0
## The unexplored veil's alpha (`veil := Color(0,0,0,0.45)` in the old per-cell pass).
const FOG_VEIL_ALPHA := 0.45


## The world transform as a MATRIX, because `draw_set_transform()` REPLACES the canvas transform
## rather than nesting inside it.
##
## ⚠️  This is what made the rocks float. After the zoom pass every contact shadow and grass patch
## did `draw_set_transform(pos, 0, Vector2(1, 0.34))` and then "restored" the transform with
## `draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)` — which was a no-op while the world
## transform WAS identity, but here it throws the 0.82 away. From the first patch onward the whole
## arena was therefore painted at 1.0 over a ground painted at 0.82: walking moved the rocks 1.0x
## over grass moving 0.82x, i.e. every prop slid across the ground exactly like it was floating.
##
## So: local draws COMPOSE with this matrix (`_world_xform() * local`) and every restore returns to
## it, never to `Vector2.ONE`.
func _world_xform() -> Transform2D:
	return Transform2D(Vector2(ZOOM, 0.0), Vector2(0.0, ZOOM), Vector2.ZERO)


## Paint the next shapes in LOCAL world coordinates anchored at `origin`, optionally squashed.
## `scale` is applied before the translation, so a (1, 0.34) shadow sits exactly on `origin`.
func _set_local(origin: Vector2, scale: Vector2 = Vector2.ONE) -> void:
	if _baking:
		# The bake stores WORLD-space points, so the local transform is the prop's own origin and
		# squash — without the ZOOM/camera matrix the live path multiplies in.
		_bake_xf = Transform2D(Vector2(scale.x, 0.0), Vector2(0.0, scale.y), origin)
		return
	draw_set_transform_matrix(_world_xform() * Transform2D(
		Vector2(scale.x, 0.0), Vector2(0.0, scale.y), origin))


## Back to plain world coordinates (i.e. `pos - _cam`, scaled by the zoom).
func _set_world() -> void:
	if _baking:
		_bake_xf = Transform2D()
		return
	draw_set_transform_matrix(_world_xform())



## How much WORLD the screen shows: the canvas divided by the zoom.
func _view_world_size() -> Vector2:
	return size / ZOOM


func _place_camera() -> void:
	if run == null:
		return
	var view := _view_world_size()
	_cam = run.player_pos - view * 0.5
	_cam.x = clampf(_cam.x, 0.0, maxf(0.0, SurvivorRun.WORLD.x - view.x))
	_cam.y = clampf(_cam.y, 0.0, maxf(0.0, SurvivorRun.WORLD.y - view.y))
	# The static world lives in its own viewport and is offset by the camera inside its `_draw()`,
	# so it has to re-emit when the camera moves. The geometry it emits is a baked mesh plus a
	# handful of rects, so this costs a fraction of the old per-cell world pass.
	if _world_layer != null:
		_world_layer.queue_redraw()


## Is a town-portal scroll carried? BOTH forms count — the belt counter AND a scroll lying in the
## bag (that is how a dropped scroll arrives). Jan reported the button missing "even with scrolls"
## because the old check read the counter only, and his scrolls were in the bag.
func _has_portal_scroll() -> bool:
	return TownPortal.available(_state)


## The scroll was used: a portal opens EXACTLY where the hero stands (Jan: "na místě, kde hráč
## stojí, se při použití vytvoří portál"). The run stays where it is — `Main` takes the snapshot
## and the trip — so this only marks the world.
func open_portal() -> void:
	if run == null:
		return
	run.portal_point = run.player_pos
	run.portal_open = true
	queue_redraw()


## Coming BACK through the town's portal: the hero steps out of it at the spot he left, not at
## the zone's entrance. A zone restored from memory is otherwise identical to the one he left.
func arrive_through_portal(pos: Vector2) -> void:
	if run == null:
		return
	run.player_pos = pos
	run.portal_point = pos
	run.portal_open = true
	run._prev_pos = pos
	run._reveal_around(pos)
	_place_camera()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_buttons()
		_size_world_viewport()
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		# ⚠️  A hidden Control STILL RUNS `_process`. Leaving the run therefore kept simulating it
		# behind whatever screen was opened next: monsters kept spawning, the hero kept losing
		# health, and when he died the `run_finished` signal pulled the player back to the road
		# from a screen he was already using. A screen that draws a live fight must own its clock.
		if not is_visible_in_tree():
			stop()
		elif not _paused:
			# ⚠️  NOT unconditional. The character modal keeps this screen VISIBLE underneath it
			# (the PWA dims the screen rather than hiding it), so a visibility change while the
			# player reads his inventory must not restart the clock.
			set_process(true)


## Freeze the fight for the character modal. The run object is kept exactly as it stands — the
## packs, the loot on the floor and the hero's position all survive — and only the clock stops.
func pause_run() -> void:
	_paused = true
	stop()


## Unfreeze it, and re-read everything the SAVE now owns: the player may have equipped a weapon he
## picked up two steps ago or spent a skill point. The wheel is re-resolved too, because a newly
## learned skill belongs in the default bar.
func resume_run() -> void:
	if run == null:
		return
	_paused = false
	run.refresh_from_save()
	_wheel_slots = _resolve_wheel()
	_accum = 0.0
	set_process(true)


## The two fixed controls left in the fight: the way out and the wheel's editor. Both sit in the
## top bar, out of both thumbs' way.
func _layout_buttons() -> void:
	_exit_rect = Rect2(size.x - 96.0, 10.0, 84.0, 34.0)
	_bind_rect = Rect2(size.x - 180.0, 10.0, 76.0, 34.0)
	_portal_rect = Rect2(size.x - 96.0, TOP_BAR + 6.0, 84.0, 34.0)
	_hero_rect = Rect2(size.x - 186.0, TOP_BAR + 6.0, 84.0, 34.0)
	_layout_whirlwind()


## What the wheel is bound to RIGHT NOW. The player's own bindings win; a save without any gets the
## DERIVED default (attack, potion, then the class's spells in bar order) every run. The default is
## never written to disk on its own — it has to keep following the bar as spells are learned, and a
## default written once would freeze the first level's bar into the save forever.
func _resolve_wheel() -> Array:
	var bar: Array = run.spell_bar() if run != null else []
	var saved: Variant = _state.data.get("actionWheel", null) if _state != null else null
	if saved is Array:
		return ActionWheel.normalize(saved)
	return ActionWheel.default_slots(bar)


# ============================================================================ bind panel

func _open_bind() -> void:
	_bind_open = true
	_bind_pick = -1
	# Opening the editor must not leave an action held behind it.
	_set_wheel_slot(-1)
	_layout_bind()
	queue_redraw()


func _close_bind() -> void:
	_bind_open = false
	_bind_pick = -1
	_layout_bind()
	queue_redraw()


## Every action a sector may hold: empty, the two built-ins, then everything the hero could cast
## (bar order — an unbought spell is still listable, it just refuses with a reason).
func _bind_choices() -> Array:
	var out: Array = [ActionWheel.EMPTY, ActionWheel.ATTACK, ActionWheel.POTION]
	if run != null:
		for e in run.spell_bar():
			out.append(str((e as Dictionary).get("id", "")))
	return out


## Rows for BOTH states of the panel, in one place: the slot list (6 rows, two columns) or the
## action list for one slot. `_bind_rects` is what the press handler tests, so a row can never be
## drawn somewhere a tap is not expected.
func _layout_bind() -> void:
	_bind_rects.clear()
	var left := 12.0 + BIND_PAD
	var width := size.x - 24.0 - BIND_PAD * 2.0
	var col_w := (width - BIND_GAP) * 0.5
	var top := 150.0
	if _bind_pick < 0:
		for i in ActionWheel.SLOTS:
			var col := i % 2
			var row := i / 2
			_bind_rects.append({
				"slot": i,
				"action": "",
				"rect": Rect2(left + float(col) * (col_w + BIND_GAP),
					top + float(row) * (BIND_ROW_H + BIND_GAP), col_w, BIND_ROW_H),
			})
		_bind_back_rect = Rect2(left, size.y - 78.0, col_w, BIND_BACK_H)
	else:
		var choices := _bind_choices()
		for i in choices.size():
			var col := i % 2
			var row := i / 2
			_bind_rects.append({
				"slot": i,
				"action": str(choices[i]),
				"rect": Rect2(left + float(col) * (col_w + BIND_GAP),
					top + float(row) * (BIND_PICK_ROW_H + BIND_GAP), col_w, BIND_PICK_ROW_H),
			})
		_bind_back_rect = Rect2(left, size.y - 78.0, col_w, BIND_BACK_H)


func _bind_press(pos: Vector2) -> void:
	if _bind_back_rect.has_point(pos):
		if _bind_pick >= 0:
			_bind_pick = -1
			_layout_bind()
		else:
			_close_bind()
		queue_redraw()
		return
	for r in _bind_rects:
		if (r["rect"] as Rect2).has_point(pos):
			if _bind_pick < 0:
				_bind_pick = int(r["slot"])
				_layout_bind()
			else:
				_assign_slot(_bind_pick, str(r["action"]))
			queue_redraw()
			return


## Put `action` into `slot` and save it. An action lives in ONE sector: binding it elsewhere MOVES
## it, so the player cannot end up with two "attack" sectors and a spell that fires when he means
## to swing.
func _assign_slot(slot: int, action: String) -> void:
	for i in _wheel_slots.size():
		if i != slot and str(_wheel_slots[i]) == action:
			_wheel_slots[i] = ActionWheel.EMPTY
	_wheel_slots[slot] = action
	if _state != null:
		_state.data["actionWheel"] = _wheel_slots.duplicate()
		_state.save()
	_bind_pick = -1
	_layout_bind()


## The flurry's four symbols, in one row across the upper middle of the screen. Above the hero on
## purpose: the fight happens under his portrait, and a row at the bottom would be under the
## thumb that is steering him.
func _layout_whirlwind() -> void:
	_ww_buttons.clear()
	var step := WW_BUTTON_RADIUS * 2.0 + 12.0
	for i in WW_KEYS.size():
		var x := size.x * 0.5 + (float(i) - 1.5) * step
		_ww_buttons.append({"key": str(WW_KEYS[i]), "centre": Vector2(x, WW_ROW_Y)})


## Send one spell to the rules and report a refusal the way the duel does — as a line over the
## arena, not as silence.
func _cast_spell(spell_id: String) -> void:
	if run == null:
		return
	var result: Dictionary = run.cast_spell(spell_id)
	if not bool(result.get("ok", false)):
		_say("Nelze: %s" % str(result.get("message", "")))
	queue_redraw()


func _tap_whirlwind(key: String) -> void:
	if run == null:
		return
	var result: Dictionary = run.answer_whirlwind(key)
	if str(result.get("result", "")) == "fail":
		_say("Whirlwind přerušen")
	queue_redraw()


# ============================================================================ draw

func _draw() -> void:
	if run == null:
		return
	# The backdrop is NOT zoomed: it has to cover the whole canvas whatever the camera does.
	draw_rect(Rect2(Vector2.ZERO, size), Color("#1b1712"))
	# THE STATIC HALF: ground, rock, river, deck and the baked props arrive as ONE texture, rendered
	# at `WORLD_RENDER_SCALE` and stretched back up. Everything below is dynamic and stays at the
	# screen's own resolution.
	if _world_vp != null:
		draw_texture_rect(_world_vp.get_texture(), Rect2(Vector2.ZERO, size), false)
	# Everything the arena IS — the bodies, the reach rings, the numbers — is drawn in
	# SCREEN coordinates that were already shifted by `_cam`, so one scale about the canvas origin
	# is the whole camera zoom. `_place_camera` divides the view by the same `ZOOM`, which is what
	# keeps the hero (and the point a tap aims at) in the middle.
	draw_set_transform_matrix(_world_xform())
	_draw_zone_links()
	_draw_portal()
	_draw_attack_ring()
	_draw_drops()
	_draw_actors()
	_draw_projectiles()
	_draw_bolts()
	_draw_effects()
	_draw_numbers()
	# The fog sits OVER the world — props, bodies, loot and numbers included. That is the point:
	# a pack standing in an unexplored cell is not a fully lit portrait on a black screen.
	_draw_fog()
	# The HUD and the wheel are UI, not world: back to 1:1 or the text would shrink with the zoom.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_hud()
	_draw_wheel()
	_draw_whirlwind()
	# The bind panel is the LAST paint: it is a modal over a live fight and nothing may come up
	# over it.
	if _bind_open:
		_draw_bind_panel()


func _draw_rock() -> void:
	if run == null:
		return
	var view := _view_world_size()
	var c0: Vector2i = run.cell_of(_cam)
	var c1: Vector2i = run.cell_of(_cam + view)
	if _baking:
		# The bake stores the WHOLE grid, not the frame: a camera-culled bake would paint the
		# start room's corner of rock and leave the rest of the zone bare.
		c0 = Vector2i.ZERO
		c1 = Vector2i(SurvivorRun.COLS - 1, SurvivorRun.ROWS - 1)
	var dark: Color = _theme.get("rock", Color("#191510"))
	var rock_line: Color = _theme.get("rock_line", Color("#2e2619"))
	for cy in range(maxi(c0.y, 0), mini(c1.y + 1, SurvivorRun.ROWS)):
		var x := maxi(c0.x, 0)
		var stop := mini(c1.x + 1, SurvivorRun.COLS)
		while x < stop:
			if run.is_floor_cell(x, cy) or run.is_water_cell(x, cy):
				x += 1
				continue
			var start := x
			while x < stop and not run.is_floor_cell(x, cy) and not run.is_water_cell(x, cy):
				x += 1
			var rect := Rect2(Vector2(float(start) * SurvivorRun.TILE,
				float(cy) * SurvivorRun.TILE) - _cam,
				Vector2(float(x - start) * SurvivorRun.TILE, SurvivorRun.TILE))
			# Routed through `_P_*`: `_draw_rock()` is the one painter the BAKE still calls (the rock
			# mesh is built from it in `_bake_props`), and raw `draw_*` outside `_draw()` is an
			# engine error (measured: 3447 of them per test run before this).
			_P_rect(rect, dark)
	# Pass 2: an ORGANIC edge. Filling whole cells makes the corridor a staircase of 60 px
	# squares — the first capture read as "vyříznuté z papíru" — so every rock cell that touches
	# floor is redrawn as a jittered polygon that may overhang the path by a few pixels. The
	# overshoot reads as rock leaning over the trail; where it shrinks the dark pass-1 fill shows
	# through as a crevice, so no bright grass ever leaks between two rocks.
	for cy in range(maxi(c0.y - 1, 0), mini(c1.y + 2, SurvivorRun.ROWS)):
		for cx in range(maxi(c0.x - 1, 0), mini(c1.x + 2, SurvivorRun.COLS)):
			if run.is_floor_cell(cx, cy) or run.is_water_cell(cx, cy) or not _touches_floor(cx, cy):
				continue
			var poly := _rock_polygon(cx, cy)
			for i in poly.size():
				poly[i] -= _cam
			_P_poly(poly, rock_line)
			# The wall is the DARKEST thing on screen and it is most of the frame, so a
			# one-shade outline leaves it reading as a HOLE rather than as rock. One lit
			# ridge per hexagon is what makes it a surface (measured on zone 4, where the
			# pale dirt runs straight into it and the top of the frame went black).
			_P_polyline(poly, rock_line.lightened(0.26), 2.0)


## A rock cell's silhouette: a hexagon with every corner pushed out by a stable pseudo-random
## 4-14 px, so the same cell always draws the same shape (a per-frame `randf()` would make the
## whole wall crawl).
func _rock_polygon(cx: int, cy: int) -> PackedVector2Array:
	var origin := Vector2(float(cx) * SurvivorRun.TILE, float(cy) * SurvivorRun.TILE)
	var seed_v := float((cx * 73856093) ^ (cy * 19349663)) * 0.0001
	var out := PackedVector2Array()
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.2618
		var wobble := 0.72 + fposmod(sin(seed_v * (float(i) + 1.7) * 3.1) * 0.5 + 0.5, 1.0) * 0.34
		out.append(origin + Vector2(SurvivorRun.TILE * 0.5, SurvivorRun.TILE * 0.5)
			+ Vector2(cos(a), sin(a)) * (SurvivorRun.TILE * 0.78 * wobble))
	return out


func _touches_floor(cx: int, cy: int) -> bool:
	return run.is_floor_cell(cx - 1, cy) or run.is_floor_cell(cx + 1, cy) \
		or run.is_floor_cell(cx, cy - 1) or run.is_floor_cell(cx, cy + 1) \
		or run.is_water_cell(cx - 1, cy) or run.is_water_cell(cx + 1, cy) \
		or run.is_water_cell(cx, cy - 1) or run.is_water_cell(cx, cy + 1)


# ============================================================================ water and deck
#
# Jan, Nov 2026: "Močály nebudou mít jen jinou texturu na zemi, ale můžeme doslova napodobit
# dřevěné lávky uprostřed močálů… do močálů se vstoupit nedá a chodit se dá jen po lávkách. Ty
# mohou směřovat různě, ne jen rovně nahoru. Samozřejmě lávky musí mít texturu dřeva."
#
# Both surfaces are drawn FLAT, from the zone's palette, in the same icon language as the props:
# no gradients, no bloom, no textures to download. The water is a colour plus a handful of ripple
# strokes and a darker line where it meets a bank; the deck is planks with seams and a lit edge.

func _draw_fog() -> void:
	if run == null:
		return
	if _fog_tex == null or _fog_version != run.explored_version:
		_rebuild_fog_texture()
		_fog_version = run.explored_version
	# One textured quad. The texture holds a CORNER per texel, so it is drawn half a cell
	# larger on every side: a texel CENTRE then lands exactly on a cell corner and the
	# hardware's bilinear filter reproduces the per-cell corner-alpha ramp for free.
	var t := float(SurvivorRun.TILE)
	var rect := Rect2(Vector2(-0.5 * t, -0.5 * t) - _cam,
		Vector2(float(SurvivorRun.COLS + 1) * t, float(SurvivorRun.ROWS + 1) * t))
	draw_texture_rect(_fog_tex, rect, false)


## Bake the corner-alpha grid the veil is drawn from. Called only when a cell was newly
## explored (`explored_version`), so a frame with no discovery costs zero uploads.
func _rebuild_fog_texture() -> void:
	var w := SurvivorRun.COLS + 1
	var h := SurvivorRun.ROWS + 1
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for vy in h:
		for vx in w:
			var a := _veil_corner(vx, vy) * FOG_VEIL_ALPHA
			img.set_pixel(vx, vy, Color(0.0, 0.0, 0.0, a))
	if _fog_tex == null:
		_fog_tex = ImageTexture.create_from_image(img)
	else:
		_fog_tex.update(img)


## The veil weight at a cell CORNER, i.e. the share of the four cells meeting there that the hero
## has not seen. A cell outside the grid counts as veiled: the world ends in fog, not in grass.
func _veil_corner(vx: int, vy: int) -> float:
	var unseen := 0
	for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var dv: Vector2i = d
		var cx: int = vx + dv.x
		var cy: int = vy + dv.y
		if not run.in_grid(cx, cy) or not run.is_explored_cell(cx, cy):
			unseen += 1
	return float(unseen) / 4.0


## Is a world-space shape — `pos` is already camera-shifted, `extent` its half-size — inside
## the visible stretch of world? The world half is drawn under `ZOOM`, so the view is
## `size / ZOOM` in WORLD units; culling against `size` drops the border while it is still on
## screen (Jan's "objekty ohraničující oblast různě mizí a zase se objevují. Všechny zaráz.").
## Static so the test calls the REAL predicate instead of recomputing it.
static func on_screen(pos: Vector2, extent: float, view: Vector2) -> bool:
	return pos.x + extent >= 0.0 and pos.y + extent >= 0.0 \
		and pos.x - extent <= view.x and pos.y - extent <= view.y


func _draw_patches() -> void:
	# ⚠️  THE CULL IS IN WORLD UNITS, NOT CANVAS PIXELS. Measured: the port culled at
	# `size.x + 180` (570 of a 390 canvas) while the screen really showed 475 world px. Every
	# prop and patch past that line was dropped WHILE STILL ON SCREEN, and because each piece
	# of the border sits on one line, the whole row vanished at once as the camera clamped.
	# Jan: "když chodím kolem okrajů oblasti, objekty ohraničující oblast různě mizí a zase se
	# objevují. Všechny zaráz."
	var view := _view_world_size()
	if _baking:
		# Baking stores the WHOLE zone: an "infinite" view disables the cull without touching the
		# predicate itself (the cull is asserted by `test_survivor`, and the units it uses are the
		# bug it guards against — do not rewrite the line).
		view = Vector2(1.0e9, 1.0e9)
	for p in _patches:
		var pos: Vector2 = (p["pos"] as Vector2) - _cam
		var rx := float(p["rx"])
		if not on_screen(pos, rx, view):
			continue
		# A patch of bare mud is not a thing you find on open water: the patches are laid on
		# FLOOR at build time and a zone's terrain can turn that floor into a bog.
		var pc: Vector2i = run.cell_of(pos + _cam)
		if run.is_water_cell(pc.x, pc.y) or run.is_deck_cell(pc.x, pc.y):
			continue
		var ry := float(p["ry"])
		_set_local(pos, Vector2(1.0, ry / rx))
		var pa: Color = _theme.get("patch_a", Color("#5a503e"))
		var pb: Color = _theme.get("patch_b", Color("#645945"))
		_P_circle(Vector2.ZERO, rx, Color(pa.r, pa.g, pa.b, 0.34))
		_P_circle(Vector2.ZERO, rx * 0.66, Color(pb.r, pb.g, pb.b, 0.26))
	_set_world()


## --- BAKED STATIC LAYER: props and landmarks as ONE mesh -------------------------------
## Jan, Nov 2026: "Takhle graficky primitivní hra se nesmí sekat ani ve snu."
##
## The props are static — they are placed once when the zone is built and never move — yet the
## painter emitted ~120 draw commands for them EVERY FRAME (one per shadow, one per shape, one per
## outline). That is a quarter of a 425-command frame, rebuilt in GDScript 60 times a second for a
## picture that does not change.
##
## So the painter is RUN ONCE per zone into world-space triangles, and the frame draws a single
## ArrayMesh instead. The trick that makes it a small, safe change: the six primitives the prop
## painter uses are routed through `_P_*` wrappers. With `_baking` off they call the engine exactly
## as before (so the picture cannot change if this is ever turned off); with it on they append
## triangles in the SAME order, which is what keeps the painter's layering (a shadow before its
## prop, a cap before its rim) intact.
var _baking := false
var _bake_xf := Transform2D()
var _bake_tris := PackedVector2Array()
var _bake_cols := PackedColorArray()
var _prop_mesh: ArrayMesh = null
var _rock_mesh: ArrayMesh = null


func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	_bake_tris.append(a)
	_bake_tris.append(b)
	_bake_tris.append(c)
	_bake_cols.append(col)
	_bake_cols.append(col)
	_bake_cols.append(col)


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	_tri(a, b, c, col)
	_tri(a, c, d, col)


func _P_rect(r: Rect2, col: Color) -> void:
	if not _baking:
		draw_rect(r, col)
		return
	var p0 := _bake_xf * r.position
	var p1 := _bake_xf * Vector2(r.position.x + r.size.x, r.position.y)
	var p2 := _bake_xf * (r.position + r.size)
	var p3 := _bake_xf * Vector2(r.position.x, r.position.y + r.size.y)
	_quad(p0, p1, p2, p3, col)


func _P_poly(pts: PackedVector2Array, col: Color) -> void:
	if not _baking:
		draw_colored_polygon(pts, col)
		return
	var world := PackedVector2Array()
	for pt in pts:
		world.append(_bake_xf * pt)
	var idx := Geometry2D.triangulate_polygon(world)
	if idx.is_empty():
		return
	for i in range(0, idx.size(), 3):
		_tri(world[idx[i]], world[idx[i + 1]], world[idx[i + 2]], col)


func _P_line(a: Vector2, b: Vector2, col: Color, w: float = -1.0) -> void:
	if not _baking:
		draw_line(a, b, col, w)
		return
	var pa := _bake_xf * a
	var pb := _bake_xf * b
	var d := pb - pa
	if d.length() < 0.01:
		return
	var n := Vector2(-d.y, d.x).normalized() * ((w if w > 0.0 else 1.0) * 0.5)
	_quad(pa - n, pb - n, pb + n, pa + n, col)


func _P_circle(c: Vector2, radius: float, col: Color) -> void:
	if not _baking:
		draw_circle(c, radius, col)
		return
	# 18 sides: a prop is 30-80 px across at the phone's zoom, so the facets are under a pixel.
	var prev := _bake_xf * (c + Vector2(radius, 0.0))
	for i in range(1, 19):
		var a := TAU * float(i) / 18.0
		var cur := _bake_xf * (c + Vector2(cos(a), sin(a)) * radius)
		_tri(_bake_xf * c, prev, cur, col)
		prev = cur


func _P_polyline(pts: PackedVector2Array, col: Color, w: float = -1.0) -> void:
	if not _baking:
		draw_polyline(pts, col, w)
		return
	for i in range(1, pts.size()):
		_P_line(pts[i - 1], pts[i], col, w)


func _P_arc(c: Vector2, radius: float, start: float, end: float, count: int, col: Color,
		w: float = -1.0) -> void:
	if not _baking:
		draw_arc(c, radius, start, end, count, col, w)
		return
	var pts := PackedVector2Array()
	for i in count + 1:
		var a := lerpf(start, end, float(i) / float(maxi(count, 1)))
		pts.append(c + Vector2(cos(a), sin(a)) * radius)
	_P_polyline(pts, col, w)


## The current bake buffer as one mesh, or null when nothing was emitted.
func _mesh_from_bake() -> ArrayMesh:
	if _bake_tris.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _bake_tris
	arrays[Mesh.ARRAY_COLOR] = _bake_cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Bake the zone's props into one mesh. Called from `setup()`, i.e. once per zone, never per frame.
func _bake_props() -> void:
	_bake_tris.clear()
	_bake_cols.clear()
	_prop_mesh = null
	if _props.is_empty():
		return
	var saved_cam := _cam
	# World space: the painter subtracts `_cam` from every prop, so a zero camera stores world
	# coordinates and the frame can put the camera back with ONE transform.
	_cam = Vector2.ZERO
	_baking = true
	_bake_xf = Transform2D()
	# Patches and props share one mesh: they are adjacent in the draw order, so keeping them in
	# one buffer preserves the layering exactly and costs no extra call.
	_draw_patches()
	_draw_props()
	_baking = false
	_cam = saved_cam
	_prop_mesh = _mesh_from_bake()

	# THE ROCK is static too, and it was 69 of a 360-command frame on its own (measured by
	# skip-subtraction). It bakes into its own mesh because it has to be drawn BEFORE the water
	# and the deck, which are painted over it.
	_bake_tris = PackedVector2Array()
	_bake_cols = PackedColorArray()
	_baking = true
	_bake_xf = Transform2D()
	_draw_rock()
	_baking = false
	_rock_mesh = _mesh_from_bake()


func _draw_props() -> void:
	# ⚠️  Cull against the VISIBLE WORLD, not the canvas. See `_draw_patches`: the border is
	# built as one row per side, so a cull line that is short of `size / ZOOM` drops an entire
	# side of the wall at the same instant — Jan's "všechny zaráz". The prop's own size is
	# part of its footprint, so a boulder is not removed while half of it is still on screen.
	var view := _view_world_size()
	if _baking:
		# See `_draw_patches`: the bake keeps every prop, and the cull line stays as the test
		# asserts it.
		view = Vector2(1.0e9, 1.0e9)
	for p in _props:
		var pos: Vector2 = (p["pos"] as Vector2) - _cam
		var s := float(p["size"])
		var extent := s * 1.6
		if not on_screen(pos, extent, view):
			continue
		# A dark disc on a dark ground reads as a shadow with nothing casting it — Jan's own
		# report on the first render. Every prop therefore has a BODY and a lit edge.
		_set_local(pos + Vector2(0, s * 0.16), Vector2(1.0, 0.30))
		_P_circle(Vector2.ZERO, s * 0.52, Color(0, 0, 0, 0.36))
		_set_local(pos)
		# A landmark composes several shapes, so it needs to place sub-parts RELATIVE to the
		# prop's own origin. `_set_local()` takes an absolute canvas point, so the base is kept
		# here and `_set_prop_offset()` adds to it.
		_prop_base = pos
		_draw_prop_kind(str(p["kind"]), s, float(p["seed"]))
	_set_world()


## One palette entry as a Color. The theme is already expanded, but a screen built before a run
## exists has the DEFAULT theme too — so a missing key must never throw mid-draw.
func _col(key: String, fallback: String) -> Color:
	var value: Variant = _theme.get(key, null)
	if value is Color:
		return value
	return Color(fallback)


## Place the next shapes at `off` from the CURRENT prop's own ground point, in the prop's flat
## local space. Needed by the landmarks, which are several shapes standing on one spot.
func _set_prop_offset(off: Vector2) -> void:
	_set_local(_prop_base + off)


## An ellipse as a polygon. The prop painter works in a FLAT local space (no squash in the node
## transform, because a squashed transform would also squash the line widths), so every round
## shape is emitted as points instead.
func _ellipse_pts(c: Vector2, rx: float, ry: float, n: int = 14) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


## The half of an ellipse ABOVE its centre — a mushroom cap, a cairn stone's dome, a fountain
## rim seen from the game's own high angle.
func _dome_pts(c: Vector2, rx: float, ry: float, n: int = 10) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var a := PI + PI * float(i) / float(n)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


## Every prop the game can build, as its own ICON. Deliberately coarse: at the 0.82 zoom the
## phone plays at, a 60 px pine is 49 px tall, so a pine is a trunk and three triangles and a
## menhir is four straight edges. Anything finer is four grey pixels nobody reads.
##
## The palette comes from the ZONE (`ZoneTheme`), never from this function, so the same shape
## reads as a pale ruin in zone 2 and as a warm village post in zone 6.
func _draw_prop_kind(kind: String, s: float, seed_v: float) -> void:
	match kind:
		"rock":
			_prop_rock(s, seed_v)
		"bush":
			_prop_bush(s)
		"menhir":
			_prop_menhir(s)
		"pine":
			_prop_pine(s, seed_v)
		"dead_tree":
			_prop_dead_tree(s, seed_v)
		"reed":
			_prop_reed(s, seed_v)
		"stump":
			_prop_stump(s)
		"column":
			_prop_column(s)
		"rubble":
			_prop_rubble(s, seed_v)
		"cairn":
			_prop_cairn(s)
		"plank":
			_prop_plank(s, seed_v)
		"fern":
			_prop_fern(s, seed_v)
		"mushroom":
			_prop_mushroom(s)
		"barrel":
			_prop_barrel(s)
		"hut":
			_prop_hut(s)
		"torch":
			_prop_torch(s)
		"fence":
			_prop_fence(s)
		"wall_block":
			_prop_wall_block(s)
		"root":
			_prop_root(s, seed_v)
		_:
			_draw_landmark(kind, s, seed_v)


func _prop_rock(s: float, seed_v: float) -> void:
	var pts := PackedVector2Array([
		Vector2(-s * 0.52, 0.0), Vector2(-s * 0.30, -s * 0.62),
		Vector2(s * 0.16, -s * 0.78), Vector2(s * 0.50, -s * 0.20),
		Vector2(s * 0.28, s * 0.10), Vector2(-s * 0.34, s * 0.06),
	])
	_P_poly(pts, _col("stone", "#6a614f"))
	_P_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3]]),
		_col("stone_light", "#857a63"), 2.0)
	_P_line(Vector2(-s * 0.1, -s * 0.1), Vector2(s * 0.2, -s * 0.35),
		Color(0, 0, 0, 0.25 + 0.05 * seed_v), 1.5)


func _prop_bush(s: float) -> void:
	_P_circle(Vector2(0, -s * 0.30), s * 0.60, _col("foliage", "#373c26"))
	_P_circle(Vector2(-s * 0.14, -s * 0.44), s * 0.36, _col("foliage_light", "#454b2f"))
	_P_arc(Vector2(0, -s * 0.30), s * 0.60, PI * 1.15, PI * 1.95, 14,
		_col("foliage_light", "#5e6440").lightened(0.10), 2.0)


## An upright slab, wider at the foot, with one carved mark. It is the same silhouette from any
## angle — the point of a menhir is that the eye reads it as "made by someone".
func _prop_menhir(s: float) -> void:
	var pts := PackedVector2Array([
		Vector2(-s * 0.30, 0.0), Vector2(-s * 0.23, -s * 1.04),
		Vector2(-s * 0.03, -s * 1.20), Vector2(s * 0.22, -s * 0.94),
		Vector2(s * 0.28, 0.0),
	])
	_P_poly(pts, _col("stone", "#6b6a5c"))
	_P_polyline(PackedVector2Array([pts[0], pts[1], pts[2]]), _col("stone_light", "#8a8975"), 2.0)
	var accent := _col("accent", "#5f8f7a").darkened(0.15)
	_P_line(Vector2(0, -s * 0.72), Vector2(0, -s * 0.44), accent, 2.0)
	_P_circle(Vector2(0, -s * 0.82), s * 0.055, accent)


## A conifer: a trunk and three triangles, the widest at the bottom. Darker at the base and
## lighter at the crown, which is what gives a stand of them depth without any shading pass.
func _prop_pine(s: float, seed_v: float) -> void:
	_P_rect(Rect2(-s * 0.08, -s * 0.46, s * 0.16, s * 0.46), _col("wood", "#3c2e20"))
	var dark := _col("foliage", "#2b3421")
	var light := _col("foliage_light", "#39442c")
	var lean := (fposmod(seed_v, 1.0) - 0.5) * s * 0.10
	for i in 3:
		var by := -s * (0.26 + 0.24 * float(i))
		var hw := s * (0.50 - 0.13 * float(i))
		var tone := dark if i % 2 == 0 else light
		_P_poly(PackedVector2Array([
			Vector2(-hw + lean, by), Vector2(hw + lean, by),
			Vector2(lean, by - s * 0.44),
		]), tone)
	_P_line(Vector2(lean, -s * 1.14), Vector2(lean, -s * 0.98), light, 2.0)


## A bare trunk with two bent limbs. In the bog and in the ruin it is the WALL, so it has to be
## taller than a bush and thinner than a rock — a silhouette you see the corridor's edge in.
func _prop_dead_tree(s: float, seed_v: float) -> void:
	var bend := (fposmod(seed_v * 1.7, 1.0) - 0.5) * s * 0.16
	var wood := _col("wood", "#3f3427")
	var wood_light := _col("wood_light", "#524534")
	_P_poly(PackedVector2Array([
		Vector2(-s * 0.10, 0.0), Vector2(-s * 0.05, -s * 0.60),
		Vector2(bend * 0.4, -s * 1.00), Vector2(s * 0.04, -s * 0.62),
		Vector2(s * 0.11, 0.0),
	]), wood)
	_P_line(Vector2(bend * 0.4, -s * 0.62), Vector2(bend - s * 0.34, -s * 0.90), wood_light, 3.0)
	_P_line(Vector2(bend * 0.6, -s * 0.80), Vector2(bend + s * 0.30, -s * 1.02), wood_light, 2.5)


func _prop_reed(s: float, seed_v: float) -> void:
	var light := _col("foliage_light", "#3a4a37")
	var dark := _col("foliage", "#2c3a2c")
	for k in 6:
		var t := float(k) / 5.0
		var x := (t - 0.5) * s * 0.9
		var h := s * (0.52 + 0.30 * absf(sin(seed_v * 2.3 + float(k))))
		var col := light if k % 2 == 0 else dark
		_P_line(Vector2(x * 0.35, 0.0), Vector2(x, -h), col, 2.0)
		# a seed head, drawn as one flat lozenge — the bog's "cattail" tell at a glance
		if k % 3 == 0:
			_P_poly(_ellipse_pts(Vector2(x, -h - s * 0.06), s * 0.035, s * 0.09, 6), dark)


func _prop_stump(s: float) -> void:
	var wood := _col("wood", "#4a3a28")
	_P_rect(Rect2(-s * 0.26, -s * 0.30, s * 0.52, s * 0.30), wood)
	_P_poly(_ellipse_pts(Vector2(0, -s * 0.30), s * 0.26, s * 0.10), _col("wood_light", "#634c33"))
	_P_poly(_ellipse_pts(Vector2(0, -s * 0.30), s * 0.13, s * 0.05), wood.darkened(0.18))


## A fallen drum of a column lying across the ground, one end face turned to the camera. Two of
## these in a row already say "this was a building" without a single wall standing.
func _prop_column(s: float) -> void:
	var stone := _col("stone", "#767a80")
	var light := _col("stone_light", "#93979d")
	var r := s * 0.20
	_P_rect(Rect2(-s * 0.55, -2.0 * r, s * 0.88, 2.0 * r), stone)
	_P_line(Vector2(-s * 0.55, -2.0 * r), Vector2(s * 0.33, -2.0 * r), light, 2.0)
	_P_poly(_ellipse_pts(Vector2(s * 0.33, -r), r * 0.55, r), light)
	_P_poly(_ellipse_pts(Vector2(s * 0.33, -r), r * 0.30, r * 0.55), stone.darkened(0.12))


func _prop_rubble(s: float, seed_v: float) -> void:
	var stone := _col("stone", "#767a80")
	var light := _col("stone_light", "#93979d")
	for k in 3:
		var t := float(k)
		var cx := (t - 1.0) * s * 0.30 + fposmod(seed_v + t, 1.0) * s * 0.08
		var hw := s * (0.20 - 0.04 * t)
		var h := s * (0.34 - 0.07 * t)
		var pts := PackedVector2Array([
			Vector2(cx - hw, 0.0), Vector2(cx - hw * 0.6, -h),
			Vector2(cx + hw * 0.4, -h * 0.86), Vector2(cx + hw, 0.0),
		])
		_P_poly(pts, stone if k % 2 == 0 else stone.darkened(0.08))
		_P_polyline(PackedVector2Array([pts[0], pts[1], pts[2]]), light, 1.5)


## A trail marker: three stones, each smaller than the one under it.
func _prop_cairn(s: float) -> void:
	var stone := _col("stone", "#79705f")
	var light := _col("stone_light", "#968c78")
	var y := 0.0
	var w := s * 0.34
	for k in 3:
		var h := w * 0.62
		_P_poly(_dome_pts(Vector2(0, y), w, h), stone if k % 2 == 0 else stone.darkened(0.07))
		_P_arc(Vector2(0, y), w, PI, TAU, 8, light, 1.5)
		y -= h * 0.92
		w *= 0.72


## A broken board of the old walkway: two boards at different angles, one of them sunken.
func _prop_plank(s: float, seed_v: float) -> void:
	var wood := _col("wood", "#3f3427")
	var light := _col("wood_light", "#524534")
	for k in 2:
		var ang := (fposmod(seed_v + float(k) * 3.1, 1.0) - 0.5) * 0.5
		var cx := (float(k) - 0.5) * s * 0.34
		var cy := -s * (0.10 + 0.06 * float(k))
		var dir := Vector2(cos(ang), sin(ang))
		var across := Vector2(-dir.y, dir.x)
		var a := Vector2(cx, cy) - dir * s * 0.40
		var b := Vector2(cx, cy) + dir * s * 0.40
		var t := s * 0.06
		_P_poly(PackedVector2Array([
			a - across * t, b - across * t, b + across * t, a + across * t,
		]), wood)
		_P_line(a + across * t, b + across * t, light, 1.5)


func _prop_fern(s: float, seed_v: float) -> void:
	var col := _col("foliage_light", "#3b4e40")
	var swing := (fposmod(seed_v, 1.0) - 0.5) * 0.5
	for k in 5:
		var ang := -PI * 0.5 + (float(k) - 2.0) * 0.40 + swing * 0.2
		var p1 := Vector2(cos(ang), sin(ang)) * s * 0.44
		var p2 := p1 + Vector2(cos(ang + swing), sin(ang + swing)) * s * 0.28
		_P_line(Vector2.ZERO, p1, col, 2.0)
		_P_line(p1, p2, col, 1.5)


func _prop_mushroom(s: float) -> void:
	_P_rect(Rect2(-s * 0.05, -s * 0.22, s * 0.10, s * 0.22), _col("stone_light", "#8a8975"))
	var cap := _col("accent", "#6fb3a0").darkened(0.18)
	_P_poly(_dome_pts(Vector2(0, -s * 0.22), s * 0.20, s * 0.17), cap)
	_P_arc(Vector2(0, -s * 0.22), s * 0.20, PI, TAU, 8, cap.lightened(0.12), 1.5)


func _prop_barrel(s: float) -> void:
	var wood := _col("wood", "#4d3a26")
	_P_rect(Rect2(-s * 0.22, -s * 0.50, s * 0.44, s * 0.50), wood)
	_P_poly(_ellipse_pts(Vector2(0, -s * 0.50), s * 0.22, s * 0.08), _col("wood_light", "#634c33"))
	for y in [-s * 0.16, -s * 0.38]:
		_P_rect(Rect2(-s * 0.24, float(y), s * 0.48, s * 0.05), wood.darkened(0.30))


## A hut is a box and a gable. No window light: Jan's rule is no glow, and a village of lit
## windows at night would be the only glowing thing in the game.
func _prop_hut(s: float) -> void:
	var wood := _col("wood", "#4d3a26")
	_P_rect(Rect2(-s * 0.38, -s * 0.52, s * 0.76, s * 0.52), wood)
	_P_poly(PackedVector2Array([
		Vector2(-s * 0.50, -s * 0.52), Vector2(s * 0.50, -s * 0.52), Vector2(0.0, -s * 0.98),
	]), _col("wood_light", "#634c33").darkened(0.25))
	_P_line(Vector2(-s * 0.50, -s * 0.52), Vector2(s * 0.50, -s * 0.52),
		_col("wood_light", "#634c33"), 2.0)
	_P_rect(Rect2(-s * 0.09, -s * 0.28, s * 0.18, s * 0.28), _col("rock", "#1b1610"))


func _prop_torch(s: float) -> void:
	_P_rect(Rect2(-s * 0.045, -s * 0.66, s * 0.09, s * 0.66), _col("wood_light", "#634c33"))
	var flame := _col("accent", "#b8763a")
	_P_poly(PackedVector2Array([
		Vector2(-s * 0.09, -s * 0.62), Vector2(0.0, -s * 0.94), Vector2(s * 0.09, -s * 0.62),
	]), flame)
	_P_poly(PackedVector2Array([
		Vector2(-s * 0.04, -s * 0.62), Vector2(0.0, -s * 0.80), Vector2(s * 0.04, -s * 0.62),
	]), flame.lightened(0.18))


func _prop_fence(s: float) -> void:
	var wood := _col("wood", "#4d3a26")
	var light := _col("wood_light", "#634c33")
	for x in [-s * 0.38, s * 0.38]:
		_P_rect(Rect2(float(x) - s * 0.05, -s * 0.60, s * 0.10, s * 0.60), wood)
	for y in [-s * 0.44, -s * 0.22]:
		_P_rect(Rect2(-s * 0.44, float(y), s * 0.88, s * 0.06), light)


## A segment of standing masonry — the fortress's edge, not a rock. One course line per brick
## row and staggered joints, so it reads as BUILT at 49 px.
func _prop_wall_block(s: float) -> void:
	var stone := _col("stone", "#6e726b")
	var line := stone.darkened(0.30)
	_P_rect(Rect2(-s * 0.50, -s * 0.82, s * 1.00, s * 0.82), stone)
	_P_line(Vector2(-s * 0.50, -s * 0.82), Vector2(s * 0.50, -s * 0.82), _col("stone_light", "#8b8f86"), 2.0)
	for row in 3:
		var y := -s * (0.22 + 0.22 * float(row))
		_P_line(Vector2(-s * 0.50, y), Vector2(s * 0.50, y), line, 1.5)
		var off := 0.0 if row % 2 == 0 else s * 0.22
		for k in 2:
			var x := -s * 0.25 + off + float(k) * s * 0.45
			_P_line(Vector2(x, y), Vector2(x, y + s * 0.22), line, 1.5)


## A thick root crawling out of the ground and over whatever is in its way. The gate's ruin is
## strangled by these, so the wall in zone 9 is half masonry and half root.
func _prop_root(s: float, seed_v: float) -> void:
	var pts := PackedVector2Array()
	var lift := s * (0.34 + 0.10 * fposmod(seed_v, 1.0))
	for i in 6:
		var t := float(i) / 5.0
		var x := (t - 0.5) * s * 1.05
		var y := -sin(t * PI) * lift
		pts.append(Vector2(x, y))
	_P_polyline(pts, _col("wood", "#463424"), s * 0.15)
	_P_polyline(pts, _col("wood_light", "#5a4530"), s * 0.07)


## ── landmarks ────────────────────────────────────────────────────────────────────────────────
## The zone's signature, four to six times the size of cover and drawn in the ROCK beyond the
## path (see `_build_landmarks`). One shape each, recognisable from across the map, in the flat
## palette of the zone's own painting.
func _draw_landmark(kind: String, s: float, seed_v: float) -> void:
	match kind:
		"lm_circle":
			_lm_circle(s)
		"lm_grove":
			_lm_grove(s, seed_v)
		"lm_tower":
			_lm_tower(s)
		"lm_fallen_log":
			_lm_fallen_log(s)
		"lm_bridge":
			_lm_bridge(s)
		"lm_cairn_field":
			_lm_cairn_field(s)
		"lm_village":
			_lm_village(s)
		"lm_fountain":
			_lm_fountain(s)
		"lm_watchtower":
			_lm_watchtower(s)
		"lm_gate":
			_lm_gate(s)
		_:
			_prop_rock(s, seed_v)


## Zone 0 — the ring of standing stones. Nearer stones are drawn last so the ring reads as a
## ring and not as a row.
func _lm_circle(s: float) -> void:
	var stone := _col("stone", "#6b6a5c")
	var light := _col("stone_light", "#8a8975")
	var accent := _col("accent", "#5f8f7a").darkened(0.20)
	var rx := s * 0.95
	var ry := s * 0.42
	var order := [5, 0, 4, 1, 3, 2]
	for i in order:
		var a := TAU * float(i) / 6.0 + 0.4
		var base := Vector2(cos(a) * rx, sin(a) * ry)
		var h := s * (0.52 + 0.12 * float(i % 2))
		var hw := s * 0.10
		_P_poly(PackedVector2Array([
			base + Vector2(-hw * 1.3, 0), base + Vector2(-hw, -h),
			base + Vector2(hw * 0.9, -h * 0.94), base + Vector2(hw * 1.25, 0),
		]), stone)
		_P_line(base + Vector2(-hw * 1.3, 0), base + Vector2(-hw, -h), light, 2.0)
	# the altar in the middle: a flat slab, no flame, no glow
	_P_poly(_ellipse_pts(Vector2(0, -s * 0.06), s * 0.30, s * 0.13), stone.darkened(0.12))
	_P_poly(_ellipse_pts(Vector2(0, -s * 0.10), s * 0.26, s * 0.11), light.darkened(0.10))
	_P_circle(Vector2(0, -s * 0.10), s * 0.05, accent)


## Zone 1 — three pines taller than any wall prop: the wood closes over the road.
func _lm_grove(s: float, seed_v: float) -> void:
	# FIVE pines, the middle one the tallest: three read as "some trees", five read as a stand
	# that closes the road.
	var spots := [[-0.72, 0.78], [-0.34, 1.02], [0.04, 1.22], [0.42, 0.94], [0.74, 0.70]]
	for i in 5:
		var x := float(spots[i][0]) * s
		var h := float(spots[i][1]) * s
		_set_prop_offset(Vector2(x, 0.0))
		_prop_pine(h * 0.98, seed_v + float(i) * 2.3)
	_set_prop_offset(Vector2.ZERO)


## Zone 2 — the tower, broken at the top. Its shadow is the landmark as much as its shape.
func _lm_tower(s: float) -> void:
	var stone := _col("stone", "#767a80")
	var light := _col("stone_light", "#93979d")
	var dark := stone.darkened(0.22)
	# tower body, tapering, with a jagged broken silhouette
	_P_poly(PackedVector2Array([
		Vector2(-s * 0.34, 0), Vector2(-s * 0.26, -s * 1.42),
		Vector2(-s * 0.08, -s * 1.52), Vector2(s * 0.02, -s * 1.34),
		Vector2(s * 0.14, -s * 1.46), Vector2(s * 0.26, -s * 1.20),
		Vector2(s * 0.32, 0),
	]), stone)
	_P_line(Vector2(-s * 0.34, 0), Vector2(-s * 0.26, -s * 1.42), light, 2.0)
	# two slit windows and a door arch
	_P_rect(Rect2(-s * 0.06, -s * 1.16, s * 0.09, s * 0.20), dark)
	_P_rect(Rect2(-s * 0.06, -s * 0.86, s * 0.09, s * 0.20), dark)
	_P_poly(_dome_pts(Vector2(-s * 0.01, -s * 0.06), s * 0.11, s * 0.18), dark)
	# rubble at the foot
	for k in 3:
		var cx := (float(k) - 1.0) * s * 0.26
		_P_poly(_dome_pts(Vector2(cx, 0.0), s * 0.11, s * 0.10), stone.darkened(0.10))


## Zone 3 — the giant trunk that fell across the bog. The boardwalk is built around it.
func _lm_fallen_log(s: float) -> void:
	var wood := _col("wood", "#3f3427")
	var light := _col("wood_light", "#524534")
	var body := PackedVector2Array([
		Vector2(-s * 0.95, -s * 0.02), Vector2(-s * 0.95, -s * 0.30),
		Vector2(s * 0.85, -s * 0.38), Vector2(s * 0.90, -s * 0.06),
	])
	_P_poly(body, wood)
	_P_line(Vector2(-s * 0.95, -s * 0.30), Vector2(s * 0.85, -s * 0.38), light, 2.5)
	# root disc at the near end
	_P_poly(_ellipse_pts(Vector2(-s * 0.95, -s * 0.16), s * 0.20, s * 0.28, 10), wood.darkened(0.18))
	# moss along the top — flat, no sheen
	_P_line(Vector2(-s * 0.60, -s * 0.32), Vector2(s * 0.50, -s * 0.36),
		_col("foliage", "#2c3a2c").lightened(0.10), 3.0)


## Zone 5 — the stone bridge. Deck, parapets and two pillars standing in the canyon.
func _lm_bridge(s: float) -> void:
	var stone := _col("stone", "#6d7375")
	var light := _col("stone_light", "#8a9092")
	var dark := stone.darkened(0.24)
	for x in [-s * 0.62, s * 0.58]:
		_P_rect(Rect2(float(x) - s * 0.09, -s * 0.40, s * 0.18, s * 0.40), dark)
	_P_rect(Rect2(-s * 1.05, -s * 0.56, s * 2.10, s * 0.18), stone)
	_P_line(Vector2(-s * 1.05, -s * 0.56), Vector2(s * 1.05, -s * 0.56), light, 2.5)
	# parapet: two low walls with a gap in the middle, so the deck reads as a way through
	_P_rect(Rect2(-s * 1.05, -s * 0.74, s * 0.78, s * 0.18), stone.darkened(0.10))
	_P_rect(Rect2(s * 0.27, -s * 0.74, s * 0.78, s * 0.18), stone.darkened(0.10))
	# the arch under the deck
	var arch := PackedVector2Array()
	for i in 9:
		var a := PI + PI * float(i) / 8.0
		arch.append(Vector2(cos(a) * s * 0.55, -s * 0.38 + sin(a) * s * 0.16))
	_P_polyline(arch, light, 2.0)


## Zone 4 — the valley's cairns, three of them, the tall one in the middle.
func _lm_cairn_field(s: float) -> void:
	var spots := [[-0.72, 0.60], [0.02, 0.92], [0.66, 0.48]]
	for i in 3:
		_set_prop_offset(Vector2(float(spots[i][0]) * s, 0.0))
		_prop_cairn(float(spots[i][1]) * s)
	_set_prop_offset(Vector2.ZERO)


## Zone 6 — the village up the trunks: two huts on stilts, a ladder between them.
func _lm_village(s: float) -> void:
	# stilts under both huts
	for x in [-0.42, 0.30]:
		for dx in [-0.16, 0.16]:
			_P_rect(Rect2(float(x) + float(dx) * s - s * 0.03, -s * 0.30, s * 0.06, s * 0.30),
				_col("wood", "#4d3a26"))
	_set_prop_offset(Vector2(-s * 0.42, -s * 0.30))
	_prop_hut(s * 0.52)
	_set_prop_offset(Vector2(s * 0.34, -s * 0.24))
	_prop_hut(s * 0.40)
	_set_prop_offset(Vector2.ZERO)
	# the ladder between them
	var wood := _col("wood_light", "#634c33")
	_P_line(Vector2(-s * 0.16, -s * 0.34), Vector2(s * 0.10, -s * 0.58), wood, 2.0)
	_P_line(Vector2(-s * 0.10, -s * 0.30), Vector2(s * 0.16, -s * 0.54), wood, 2.0)
	for k in 3:
		var t := 0.25 + 0.25 * float(k)
		var a := Vector2(-s * 0.16, -s * 0.34).lerp(Vector2(s * 0.10, -s * 0.58), t)
		_P_line(a, a + Vector2(-s * 0.06, 0.04 * s), wood, 1.5)


## Zone 7 — the spring: a stone basin holding flat water. The one "magic" thing in act 1, and it
## is still a flat colour with no halo.
func _lm_fountain(s: float) -> void:
	var stone := _col("stone", "#6a7268")
	var light := _col("stone_light", "#868e80")
	var water := _col("accent", "#6fb3a0")
	_P_poly(_ellipse_pts(Vector2(0, -s * 0.16), s * 0.86, s * 0.40, 18), stone.darkened(0.14))
	_P_poly(_ellipse_pts(Vector2(0, -s * 0.20), s * 0.76, s * 0.34, 18), stone)
	_P_poly(_ellipse_pts(Vector2(0, -s * 0.20), s * 0.62, s * 0.26, 18), water.darkened(0.10))
	_P_arc(Vector2(0, -s * 0.20), s * 0.86, PI * 1.02, PI * 1.98, 20, light, 2.5)
	# the spring stone in the middle
	_P_poly(_ellipse_pts(Vector2(0, -s * 0.22), s * 0.16, s * 0.09), stone.darkened(0.20))
	_P_rect(Rect2(-s * 0.07, -s * 0.34, s * 0.14, s * 0.14), stone)


## Zone 8 — the fortress on the far bank: a square tower with crenellations.
func _lm_watchtower(s: float) -> void:
	var stone := _col("stone", "#6e726b")
	var light := _col("stone_light", "#8b8f86")
	var dark := stone.darkened(0.26)
	_P_rect(Rect2(-s * 0.36, -s * 1.34, s * 0.72, s * 1.34), stone)
	_P_line(Vector2(-s * 0.36, -s * 1.34), Vector2(-s * 0.36, 0), light, 2.0)
	# crenellations
	for k in 3:
		_P_rect(Rect2(-s * 0.36 + float(k) * s * 0.26, -s * 1.48, s * 0.16, s * 0.16), stone)
	# slit windows
	_P_rect(Rect2(-s * 0.05, -s * 1.02, s * 0.10, s * 0.22), dark)
	_P_rect(Rect2(-s * 0.05, -s * 0.62, s * 0.10, s * 0.22), dark)
	_P_rect(Rect2(-s * 0.10, -s * 0.26, s * 0.20, s * 0.26), dark)


## Zone 9 — the broken gate, strangled by roots: two pillars, the arch fallen between them.
func _lm_gate(s: float) -> void:
	var stone := _col("stone", "#736a58")
	var light := _col("stone_light", "#8f8570")
	for x in [-0.66, 0.60]:
		var bx := float(x) * s
		_P_rect(Rect2(bx - s * 0.13, -s * 1.20, s * 0.26, s * 1.20), stone)
		_P_line(Vector2(bx - s * 0.13, -s * 1.20), Vector2(bx - s * 0.13, 0), light, 2.0)
		_P_rect(Rect2(bx - s * 0.17, -s * 1.28, s * 0.34, s * 0.10), stone.darkened(0.08))
	# the fallen arch: a stump on each pillar and nothing between them
	_P_poly(PackedVector2Array([
		Vector2(-s * 0.53, -s * 1.06), Vector2(-s * 0.20, -s * 1.02),
		Vector2(-s * 0.26, -s * 0.92), Vector2(-s * 0.53, -s * 0.94),
	]), stone.darkened(0.06))
	_P_poly(PackedVector2Array([
		Vector2(s * 0.14, -s * 0.98), Vector2(s * 0.47, -s * 0.90),
		Vector2(s * 0.43, -s * 0.80), Vector2(s * 0.16, -s * 0.86),
	]), stone.darkened(0.06))
	# roots crawling over both pillars
	for x in [-0.66, 0.60]:
		var bx := float(x) * s
		var pts := PackedVector2Array()
		for i in 6:
			var t := float(i) / 5.0
			pts.append(Vector2(bx - s * 0.22 + t * s * 0.44, -s * 1.10 - sin(t * PI) * s * 0.10))
		_P_polyline(pts, _col("wood", "#463424"), s * 0.10)
	_set_prop_offset(Vector2(-s * 0.05, 0.0))
	_prop_root(s * 0.55, 0.3)
	_set_prop_offset(Vector2.ZERO)


func _disc(face: String) -> Texture2D:
	if _disc_cache.has(face):
		return _disc_cache[face]
	var src := UIKit.load_texture(face)
	var tex: Texture2D = null
	if src != null:
		var img := src.get_image()
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			var side := mini(img.get_width(), img.get_height())
			img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
			img.resize(192, 192, Image.INTERPOLATE_BILINEAR)
			# A portrait is a BUST on a near-black plate: cropped to a circle it reads as a
			# medallion, which is exactly the "walking portrait" the design asks for. The crop
			# is what removes the black square Jan rejected in the duel arena.
			for y in 192:
				for x in 192:
					var dx := float(x) - 95.5
					var dy := float(y) - 95.5
					if dx * dx + dy * dy > 95.5 * 95.5:
						img.set_pixel(x, y, Color(0, 0, 0, 0))
			tex = ImageTexture.create_from_image(img)
	_disc_cache[face] = tex
	return tex


## The zone's two pieces of structure: the WAYPOINT beside the entrance and the EXIT at the
## far end. Both are flat, desaturated shapes — no glow (Jan's rule) — and both are pure paint:
## the rules only read `run.waypoint_point` / `run.exit_point`, which this draws.
func _draw_zone_links() -> void:
	if run == null:
		return
	var wp: Vector2 = run.waypoint_point - _cam
	# A round stone slab with a ring: a checkpoint you can recognise from a screen away.
	draw_circle(wp, 27.0, Color("#2b2620"))
	draw_circle(wp, 23.0, Color("#3b342b"))
	draw_arc(wp, 27.0, 0.0, TAU, 28, Color("#6d5f4a"), 2.0)
	draw_circle(wp, 9.0, Color("#4a6b7a"))
	# The EXIT: a stone gate — two pillars and a dark opening — so "dál" reads as architecture,
	# not as a coloured dot on the floor.
	var ex: Vector2 = run.exit_point - _cam
	var gate := Rect2(ex + Vector2(-30.0, -46.0), Vector2(60.0, 64.0))
	draw_rect(gate, Color("#0e0c0a"))
	draw_rect(Rect2(ex + Vector2(-34.0, -50.0), Vector2(8.0, 68.0)), Color("#3b342b"))
	draw_rect(Rect2(ex + Vector2(26.0, -50.0), Vector2(8.0, 68.0)), Color("#3b342b"))
	draw_rect(Rect2(ex + Vector2(-34.0, -56.0), Vector2(68.0, 8.0)), Color("#463d31"))
	# A single dim arrow above the gate, pointing at it from inside the room.
	var tip := ex + Vector2(0.0, -78.0)
	draw_colored_polygon(PackedVector2Array([
		tip, tip + Vector2(-9.0, 14.0), tip + Vector2(9.0, 14.0)]), Color("#7d6e56"))


## The town portal the scroll opened. FLAT and desaturated (Jan's rule — no glow): a dark oval
## mouth with one cold arc, the colour the waypoint's stone already uses so the two read as the
## same family of magic. It sits on the exact spot the hero stood on, which is also where he comes
## back out, so the picture matches the rule.
func _draw_portal() -> void:
	if run == null or not run.portal_open:
		return
	var p: Vector2 = run.portal_point - _cam
	if not on_screen(p, 70.0, _view_world_size()):
		return
	draw_circle(p, 30.0, Color("#161b20"))
	draw_circle(p, 25.0, Color("#233540"))
	draw_arc(p, 30.0, 0.0, TAU, 30, Color("#5b7d8c"), 2.0)
	draw_arc(p, 20.0, 0.0, TAU, 24, Color("#3d5a68"), 2.0)
	# Two still shards of light, not a spinning effect: the run has no animation pass and Jan
	# rejected glow, so the mouth is told apart by SHAPE and by the cold ring on the warm floor.
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-9.0, -6.0), p + Vector2(-2.0, -14.0), p + Vector2(3.0, -6.0)]),
		Color("#6f94a3"))
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(6.0, 2.0), p + Vector2(12.0, -5.0), p + Vector2(14.0, 4.0)]),
		Color("#54747f"))


func _draw_actors() -> void:
	# Loot first: it lies ON the ground, so a body always covers it.
	var actors: Array = []
	for m in run.monsters:
		actors.append({"y": (m["pos"] as Vector2).y, "kind": "monster", "ref": m})
	actors.append({"y": run.player_pos.y, "kind": "hero", "ref": null})
	actors.sort_custom(func(a, b): return float(a["y"]) < float(b["y"]))
	for a in actors:
		if str(a["kind"]) == "monster":
			_draw_monster(a["ref"])
		else:
			_draw_hero()


func _draw_monster(m: Dictionary) -> void:
	var base_pos: Vector2 = (m["pos"] as Vector2) - _cam
	var pos := base_pos
	var bob := sin(float(m["bob"])) * 2.2
	# ⚠️  World units, not canvas pixels — see `on_screen`. A monster walking near the right or
	# bottom edge of the arena used to vanish while still on screen for exactly this reason.
	if not on_screen(base_pos, DISC_DIA, _view_world_size()):
		return
	# ITS OWN STRIKE. A body that lunges at the hero and whips a red arc across him is what
	# says "this one attacked you" — the damage number alone arrives after the blow and reads
	# as a receipt rather than as a blow. Driven by `atk_age`, which only ever starts on a hit
	# it LANDED, so a blocked or out-of-reach monster never lunges.
	var atk := float(m.get("atk_age", -1.0))
	var swinging := atk >= 0.0 and atk < MON_ATK_ANIM
	var atk_dir: Vector2 = m.get("atk_dir", Vector2.RIGHT)
	if swinging:
		pos += atk_dir * MON_LUNGE_PX * sin(PI * clampf(atk / MON_ATK_ANIM, 0.0, 1.0))
	var role := str(m.get("role", "normal"))

	# THE AURA, on the ground under the elite. `Aura Enchanted` is a real rule (its slaves hit
	# 30 % harder), and a rule the player cannot SEE is a rule he cannot play around. Drawn as
	# one flat ring, no glow — Jan's rule for the whole game.
	if role == "elite":
		_aura_ring(pos, Color("#c8913f"))
	# A round shadow under a disc reads as a second sphere. The contact shadow is FLATTENED and
	# sits at the disc's own bottom edge — that is what puts a portrait ON the ground.
	_set_local(Vector2(pos.x, pos.y + DISC_DIA * 0.52), Vector2(1.0, 0.34))
	draw_circle(Vector2.ZERO, DISC_DIA * 0.54, Color(0, 0, 0, 0.48))
	_set_world()
	var tex := _disc(str(m["face"]))
	if tex != null:
		var r := Rect2(pos.x - DISC_DIA * 0.5, pos.y - DISC_DIA * 0.5 + bob, DISC_DIA, DISC_DIA)
		draw_texture_rect(tex, r, false)
	# WHICH RANK the body is. Three rings, no badge: bronze = a stray, violet = a champion,
	# amber (with the aura under it) = the elite. The hero's ring is blue, so none of them can
	# be mistaken for him, and a minion stays bronze — it is the LEADER that is special.
	var ring := Color("#b09464")
	var width := 2.0
	match role:
		"champion":
			ring = Color("#8a6fbf")
			width = 2.5
		"elite":
			ring = Color("#d8a24a")
			width = 3.0
	if float(m["hit_flash"]) > 0.0:
		ring = Color("#f0d8a0")
	draw_arc(pos + Vector2(0, bob), DISC_DIA * 0.5, 0.0, TAU, 28, ring, width, true)
	# THE SLASH ACROSS THE BODY. Jan: "Co takhle zkrátka udělat zahnutý tenký oblouk přímo přes
	# portrét nepřítele, do kterého sekám?" — so the blow is drawn WHERE it landed instead of as
	# a shape swinging round the hero: one thin curved stroke crossing the whole disc, bowed
	# against the direction the blow came from. No ring, no crescent, no fan.
	if float(m["hit_flash"]) > 0.0:
		var f := clampf(float(m["hit_flash"]) / 0.12, 0.0, 1.0)
		var c := pos + Vector2(0, bob)
		var to_mon: Vector2 = c - (run.player_pos - _cam)
		if to_mon.length() < 0.01:
			to_mon = Vector2.RIGHT
		to_mon = to_mon.normalized()
		var across := Vector2(-to_mon.y, to_mon.x)
		# A circle far behind the body, so the stroke crossing it is only gently bent.
		var arc_r := DISC_DIA * 1.55
		var arc_c: Vector2 = c - across * arc_r
		var span := 0.58
		var mid_a: float = across.angle()
		var pts_o := PackedVector2Array()
		var pts_i := PackedVector2Array()
		var step := 12
		for i in step + 1:
			var u := float(i) / float(step)
			var w := pow(sin(PI * clampf(u, 0.0, 1.0)), 0.45)
			var a := lerpf(mid_a - span, mid_a + span, u)
			var d := Vector2(cos(a), sin(a))
			var half := 3.0 * w + 0.6
			pts_o.append(arc_c + d * (arc_r + half))
			pts_i.append(arc_c + d * (arc_r - half))
		var poly := pts_o.duplicate()
		for i in range(pts_i.size() - 1, -1, -1):
			poly.append(pts_i[i])
		draw_colored_polygon(poly, Color(1, 1, 1, 0.92 * f))
		draw_colored_polygon(poly, Color(1, 0.97, 0.9, 0.35 * f))
	# ITS SWIPE, over the hero's side: a red crescent sweeping across the gap it just struck
	# through. Drawn after the body so it reads as coming FROM it.
	if swinging:
		var t := clampf(atk / MON_ATK_ANIM, 0.0, 1.0)
		var a := 0.9 * (1.0 - t)
		var base_a := atk_dir.angle()
		var lead := base_a - 0.62 + 1.24 * (1.0 - pow(1.0 - clampf(t / 0.6, 0.0, 1.0), 2.0))
		var col := Color(0.92, 0.30, 0.24, a)
		draw_arc(pos, DISC_DIA * 0.78, lead - 0.55, lead, 14, col, 7.0 * (1.0 - t) + 2.0, true)
		draw_arc(pos, DISC_DIA * 0.60, lead - 0.38, lead, 10,
			Color(1.0, 0.55, 0.45, a * 0.75), 3.0, true)
	if role == "elite":
		# A second hairline ring outside the amber one: the elite reads as DOUBLE-ringed from
		# across the screen, which is what a body worth 5x XP has to be.
		draw_arc(pos + Vector2(0, bob), DISC_DIA * 0.5 + 5.0, 0.0, TAU, 30,
			Color(0.85, 0.64, 0.29, 0.55), 1.5, true)
	# WHICH BODY THE ASSIST PICKED. Without this the player cannot tell what he is hitting: the
	# game chooses the target, so it has to show its choice. A blue ring outside the bronze one
	# plus a small chevron over the portrait — the hero's own colour, so nobody reads it as a buff.
	if int(m["id"]) == int(run.target_id):
		var mark := Color(UIKit.MOD_BLUE)
		draw_arc(pos + Vector2(0, bob), DISC_DIA * 0.5 + 12.0, 0.0, TAU, 30,
			Color(mark.r, mark.g, mark.b, 0.85), 2.0, true)
		var ty := pos.y - DISC_DIA * 0.5 - 8.0 + bob * 0.5
		draw_polyline(PackedVector2Array([
			Vector2(pos.x - 7.0, ty - 7.0), Vector2(pos.x, ty), Vector2(pos.x + 7.0, ty - 7.0),
		]), mark, 2.5, true)
	# HP: a thin bar under the disc, only while it is hurt (a full bar is noise).
	var frac := clampf(float(m["hp"]) / maxf(1.0, float(m["max_hp"])), 0.0, 1.0)
	if frac < 0.999:
		var w := DISC_DIA * 0.92
		var top := pos.y + DISC_DIA * 0.5 - 2.0 + bob
		draw_rect(Rect2(pos.x - w * 0.5, top, w, 4.0), C_BAR_BG)
		draw_rect(Rect2(pos.x - w * 0.5, top, w * frac, 4.0), C_RED)


func _draw_hero() -> void:
	var pos: Vector2 = run.player_pos - _cam
	var base_pos := pos
	# The whole body lunges a few pixels toward the blow, so the attack is visible even when the
	# damage number is off screen. The SHADOW stays at the base: it is on the ground, the body is
	# not.
	var lunge := Vector2.ZERO
	if run.swing_age >= 0.0 and run.swing_age < SWING_ANIM:
		lunge = run.swing_dir * 14.0 * sin(PI * clampf(float(run.swing_age) / SWING_ANIM, 0.0, 1.0))
	pos += lunge
	# The hero is a WALKING PORTRAIT like everything else, and the only thing that separates him
	# from a monster is the GOLD ring — the same distinction the arena's rings already use.
	_set_local(Vector2(base_pos.x, base_pos.y + DISC_DIA * 0.52), Vector2(1.0, 0.34))
	draw_circle(Vector2.ZERO, DISC_DIA * 0.54, Color(0, 0, 0, 0.48))
	_set_world()
	var tex: Texture2D = _disc("assets/monsters/%s.png" % _hero_face())
	if tex != null:
		draw_texture_rect(tex, Rect2(pos.x - DISC_DIA * 0.5, pos.y - DISC_DIA * 0.5, DISC_DIA, DISC_DIA), false)
	# The player's ring is the SAME blue the hero's stat page uses for his portrait frame
	# (`MOD_BLUE #4a7dff`). A gold ring on both sides made the hero indistinguishable from the
	# pack — the two looked like five enemies. Colour, not size, is what separates him.
	var hero_ring := Color(UIKit.MOD_BLUE)
	draw_arc(pos, DISC_DIA * 0.5 + 3.5, 0.0, TAU, 32, Color(0, 0, 0, 0.45), 2.0, true)
	draw_arc(pos, DISC_DIA * 0.5, 0.0, TAU, 32, hero_ring, 2.5, true)
	# ⚠️  NO FACING CHEVRON ON THE PORTRAIT ANY MORE. Jan: "Šipka u portrétu hrdiny, která
	# ukazuje směr, je tam zbytečná. Stačí ta kružnice kolem něj. Z té je dobře poznat směr."
	# The reach ring already draws its BRIGHT HALF in the facing direction plus a nose dot
	# (`_draw_attack_ring`), and a second arrow on top of the body was noise on the busiest
	# part of the frame. The direction still has to stay readable — keep the ring's front
	# half and the nose; do not remove those.


## The hero's REACH, drawn on the ground he stands on. Dashed, because a solid circle reads as a
## second body outline; it brightens and thickens for a moment on every landed swing, which is
## half of "the player can see something happened".
const SWING_ANIM := 0.22
## How long a monster's own strike is drawn for. Longer than the hero's swing: a lunge plus a
## sweep has to be SEEN, and the hero's next blow lands inside 0.3 s anyway.
const MON_ATK_ANIM := 0.30
## How far a monster's disc travels at the hero on its strike, in px.
const MON_LUNGE_PX := 13.0
const RING_SEGMENTS := 28


func _draw_attack_ring() -> void:
	var pos: Vector2 = run.player_pos - _cam
	var hot := 0.0
	if run.swing_age >= 0.0 and run.swing_age < SWING_ANIM:
		hot = 1.0 - float(run.swing_age) / SWING_ANIM
	# The FULL circle is the reach — what the weapon can touch.
	var faint := Color(UIKit.MOD_BLUE)
	faint.a = 0.07 + 0.13 * hot
	_dashed_ring(pos, run.reach_main, faint, 1.2)
	# The FRONT HALF is the part the hero can actually hit. Jan's rule ("útočí jen když je
	# otočen čelem") is a rule the player has to be able to SEE, and a full bright ring while
	# half of it is unreachable is exactly the lie the reach ring was fixed for once already.
	# ⚠️  The contrast between the two halves is the feature: at 0.22 against 0.10 the front half
	# was read as "a circle", which is a frame that proves nothing (the reference frame showed
	# exactly that). The faint half is now dim enough to read as a guide, not as a promise.
	var base: float = run.facing.angle()
	var col := Color(UIKit.MOD_BLUE)
	col.a = 0.42 + 0.50 * hot
	_dashed_ring(pos, run.reach_main, col, 2.0 + 1.5 * hot, base - PI * 0.5, base + PI * 0.5)
	# A short nose on the ring in the facing direction: the smallest mark that says "this way".
	var nose: Vector2 = pos + run.facing * run.reach_main
	draw_circle(nose, 4.5 + 1.5 * hot, Color(UIKit.MOD_BLUE, 0.75 + 0.25 * hot))
	# A second hand with a DIFFERENT reach gets its own, fainter circle. ONE ring cannot be the
	# promise for two weapons: a hand that really reaches 10 px further has to be visible, or the
	# ring lies about the off hand.
	if run.off_swing > 0.0 and absf(run.reach_off - run.reach_main) > 6.0:
		var off_col := Color(UIKit.MOD_BLUE)
		off_col.a = 0.10 + 0.26 * hot
		_dashed_ring(pos, run.reach_off, off_col, 1.2 + hot, base - PI * 0.5, base + PI * 0.5)


## The dashed circle itself, so the main and the off hand draw the SAME shape at two radii.
## `a0`/`a1` cut it to a sector: the front half needs the same dashes at a hotter alpha, and two
## loops that could drift apart is one loop too many.
func _dashed_ring(pos: Vector2, radius: float, col: Color, width: float,
		a0: float = 0.0, a1: float = TAU) -> void:
	var span := a1 - a0
	for i in RING_SEGMENTS:
		var f0 := float(i) / float(RING_SEGMENTS)
		var f1 := float(i + 0.55) / float(RING_SEGMENTS)
		if f1 > 1.0:
			f1 = 1.0
		draw_arc(pos, radius, a0 + span * f0, a0 + span * f1, 6, col, width, true)


## The ELITE's aura, on the ground: a broken ring wide enough that its MINIONS stand inside it.
## Broken rather than solid because a solid circle at that radius reads as a second reach ring;
## the aura is a place, not a boundary. No glow, no animation — flat, like everything else.
func _aura_ring(pos: Vector2, col: Color) -> void:
	var radius: float = SurvivorRun.ELITE_RING + DISC_DIA * 0.5
	var faint := Color(col.r, col.g, col.b, 0.30)
	_dashed_ring(pos, radius, faint, 2.0)
	var inner := Color(col.r, col.g, col.b, 0.16)
	draw_arc(pos, radius - 7.0, 0.0, TAU, 34, inner, 1.0, true)


## The orb is a BODY, not a UI dot: it gets the same flattened contact shadow the portraits have,
## because a green ball with no shadow reads as something stuck to the camera. The short tail
## behind it is the direction — a phone player has to be able to tell an incoming throw from a
## passing one at a glance.
##
## No glow (Jan's rule): the edge is a darker rim of the orb's own colour, which is what
## separates it from the grass without lighting anything up.
func _draw_projectiles() -> void:
	var radius: float = SurvivorRun.PROJECTILE_RADIUS
	for p in run.projectiles:
		var pos: Vector2 = (p["pos"] as Vector2) - _cam
		if pos.x < -40.0 or pos.y < -40.0 or pos.x > size.x + 40.0 or pos.y > size.y + 40.0:
			continue
		var col := Color(str(p["colour"]))
		var rim := col.darkened(0.66)
		var vel: Vector2 = p["vel"]
		var dir := vel.normalized() if vel.length() > 0.001 else Vector2.RIGHT
		# TAIL: three tapered blobs BEHIND the orb, and none of them touches it. A trail that
		# overlaps its own head reads as a glow — measured on the first frame, where the orb
		# was described as "a soft glowing particle" — and the port has no glow.
		for i in 3:
			var t := float(i + 1)
			var trail: Vector2 = pos - dir * (radius + 6.0 + t * 9.0)
			draw_circle(trail, maxf(1.5, radius * (0.56 - 0.13 * t)),
				Color(col.r, col.g, col.b, 0.42 - 0.11 * t))
		# The contact shadow is what puts the orb IN the arena instead of on the lens.
		_set_local(Vector2(pos.x, pos.y + radius * 1.2), Vector2(1.0, 0.34))
		draw_circle(Vector2.ZERO, radius * 1.15, Color(0, 0, 0, 0.55))
		_set_world()
		# A hard dark rim, then the fill. No highlight and no bloom: the edge is the contrast,
		# which is the only way a green ball stays readable on green grass.
		draw_circle(pos, radius + 2.0, rim)
		draw_circle(pos, radius, col)


func _draw_drops() -> void:
	for d in run.drops:
		var pos: Vector2 = (d["pos"] as Vector2) - _cam
		if pos.x < -20.0 or pos.y < -20.0 or pos.x > size.x + 20.0 or pos.y > size.y + 20.0:
			continue
		var bob := sin(float(d["age"]) * 6.0) * 2.0
		if str(d["kind"]) == "gold":
			draw_circle(pos + Vector2(0, bob), 7.0, Color(0, 0, 0, 0.3))
			draw_circle(pos + Vector2(0, bob), 5.5, C_GOLD)
			draw_circle(pos + Vector2(-1.5, -1.5 + bob), 2.0, Color("#f4e4b8"))
		else:
			# Jan, Nov 2026: "když dropne item, tak se na zemi zobrazí černý čtvereček, dokud ho
			# nezvednu. Dejme tam místo čtverečku třeba malou truhličku dřevěnou."
			_draw_ground_chest(pos + Vector2(0, bob), Color(str(d.get("color", "#888888"))))


## A small wooden chest lying on the ground — two planks of body, a shallow lid, two iron bands
## and a LOCK in the item's quality colour. About 24x20 world px, i.e. 20x16 on the phone: big
## enough to spot across the arena, small enough not to hide a body.
##
## The quality is carried by the lock on purpose. The old marker WAS a quality-coloured square,
## and painting the whole chest in that colour would put the same flat chip back on screen with
## a lid on it; one metal part in the item's colour reads as "this one is rare" and still looks
## like a chest first.
func _draw_ground_chest(at: Vector2, quality: Color) -> void:
	# Sized in WORLD px and seen at the 0.82 zoom, so 26 x 20 here is ~21 x 16 on the phone —
	# twice the footprint of the 12 px chip it replaces. The wood is deliberately a shade
	# LIGHTER than the ground in every zone: a chest the colour of the dirt is a smudge, and
	# this is the one object the player must spot without looking for it.
	var body := Color("#6a5238")
	var lid := Color("#86653f")
	var iron := Color("#2b2320")
	var w := 13.0
	var h := 10.0
	_set_local(at + Vector2(0, 1.0), Vector2(1.0, 0.32))
	draw_circle(Vector2.ZERO, 12.5, Color(0, 0, 0, 0.38))
	_set_local(at)
	# A DARK RIM first, then the chest inside it. Measured on zone 6: warm wood on warm dirt
	# left the chest indistinguishable from the ground at native size — the same wood the
	# ground is made of. Flat art separates by a silhouette, not by glow (Jan's rule), so the
	# object gets a 2 px near-black edge and the palette is lifted one step above every ground.
	draw_rect(Rect2(-w - 1.8, -h - 2.0, (w + 1.8) * 2.0, h + 2.0), Color(0, 0, 0, 0.62))
	draw_colored_polygon(_dome_pts(Vector2(0, -h), w + 1.8, 7.6, 8), Color(0, 0, 0, 0.62))
	draw_rect(Rect2(-w, -h, w * 2.0, h), body)
	draw_colored_polygon(_dome_pts(Vector2(0, -h), w, 6.0, 8), lid)
	# the lid/body seam and one lit edge — a dark object on dark ground needs an edge
	draw_line(Vector2(-w, -h), Vector2(w, -h), lid.lightened(0.20), 1.5)
	draw_line(Vector2(-w, -h), Vector2(-w, 0), body.lightened(0.14), 1.5)
	for x in [-w * 0.55, w * 0.55]:
		draw_rect(Rect2(float(x) - 1.4, -h - 2.4, 2.8, h + 2.4), iron)
	draw_rect(Rect2(-2.6, -h - 1.2, 5.2, 4.6), quality)
	draw_rect(Rect2(-2.6, -h - 1.2, 5.2, 4.6), Color(0, 0, 0, 0.45), false, 1.0)
	_set_world()


func _draw_numbers() -> void:
	var font := UIFonts.bold()
	for n in run.numbers:
		var age := float(n["age"])
		var pos: Vector2 = (n["pos"] as Vector2) - _cam - Vector2(0, age * 26.0)
		var alpha := clampf(1.0 - age / 0.85, 0.0, 1.0)
		var col := C_TEXT
		var fs := 15
		match str(n["kind"]):
			"crit":
				col = Color("#f0c860")
				fs = 20
			"hit_off":
				# The off hand's own number, dimmer and smaller: with two weapons landing at once,
				# two identical white numbers read as one number drawn twice.
				col = Color("#cfd8ea")
				fs = 13
			"hurt":
				col = Color("#e07068")
				fs = 17
			"gold":
				col = C_GOLD
				fs = 13
			"item":
				col = Color("#d8d0b0")
				fs = 12
			"spell":
				# A spell's damage: warmer than a blow, so a cast is distinguishable from a swing
				# in a fight with two hands and a crowd.
				col = Color("#f2b45e")
				fs = 17
			"word":
				# The duel's own receipt ("DOUBLE SWING", "FRENZY 2/5") over the portrait it
				# landed on.
				col = Color("#e8c66a")
				fs = 11
		col.a = alpha
		draw_string(font, pos, str(n["text"]), HORIZONTAL_ALIGNMENT_CENTER, -1.0, fs, col)


func _draw_hud() -> void:
	var font := UIFonts.bold()
	var font_r := UIFonts.regular()
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.75, 0.10, 0.08, 0.20 * _flash))

	# Top bar
	draw_rect(Rect2(0, 0, size.x, TOP_BAR), Color(0, 0, 0, 0.55))
	var act_name := "Akt %d" % (run.act_id + 1)
	draw_string(font_r, Vector2(12, 22), act_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, C_DIM)
	# ⚠️  The clock sits on the FIRST line, beside the act. It used to be at `size.x - 168` on the
	# second line — exactly where the wheel's "Akce" button now lives, so the two drew over each
	# other (measured: the timer was hidden behind the button). Nothing on this bar may share a
	# rectangle with another element.
	draw_string(font, Vector2(64, 22), _clock(), HORIZONTAL_ALIGNMENT_LEFT, 66.0, 13, C_GOLD)
	draw_string(font, Vector2(12, 42), "Oblasti %d/%d" % [run.cleared_zones(), run.zones.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, C_TEXT)
	draw_string(font_r, Vector2(126, 42), "%d zabito" % run.kills, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, C_DIM)

	# Exit (a fixed, always-visible way out — a run must never trap the player on a phone) and the
	# wheel's editor beside it. Both are TOP bar controls: the bottom belongs to the two thumbs.
	draw_rect(_bind_rect, Color(0x2a / 255.0, 0x24 / 255.0, 0x1c / 255.0, 0.95))
	draw_rect(_bind_rect, Color(0x6a / 255.0, 0x61 / 255.0, 0x4f / 255.0, 0.75), false, 1.5)
	draw_string(font_r, Vector2(_bind_rect.position.x + _bind_rect.size.x * 0.5,
		_bind_rect.position.y + 23), "Akce", HORIZONTAL_ALIGNMENT_CENTER, -1.0, 12, C_DIM)
	draw_rect(_exit_rect, Color(0x2a / 255.0, 0x24 / 255.0, 0x1c / 255.0, 0.95))
	draw_rect(_exit_rect, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.55), false, 1.5)
	draw_string(font_r, Vector2(_exit_rect.position.x + _exit_rect.size.x * 0.5, _exit_rect.position.y + 23),
		"Hrdina", HORIZONTAL_ALIGNMENT_CENTER, -1.0, 12, C_TEXT)

	# THE HERO BUTTON — Inventory / Skills / Stats are reachable DURING a fight (Jan, Nov 2026):
	# loot picked up mid-run has to be wearable without walking out of the zone first. It sits on
	# the second row, left of the portal, because the top row has no free rectangle left.
	draw_rect(_hero_rect, Color(0x2a / 255.0, 0x24 / 255.0, 0x1c / 255.0, 0.95))
	draw_rect(_hero_rect, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.45), false, 1.5)
	draw_string(font_r, Vector2(_hero_rect.position.x + _hero_rect.size.x * 0.5,
		_hero_rect.position.y + 23), "Inventar", HORIZONTAL_ALIGNMENT_CENTER, -1.0, 12, C_DIM)

	# THE TOWN PORTAL BUTTON — only while a scroll is carried, so the bar does not grow a dead
	# control. Jan: "po návratu z města pomocí portálu (ve městě na to musí být tlačítko) to hráče
	# musí vrátit na stejnou pozici" — the button on THIS side is what opens the portal, the one in
	# town is what brings him back.
	if _has_portal_scroll():
		draw_rect(_portal_rect, Color(0x1e / 255.0, 0x27 / 255.0, 0x2b / 255.0, 0.95))
		draw_rect(_portal_rect, Color(0x5b / 255.0, 0x7d / 255.0, 0x8c / 255.0, 0.8), false, 1.5)
		draw_string(font_r, Vector2(_portal_rect.position.x + _portal_rect.size.x * 0.5,
			_portal_rect.position.y + 23), "Portal", HORIZONTAL_ALIGNMENT_CENTER, -1.0, 12,
			Color("#a8c2cc"))

	# HP bar, above the thumb row
	# ⚠️  Not flush with the bottom: a phone's home-gesture strip sits there and a bar a few
	# pixels from the edge is read as cut off.
	var bar_h := 14.0
	var bar_y := size.y - bar_h - 26.0
	draw_rect(Rect2(0, bar_y, size.x, bar_h), C_BAR_BG)
	var frac := clampf(float(run.hp) / maxf(1.0, float(run.max_hp)), 0.0, 1.0)
	draw_rect(Rect2(0, bar_y, size.x * frac, bar_h), C_RED)
	draw_rect(Rect2(0, bar_y, size.x, bar_h), Color(0, 0, 0, 0.5), false, 1.0)
	draw_string(font, Vector2(8, bar_y + 11), "%d / %d" % [run.hp, run.max_hp],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, C_TEXT)

	# MANA, just above the health: the pool every class spell is paid from. A fight that can
	# refuse a spell for "Malo many" without ever showing the pool is a fight that hides its own
	# rule — the duel shows the same number as a thin bar.
	var mana_h := 8.0
	var mana_y := bar_y - mana_h - 3.0
	draw_rect(Rect2(0, mana_y, size.x, mana_h), C_BAR_BG)
	var mfrac := clampf(float(run.mana) / maxf(1.0, float(run.max_mana)), 0.0, 1.0)
	draw_rect(Rect2(0, mana_y, size.x * mfrac, mana_h), Color(UIKit.MOD_BLUE))
	draw_string(font_r, Vector2(8, mana_y - 2.0), "%d / %d" % [int(run.mana), run.max_mana],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, C_DIM)

	# Floating stick
	if _pointer_down and _stick_vec != Vector2.ZERO:
		draw_circle(_stick_origin, STICK_RADIUS, Color(0, 0, 0, 0.28))
		draw_arc(_stick_origin, STICK_RADIUS, 0.0, TAU, 40, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.35), 2.0, true)
		draw_circle(_stick_origin + _stick_vec * STICK_RADIUS, 19.0, Color(0xd8 / 255.0, 0xc8 / 255.0, 0xa0 / 255.0, 0.55))

	if _toast_ticks > 0.0:
		var a := clampf(_toast_ticks / 0.6, 0.0, 1.0)
		var w := 300.0
		var r := Rect2(size.x * 0.5 - w * 0.5, size.y * 0.5 - 96.0, w, 32.0)
		draw_rect(r, Color(0, 0, 0, 0.75 * a))
		draw_string(font_r, Vector2(size.x * 0.5, r.position.y + 21), _toast,
			HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, a))

	# Loot tally, so a run pays out visibly
	var tally := "%d %s   %d %s" % [run.gold, _plural(run.gold, "zlato", "zlata", "zlata"),
		run.items_taken, _plural(run.items_taken, "predmet", "predmety", "predmetu")]
	draw_string(font_r, Vector2(8, size.y - 6), _with_diacritics(tally),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, C_DIM)


## THE ACTION WHEEL — ALWAYS on screen, bottom-left (Jan: "měl by být viditelný permanentně. I s
## výsečemi."). One fixed disc with a ring of six WEDGES around it, each wedge holding one action:
## the thumb only has to be somewhere in the wedge, never on a small icon.
##
## Two states per wedge, because the actions are not the same gesture any more:
##   · the ATTACK is HELD — the wedge lights the moment the thumb is in it and stays lit while it
##     stays there; the knob follows the finger so a held action has a visible body.
##   · a SPELL or a POTION is ARMED — lit, and fired by LIFTING the thumb. The label above the wheel
##     says so, in words, because "release to use" is the one rule that cannot be read from a shape.
func _draw_wheel() -> void:
	var o := wheel_centre()
	var font := UIFonts.bold()
	var font_r := UIFonts.regular()
	var engaged := _wheel_index >= 0
	var r_in := wheel_inner()
	var r_out := wheel_outer()
	# The resting disc: the joystick-like area under the thumb. Nothing fires inside it, so it is
	# drawn darker than the wedges even while a thumb sits in it.
	draw_circle(o, r_in, Color(0, 0, 0, 0.34 if engaged else 0.26))
	draw_arc(o, r_in, 0.0, TAU, 48,
		Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.34 if engaged else 0.24), 2.0, true)

	var span := TAU / float(ActionWheel.SLOTS)
	for i in ActionWheel.SLOTS:
		var a0: float = ActionWheel.centre_angle(i) - span * 0.5
		var a1: float = ActionWheel.centre_angle(i) + span * 0.5
		var action := wheel_action(i)
		var empty := action == ActionWheel.EMPTY
		var active := engaged and i == _wheel_slot
		var fill := Color(0x25 / 255.0, 0x21 / 255.0, 0x1b / 255.0, 0.82)
		if empty:
			fill = Color(0x16 / 255.0, 0x14 / 255.0, 0x12 / 255.0, 0.50)
		if active:
			fill = Color(0x46 / 255.0, 0x3a / 255.0, 0x29 / 255.0, 0.96)
		_draw_wheel_wedge(o, a0, a1, fill, r_in, r_out)
		# The wedge's own rim: the outline that makes the ring read as six places, not one annulus.
		var rim := Color(0x7a / 255.0, 0x6f / 255.0, 0x59 / 255.0, 0.90)
		var rim_w := 1.5
		if empty:
			rim = Color(0x4a / 255.0, 0x44 / 255.0, 0x3a / 255.0, 0.55)
		if active:
			rim = Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.95)
			rim_w = 3.0
		draw_arc(o, r_out, a0 + 0.02, a1 - 0.02, 14, rim, rim_w, true)
		# A boundary line on both edges: the fill alone is a quiet map, the lines say where one
		# action ends and the next begins.
		for a in [a0, a1]:
			draw_line(o + Vector2.from_angle(a) * r_in, o + Vector2.from_angle(a) * r_out,
				Color(1, 1, 1, 0.11), 1.0, true)
		var c := o + Vector2.from_angle(ActionWheel.centre_angle(i)) * ((r_in + r_out) * 0.5)
		if not empty:
			# A round backing, so a square spell texture never shows a black corner plate (Jan).
			draw_circle(c, WHEEL_ICON_RADIUS, Color(0x14 / 255.0, 0x12 / 255.0, 0x10 / 255.0,
				0.90 if active else 0.70))
			_draw_action_icon(action, c, WHEEL_ICON_RADIUS, active)

	# The thumb itself, at the offset it has pulled (clamped to the ring, so it never leaves the
	# wheel's edge on a hard drag). Drawn as a RING, not a disc: the icon under it has to stay
	# readable while the action is being aimed.
	if engaged:
		draw_arc(o + _wheel_vec, 21.0, 0.0, TAU, 28,
			Color(0xd8 / 255.0, 0xc8 / 255.0, 0xa0 / 255.0, 0.60), 2.5, true)

	var action_now := wheel_action(_wheel_slot)
	if action_now == ActionWheel.EMPTY:
		return
	var held := ActionWheel.is_hold(action_now, RunSpells)
	var word := ActionWheel.action_name(action_now, run.spell_bar())
	# ABOVE the wheel: the HP bar and the loot tally own everything below it.
	var label_y := o.y - r_out - 18.0
	draw_string(font, Vector2(o.x - 110.0, label_y), word,
		HORIZONTAL_ALIGNMENT_CENTER, 220.0, 15, C_GOLD)
	draw_string(font_r, Vector2(o.x - 110.0, label_y + 15.0),
		"drž" if held else "pusť pro aktivaci", HORIZONTAL_ALIGNMENT_CENTER, 220.0, 10, C_DIM)


## One wedge of the ring, as a fan of convex quads: `draw_colored_polygon` wants a convex polygon,
## and an annular sector is not one.
func _draw_wheel_wedge(o: Vector2, a0: float, a1: float, fill: Color,
		r_in: float, r_out: float) -> void:
	var steps := 8
	for k in steps:
		var d0 := Vector2.from_angle(lerpf(a0, a1, float(k) / float(steps)))
		var d1 := Vector2.from_angle(lerpf(a0, a1, float(k + 1) / float(steps)))
		draw_colored_polygon(PackedVector2Array([
			o + d0 * r_in, o + d0 * r_out,
			o + d1 * r_out, o + d1 * r_in,
		]), fill)


## One action's symbol inside a circle: the class's spell art cropped round, a blade for the attack,
## an "L" for the potion. No emoji, no icon file invented for the two built-ins.
func _draw_action_icon(action: String, centre: Vector2, radius: float, lit: bool) -> void:
	var tint := Color(1, 1, 1, 1.0 if lit else 0.62)
	if action == ActionWheel.ATTACK:
		var blade := PackedVector2Array([
			centre + Vector2(0, -radius * 0.95), centre + Vector2(radius * 0.26, -radius * 0.55),
			centre + Vector2(radius * 0.26, radius * 0.42),
			centre + Vector2(-radius * 0.26, radius * 0.42),
			centre + Vector2(-radius * 0.26, -radius * 0.55),
		])
		draw_colored_polygon(blade, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, tint.a))
		draw_line(centre + Vector2(-radius * 0.62, radius * 0.5),
			centre + Vector2(radius * 0.62, radius * 0.5), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, tint.a), 3.0, true)
		draw_line(centre + Vector2(0, radius * 0.5), centre + Vector2(0, radius * 0.95),
			Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, tint.a), 3.0, true)
		return
	if action == ActionWheel.POTION:
		draw_string(UIFonts.bold(), centre + Vector2(-radius, radius * 0.62), "L",
			HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, int(radius * 1.5), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, tint.a))
		return
	var tex: Texture2D = _disc("assets/spells/%s.png" % action)
	if tex != null:
		draw_texture_rect(tex, Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2.0),
			false, tint)


## The wheel's editor. Two states, one panel: the six sectors (tap one), then the list of every
## action it may hold (tap one) — the answer to "hráč musí mít možnost nabindovat akce na libovolná
## tlačítka (směry)".
func _draw_bind_panel() -> void:
	var font := UIFonts.bold()
	var font_r := UIFonts.regular()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.86))
	draw_rect(Rect2(12, 62, size.x - 24, size.y - 76), Color(0x12 / 255.0, 0x12 / 255.0, 0x12 / 255.0, 1.0))
	draw_rect(Rect2(12, 62, size.x - 24, size.y - 76), Color(0x33 / 255.0, 0x33 / 255.0, 0x33 / 255.0, 1.0), false, 1.5)
	if _bind_pick < 0:
		draw_string(font, Vector2(26, 96), "Akce na směrech", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, C_TEXT)
		draw_string(font_r, Vector2(26, 118), "Klepni na směr a vyber akci.", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, C_DIM)
	else:
		draw_string(font, Vector2(26, 96), "Směr %s" % _direction_name(_bind_pick),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, C_TEXT)
		draw_string(font_r, Vector2(26, 118), "Co má tenhle směr dělat?", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, C_DIM)

	for r in _bind_rects:
		var rect: Rect2 = r["rect"]
		var slot := int(r["slot"])
		var action := str(r["action"]) if _bind_pick >= 0 else wheel_action(slot)
		var selected := _bind_pick >= 0 and action == wheel_action(_bind_pick)
		draw_rect(rect, Color(0x1a / 255.0, 0x1a / 255.0, 0x1a / 255.0, 1.0))
		draw_rect(rect, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.9) if selected
			else Color(0x33 / 255.0, 0x33 / 255.0, 0x33 / 255.0, 1.0), false, 2.0 if selected else 1.0)
		if _bind_pick < 0:
			# A slot row: the direction on the left, the action on the right.
			draw_string(font, Vector2(rect.position.x + 12.0, rect.position.y + 30.0),
				_direction_name(slot), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, C_GOLD)
			draw_string(font, Vector2(rect.position.x + 12.0, rect.position.y + 56.0),
				ActionWheel.action_name(action, run.spell_bar()), HORIZONTAL_ALIGNMENT_LEFT,
				rect.size.x - 24.0, 12, C_TEXT if action != ActionWheel.EMPTY else C_DIM)
		else:
			var name := ActionWheel.action_name(action, run.spell_bar())
			var dim := _action_available(action)
			draw_string(font, Vector2(rect.position.x + 10.0, rect.position.y + 32.0), name,
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0, 13,
				C_TEXT if dim else Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.55))

	# Back / close. One button: it steps out of the action list first, then out of the panel.
	var back_text := "Zpět" if _bind_pick >= 0 else "Zavřít"
	draw_rect(_bind_back_rect, Color(0x2a / 255.0, 0x24 / 255.0, 0x1c / 255.0, 1.0))
	draw_rect(_bind_back_rect, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.75), false, 1.5)
	draw_string(font, Vector2(_bind_back_rect.position.x, _bind_back_rect.position.y + 28.0),
		back_text, HORIZONTAL_ALIGNMENT_CENTER, _bind_back_rect.size.x, 14, C_TEXT)
	draw_string(font_r, Vector2(size.x - 26.0 - 190.0, _bind_back_rect.position.y + 28.0),
		"Uloženo hned", HORIZONTAL_ALIGNMENT_RIGHT, 190.0, 11, C_DIM)


## The word a sector is called by, in the panel. Kept apart from the ANGLE maths so the panel can
## name a direction without knowing where it is drawn.
func _direction_name(slot: int) -> String:
	var names := ["nahoru", "vpravo nahoru", "vpravo dolů", "dolů", "vlevo dolů", "vlevo nahoru"]
	return names[posmod(slot, names.size())]


## Can this action do anything right now? Only used to DIM a choice, never to refuse it: a player
## may bind a spell he has not learned yet.
func _action_available(action: String) -> bool:
	if action == ActionWheel.EMPTY or action == ActionWheel.ATTACK or action == ActionWheel.POTION:
		return true
	for e in run.spell_bar():
		if str((e as Dictionary).get("id", "")) == action:
			return bool((e as Dictionary).get("can", false))
	return false


## Czech counts must not read "2 předmětu". One helper, used by every count on this screen.
func _plural(n: int, one: String, few: String, many: String) -> String:
	var n100 := n % 100
	if n100 == 1:
		return one
	var n10 := n % 10
	if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14):
		return few
	return many


## The tallies are built from ASCII stems so the numbers and the words stay one string; this
## is the one place that puts the háčky back.
func _with_diacritics(text: String) -> String:
	return text.replace("predmet", "předmět").replace("predmety", "předměty")


func _clock() -> String:
	var total := int(run.elapsed)
	return "%02d:%02d" % [total / 60, total % 60]


# ============================================================================ spells & flurry

## The HERO's bolt in the air: the same body rules as an enemy orb (shadow, tail, hard dark rim,
## no glow) in the spell's own colour, so the player can tell HIS bolt from an incoming one by
## direction and colour at a glance.
func _draw_bolts() -> void:
	var radius: float = SurvivorRun.BOLT_RADIUS
	for b in run.bolts:
		var pos: Vector2 = (b["pos"] as Vector2) - _cam
		if pos.x < -40.0 or pos.y < -40.0 or pos.x > size.x + 40.0 or pos.y > size.y + 40.0:
			continue
		var col := Color(str(b["colour"]))
		var vel: Vector2 = b["vel"]
		var dir := vel.normalized() if vel.length() > 0.001 else Vector2.RIGHT
		for i in 3:
			var t := float(i + 1)
			var trail: Vector2 = pos - dir * (radius + 5.0 + t * 8.0)
			draw_circle(trail, maxf(1.5, radius * (0.55 - 0.13 * t)),
				Color(col.r, col.g, col.b, 0.45 - 0.12 * t))
		_set_local(Vector2(pos.x, pos.y + radius * 1.1), Vector2(1.0, 0.34))
		draw_circle(Vector2.ZERO, radius * 1.1, Color(0, 0, 0, 0.5))
		_set_world()
		draw_circle(pos, radius + 2.0, col.darkened(0.6))
		draw_circle(pos, radius, col)
		draw_circle(pos, radius * 0.42, Color(1, 1, 1, 0.75))


## The spell effects, in the shapes the DUEL uses (the PWA's own canvas animations):
##   ring   — five expanding circles leaving the hero (Battle/Defensive Shout, Spell Reflect)
##   flash  — a white full-screen blast (Thunder Clap, its first 200 ms)
##   cracks — 4-6 jagged lightning lines running out of the centre (Thunder Clap)
##   shield — a grey shield falling from above a body, shrinking as it lands (Shield Slam)
##   spiral — a tightening spiral on the body a bolt hit (Thunder Bolt's impact)
## All of it is drawn flat: no glow, no bloom — Jan's rule, which the PWA's shadowBlur breaks.
func _draw_effects() -> void:
	for e in run.effects:
		var t := clampf(float(e["age"]) / maxf(float(e["life"]), 0.001), 0.0, 1.0)
		var pos: Vector2 = (e["pos"] as Vector2) - _cam
		var col := Color(str(e["colour"]))
		var data: Dictionary = e.get("data", {})
		match str(e["kind"]):
			"ring":
				var count := int(data.get("count", 5))
				var delay := float(data.get("delay", 0.10))
				var r0 := float(data.get("r0", 10.0))
				var r1 := float(data.get("r1", 148.0))
				var width := float(data.get("width", 4.0))
				for i in count:
					var d := float(i) * delay
					var p := clampf((t - d) / maxf(1.0 - d, 0.05), 0.0, 1.0)
					if p <= 0.0:
						continue
					var radius := lerpf(r0, r1, p)
					if pos.x < -radius or pos.y < -radius \
							or pos.x > size.x + radius or pos.y > size.y + radius:
						continue
					draw_arc(pos, radius, 0.0, TAU, 48,
						Color(col.r, col.g, col.b, (1.0 - p) * 0.8), width * (1.0 - 0.4 * p), true)
			"flash":
				# A CANVAS-space blast: inside the world transform a `size`-sized rect would leave
				# the outer 18 % of the frame dark, which reads as a vignette, not as a flash.
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_rect(Rect2(Vector2.ZERO, size),
					Color(col.r, col.g, col.b, (1.0 - t) * 0.45))
				_set_world()
			"cracks":
				# ⚠️  AGE and LIFE, not the normalised `t`: this shape's reveal/fade are in
				# SECONDS of its own (see `_draw_cracks`), and passing the 0..1 progress made the
				# fade eat it — measured as `effects=["flash","cracks"]` on a frame with no
				# lightning visible at all.
				_draw_cracks(pos, col, float(e["age"]), float(e["life"]),
					int(data.get("count", 5)), float(data.get("length", 96.0)))
			"shield":
				# Starts huge and above the body, ends small and on it — the duel's own motion.
				var shrink := 1.0 - t * 0.55
				var sx := 118.0 * shrink
				var sy := pos.y - 120.0 * (1.0 - t)
				var a := (1.0 - t) * 0.55
				var pts := PackedVector2Array([
					Vector2(pos.x - sx * 0.30, sy - sx * 0.40),
					Vector2(pos.x + sx * 0.30, sy - sx * 0.40),
					Vector2(pos.x + sx * 0.30, sy + sx * 0.10),
					Vector2(pos.x, sy + sx * 0.40),
					Vector2(pos.x - sx * 0.30, sy + sx * 0.10),
				])
				draw_colored_polygon(pts, Color(0.53, 0.53, 0.53, a))
				var outline := pts.duplicate()
				outline.append(pts[0])
				draw_polyline(outline, Color(0.67, 0.67, 0.67, a + 0.15), 2.0, true)
			"spiral":
				var turns := 4.0 * (1.0 - t)
				var alpha := 1.0 - t
				var prev := pos
				var steps := int(maxf(turns * 24.0, 0.0))
				for k in steps:
					var tt := float(k) * 0.12
					var r := 4.0 + tt * 3.0
					var sp := pos + Vector2(cos(tt), sin(tt)) * r
					draw_line(prev, sp, Color(col.r, col.g, col.b, alpha), 2.0, true)
					prev = sp


## The lightning of a Thunder Clap. The shape is generated from a seed derived from the effect's
## own position, so it does not shimmer between frames — a crack pattern that re-rolls every
## frame reads as noise, not as lightning.
##
## ⚠️  A crack is NOT a spoke. The first version bent each segment by ±0.3 rad, and a still frame
## was read as "four straight lines, a UI reticle" — which is exactly what a spoke is. Lightning
## is built from LARGE direction swings (±0.75 rad), uneven segment lengths and short side
## BRANCHES; without the branches it stays a star.
func _draw_cracks(pos: Vector2, col: Color, age: float, life: float,
		count: int, reach: float) -> void:
	# The reveal is FAST (full length in ~0.18 s) and the fade is the rest. The PWA spread it
	# over 0.28 s, which at 60 fps caught the crack as a stub no longer than the hero's own
	# portrait — measured on a frame 0.1 s after the cast, where the vision pass reported "no
	# lightning at all". Lightning is instant; only its afterglow lingers.
	var reveal := 0.18
	var progress := clampf(age / reveal, 0.0, 1.0)
	if progress <= 0.0:
		return
	var alpha := clampf(1.0 - maxf(0.0, age - reveal) / maxf(life - reveal, 0.05), 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(pos.x) * 7.0 + absf(pos.y) * 13.0) + 1
	var lines: Array = []
	for i in count:
		var base := TAU * float(i) / float(count) + rng.randf_range(-0.3, 0.3)
		var segs := 4 + rng.randi_range(0, 2)
		var step_len := reach * rng.randf_range(0.55, 1.0) / float(segs)
		var px := pos
		var dir := base
		var pts := PackedVector2Array([pos])
		for _s in segs:
			# Pull back toward the base direction each step, or a big swing sends the bolt
			# curling into a spiral instead of running OUT of the hero.
			dir = lerp_angle(dir, base, 0.30) + rng.randf_range(-0.75, 0.75)
			px += Vector2(cos(dir), sin(dir)) * step_len * rng.randf_range(0.55, 1.45)
			pts.append(px)
		lines.append(pts)
		# One or two short forks off the middle of the bolt.
		for _b in rng.randi_range(1, 2):
			var k := rng.randi_range(1, maxi(pts.size() - 2, 1))
			var root: Vector2 = pts[k]
			var bdir := base + rng.randf_range(-1.5, 1.5)
			var blen := reach * rng.randf_range(0.16, 0.34)
			var bp := PackedVector2Array([root])
			var cur := root
			var cdir := bdir
			for _j in 2:
				cdir += rng.randf_range(-0.7, 0.7)
				cur += Vector2(cos(cdir), sin(cdir)) * blen * 0.55
				bp.append(cur)
			lines.append(bp)

	var total_pts := 0
	for l in lines:
		total_pts += (l as PackedVector2Array).size()
	var wanted := maxi(2, int(ceil(float(total_pts) * progress)))
	var drawn := 0
	for l in lines:
		var pts2: PackedVector2Array = l
		var take := clampi(wanted - drawn, 0, pts2.size())
		drawn += take
		if take < 2:
			continue
		var shown := PackedVector2Array()
		for k in take:
			shown.append(pts2[k])
		# The port's contrast recipe, applied to a LINE instead of a ball: a dark rim that
		# separates it from the grass, the spell's colour, then a near-white core. On this ground
		# the EDGE is what carries it (no glow — Jan's rule).
		draw_polyline(shown, Color(0.02, 0.08, 0.16, alpha * 0.75), 9.0, true)
		draw_polyline(shown, Color(col.r, col.g, col.b, alpha * 0.95), 5.0, true)
		draw_polyline(shown, Color(0.88, 0.95, 1.0, alpha), 2.0, true)


## The Whirlwind row: the duel's four PS symbols, the one being asked for pulled OUT of the row
## by a gold countdown ring. A wrong symbol ends the flurry, so the row must never be a guess —
## the symbols stay in one fixed order and only the ring moves.
func _draw_whirlwind() -> void:
	if run == null or not run.whirlwind_open():
		return
	var prompt: String = run.whirlwind_prompt()
	var font := UIFonts.bold()
	# A dark band behind the row: the symbols are drawn over grass, and a red circle on green
	# needs the plate the duel gives every symbol anyway.
	draw_rect(Rect2(0, WW_ROW_Y - WW_BUTTON_RADIUS - 30.0, size.x, WW_BUTTON_RADIUS * 2.0 + 58.0),
		Color(0, 0, 0, 0.30))
	for b in _ww_buttons:
		var key := str(b["key"])
		var c: Vector2 = b["centre"]
		var is_prompt: bool = key == prompt
		draw_circle(c, WW_BUTTON_RADIUS, Color(0, 0, 0, 0.86))
		var border := Color(str(WW_KEY_BORDERS.get(key, "#2a2a2a")))
		var tex := UIKit.load_texture("assets/ps/ps_%s.png" % key)
		if tex != null:
			var ir := WW_BUTTON_RADIUS - 6.0
			draw_texture_rect(tex, Rect2(c - Vector2(ir, ir), Vector2(ir, ir) * 2.0), false,
				Color(1, 1, 1, 1.0 if is_prompt else 0.42))
		draw_arc(c, WW_BUTTON_RADIUS, 0.0, TAU, 24,
			Color(border.r, border.g, border.b, 1.0 if is_prompt else 0.32),
			3.0 if is_prompt else 1.5, true)
		if is_prompt:
			var total := maxf(float(run.ww_reaction_ms), 1.0)
			var frac := clampf(float(run.ww_deadline_ms) / total, 0.0, 1.0)
			draw_arc(c, WW_BUTTON_RADIUS + 7.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 32,
				Color("#f1c40f"), 3.5, true)
	draw_string(font, Vector2(size.x * 0.5 - 70.0, WW_ROW_Y - WW_BUTTON_RADIUS - 10.0),
		"Whirlwind %d/%d" % [run.ww_index, run.ww_dirs.size()],
		HORIZONTAL_ALIGNMENT_CENTER, 140.0, 13, C_GOLD)

