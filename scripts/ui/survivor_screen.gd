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
## Controls, per Jan's decision: the MOVEMENT is a FLOATING stick — it appears wherever the
## thumb lands — and the buttons are FIXED in the bottom-right. The attack is automatic.
##
## ⚠️  One finger arrives TWICE on this engine (`Input` synthesises a mouse event from every
## touch), so the press/release pair goes through `_pointer_down`: the first event of the
## pair starts the gesture and the second is ignored. Motion is never gated — a finger DRAG
## delivers `ScreenDrag` and no `MouseMotion` at all, so a motion gate breaks dragging on
## the phone.

signal leave_requested
signal run_finished(outcome: String)

const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")
const UIKit := preload("res://scripts/ui/ui_kit.gd")
const UIFonts := preload("res://scripts/ui/ui_fonts.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")

const STEP := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 6

const TOP_BAR := 54.0
const STICK_RADIUS := 58.0
const STICK_DEADZONE := 9.0
const BUTTON_RADIUS := 38.0
## One disc diameter for every actor: the hero is a walking portrait too (Jan), and a single
## size is what makes the collision radius (BODY_RADIUS 31 = DISC_DIA / 2) true on screen.
const DISC_DIA := 62.0

const GRASS_PATH := "res://assets/ground/grass.png"

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
var _disc_cache: Dictionary = {}

## Camera, in world pixels (top-left of the view).
var _cam := Vector2.ZERO

## Floating stick. `_stick_origin` is where the thumb landed; `_stick_vec` is 0..1.
var _pointer_down := false
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _pointer_kind := ""

## Buttons, fixed in the bottom-right. Rebuilt on resize.
var _exit_rect := Rect2()
var _potion_centre := Vector2.ZERO
var _toast := ""
var _toast_ticks := 0.0
var _flash := 0.0
var _death_reported := false

## Seeded decorations: they are DATA so a re-layout cannot move the cover the fight uses.
var _props: Array = []
var _patches: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_grass = UIKit.load_texture(GRASS_PATH)


## Stop the clock. The run object is KEPT (the payout is read from it when the screen hands the
## player back), but nothing advances it any more.
func stop() -> void:
	set_process(false)
	_pointer_down = false
	_stick_vec = Vector2.ZERO
	_accum = 0.0


func setup(state, find_item: Callable, loot_system, act_id: int) -> void:
	_state = state
	_find_item = find_item
	run = SurvivorRun.new()
	run.setup(state, find_item, loot_system, act_id)
	_accum = 0.0
	_death_reported = false
	set_process(true)
	_toast = ""
	_toast_ticks = 0.0
	_flash = 0.0
	_stick_vec = Vector2.ZERO
	_pointer_down = false
	_build_decoration()
	_place_camera()
	_layout_buttons()
	queue_redraw()


## The "procedurally generated environment": a handful of rules over one seed, not a map.
## Dirt patches break the grass into places; boulders and dead bushes give the eye something
## to run past. Every entry is world-space data and is drawn only when it is on screen.
func _build_decoration() -> void:
	_props.clear()
	_patches.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	for _i in 18:
		_patches.append({
			"pos": Vector2(rng.randf_range(60, SurvivorRun.WORLD.x - 60),
				rng.randf_range(60, SurvivorRun.WORLD.y - 60)),
			"rx": rng.randf_range(38, 96), "ry": rng.randf_range(28, 66),
		})
	for _i in 46:
		var kind := "rock" if rng.randf() < 0.6 else "bush"
		_props.append({
			"pos": Vector2(rng.randf_range(40, SurvivorRun.WORLD.x - 40),
				rng.randf_range(40, SurvivorRun.WORLD.y - 40)),
			"kind": kind,
			"size": rng.randf_range(20, 44) if kind == "rock" else rng.randf_range(22, 40),
			"seed": rng.randf() * 10.0,
		})
	# Nothing may spawn on the hero's first step.
	_props = _props.filter(func(p): return (p["pos"] as Vector2).distance_to(SurvivorRun.WORLD * 0.5) > 70.0)


## The hero's medallion is the SAME portrait his stat page shows: `hero.face` ->
## `assets/monsters/<face>.png`, the one route the stats panel uses. No second art source.
func _hero_face() -> String:
	if _state == null:
		return "hero"
	return str(_state.hero().get("face", "hero"))


# ============================================================================ input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed := false
		var pos := Vector2.ZERO
		if event is InputEventScreenTouch:
			pressed = event.pressed
			pos = event.position
			_pointer_kind = "touch"
		else:
			pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
			pos = event.position
			_pointer_kind = "mouse"
		if pressed:
			if _pointer_down:
				return
			_on_press(pos)
		else:
			if not _pointer_down:
				return
			_on_release()
		accept_event()
		return

	if event is InputEventScreenDrag:
		if _pointer_down:
			_on_drag(event.position)
			accept_event()
		return
	if event is InputEventMouseMotion:
		# ⚠️  Gated on `_pointer_down` only, never on the device: a finger drag emits no
		# MouseMotion at all, so both paths stay open and the one that arrives is used.
		if _pointer_down:
			_on_drag(event.position)
			accept_event()


