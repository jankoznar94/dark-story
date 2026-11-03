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
## wherever the thumb lands — and the buttons are FIXED in the bottom-LEFT, so the hand that walks
## is the other one. The ATTACK is HELD, never automatic: while the button (or an offensive spell)
## is down, the RULES pick a target in the direction the hero looks and walk him into it (see
## `survivor_run._pick_target`).
##
## ⚠️  One finger arrives TWICE on this engine (`Input` synthesises a mouse event from every
## touch), so the press/release pair goes through `_pointer_down`: the first event of the
## pair starts the gesture and the second is ignored. Motion is never gated — a finger DRAG
## delivers `ScreenDrag` and no `MouseMotion` at all, so a motion gate breaks dragging on
## the phone.

signal leave_requested
signal run_finished(outcome: String)

const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")
const ActionWheel := preload("res://scripts/combat/action_wheel.gd")
const RunSpells := preload("res://scripts/combat/run_spells.gd")
const UIKit := preload("res://scripts/ui/ui_kit.gd")
const UIFonts := preload("res://scripts/ui/ui_fonts.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")

const STEP := 1.0 / 60.0
const MAX_STEPS_PER_FRAME := 6

const TOP_BAR := 54.0
const STICK_RADIUS := 58.0
const STICK_DEADZONE := 9.0
## The action wheel: the same round area the movement stick uses, and a thumb has to push PAST the
## ring for the sector to count. `WHEEL_ACTIVATE` is deliberately outside `STICK_RADIUS` — Jan:
## "když hráč určitým směrem přetáhne mimo kruh, tak se to bere jako aktivace."
const WHEEL_DEADZONE := 12.0
const WHEEL_ACTIVATE := 74.0
const WHEEL_MAX := 92.0
const WHEEL_ICON_RADIUS := 20.0
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

## THE ACTION WHEEL (left thumb). It appears where the thumb lands; the direction it is pushed
## into is the action. `_wheel_slot` is the sector under the thumb right now (-1 = inside the
## deadzone, i.e. nothing held), and `_wheel_slots` is what each sector is bound to.
var _wheel_origin := Vector2.ZERO
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
	_stick_index = -1
	_wheel_index = -1
	_wheel_vec = Vector2.ZERO
	_wheel_slot = -1
	_attack_held = false
	_held_spell = ""
	_bind_open = false
	_bind_pick = -1
	_wheel_slots = _resolve_wheel()
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
	# THE WALL. A band of boulders and dead bushes standing on the inset rectangle the rules
	# stop the hero at: the area has ends, and the thing the player runs into is the thing that
	# stopped him. Spaced ~74 px with a lit rock in every other slot, so there is no gap to read
	# as an exit. Nothing collides with a prop — the clamp is the wall.
	var x0 := SurvivorRun.AREA_MARGIN
	var y0 := SurvivorRun.AREA_MARGIN
	var x1 := SurvivorRun.WORLD.x - SurvivorRun.AREA_MARGIN
	var y1 := SurvivorRun.WORLD.y - SurvivorRun.AREA_MARGIN
	var along := 0
	var x := x0
	while x <= x1:
		for yy in [y0, y1]:
			_props.append(_wall_prop(Vector2(x + rng.randf_range(-12, 12),
				yy + rng.randf_range(-9, 9)), along, rng))
			along += 1
		x += 74.0
	var y := y0 + 74.0
	while y < y1 - 40.0:
		for xx in [x0, x1]:
			_props.append(_wall_prop(Vector2(xx + rng.randf_range(-9, 9),
				y + rng.randf_range(-12, 12)), along, rng))
			along += 1
		y += 74.0
	# Interior cover. Sparse on purpose: it is something to run past, and a pack has to be
	# readable from a distance instead of hiding behind a bush.
	for _i in 26:
		var kind := "rock" if rng.randf() < 0.6 else "bush"
		_props.append({
			"pos": Vector2(rng.randf_range(x0 + 60, x1 - 60),
				rng.randf_range(y0 + 60, y1 - 60)),
			"kind": kind,
			"size": rng.randf_range(20, 44) if kind == "rock" else rng.randf_range(22, 40),
			"seed": rng.randf() * 10.0,
		})
	# Nothing may spawn on the hero's first step.
	_props = _props.filter(func(p): return (p["pos"] as Vector2).distance_to(SurvivorRun.WORLD * 0.5) > 70.0)