func _on_press(pos: Vector2) -> void:
	_pointer_down = true
	if _potion_centre.distance_to(pos) <= BUTTON_RADIUS + 6.0:
		_drink_potion()
		return
	if _exit_rect.has_point(pos):
		leave_requested.emit()
		return
	if pos.y < TOP_BAR:
		return
	_stick_origin = pos
	_stick_vec = Vector2.ZERO
	queue_redraw()


func _on_drag(pos: Vector2) -> void:
	var delta := pos - _stick_origin
	if delta.length() < STICK_DEADZONE:
		_stick_vec = Vector2.ZERO
	else:
		_stick_vec = delta.limit_length(STICK_RADIUS) / STICK_RADIUS
	queue_redraw()


func _on_release() -> void:
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
	# ONE report per run. The old code cleared `finished` after emitting, so a run whose hp had
	# already reached 0 re-entered `step()`, died again on the next frame and emitted again — with
	# the player on another screen each `run_finished` dragged him back.
	if run.finished and run.outcome == "dead" and not _death_reported:
		_death_reported = true
		stop()
		run_finished.emit("dead")
	_place_camera()
	queue_redraw()


## The RULES decide what a fight sounded like; the screen only plays it. Drained every
## frame so a cue cannot be heard twice, which is the same contract `battle.gd` has.
func _play_events() -> void:
	for cue in run.drain_events():
		match str(cue):
			"hit":
				Sfx.play_global(Sfx.CUE_MELEE_HIT)
			"crit":
				Sfx.play_global(Sfx.CUE_MELEE_CRIT)
			"kill":
				Sfx.play_global(Sfx.CUE_BLUNT_HIT)
			"hurt":
				Sfx.play_global(Sfx.CUE_HURT)
				_flash = 1.0
			"gold":
				Sfx.play_global(Sfx.CUE_TREASURE)
			"item":
				Sfx.play_global(Sfx.CUE_TREASURE)
			"bagfull":
				_say("Batoh je plný — předmět zůstal na zemi")
			"dead":
				Sfx.play_global(Sfx.CUE_HURT)


func _place_camera() -> void:
	if run == null:
		return
	var half := size * 0.5
	_cam = run.player_pos - half
	_cam.x = clampf(_cam.x, 0.0, maxf(0.0, SurvivorRun.WORLD.x - size.x))
	_cam.y = clampf(_cam.y, 0.0, maxf(0.0, SurvivorRun.WORLD.y - size.y))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_buttons()
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		# ⚠️  A hidden Control STILL RUNS `_process`. Leaving the run therefore kept simulating it
		# behind whatever screen was opened next: monsters kept spawning, the hero kept losing
		# health, and when he died the `run_finished` signal pulled the player back to the road
		# from a screen he was already using. A screen that draws a live fight must own its clock.
		if not is_visible_in_tree():
			stop()
		else:
			set_process(true)


func _layout_buttons() -> void:
	var bottom := size.y - 42.0
	_exit_rect = Rect2(size.x - 96.0, 10.0, 84.0, 34.0)
	_potion_centre = Vector2(size.x - 58.0, bottom - 34.0)


# ============================================================================ draw

func _draw() -> void:
	if run == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("#1b1712"))
	_draw_ground()
	_draw_patches()
	_draw_props()
	_draw_attack_ring()
	_draw_drops()
	_draw_actors()
	_draw_slash()
	_draw_numbers()
	_draw_hud()


func _draw_ground() -> void:
	if _grass == null:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#4a4a36"))
		return
	# One tiling call for the whole world, shifted by the camera. `tile = true` repeats the
	# seamless 256px tile; there is no per-tile loop and therefore no tile grid to drift.
	draw_texture_rect(_grass, Rect2(-_cam, SurvivorRun.WORLD), true)


func _draw_patches() -> void:
	for p in _patches:
		var pos: Vector2 = (p["pos"] as Vector2) - _cam
		if pos.x < -180.0 or pos.y < -180.0 or pos.x > size.x + 180.0 or pos.y > size.y + 180.0:
			continue
		var rx := float(p["rx"])
		var ry := float(p["ry"])
		draw_set_transform(pos, 0.0, Vector2(1.0, ry / rx))
		draw_circle(Vector2.ZERO, rx, Color(0x5a / 255.0, 0x50 / 255.0, 0x3e / 255.0, 0.34))
		draw_circle(Vector2.ZERO, rx * 0.66, Color(0x64 / 255.0, 0x59 / 255.0, 0x45 / 255.0, 0.26))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_props() -> void:
	for p in _props:
		var pos: Vector2 = (p["pos"] as Vector2) - _cam
		if pos.x < -60.0 or pos.y < -80.0 or pos.x > size.x + 60.0 or pos.y > size.y + 60.0:
			continue
		var s := float(p["size"])
		draw_set_transform(pos, 0.0, Vector2.ONE)
		draw_set_transform(pos + Vector2(0, s * 0.20), 0.0, Vector2(1.0, 0.34))
		draw_circle(Vector2.ZERO, s * 0.66, Color(0, 0, 0, 0.40))
		draw_set_transform(pos, 0.0, Vector2.ONE)
		if str(p["kind"]) == "rock":
			var seed_v := float(p["seed"])
			var pts := PackedVector2Array([
				Vector2(-s * 0.52, 0.0), Vector2(-s * 0.30, -s * 0.62),
				Vector2(s * 0.16, -s * 0.78), Vector2(s * 0.50, -s * 0.20),
				Vector2(s * 0.28, s * 0.10), Vector2(-s * 0.34, s * 0.06),
			])
			draw_colored_polygon(pts, Color(0x6a / 255.0, 0x61 / 255.0, 0x4f / 255.0))
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3]]),
				Color(0x85 / 255.0, 0x7a / 255.0, 0x63 / 255.0), 2.0)
			draw_line(Vector2(-s * 0.1, -s * 0.1), Vector2(s * 0.2, -s * 0.35),
				Color(0, 0, 0, 0.25 + 0.05 * seed_v), 1.5)
		else:
			# A dark disc on a dark ground reads as a shadow with nothing casting it — Jan's
			# own report on the first render. A bush therefore has a BODY and a lit rim.
			draw_circle(Vector2(0, -s * 0.30), s * 0.60, Color(0x37 / 255.0, 0x3c / 255.0, 0x26 / 255.0))
			draw_circle(Vector2(-s * 0.14, -s * 0.44), s * 0.36, Color(0x45 / 255.0, 0x4b / 255.0, 0x2f / 255.0))
			draw_arc(Vector2(0, -s * 0.30), s * 0.60, PI * 1.15, PI * 1.95, 14,
				Color(0x5e / 255.0, 0x64 / 255.0, 0x40 / 255.0), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
	var pos: Vector2 = (m["pos"] as Vector2) - _cam
	if pos.x < -60.0 or pos.y < -80.0 or pos.x > size.x + 60.0 or pos.y > size.y + 60.0:
		return
	var bob := sin(float(m["bob"])) * 2.2
	# A round shadow under a disc reads as a second sphere. The contact shadow is FLATTENED and
	# sits at the disc's own bottom edge — that is what puts a portrait ON the ground.
	draw_set_transform(Vector2(pos.x, pos.y + DISC_DIA * 0.52), 0.0, Vector2(1.0, 0.34))
	draw_circle(Vector2.ZERO, DISC_DIA * 0.54, Color(0, 0, 0, 0.48))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tex := _disc(str(m["face"]))
	if tex != null:
		var r := Rect2(pos.x - DISC_DIA * 0.5, pos.y - DISC_DIA * 0.5 + bob, DISC_DIA, DISC_DIA)
		draw_texture_rect(tex, r, false)
	var ring := Color("#b09464")
	if float(m["hit_flash"]) > 0.0:
		ring = Color("#f0d8a0")
	draw_arc(pos + Vector2(0, bob), DISC_DIA * 0.5, 0.0, TAU, 28, ring, 2.0, true)
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
		lunge = run.swing_dir * 8.0 * sin(PI * clampf(float(run.swing_age) / SWING_ANIM, 0.0, 1.0))
	pos += lunge
	# The hero is a WALKING PORTRAIT like everything else, and the only thing that separates him
	# from a monster is the GOLD ring — the same distinction the arena's rings already use.
	draw_set_transform(Vector2(base_pos.x, base_pos.y + DISC_DIA * 0.52), 0.0, Vector2(1.0, 0.34))
	draw_circle(Vector2.ZERO, DISC_DIA * 0.54, Color(0, 0, 0, 0.48))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tex: Texture2D = _disc("assets/monsters/%s.png" % _hero_face())
	if tex != null:
		draw_texture_rect(tex, Rect2(pos.x - DISC_DIA * 0.5, pos.y - DISC_DIA * 0.5, DISC_DIA, DISC_DIA), false)
	# The player's ring is the SAME blue the hero's stat page uses for his portrait frame
	# (`MOD_BLUE #4a7dff`). A gold ring on both sides made the hero indistinguishable from the
	# pack — the two looked like five enemies. Colour, not size, is what separates him.
	var hero_ring := Color(UIKit.MOD_BLUE)
	draw_arc(pos, DISC_DIA * 0.5 + 3.5, 0.0, TAU, 32, Color(0, 0, 0, 0.45), 2.0, true)
	draw_arc(pos, DISC_DIA * 0.5, 0.0, TAU, 32, hero_ring, 2.5, true)


## The hero's REACH, drawn on the ground he stands on. Dashed, because a solid circle reads as a
## second body outline; it brightens and thickens for a moment on every landed swing, which is
## half of "the player can see something happened".
const SWING_ANIM := 0.22
const RING_SEGMENTS := 28


func _draw_attack_ring() -> void:
	var pos: Vector2 = run.player_pos - _cam
	var hot := 0.0
	if run.swing_age >= 0.0 and run.swing_age < SWING_ANIM:
		hot = 1.0 - float(run.swing_age) / SWING_ANIM
	var col := Color(UIKit.MOD_BLUE)
	col.a = 0.20 + 0.55 * hot
	var radius := SurvivorRun.ATTACK_RANGE
	for i in RING_SEGMENTS:
		var a0 := TAU * float(i) / float(RING_SEGMENTS)
		var a1 := a0 + TAU / float(RING_SEGMENTS) * 0.55
		draw_arc(pos, radius, a0, a1, 6, col, 1.5 + 1.5 * hot, true)


## The swing itself: an arc sweeping across the reach in the direction the blow was aimed. Drawn
## OVER the bodies so it reads as the blow landing on them, not as a decal on the grass.
func _draw_slash() -> void:
	if run.swing_age < 0.0 or run.swing_age > SWING_ANIM:
		return
	var t := clampf(float(run.swing_age) / SWING_ANIM, 0.0, 1.0)
	var pos: Vector2 = run.player_pos - _cam
	var base: float = run.swing_dir.angle()
	# The leading edge travels ~40 deg across the target, the stroke fades and thins as it goes.
	var lead := base - 0.55 + 1.10 * t
	var col := Color("#f0e0c0")
	col.a = 0.95 * (1.0 - t * 0.75)
	var r0 := SurvivorRun.ATTACK_RANGE * 0.62
	var r1 := SurvivorRun.ATTACK_RANGE
	draw_arc(pos, r1, lead - 0.42, lead, 12, col, 4.0 * (1.0 - t) + 1.0, true)
	draw_arc(pos, r0, lead - 0.30, lead, 10, Color(col.r, col.g, col.b, col.a * 0.55), 2.0, true)


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
			var col := Color(str(d.get("color", "#888888")))
			draw_circle(pos + Vector2(0, bob), 8.0, Color(0, 0, 0, 0.35))
			draw_rect(Rect2(pos.x - 6.0, pos.y - 6.0 + bob, 12.0, 12.0), Color(0x1b / 255.0, 0x17 / 255.0, 0x12 / 255.0))
			draw_rect(Rect2(pos.x - 6.0, pos.y - 6.0 + bob, 12.0, 12.0), col, false, 2.0)


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
			"hurt":
				col = Color("#e07068")
				fs = 17
			"gold":
				col = C_GOLD
				fs = 13
			"item":
				col = Color("#d8d0b0")
				fs = 12
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
	draw_string(font, Vector2(12, 42), "Vlna %d" % run.wave, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, C_TEXT)
	draw_string(font_r, Vector2(96, 42), "%d zabito" % run.kills, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, C_DIM)
	# ⚠️  `draw_string` with a width of -1 and RIGHT alignment does NOT right-align — it draws
	# rightwards from the anchor and ran under the Konec box. Give it a box of its own.
	draw_string(font, Vector2(size.x - 168, 42), _clock(), HORIZONTAL_ALIGNMENT_LEFT, 66.0, 15, C_GOLD)

	# Exit (a fixed, always-visible way out — a run must never trap the player on a phone)
	draw_rect(_exit_rect, Color(0x2a / 255.0, 0x24 / 255.0, 0x1c / 255.0, 0.95))
	draw_rect(_exit_rect, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.55), false, 1.5)
	draw_string(font_r, Vector2(_exit_rect.position.x + _exit_rect.size.x * 0.5, _exit_rect.position.y + 23),
		"Konec", HORIZONTAL_ALIGNMENT_CENTER, -1.0, 12, C_TEXT)

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

	# Fixed potion button
	draw_circle(_potion_centre, BUTTON_RADIUS, Color(0x1e / 255.0, 0x1b / 255.0, 0x17 / 255.0, 0.85))
	draw_arc(_potion_centre, BUTTON_RADIUS, 0.0, TAU, 32, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.75), 2.0, true)
	draw_string(font, _potion_centre + Vector2(0, 6), "L", HORIZONTAL_ALIGNMENT_CENTER, -1.0, 18, C_GOLD)

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