## One piece of the wall. Bigger and darker than interior cover: at a glance it has to read as
## "the area ends here", not as one more rock to walk around.
func _wall_prop(pos: Vector2, index: int, rng: RandomNumberGenerator) -> Dictionary:
	var rock := index % 3 != 2
	return {
		"pos": pos,
		"kind": "rock" if rock else "bush",
		"size": rng.randf_range(42, 66) if rock else rng.randf_range(30, 46),
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
	if _bind_rect.has_point(pos):
		_open_bind()
		return
	if pos.y < TOP_BAR:
		return
	# TWO THUMBS, TWO WHEELS, split down the middle of the screen: the LEFT one is the action
	# wheel, the RIGHT one walks. Nobody has to find a small button any more — a press anywhere in
	# a half starts that half's control.
	if pos.x < size.x * 0.5:
		if _wheel_index >= 0:
			return
		_wheel_index = index
		_wheel_origin = pos
		_wheel_vec = Vector2.ZERO
		_set_wheel_slot(-1)
		queue_redraw()
		return
	if _stick_index >= 0:
		return
	_stick_index = index
	_pointer_down = true
	_stick_origin = pos
	_stick_vec = Vector2.ZERO
	queue_redraw()


func _on_drag(pos: Vector2, index: int = 0) -> void:
	if index == _wheel_index:
		_wheel_vec = (pos - _wheel_origin).limit_length(WHEEL_MAX)
		# A sector only counts once the thumb is PAST the ring (Jan): inside it the wheel is a
		# resting thumb, and a resting thumb must not keep an action running.
		var slot := -1
		if _wheel_vec.length() >= WHEEL_ACTIVATE:
			slot = ActionWheel.sector_at(_wheel_vec)
		_set_wheel_slot(slot)
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


## Enter (or leave) a sector. ONE place decides what the run is being told: the HOLD side (attack /
## an offensive spell, which keeps playing while the thumb stays) and the TRIGGER side (a potion or
## a queued spell, fired once on ENTERING the sector — a potion drunk twice because the thumb
## drifted is a bug the player pays for).
func _set_wheel_slot(slot: int) -> void:
	if slot == _wheel_slot:
		return
	_wheel_slot = slot
	var action := wheel_action(slot)
	var hold_attack := action == ActionWheel.ATTACK
	var hold_spell := action if RunSpells.is_offensive(action) else ""
	_attack_held = hold_attack
	_held_spell = hold_spell
	if run != null:
		run.attack_held = hold_attack
		run.held_spell = hold_spell
	if action != ActionWheel.EMPTY and not ActionWheel.is_hold(action, RunSpells):
		_fire_action(action)


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
		_wheel_index = -1
		_wheel_vec = Vector2.ZERO
		_set_wheel_slot(-1)
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
	# ONE report per run, whatever ended it: contact damage ("dead") or the last pack of the area
	# ("cleared"). The old code only knew death, so a finished area kept simulating.
	if run.finished and run.outcome != "" and not _death_reported:
		_death_reported = true
		stop()
		run_finished.emit(run.outcome)
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
			"orb":
				# The throw itself. A caster that fires silently reads as a bug in the hero's
				# health bar, so the cue is part of the feature, not decoration.
				Sfx.play_global(Sfx.CUE_ENEMY_CAST)
			"pack":
				# A pack waking is the beat the whole area model exists for: the player has to
				# HEAR that walking into the next cell started something.
				Sfx.play_global(Sfx.CUE_SHOUT)
			"zone":
				_say("Oblast vyčištěna")
			"cleared":
				Sfx.play_global(Sfx.CUE_VICTORY)
				_say("Celá oblast je čistá")
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


## The two fixed controls left in the fight: the way out and the wheel's editor. Both sit in the
## top bar, out of both thumbs' way.
func _layout_buttons() -> void:
	_exit_rect = Rect2(size.x - 96.0, 10.0, 84.0, 34.0)
	_bind_rect = Rect2(size.x - 180.0, 10.0, 76.0, 34.0)
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
	draw_rect(Rect2(Vector2.ZERO, size), Color("#1b1712"))
	_draw_ground()
	_draw_patches()
	_draw_props()
	_draw_attack_ring()
	_draw_drops()
	_draw_actors()
	_draw_projectiles()
	_draw_bolts()
	_draw_slash()
	_draw_slash_off()
	_draw_effects()
	_draw_numbers()
	_draw_hud()
	_draw_wheel()
	_draw_whirlwind()
	# The bind panel is the LAST paint: it is a modal over a live fight and nothing may come up
	# over it.
	if _bind_open:
		_draw_bind_panel()


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
	# WHICH BODY THE ASSIST PICKED. Without this the player cannot tell what he is hitting: the
	# game chooses the target, so it has to show its choice. A blue ring outside the bronze one
	# plus a small chevron over the portrait — the hero's own colour, so nobody reads it as a buff.
	if int(m["id"]) == int(run.target_id):
		var mark := Color(UIKit.MOD_BLUE)
		draw_arc(pos + Vector2(0, bob), DISC_DIA * 0.5 + 7.0, 0.0, TAU, 30,
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
	# WHICH WAY HE FACES, drawn ON his own portrait. The reach ring says it too, but a crowded
	# frame buries that ring under the bodies that are touching him — measured: with three kinds
	# in contact the front half of the reach circle is behind their discs, so the only honest
	# place for the mark is the hero himself. A chevron, dark-underlaid so it reads on the
	# portrait's own dark plate (no glow — Jan's rule).
	var f: Vector2 = run.facing
	var perp := Vector2(-f.y, f.x)
	var tip := pos + f * 25.0
	var l := tip - f * 9.0 + perp * 7.0
	var r := tip - f * 9.0 - perp * 7.0
	draw_polyline(PackedVector2Array([l, tip, r]), Color(0, 0, 0, 0.65), 5.0, true)
	draw_polyline(PackedVector2Array([l, tip, r]), Color(UIKit.MOD_BLUE), 2.5, true)


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
		draw_set_transform(Vector2(pos.x, pos.y + radius * 1.2), 0.0, Vector2(1.0, 0.34))
		draw_circle(Vector2.ZERO, radius * 1.15, Color(0, 0, 0, 0.55))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# A hard dark rim, then the fill. No highlight and no bloom: the edge is the contrast,
		# which is the only way a green ball stays readable on green grass.
		draw_circle(pos, radius + 2.0, rim)
		draw_circle(pos, radius, col)


## The swing itself: an arc sweeping across the reach in the direction the blow was aimed. Drawn
## OVER the bodies so it reads as the blow landing on them, not as a decal on the grass.
##
## TWO ARCS, TWO DIRECTIONS. Jan's rule for a dual-wielder: the MAIN hand sweeps left to right
## and the OFF hand right to left, each at its own weapon's reach and on its own clock. One arc
## drawn twice was what made a barbarian with two swords look like a barbarian with one.
func _draw_slash() -> void:
	_slash(run.swing_age, run.swing_dir, run.reach_main, false)


func _draw_slash_off() -> void:
	if run.off_swing <= 0.0:
		return
	_slash(run.swing_age_off, run.swing_dir_off, run.reach_off, true)


func _slash(age: float, dir: Vector2, reach: float, mirrored: bool) -> void:
	if age < 0.0 or age > SWING_ANIM:
		return
	var t := clampf(age / SWING_ANIM, 0.0, 1.0)
	var pos: Vector2 = run.player_pos - _cam
	var base: float = dir.angle()
	# The off hand is a COOLER stroke on purpose: when both hands swing together the eye has to
	# be able to tell which arc belongs to which weapon. That is a COLOUR difference and
	# nothing else — Jan, Nov 2026: "aby sekání obou zbraní bylo na stejné vizuální úrovni.
	# Stejně daleko … tam, kde reálně končí dosah hrdinových zbraní." So both arcs sweep the SAME
	# band of their own reach and carry the same width and the same opacity. The off hand used to
	# be drawn 0.54-0.92 R, a little inside, and that read as a shorter arm rather than as a
	# second weapon.
	var col := Color("#f0e0c0") if not mirrored else Color("#a9c2e0")
	col.a = 0.95 * (1.0 - t * 0.75)
	var r0 := reach * 0.62
	var r1 := reach
	var width := 4.0 * (1.0 - t) + 1.0
	if mirrored:
		# Right to left, the same band the main hand sweeps, so the two arcs cross rather than
		# nest.
		var lead := base + 0.55 - 1.10 * t
		draw_arc(pos, r1, lead, lead + 0.42, 12, col, width, true)
		draw_arc(pos, r0, lead, lead + 0.30, 10,
			Color(col.r, col.g, col.b, col.a * 0.55), 2.0, true)
	else:
		# Left to right.
		var lead := base - 0.55 + 1.10 * t
		draw_arc(pos, r1, lead - 0.42, lead, 12, col, width, true)
		draw_arc(pos, r0, lead - 0.30, lead, 10,
			Color(col.r, col.g, col.b, col.a * 0.55), 2.0, true)


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


## THE ACTION WHEEL. It appears where the thumb lands, so the player never has to find a button:
## the six icons sit ON the ring (outside the thumb's own disc), the sector under the thumb is lit,
## and a knob follows the finger so the gesture has a visible body.
##
## The activation ring is drawn as a thin DASHED circle OUTSIDE the plate, because it is a line the
## thumb has to CROSS — Jan's own rule ("když hráč určitým směrem přetáhne mimo kruh, tak se to bere
## jako aktivace"). Below the wheel, the active action's name is written out: the one thing a
## player who is NOT looking at his thumb still needs to be sure about.
func _draw_wheel() -> void:
	if _wheel_index < 0:
		return
	var o := _wheel_origin
	var font := UIFonts.bold()
	var font_r := UIFonts.regular()
	draw_circle(o, STICK_RADIUS, Color(0, 0, 0, 0.34))
	draw_arc(o, STICK_RADIUS, 0.0, TAU, 48, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.30), 2.0, true)
	_dashed_ring(o, WHEEL_ACTIVATE, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.22), 1.2)
	# The boundaries between sectors: faint, so the icons carry the reading and the lines only say
	# "this wheel has six places".
	for i in ActionWheel.SLOTS:
		var a: float = ActionWheel.centre_angle(i) + PI / float(ActionWheel.SLOTS)
		draw_line(o + Vector2(cos(a), sin(a)) * 22.0,
			o + Vector2(cos(a), sin(a)) * STICK_RADIUS,
			Color(1, 1, 1, 0.055), 1.0, true)
	# The six slots, on the ring.
	for i in ActionWheel.SLOTS:
		var c := o + Vector2.from_angle(ActionWheel.centre_angle(i)) * STICK_RADIUS
		var action := wheel_action(i)
		var active := i == _wheel_slot
		var empty := action == ActionWheel.EMPTY
		var fill := Color(0x1e / 255.0, 0x1b / 255.0, 0x17 / 255.0, 0.92 if active else 0.72)
		draw_circle(c, WHEEL_ICON_RADIUS, fill)
		if not empty:
			_draw_action_icon(action, c, WHEEL_ICON_RADIUS - 4.0, active)
		var rim := Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.95) if active else Color(
			0x6a / 255.0, 0x61 / 255.0, 0x4f / 255.0, 0.75)
		if empty:
			rim = Color(0x4a / 255.0, 0x44 / 255.0, 0x3a / 255.0, 0.7)
		draw_arc(c, WHEEL_ICON_RADIUS, 0.0, TAU, 26, rim, 3.0 if active else 1.5, true)
	# The knob: the thumb itself, at the vector it has pulled.
	draw_circle(o + _wheel_vec * (STICK_RADIUS / WHEEL_ACTIVATE),
		20.0, Color(0xd8 / 255.0, 0xc8 / 255.0, 0xa0 / 255.0, 0.55))
	# What is being held, in words, UNDER the wheel (the wheel is above the thumb, the label above
	# the wheel would sit under the hero's own portrait).
	var label_y := o.y + WHEEL_ACTIVATE + 26.0
	var action_now := wheel_action(_wheel_slot)
	if action_now == ActionWheel.EMPTY:
		draw_string(font_r, Vector2(o.x - 90.0, label_y), "přetáhni na akci",
			HORIZONTAL_ALIGNMENT_CENTER, 180.0, 12, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.85))
		return
	var held := ActionWheel.is_hold(action_now, RunSpells)
	var word := ActionWheel.action_name(action_now, run.spell_bar())
	draw_string(font, Vector2(o.x - 90.0, label_y), word,
		HORIZONTAL_ALIGNMENT_CENTER, 180.0, 14, C_GOLD)
	draw_string(font_r, Vector2(o.x - 90.0, label_y + 14.0),
		"držíš" if held else "spuštěno", HORIZONTAL_ALIGNMENT_CENTER, 180.0, 10, C_DIM)


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
		draw_set_transform(Vector2(pos.x, pos.y + radius * 1.1), 0.0, Vector2(1.0, 0.34))
		draw_circle(Vector2.ZERO, radius * 1.1, Color(0, 0, 0, 0.5))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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
				draw_rect(Rect2(Vector2.ZERO, size),
					Color(col.r, col.g, col.b, (1.0 - t) * 0.45))
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

