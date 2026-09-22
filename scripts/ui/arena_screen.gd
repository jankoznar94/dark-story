extends Control
class_name ArenaScreen
## ArenaScreen — the fight screen, laid out from the PWA's own CSS.
##
## This screen owns NO rules. `scripts/combat/battle.gd` ticks the fight; everything here
## draws a number the battle already settled. That split is what lets a test drive a real
## fight headlessly — see tools/test_arena_screen.gd.
##
## Geometry is taken from the PWA, not re-invented, because "it looks like a different
## game" was the whole complaint. Source: `public/style.css` of pwa-game-auto-combat.
##
##   .attack-timer-ring   260x260, centred
##       player timer     r=110 w=12  #f1c40f   (from 12 o'clock clockwise)
##       offhand timer    r=120 w=8   #f1c40f   opacity 0.5
##       enemy timer bg   r=88  w=5   #333333
##       enemy timer      r=88  w=5   #e67e22
##       zone divider     r=104 w=3   #9a9a9a
##   .monster-in-ring     180x180, circular crop, centred
##   .enemy-hp-ring       200x200: track r=95 #2a0a0a, ghost #8a1f1f, fill #e74c3c, w=9
##   .hp-ring-label       24px bold #e74c3c, ~55px above centre
##   .player-figure       hero BODY sprite (not the head), size/position see HERO_*
##   .mb-spells           36x36, radius 6, border #2a2a2a
##   .mb-hp-bar           22px, radius 6, track #2a0a0a, border #e74c3c, fill #e74c3c
##   .mb-mana-bar         22px, radius 6, track #1a1a2a, border #3a3a6a, fill #4a6ad4
##
## What is deliberately NOT here: the PWA's rapid-tap minigames and its opportunity
## dodge/block/counter reaction buttons — interaction models for a page that is watched
## while tapped (see docs/port-notes.md). The depth axis IS here: `_gap` drives the
## hero's walk-in, his scale and the monster's lean.
##
## ============================================================================ the clock
##
## There are TWO clocks on this screen and confusing them is what made the fight look like
## 5 FPS:
##
##   * `battle.gd`'s clock — a fixed 100 ms step. Every RULE is settled on it (when a swing
##     lands, when a DoT ticks, when a pack hands over) and it must stay fixed: a swing
##     interval is a whole number of ticks.
##   * the FRAME — real time, ~60 fps on a phone.
##
## `render()` used to be the only thing that moved anything on screen, and it is called from
## `step()` — i.e. TEN TIMES A SECOND. So the swing arc advanced in ten 100 ms jumps, the
## bars and the walk-in jumped with it, and the screen ran at 10 fps while the engine drew
## 60: `probe_watch.gd` measured the arc changing in 21 of 120 frames. Nothing was slow —
## the numbers were computed smoothly and then not drawn.
##
## So the split is now:
##
##   * `step()` -> the RULES (a fixed 100 ms), plus `render()` for everything that only
##     changes when a rule does (labels, name, portrait, roster, the bar's contents).
##   * `_animate(delta)` -> the FIGURES, every frame, from real time (lunges, flinch, the
##     walk-in, the monster's lean, the floating numbers).
##   * `_smooth_update()` -> the GAUGES and BARS, every frame, interpolated: the swing arcs
##     take the battle's elapsed time PLUS the real time this frame has not spent on a tick
##     yet, so a 1156 ms weapon sweeps its ring over 1156 ms instead of in 11 visible steps.
##
## An ANIMATION may interpolate; a RULE must not. Nothing here ever feeds a partial tick
## back into the battle.

const ItemGen := preload("res://scripts/items/item_gen.gd")
const Battle := preload("res://scripts/combat/battle.gd")
const GaugeArc := preload("res://scripts/ui/ui_gauge.gd")

signal fight_over(won: bool)
signal leave_requested()
signal another_fight_requested()

## One rendered frame is one fight tick. A fixed step rather than the frame's real delta
## keeps the pace identical on every machine and lets a test drive the same fight.
const TICK_MS := 100

## The screen's own clock is REAL TIME. `_process` used to pump exactly ONE 100 ms tick
## per frame and ignore `delta`, which made the FRAME RATE the fight's speed: the port
## renders at roughly 60 fps (its per-frame work is ~0.1 ms — measured by
## tools/probe_timing.gd), so a 1156 ms weapon swung every ~17 frames, about 170 ms.
## The fight ran ~6x fast and no weapon's `swingMs` could be felt at all.
##
## Now the accumulator converts elapsed real time into fixed steps, which is what the
## PWA did with `performance.now()`: the fight advances by however much time passed, and
## the intervals in `battle.gd` are the ones the player actually experiences.
##
## A step is still TICK_MS, never `delta`, so a frame dropped on a slow machine cannot
## hand either side a free swing.
const MAX_STEPS_PER_FRAME := 5
var _tick_accumulator := 0.0

## One class spell is at most one cast per frame: `_refresh_spells()` rebuilds the bar
## when a spell's blocked reason changes, so casting every spell in one frame would free
## the buttons under the player's finger mid-tap.
var _cast_this_frame := false

## How many log lines the (small, dim) footer keeps. The PWA had no text log at all —
## its feedback was floating numbers over the arena — so the log is deliberately quiet
## here: it is a debugging aid, not the main readout.
const LOG_LINES := 3

## PWA colours, verbatim from public/style.css.
const C_BG := "#121212"
const C_GOLD := "#f1c40f"
const C_ENEMY_TIMER := "#e67e22"
const C_DIVIDER := "#9a9a9a"
const C_ENEMY_HP := "#e74c3c"
const C_ENEMY_HP_TRACK := "#2a0a0a"
const C_ENEMY_HP_GHOST := "#8a1f1f"
const C_NAME := "#e8e8e8"
const C_LOCATION := "#999999"
const C_BORDER := "#2a2a2a"
const C_MANA_TRACK := "#1a1a2a"
const C_MANA_BORDER := "#3a3a6a"
const C_MANA_FILL := "#4a6ad4"
const C_HERO_RING := "#4a7dff"

## Hero placement in the arena — the PWA's HERO_X_START / HERO_X_NEAR, HERO_Y_FAR /
## HERO_Y_NEAR and HERO_SCALE_FAR, as fractions. The hero starts at the arena's centre
## (bottom) at maximum separation and walks in SIDEWAYS to stand beside the monster at
## contact; he also grows as he arrives, which is the main visual cue for distance.
##
## Standing him at the near position permanently (which this did while `_gap` was
## unported) reads as "the hero is pasted onto the monster", not as a duel.
const HERO_X_START := 0.50
const HERO_X_NEAR := 0.20
const HERO_Y_FAR := 0.93
const HERO_Y_NEAR := 0.84
const HERO_SCALE_FAR := 0.75
const HERO_SCALE_NEAR := 1.0
## The monster leans forward (down) as the hero arrives — the PWA's `--monster-dy`,
## `closed * 8` px, capped by the CSS comment's "0..8 px". Two figures standing at
## contact, not one figure and one portrait.
const MONSTER_TILT_MAX := 8.0
const HERO_H_RATIO := 0.19
const HERO_H_MIN := 72.0
const HERO_H_MAX := 118.0

const RING_BOX := 260.0
const PORTRAIT_BOX := 180.0
const HP_RING_BOX := 200.0

var _data: Node
var _gen: ItemGen
var _loot
var _state
var _find_item: Callable

var battle: Battle
var _monster_seen: Dictionary = {}

var _arena: Control
var _portrait      # CircularPortrait
var _enemy_name: Label
var _location_label: Label
var _enemy_hp_label: Label
var _hero_sprite: TextureRect
var _pack_row: HBoxContainer
## Which pack member the screen is currently showing, so a hand-over is noticed.
var _pack_displayed := 0
var _spell_ring_enabled := false

# Ring arcs, drawn from battle numbers each render.
var _arc_player: GaugeArc
var _arc_offhand: GaugeArc
var _arc_enemy_timer: GaugeArc
var _arc_enemy_hp: GaugeArc
var _arc_enemy_hp_ghost: GaugeArc
var _arc_enemy_mana: GaugeArc
var _arc_divider: GaugeArc

var _hero_hp_track: Control
var _hero_hp_fill: ColorRect
var _hero_hp_bar_label: Label
var _mana_track: Control
var _mana_fill: ColorRect
var _mana_label: Label
var _xp_fill: ColorRect
var _xp_label: Label

var _potion_row: HBoxContainer
## One button per learned class spell, rebuilt whenever the fight state changes.
var _spell_row: HBoxContainer
## The bar's current contents, so render() does not rebuild it ten times a second.
var _spell_signature := ""
var _log_box: VBoxContainer
var _result_label: Label
var _cast_icon: TextureRect
var _confirm_layer: Control
var _surrender_button: Button
var _next_button: Button
var _loot_button: Button
var _leave_button: Button

var _log_lines: Array = []
## Loot that did not fit in the bag. Held here so a full bag never destroys a drop.
var _pending_loot: Array = []
## How many ticks each end-of-fight button must be up before it accepts a tap. A tap
## that lands while the last damage frame is still drawing ends up on whichever button
## just appeared — the player asked to attack, not to walk away. 3 ticks = 300 ms.
var _button_lock := 0

# Floating combat text, the PWA's replacement for a damage log.
var _float_layer: Control
var _floats: Array = []
var _seen_log_index := 0
## The ghost ring needs two things a single `render()` could not give it: the last real
## frame's length and how long the PWA's transition lasted.
const GHOST_TRAIL_SECONDS := 0.6
## The last frame's length, so the ghost trail is 0.6 s of real time and not 0.6 s worth of
## frames (which would halve the trail on a 120 fps display).
var _frame_delta := 1.0 / 60.0

## Swing animations: the hero lunges, the monster lunges, on their own attack.
var _hero_lunge := 0.0
var _monster_lunge := 0.0
var _hero_flinch := 0.0

## Everything the screen consumed out of `battle.log`, with the fight's clock at the moment
## each entry arrived. The screen is what DRAINS the log, so anything that wants to know
## what the player saw has to ask here — reading `battle.log` from outside comes back
## empty, and a pacing test that did so reported "0 landed hits in 12 s" about a fight
## that was landing them the whole time.
##
## Capped, because a long fight logs a lot: the oldest entry is dropped.
const DRAIN_HISTORY_MAX := 400
var drain_history: Array = []


func _init(game_data: Node, gen: ItemGen, loot, state, find_item: Callable) -> void:
	_data = game_data
	_gen = gen
	_loot = loot
	_state = state
	_find_item = find_item


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


# ============================================================================= build

func _build() -> void:
	add_child(_background())

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_header())

	# The arena takes every pixel the header and the bottom stack do not.
	_arena = Control.new()
	_arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_arena.clip_contents = true
	root.add_child(_arena)
	_build_arena()

	root.add_child(_build_spell_row())
	root.add_child(_build_bottom())

	# The end-of-fight controls sit over the arena's lower half rather than pushing the
	# layout around: showing a "Dalsi souboj" button must not resize the fight.
	var overlay := VBoxContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.alignment = BoxContainer.ALIGNMENT_END
	overlay.add_theme_constant_override("separation", 4)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_bottom", 132)
	overlay.add_child(pad)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	pad.add_child(inner)
	_result_label = _label("", 26, Color(C_NAME), HORIZONTAL_ALIGNMENT_CENTER)
	inner.add_child(_result_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	inner.add_child(buttons)
	_next_button = _make_button("Dalsi souboj")
	_next_button.pressed.connect(func(): _on_next_pressed())
	_next_button.visible = false
	buttons.add_child(_next_button)
	_loot_button = _make_button("Sebrat loot")
	_loot_button.pressed.connect(func(): _on_loot_pressed())
	_loot_button.visible = false
	buttons.add_child(_loot_button)
	_leave_button = _make_button("Zpet do mesta")
	_leave_button.pressed.connect(func(): _on_leave_pressed())
	buttons.add_child(_leave_button)

	_build_confirm()


## `.surrender-modal` — the confirmation the PWA put between the flag and the forfeit.
## Drawn as a layer over the arena rather than as a Godot `AcceptDialog`, because the game
## forbids the OS dialog chrome and the PWA's own modal is a flat panel on the page.
func _build_confirm() -> void:
	_confirm_layer = Control.new()
	_confirm_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.visible = false
	add_child(_confirm_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_layer.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_layer.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 0)
	panel.add_theme_stylebox_override("panel", _flat_style("#1a1a1a", C_BORDER, 10))
	centre.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	pad.add_child(column)

	var title := _label("Vzdát souboj?", 16, Color(C_NAME), HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(title)
	var body := _label("Přijdeš o všechny souboje této zastávky a započítá se smrt.",
		12, Color(C_LOCATION), HORIZONTAL_ALIGNMENT_CENTER)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(240, 0)
	column.add_child(body)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	var no_button := _make_button("Zrušit")
	no_button.custom_minimum_size = Vector2(110, 38)
	no_button.pressed.connect(func(): _close_confirm())
	row.add_child(no_button)
	var yes_button := _make_button("Vzdát se")
	yes_button.custom_minimum_size = Vector2(110, 38)
	yes_button.pressed.connect(func(): _on_surrender_confirmed())
	row.add_child(yes_button)


func _background() -> Control:
	var bg := ColorRect.new()
	bg.color = Color(C_BG)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg


## `.battle-header` — enemy name on the left, location on the right, 6px/12px padding.
func _build_header() -> Control:
	var header := MarginContainer.new()
	header.add_theme_constant_override("margin_left", 12)
	header.add_theme_constant_override("margin_right", 12)
	header.add_theme_constant_override("margin_top", 6)
	header.add_theme_constant_override("margin_bottom", 6)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	header.add_child(row)

	_enemy_name = _label("", 15, Color(C_NAME))
	_enemy_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_name.clip_text = true
	row.add_child(_enemy_name)

	_location_label = _label("", 12, Color(C_LOCATION), HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(_location_label)
	return header


## Everything inside `.boss-fight-arena`: the ring stack, the portraits, the overlays.
func _build_arena() -> void:
	# Draw order is the PWA's z-index stack, and it matters: the enemy's turn-timer ring
	# (r=88, stroke 5 → 85.5..90.5) hugs the 180px portrait disc (r=90) and is drawn ON
	# TOP of it. Building the portrait first and the rings after is what reproduces that.
	_portrait = CircularPortrait.new()
	_portrait.custom_minimum_size = Vector2(PORTRAIT_BOX, PORTRAIT_BOX)
	_portrait.size = Vector2(PORTRAIT_BOX, PORTRAIT_BOX)
	_arena.add_child(_portrait)
	_centre_in_arena(_portrait)

	# `.enemy-timer-bg` then the enemy timer, then the player's two gold arcs.
	_centred_arc(RING_BOX, 88.0, 5.0, "#333333")
	_arc_enemy_timer = _centred_arc(RING_BOX, 88.0, 5.0, C_ENEMY_TIMER)
	_arc_player = _centred_arc(RING_BOX, 110.0, 12.0, C_GOLD)
	_arc_offhand = _centred_arc(RING_BOX, 120.0, 8.0, C_GOLD)
	_arc_offhand.modulate = Color(1, 1, 1, 0.5)
	_arc_offhand.visible = false

	# `.enemy-hp-ring` — 200px, so it clears the portrait and reads as the outer gauge.
	_centred_arc(HP_RING_BOX, 95.0, 9.0, C_ENEMY_HP_TRACK)
	_arc_enemy_hp_ghost = _centred_arc(HP_RING_BOX, 95.0, 9.0, C_ENEMY_HP_GHOST)
	_arc_enemy_hp = _centred_arc(HP_RING_BOX, 95.0, 9.0, C_ENEMY_HP)
	_arc_enemy_mana = _centred_arc(HP_RING_BOX, 92.0, 5.0, C_MANA_FILL)
	_arc_enemy_mana.visible = false

	# `.zone-divider` — a dashed grey circle at r=104, the marker between the player's
	# window and the enemy's. Dashes are what tell it apart from a gauge.
	_arc_divider = _centred_arc(RING_BOX, 104.0, 3.0, C_DIVIDER)
	_arc_divider.dash_on_degrees = 2.5
	_arc_divider.dash_off_degrees = 3.0

	_enemy_hp_label = _label("", 24, Color(C_ENEMY_HP), HORIZONTAL_ALIGNMENT_CENTER)
	_enemy_hp_label.size = Vector2(120, 30)
	_arena.add_child(_enemy_hp_label)
	_centre_in_arena(_enemy_hp_label, -62.0)

	_float_layer = Control.new()
	_float_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.add_child(_float_layer)

	# `.player-figure` — the hero's whole BODY, standing beside the monster.
	_hero_sprite = TextureRect.new()
	_hero_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.add_child(_hero_sprite)

	# `.pack-roster` — a row of 46px members along the top, only for pack fights.
	_pack_row = HBoxContainer.new()
	_pack_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_pack_row.add_theme_constant_override("separation", 10)
	_pack_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_pack_row.offset_top = 6
	_pack_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.add_child(_pack_row)

	# `.cast-spell-icon` — the enemy's wind-up, drawn over the portrait.
	_cast_icon = TextureRect.new()
	_cast_icon.custom_minimum_size = Vector2(64, 64)
	_cast_icon.size = Vector2(64, 64)
	_cast_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cast_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cast_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cast_icon.visible = false
	_arena.add_child(_cast_icon)
	_centre_in_arena(_cast_icon)

	# `.arena-surrender-btn` — 40px, top right, red flag.
	_surrender_button = Button.new()
	_surrender_button.custom_minimum_size = Vector2(40, 40)
	_surrender_button.size = Vector2(40, 40)
	_surrender_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_surrender_button.offset_left = -44
	_surrender_button.offset_top = 4
	_surrender_button.offset_right = -4
	_surrender_button.offset_bottom = 44
	_surrender_button.focus_mode = Control.FOCUS_NONE
	_surrender_button.add_theme_stylebox_override("normal", _circle_style())
	_surrender_button.add_theme_stylebox_override("hover", _circle_style())
	_surrender_button.add_theme_stylebox_override("pressed", _circle_style())
	_surrender_button.add_theme_stylebox_override("focus", _circle_style())
	# The PWA drew a white flag emoji here. Emoji are banned in the port, so the flag is
	# a real drawn glyph: a red pennant, the same colour the PWA's surrender button used.
	var flag := FlagGlyph.new()
	flag.set_anchors_preset(Control.PRESET_FULL_RECT)
	flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surrender_button.add_child(flag)
	_surrender_button.pressed.connect(func(): _on_surrender())
	_arena.add_child(_surrender_button)

	# `.arena-class-spells` — the class spell bar sits INSIDE the arena, bottom centre.
	_spell_row = HBoxContainer.new()
	_spell_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_spell_row.add_theme_constant_override("separation", 6)
	_spell_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_spell_row.offset_top = -52
	_spell_row.offset_bottom = -10
	_arena.add_child(_spell_row)


## The surrender flag, drawn rather than emoji — a banner pole with a red pennant.
class FlagGlyph:
	extends Control

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pole_x := w * 0.38
		draw_rect(Rect2(pole_x, h * 0.2, maxf(1.5, w * 0.05), h * 0.6), Color("#cfcfcf"))
		var pts := PackedVector2Array([
			Vector2(pole_x, h * 0.2),
			Vector2(pole_x + w * 0.36, h * 0.32),
			Vector2(pole_x, h * 0.46),
		])
		draw_colored_polygon(pts, Color("#e94560"))


## `.mb-spells` wrapper — the PWA puts the class spells inside the arena, so this row is
## the pre-fight/empty state only and stays hidden while a fight is running.
func _build_spell_row() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 0)
	holder.visible = false
	_spell_fallback = holder
	return holder

var _spell_fallback: Control


## The bottom stack: potions, then the HP bar, the mana bar, then the XP line.
func _build_bottom() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.add_theme_constant_override("margin_top", 6)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)

	_potion_row = HBoxContainer.new()
	_potion_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_potion_row.add_theme_constant_override("separation", 6)
	column.add_child(_potion_row)

	var hp := _make_bar(C_ENEMY_HP_TRACK, C_ENEMY_HP)
	_hero_hp_track = hp["track"]
	_hero_hp_fill = hp["fill"]
	_hero_hp_bar_label = hp["label"]
	column.add_child(hp["root"])

	var mana := _make_bar(C_MANA_TRACK, C_MANA_FILL, C_MANA_BORDER)
	_mana_track = mana["track"]
	_mana_fill = mana["fill"]
	_mana_label = mana["label"]
	column.add_child(mana["root"])

	# `.mb-xp-bar-wrap` — a thin line under the two bars, level on the left.
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 6)
	column.add_child(xp_row)
	_xp_label = _label("", 11, Color("#8888aa"))
	xp_row.add_child(_xp_label)
	var xp_track := PanelContainer.new()
	xp_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_track.custom_minimum_size = Vector2(0, 8)
	var xp_style := _flat_style("#1a1a1a", "#2a2a2a", 4)
	xp_track.add_theme_stylebox_override("panel", xp_style)
	xp_row.add_child(xp_track)
	_xp_fill = ColorRect.new()
	_xp_fill.color = Color(C_GOLD)
	_xp_fill.size = Vector2(0, 8)
	xp_fill_holder(xp_track).add_child(_xp_fill)

	# The combat log, kept quiet: three 11px dim lines. The PWA's readout was floating
	# numbers over the arena, which this screen also draws — this is the debug trail.
	_log_box = VBoxContainer.new()
	_log_box.add_theme_constant_override("separation", 1)
	column.add_child(_log_box)
	return margin


## A ColorRect must be positioned by hand inside a PanelContainer, so it gets one.
func xp_fill_holder(track: PanelContainer) -> Control:
	var holder := Control.new()
	holder.clip_contents = true
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(holder)
	return holder


func _centred_arc(box: float, radius: float, thickness: float, colour: String) -> GaugeArc:
	var arc := GaugeArc.track(radius, thickness, colour)
	arc.custom_minimum_size = Vector2(box, box)
	arc.size = Vector2(box, box)
	arc.value = 1.0
	_arena.add_child(arc)
	_centre_in_arena(arc)
	return arc


## Centre a fixed-size child in the arena, with an optional vertical offset in pixels.
## The arena's size is only known after a layout pass, so this is re-run from _process.
func _centre_in_arena(node: Control, dy: float = 0.0) -> void:
	node.set_meta("centre_dy", dy)


func _apply_centring() -> void:
	if _arena == null:
		return
	var mid := _arena.size * 0.5
	for child in _arena.get_children():
		var control := child as Control
		if control == null or not control.has_meta("centre_dy"):
			continue
		var dy: float = control.get_meta("centre_dy")
		control.position = Vector2(
			round(mid.x - control.size.x * 0.5),
			round(mid.y - control.size.y * 0.5 + dy))


## `.monster-ring-frame` is a circle; the portrait image inside it is cropped to match.
func _circle_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.4)
	style.border_color = Color(1.0, 1.0, 1.0, 0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(20)
	return style


func _flat_style(bg: String, border: String, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(bg)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style


func _label(text: String, size: int, colour: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## `.mb-hp-bar` / `.mb-mana-bar`: a 22px rounded track with a left-anchored fill and a
## centred white bold label on top. Returns {root, track, fill, label}.
func _make_bar(track_colour: String, fill_colour: String, border_colour: String = "") -> Dictionary:
	var border := border_colour if border_colour != "" else fill_colour
	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(0, 22)
	var style := _flat_style(track_colour, border, 6)
	root.add_theme_stylebox_override("panel", style)

	var holder := Control.new()
	holder.clip_contents = true
	holder.custom_minimum_size = Vector2(0, 22)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)

	var fill := ColorRect.new()
	fill.color = Color(fill_colour)
	fill.size = Vector2(0, 22)
	holder.add_child(fill)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(centre)
	var text := _label("", 12, Color("#ffffff"), HORIZONTAL_ALIGNMENT_CENTER)
	text.add_theme_constant_override("outline_size", 0)
	centre.add_child(text)

	return {"root": root, "track": holder, "fill": fill, "label": text}


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 40)
	b.focus_mode = Control.FOCUS_NONE
	var style := _flat_style("#000000", C_BORDER, 8)
	for state_name in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(state_name, style)
	var pressed := _flat_style("#000000", "#e67e22", 8)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", Color("#dcdcdc"))
	b.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	b.add_theme_font_size_override("font_size", 13)
	return b


# ============================================================================= fight API

func start(state, find_item: Callable) -> bool:
	_log_lines = []
	_log_box_clear()
	_result_label.text = ""
	_next_button.visible = false
	_loot_button.visible = false
	_loot_button.disabled = false
	_button_lock = 0
	# A new fight starts with a clean real-time clock: a remainder left over from the
	# previous fight would hand the first swing a free 100 ms.
	_tick_accumulator = 0.0
	_cast_this_frame = false
	# A new fight gets a fresh bar: the old signature would suppress the rebuild.
	_spell_signature = ""
	_floats = []
	_seen_log_index = 0
	drain_history = []
	# The roster's "which member am I showing" marker belongs to the FIGHT, not the screen:
	# left over from a pack fight it would read as a hand-over on the next fight's first
	# render and fire a spurious monster lunge.
	_pack_displayed = 0
	# The ghost ring belongs to the FIGHT, not the screen: left over from the previous
	# enemy it would read as damage the new one never took. A fresh enemy is at full HP, so
	# the ghost starts full and trails down as hits land (see `_smooth_update`).
	#
	# It MUST be here and not in `render()`: `render()` runs on every tick, and a reset
	# there re-snapped the trail ten times a second — which is a ghost that never trails.
	_arc_enemy_hp_ghost.set_value_ratio(1.0)
	_hero_lunge = 0.0
	_monster_lunge = 0.0
	_hero_flinch = 0.0
	_clear_floats()

	var seed_value := int(Time.get_ticks_usec()) & 0x7fffffff
	battle = Battle.new(_data, seed_value)
	battle.set_monster_seen(_monster_seen)
	var ok := battle.setup(state, find_item)
	_monster_seen = battle.monster_seen()
	if not ok:
		return false
	battle.apply_swing_timers(state, find_item)

	# `.player-figure` uses the hero's BODY sprite, per class — not the head portrait.
	var hero_class := str(state.data.get("heroClass", "barbarian"))
	var body := _load("assets/monsters/hero_body_%s.png" % hero_class)
	if body == null and is_instance_valid(_hero_sprite):
		body = _load("assets/monsters/hero.png")
	if is_instance_valid(_hero_sprite):
		_hero_sprite.texture = body

	render()
	_refresh_potions()
	_append_log("Souboj zacina")
	return true


## Advance the fight one fixed step and re-render. The screen's _process calls this; a
## test calls it in a loop instead, which is the whole reason it is separate.
##
## ONE call is always exactly TICK_MS of game time — the real-time pacing lives in
## `_process`, so a test still measures ticks and not frames.
func step() -> void:
	if _button_lock > 0:
		_button_lock -= 1
	if battle == null or battle.ended:
		return
	battle.tick(float(TICK_MS), _state, _find_item)
	if battle.ended and battle.hero_hp <= 0.0:
		# A defeat is the BATTLE's to settle (`_finish` counts the death, pays the
		# consolation and resets the stop's fights). The screen used to bump `deaths`
		# here as well, so every death the player saw was counted twice.
		_state.save()
	_drain_log()
	render()
	if battle.ended:
		_finish_fight()


## The fight's real-time clock. `delta` is seconds of wall time; the accumulator turns it
## into whole fixed steps, so the intervals the battle settles are the intervals the player
## feels. The remainder carries to the next frame instead of being rounded away, which is
## what stops a fast frame from shortening a swing.
func _process(delta: float) -> void:
	_cast_this_frame = false
	_frame_delta = maxf(delta, 0.0001)
	_tick_accumulator += delta * 1000.0
	var steps := 0
	while _tick_accumulator >= float(TICK_MS) and steps < MAX_STEPS_PER_FRAME:
		_tick_accumulator -= float(TICK_MS)
		steps += 1
		step()
		if battle == null or battle.ended:
			break
	if steps > 0 and _tick_accumulator > float(TICK_MS):
		# A stall longer than MAX_STEPS_PER_FRAME worth of steps (the phone woke up, the
		# browser tab was backgrounded) leaves time nobody can spend: the cap is what stops
		# a slow frame handing out free swings, and the remainder has to be DROPPED rather
		# than carried, or the accumulator would stay ahead of the clock forever and the
		# gauges would read past the swing they are counting to.
		_tick_accumulator = fmod(_tick_accumulator, float(TICK_MS))
	# The FIGURES and the GAUGES move on real time, every frame. Only the RULES wait for a
	# tick — see the clock note at the top of this file. `step()` has already re-rendered
	# whatever a rule changed, so this must not repeat that work.
	_apply_centring()
	_animate(delta)
	_smooth_update()


func _drain_log() -> void:
	for entry in battle.log:
		var kind := str(entry.get("kind", ""))
		var amount := int(entry.get("amount", 0))
		# The battle writes `onPlayer`; this read `on_player`, so every number the HERO
		# took was drawn in the enemy's white instead of red and the whole colour code
		# of the floating text was dead. Read the key the battle actually writes.
		var on_player := bool(entry.get("onPlayer", false))
		_append_log("%s %d" % [kind, amount] if amount > 0 else kind)
		_spawn_float(kind, amount, on_player)
		drain_history.append({"kind": kind, "amount": amount, "onPlayer": on_player,
			"game_ms": battle.ticks_elapsed * TICK_MS})
		if drain_history.size() > DRAIN_HISTORY_MAX:
			drain_history = drain_history.slice(drain_history.size() - DRAIN_HISTORY_MAX)
		# Swing animations, driven by what actually happened rather than by a timer:
		# the hero lunges on his own landed hit, the monster lunges and the hero
		# flinches when the hero is the one hit.
		if not on_player and kind.begins_with("HIT"):
			_hero_lunge = 1.0
		elif on_player and kind.begins_with("ENEMY HIT"):
			_monster_lunge = 1.0
			_hero_flinch = 1.0
	battle.log.clear()


## Floating damage text over the arena — the PWA's readout, and the reason a text log
## was never visible in the fight. Damage on the enemy is white, damage on the hero is
## red, MISS/BLOCK are their own words.
func _spawn_float(kind: String, amount: int, on_player: bool) -> void:
	if _float_layer == null:
		return
	var text := kind
	if amount > 0:
		text = "%s%d" % ["-" if on_player else "", amount]
	var colour := Color("#e8e8e8")
	if on_player:
		colour = Color(C_ENEMY_HP)
	if kind == "MISS":
		colour = Color("#bdbdbd")
	elif kind == "BLOCK":
		colour = Color("#9a9a9a")
	elif kind == "POISON":
		colour = Color("#4caf50")
	var label := _label(text, 22, colour, HORIZONTAL_ALIGNMENT_CENTER)
	label.size = Vector2(140, 28)
	_float_layer.add_child(label)
	# A small horizontal drift per float so two numbers landing on the same tick do not
	# sit exactly on top of each other.
	_floats.append({"node": label, "life": 1.0, "dy": 0.0,
		"drift": (float(_floats.size() % 5) - 2.0) * 16.0})


func _clear_floats() -> void:
	if _float_layer == null:
		return
	for f in _floats:
		var node: Node = f["node"]
		if is_instance_valid(node):
			node.queue_free()
	_floats = []


## Float and fade. 1.15 s end to end: long enough to read a number, short enough that a
## 2 s swing does not stack two of them.
##
## Everything here is scaled by `delta`, not by frames: the animations used to decay a
## fixed amount per frame, so the same "0.06" was a 200 ms animation at 60 fps and a
## 100 ms one at 120 fps — and at the port's own frame rate an entire animation was over
## in six frames, which is why nothing on screen appeared to move.
func _animate(delta: float) -> void:
	if _float_layer == null:
		return
	var mid := _float_layer.size * 0.5
	var alive: Array = []
	for f in _floats:
		var node: Control = f["node"]
		if not is_instance_valid(node):
			continue
		f["life"] = float(f["life"]) - delta / 1.15
		f["dy"] = float(f["dy"]) - delta * 96.0
		node.position = Vector2(round(mid.x - node.size.x * 0.5 + float(f["drift"])),
			round(mid.y - 40.0 + float(f["dy"])))
		node.modulate = Color(1, 1, 1, clampf(float(f["life"]), 0.0, 1.0))
		if float(f["life"]) > 0.0:
			alive.append(f)
		else:
			node.queue_free()
	_floats = alive

	# Lunges decay over the PWA's 200 ms CSS animation.
	_hero_lunge = maxf(0.0, _hero_lunge - delta * 5.0)
	_monster_lunge = maxf(0.0, _monster_lunge - delta * 5.0)
	_hero_flinch = maxf(0.0, _hero_flinch - delta * 5.0)
	if is_instance_valid(_hero_sprite):
		var lift := 14.0 * _hero_lunge - 10.0 * _hero_flinch
		_place_hero(lift)
	if is_instance_valid(_portrait):
		# The monster's own lunge (20px) plus the depth tilt the PWA applies as the hero
		# walks in (`--monster-dy`, `closed * 8` px) — a boss keeps its geometry and
		# does not tilt, exactly as the PWA's `if (monsterFig && !mb.isBoss)`.
		# Smoothed with the hero: the lean is part of the same walk-in and stepped with it.
		var tilt := 0.0
		if battle != null and not battle.is_boss:
			tilt = MONSTER_TILT_MAX * (1.0 - clampf(_gap_displayed(), 0.0, 1.0))
		var drop := 20.0 * _monster_lunge + tilt
		_portrait.position.y = round(_arena.size.y * 0.5 - PORTRAIT_BOX * 0.5 + drop)
	if is_instance_valid(_cast_icon):
		var pulse := 1.0 + 0.12 * sin(Time.get_ticks_msec() / 90.0)
		_cast_icon.scale = Vector2(pulse, pulse)


## The hero walks in from the arena's centre to the monster's side as `_gap` closes, and
## grows as he arrives — the PWA's `syncArenaDepth()`. The walk-in is not decoration: it
## is the only visual that tells the player why the first hit is late.
##
## The attack lunge and the flinch ride on top of the walk-in position.
##
## `_place_hero` takes the distance as an ARGUMENT so that a caller can hand it the smoothed
## one. It used to read `_gap_value()` itself, which meant the interpolation could never reach
## it — and `test_duel_distance` drives this function directly with an explicit `battle.gap`,
## which is the RULES' number and must keep working.
func _place_hero(lift: float, gap: float = -1.0) -> void:
	var arena_h := maxf(_arena.size.y, 1.0)
	var distance := _gap_displayed() if gap < 0.0 else gap
	var closed := 1.0 - clampf(distance, 0.0, 1.0)
	var scale := HERO_SCALE_FAR + (HERO_SCALE_NEAR - HERO_SCALE_FAR) * closed
	var size := clampf(arena_h * HERO_H_RATIO * scale, HERO_H_MIN, HERO_H_MAX)
	var fx := HERO_X_START - (HERO_X_START - HERO_X_NEAR) * closed
	var fy := HERO_Y_FAR - (HERO_Y_FAR - HERO_Y_NEAR) * closed
	_hero_sprite.size = Vector2(size, size)
	_hero_sprite.position = Vector2(
		round(_arena.size.x * fx - size * 0.5),
		round(arena_h * fy - size * 0.5 + lift))


## The battle's distance, as the RULES have it. With no battle yet the PWA's own default is
## the rule: `(mb._gap === undefined ? 1 : mb._gap)` — maximum separation. Falling back to
## contact (which this did) puts the hero at the monster's side before the fight has started,
## the exact "pasted onto the monster" pose the walk-in exists to avoid.
func _gap_value() -> float:
	return battle.gap if battle != null else 1.0


## The distance as the EYE has it: the rule's `gap` projected forward by the real time this
## frame has not yet spent on a tick, exactly like the swing rings.
##
## `gap` only moves inside a tick, so placing the hero straight off it made the walk-in a
## series of 100 ms teleports (measured: 10 moves in 60 frames) while the engine drew 60 —
## the same class of bug as the ring, on the figure instead of the gauge. Clamped at 0 so a
## frame cannot walk him past contact, and never written back: the RULES never see this
## number, so a dropped frame still cannot hand either side a free hit.
func _gap_displayed() -> float:
	if battle == null:
		return 1.0
	var ahead := clampf(_tick_accumulator, 0.0, float(TICK_MS)) / 1000.0
	return maxf(0.0, battle.gap - battle.gap_speed() * ahead)


func _append_log(text: String) -> void:
	_log_lines.append(text)
	while _log_lines.size() > LOG_LINES:
		_log_lines.pop_front()
	_log_box_clear()
	for line in _log_lines:
		_log_box.add_child(_label(str(line), 11, Color("#666666")))


func _log_box_clear() -> void:
	for child in _log_box.get_children():
		_log_box.remove_child(child)
		child.queue_free()


# ============================================================================= render

func render() -> void:
	if battle == null:
		return
	# The ROSTER is checked first. A member that just stepped up owns the portrait, the
	# name and the walk-in, so it has to be noticed before the display is written — the
	# old order set `_pack_displayed` here and then called `_refresh_pack()`, so the
	# hand-over branch compared a value against itself and `_on_pack_member_began()` was
	# unreachable code. Pack member two appeared with the DEAD member's name and face.
	_refresh_pack()
	sync_enemy_display()
	var act: Dictionary = _data.act_by_id(battle.act_id)
	var diffs: Array = _data.difficulties()
	var diff_name := str((diffs[battle.difficulty] as Dictionary).get("name", "")) \
		if battle.difficulty < diffs.size() else ""
	_location_label.text = "%s - ACT %d %s - %d/%d" % [
		diff_name.to_upper(), battle.act_id + 1, str(act.get("name", "")).to_upper(),
		battle.area_fight + 1, Battle.FIGHTS_PER_ZONE]

	_enemy_hp_label.text = "%d/%d" % [maxi(0, int(battle.enemy_hp)), int(battle.enemy_max_hp)]
	# The enemy's mana ring appears only where the enemy actually casts: the PWA hid
	# `.enemy-mana-ring` for melee monsters. The ring's VALUE is in `_smooth_update()`.
	_arc_enemy_mana.visible = not battle.enemy_spells.is_empty()
	_arc_offhand.visible = battle.offhand_swing_ms > 0

	_hero_hp_bar_label.text = "%d/%d" % [maxi(0, int(battle.hero_hp)), int(battle.hero_max_hp)]

	# The hero's resource bar. EVERY class uses mana in this game — the barbarian too
	# (CLASSES.json: resource 'mana', maxResource 100, baseMana 10, manaPerLevel 1) —
	# so the bar is never hidden. An earlier note claimed the barbarian ran on rage and
	# skipped his bar; that was wrong, and it hid the pool his own spells are paid from.
	var hero: Dictionary = _state.hero()
	var hero_class := str(_state.data.get("heroClass", ""))
	var max_mana := int(hero.get("maxMana", 0))
	if max_mana <= 0:
		max_mana = _gen.hero_max_mana(hero, _state.equip(), hero_class, _find_item)
	_set_bar(_mana_track, _mana_fill, float(hero.get("mana", 0)), float(maxi(max_mana, 1)))
	# The PWA's mana bar is labelled with a water droplet emoji; emoji are banned in the
	# port, so the word carries the meaning instead.
	_mana_label.text = "Mana %d / %d" % [int(hero.get("mana", 0)), max_mana]

	_xp_label.text = "LvL %d" % int(hero.get("level", 1))
	var need := int(hero["level"]) * 40 if int(hero["level"]) <= 2 else int(hero["level"]) * 80
	var xp_track: Control = _xp_fill.get_parent()
	var xp_width: float = xp_track.size.x
	_xp_fill.size = Vector2(xp_width * clampf(float(hero.get("xp", 0)) / maxf(float(need), 1.0), 0.0, 1.0), 8)

	_refresh_pack()
	_refresh_cast_icon()
	_refresh_spells()
	_smooth_update()


## The GAUGES and the BARS, drawn every FRAME.
##
## These used to live in `render()` and were therefore only ten times a second: the gold
## swing ring advanced in eleven visible jumps per swing (a 1156 ms weapon) and the HP bar
## stepped with it. `probe_watch.gd` counted the arc changing in 21 of 120 frames — that is
## what "it looks like 5 FPS" was, and no rule was wrong.
##
## Interpolating is safe HERE and nowhere else: `battle.player_swing_elapsed` is the fight's
## own clock and `_tick_accumulator` is real time that has NOT yet been spent on a tick.
## Adding it makes the ring sweep continuously and still stop exactly at the tick where the
## swing lands, because the accumulator never exceeds one step without the next frame
## consuming it. No partial tick is ever fed back into the battle.
func _smooth_update() -> void:
	if battle == null:
		return
	var ahead := clampf(_tick_accumulator, 0.0, float(TICK_MS))

	# The player's two gold arcs: a full ring is a swing just landed and the arc fills as
	# the next one approaches. The off-hand shares the SAME elapsed clock, which is what the
	# PWA did (`_playerSwingPct` drove both rings); only the interval differs.
	var player_ms := maxf(float(battle.player_swing_ms), 1.0)
	_arc_player.set_value_ratio(clampf((battle.player_swing_elapsed + ahead) / player_ms, 0.0, 1.0))
	if battle.offhand_swing_ms > 0:
		_arc_offhand.set_value_ratio(clampf((battle.player_swing_elapsed + ahead)
			/ float(battle.offhand_swing_ms), 0.0, 1.0))
	_arc_enemy_timer.set_value_ratio(clampf((battle.enemy_swing_elapsed + ahead)
		/ maxf(float(battle.enemy_swing_ms), 1.0), 0.0, 1.0))

	var enemy_ratio := clampf(battle.enemy_hp / maxf(battle.enemy_max_hp, 1.0), 0.0, 1.0)
	_arc_enemy_hp.set_value_ratio(enemy_ratio)
	if not battle.enemy_spells.is_empty():
		_arc_enemy_mana.set_value_ratio(clampf(
			battle.enemy_resource_cur / maxf(battle.enemy_max_resource, 1.0), 0.0, 1.0))

	# The PWA's damage ghost: `.enemy-hp-fill-ring` transitions in 0.2 s and
	# `.enemy-hp-ghost-ring` in 0.6 s, so the ghost TRAILS the fill and the hit reads as a
	# bite being taken. The port snapped the ghost to the fill in the same line, which made
	# the slower transition invisible and left a second identical red ring on screen.
	var ghost: float = _arc_enemy_hp_ghost.value
	if ghost < 0.0 or ghost <= enemy_ratio:
		# `-1` is the "new fight" sentinel the renderer sets in `start()`.
		ghost = enemy_ratio
	else:
		ghost = maxf(enemy_ratio, ghost - _frame_delta / GHOST_TRAIL_SECONDS)
	# Through `set_value_ratio`, not `.value`: the setter is what queues the redraw, and
	# writing the field directly drew nothing at all.
	_arc_enemy_hp_ghost.set_value_ratio(ghost)

	_set_bar(_hero_hp_track, _hero_hp_fill, battle.hero_hp, battle.hero_max_hp)
	var hero: Dictionary = _state.hero()
	var hero_class := str(_state.data.get("heroClass", ""))
	var max_mana := int(hero.get("maxMana", 0))
	if max_mana <= 0:
		max_mana = _gen.hero_max_mana(hero, _state.equip(), hero_class, _find_item)
	_set_bar(_mana_track, _mana_fill, float(hero.get("mana", 0)), float(maxi(max_mana, 1)))


## A member that just stepped up is a NEW enemy: the portrait, the name and the walk-in all
## have to move to it, and the walk-in restarts — the port used to keep the arena in
## contact, so pack member two was hit the instant it appeared.
func _on_pack_member_began() -> void:
	sync_enemy_display()
	battle.reset_gap()
	_monster_lunge = 1.0


## The portrait and the name of the enemy currently being fought. Called from render() and
## again whenever a pack hands the fight over.
func sync_enemy_display() -> void:
	if battle == null:
		return
	_portrait.texture = _load(battle.enemy_face)
	var elite_tag := ""
	if battle.is_elite and not battle.elite_affix.is_empty():
		elite_tag = "%s " % str(battle.elite_affix.get("name", ""))
	_enemy_name.text = elite_tag + battle.enemy_name


## `.pack-roster` — one 46px tile per member, the active one outlined red, dead ones
## greyed with a cross. The LEADER is the last member, per battle.gd's pack order.
func _refresh_pack() -> void:
	if not is_instance_valid(_pack_row):
		return
	var wanted := battle.pack_size() if battle.is_pack else 0
	if _pack_row.get_child_count() != wanted:
		for child in _pack_row.get_children():
			_pack_row.remove_child(child)
			child.queue_free()
		for i in wanted:
			var tile := TextureRect.new()
			tile.custom_minimum_size = Vector2(46, 46)
			tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			_pack_row.add_child(tile)
	if wanted == 0:
		return
	if battle.pack_active != _pack_displayed:
		_pack_displayed = battle.pack_active
		if battle.pack_active > 0:
			_on_pack_member_began()
	for i in wanted:
		var tile := _pack_row.get_child(i) as TextureRect
		var member: Dictionary = battle.pack_members[i] if i < battle.pack_members.size() else {}
		tile.texture = _load(str(member.get("face", "")))
		var dead := i < battle.pack_active
		var active := i == battle.pack_active
		if dead:
			tile.modulate = Color(0.55, 0.55, 0.55, 0.5)
		elif active:
			tile.modulate = Color(1, 1, 1, 1)
		else:
			tile.modulate = Color(1, 1, 1, 0.65)


## `.cast-spell-icon` — the enemy's wind-up icon, shown while it is casting.
func _refresh_cast_icon() -> void:
	if not is_instance_valid(_cast_icon):
		return
	var casting := str(battle.cast_spell_id) != "" and float(battle.cast_time) > 0.0
	_cast_icon.visible = casting
	if casting:
		var icon := _load("assets/spells/%s.png" % str(battle.cast_spell_id))
		if icon == null:
			icon = _load("assets/spells/%s.jpg" % str(battle.cast_spell_id))
		_cast_icon.texture = icon


## Rebuild the class spell bar from `battle.spell_bar()`. A spell with no talent point in
## it is not returned at all — the PWA filtered its bar the same way, and an offered spell
## the player never bought reads as content that simply does not work.
##
## A blocked spell is drawn dim with the REASON it is blocked, rather than being hidden:
## "Cooldown 12 s" and "Malo many" are information, and a button that simply vanishes
## mid-fight is indistinguishable from a bug.
##
## Rebuilt ONLY when the bar's contents change. render() runs ten times a second, and
## freeing and recreating the buttons each tick means a tap is delivered to a node that
## has already been queue_free'd — the spell button would simply never fire.
func _refresh_spells() -> void:
	if _spell_row == null:
		return
	if battle == null:
		if _spell_row.get_child_count() > 0:
			_clear_row(_spell_row)
		return

	var entries: Array = battle.spell_bar(_state, _find_item)
	var signature := ""
	for entry in entries:
		signature += "%s|%s|%s|%s;" % [str(entry["id"]), bool(entry["can"]),
			str(entry["blocked"]), bool(entry["queued"])]
	if signature == _spell_signature:
		return
	_spell_signature = signature
	_clear_row(_spell_row)

	for entry in entries:
		var spell_id := str(entry["id"])
		var can := bool(entry["can"])
		var queued := bool(entry["queued"])
		# `.arena-class-spell-btn` — 48x42, radius 8, black, orange border when usable,
		# gold when queued. The icon is the spell's own image; the port forbids emoji.
		var button := Button.new()
		button.custom_minimum_size = Vector2(48, 42)
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = str(entry["name"])
		var border := C_BORDER
		if queued:
			border = C_GOLD
		elif can:
			border = C_ENEMY_TIMER
		var style := _flat_style("#000000", border, 8)
		for state_name in ["normal", "hover", "focus", "disabled"]:
			button.add_theme_stylebox_override(state_name, style)
		button.add_theme_stylebox_override("pressed", style)

		var icon := _load("assets/spells/%s.png" % spell_id)
		var icon_rect := TextureRect.new()
		icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture = icon
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_rect.modulate = Color(1, 1, 1, 1 if can else 0.3)
		button.add_child(icon_rect)

		# `.spell-cost` — the mana price, bottom right.
		var cost := int(entry["cost"])
		if cost > 0:
			var cost_label := _label(str(cost), 8, Color(C_ENEMY_TIMER), HORIZONTAL_ALIGNMENT_RIGHT)
			cost_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			cost_label.offset_left = -22
			cost_label.offset_top = -14
			cost_label.offset_right = -3
			cost_label.offset_bottom = -1
			button.add_child(cost_label)

		# `.spell-cd-num` — the seconds left, centred over the icon.
		var cd := int(entry["cooldown"])
		if cd > 0:
			var cd_label := _label(str(int(ceil(cd / 1000.0))), 16, Color(C_ENEMY_HP),
				HORIZONTAL_ALIGNMENT_CENTER)
			cd_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			button.add_child(cd_label)

		button.disabled = not can
		if can:
			button.pressed.connect(func(): cast_spell(spell_id))
		_spell_row.add_child(button)


func _clear_row(row: Node) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()


## Cast one class spell. The rule lives in `PlayerSpells` — this only forwards the call
## and reports what came back. A refused cast writes its reason into the log verbatim.
func cast_spell(spell_id: String) -> Dictionary:
	# One cast per rendered frame: the bar is rebuilt when a spell's state changes, so
	# a second cast in the same frame would free the button the player's finger is on.
	if _cast_this_frame:
		return {"ok": false, "message": "Pockej na dalsi snimek", "damage": 0, "spell": spell_id}
	_cast_this_frame = true
	if battle == null or battle.ended:
		return {"ok": false, "message": "Zadny souboj", "damage": 0, "spell": spell_id}
	var result: Dictionary = PlayerSpells.cast(battle, spell_id, _state, _find_item, _data, battle.rng)
	if bool(result["ok"]):
		_append_log(str(result["message"]))
	else:
		_append_log("Nelze: %s" % str(result["message"]))
	_drain_log()
	_state.save()
	render()
	return result


## One button per potion type in the belt, with the count. Tapping drinks one.
func _refresh_potions() -> void:
	for child in _potion_row.get_children():
		_potion_row.remove_child(child)
		child.queue_free()

	var counts := {}
	for pid in _state.equip().get("beltPotionSlots", []):
		if pid == null:
			continue
		var item: Dictionary = _find_item.call(pid)
		if str(item.get("subtype", "")) not in ["heal", "mana"]:
			continue
		counts[str(pid)] = int(counts.get(str(pid), 0)) + 1

	# Fixed order — heals first, then mana, each from the weakest tier up. The PWA kept
	# the same order so a belt full of mixed potions reads the same way every fight.
	var order := ["healingPotion", "healingPotion2", "healingPotion3", "healingPotion4", "healingPotion5",
		"manaPotion", "manaPotion2", "manaPotion3", "manaPotion4", "manaPotion5"]
	for potion_id in order:
		if not counts.has(potion_id):
			continue
		var item: Dictionary = _find_item.call(potion_id)
		var button := _make_button("%s x%d" % [str(item.get("name", potion_id)), int(counts[potion_id])])
		button.custom_minimum_size = Vector2(110, 32)
		button.pressed.connect(func(): use_potion(potion_id))
		_potion_row.add_child(button)


## Drink one potion from the belt: remove it, apply its effect to the LIVE fight state,
## and re-render. A potion with no fight running is refused rather than consumed — the
## PWA returned early in that case, and silently burning a potion is worse than a no-op.
func use_potion(potion_id: String) -> Dictionary:
	var item: Dictionary = _find_item.call(potion_id)
	if item.is_empty() or str(item.get("type", "")) != "consumable":
		return {"ok": false, "message": "Neni potion"}
	if battle == null or battle.ended:
		return {"ok": false, "message": "Zadny souboj"}
	if _state.consume_potion(potion_id) < 0:
		return {"ok": false, "message": "V opasku neni"}
	var value := int(item.get("effectValue", 0))
	if str(item.get("subtype", "")) == "heal":
		battle.hero_hp = minf(battle.hero_max_hp, battle.hero_hp + float(value))
		_append_log("Potion +%d HP" % value)
	else:
		var hero: Dictionary = _state.hero()
		var max_mana := int(hero.get("maxMana", 0))
		hero["mana"] = mini(max_mana, int(hero.get("mana", 0)) + value)
		_append_log("Potion +%d many" % value)
	_state.save()
	_refresh_potions()
	render()
	return {"ok": true, "message": "Vypito"}


## The fill is resized rather than scaled, so the bar reads at any width.
func _set_bar(track: Control, fill: ColorRect, value: float, maximum: float) -> void:
	var width := track.size.x
	if width <= 0.0:
		width = track.custom_minimum_size.x
	if width <= 0.0:
		width = 360.0
	var ratio := clampf(value / maxf(maximum, 1.0), 0.0, 1.0)
	fill.size = Vector2(width * ratio, 22)


func _finish_fight() -> void:
	_button_lock = 3
	var stop_complete := int(_state.data["areaFightProgress"][battle.act_id]) >= Battle.FIGHTS_PER_ZONE
	if battle.won:
		_append_log("Vyhrano")
		_result_label.text = "Vitezstvi"
		award_loot()
		# The PWA gave the finished stop a MAP button (and a way to town) instead of
		# "next fight", because the next stop is chosen on the map. The port always
		# offered another fight in the same stop, so there was no way to leave the
		# cleared stop at all.
		_next_button.visible = not stop_complete
	else:
		_append_log("Porazeno")
		_result_label.text = "Porazka"
		_state.save()
	# Only a LIVE victory gets the next fight. A loss, or a cleared stop, has exactly one
	# way on: the map (the town heals and resets the shop, and every defeat ends there).
	_next_button.visible = battle.won and not stop_complete
	# The loot that did NOT fit in the bag is offered as a button rather than dropped
	# silently: a player who wins a rare with a full bag must be able to see it exists.
	_loot_button.visible = _pending_loot.size() > 0
	# A defeat's readout says where the player is being taken, because the tap that
	# follows it leaves the arena rather than starting another fight.
	if battle.won and stop_complete:
		_leave_button.text = "Mapa"
	else:
		_leave_button.text = "Zpet do mesta"
	fight_over.emit(battle.won)
	# The next fight's clock starts from the tap, not from the last frame of this fight:
	# a remainder carried over would hand the new fight's first swing a free tick.
	_tick_accumulator = 0.0


## The surrender flag. The PWA asked for confirmation first, and the forfeit costs a
## death plus every fight of the current stop — a single tap on a 40px flag in the arena's
## corner must not do that silently.
func _on_surrender() -> void:
	if battle == null or battle.ended:
		return
	_open_confirm()


func _open_confirm() -> void:
	_confirm_layer.visible = true


func _close_confirm() -> void:
	_confirm_layer.visible = false


## Forfeit: end the fight as a defeat and leave for town. A forfeit pays no consolation
## (the PWA's own comment: "forfeit je prohra bez odmeny") but still counts a death and
## resets the current stop's fights.
func _on_surrender_confirmed() -> void:
	_close_confirm()
	if battle == null or battle.ended:
		return
	var loc_progress: Array = _state.data["locationProgress"]
	# One home for the death's bookkeeping: `Battle._finish(false, ...)` already counted
	# the death, paid the consolation and reset this stop's fights. Doing any of it again
	# here is how the port double-counted every death.
	_state.data["deaths"] = int(_state.data.get("deaths", 0)) + 1
	_state.data["areaFightProgress"][battle.act_id] = 0
	var hero: Dictionary = _state.hero()
	hero["maxHp"] = _gen.hero_max_hp(hero, _state.equip(), _find_item)
	hero["hp"] = hero["maxHp"]
	battle.ended = true
	battle.won = false
	_state.save()
	leave_requested.emit()


func _on_next_pressed() -> void:
	if _button_lock > 0:
		return
	another_fight_requested.emit()


func _on_leave_pressed() -> void:
	if _button_lock > 0:
		return
	leave_requested.emit()


## Take the loot that did not fit. It stays in `_pending_loot` until a slot frees up, so
## nothing is destroyed by a full bag.
func _on_loot_pressed() -> void:
	if _button_lock > 0:
		return
	var taken := 0
	var still: Array = []
	for item in _pending_loot:
		if _state.bag_full():
			still.append(item)
			continue
		_state.register_loot_item(item)
		_state.add_item(str(item.get("id", "")), item)
		taken += 1
	_pending_loot = still
	_loot_button.visible = _pending_loot.size() > 0
	_loot_button.disabled = _pending_loot.size() == 0
	if taken > 0:
		_append_log("Sebrano: %d" % taken)
	elif _pending_loot.size() > 0:
		_append_log("Batoh je plny")
	_state.save()


## Loot and inventory. The battle already settled XP, kill gold and the fight
## counters; this adds the item drops, which need the loot system, and then levels.
func award_loot() -> void:
	var mf := _gen.magic_find(_state.equip(), _find_item)
	var gf := _gen.gold_find(_state.equip(), _find_item)
	var result: Dictionary = battle.roll_loot(_loot, _state, _find_item, mf, gf)
	var bagged := 0
	_pending_loot = []
	for item in result["items"]:
		_state.register_loot_item(item)
		var item_id := str(item.get("id", ""))
		# A full bag no longer swallows the drop: it is kept and offered by the loot
		# button. Stackable items always fit, so they go straight in.
		if _state.bag_full() and not ItemGen.is_stackable(item):
			_pending_loot.append(item)
			continue
		_state.add_item(item_id, item)
		bagged += 1
	_state.hero()["gold"] = int(_state.hero().get("gold", 0)) + int(result["gold"])
	_state.data["townPortalCount"] = int(_state.data.get("townPortalCount", 0)) + int(result["portals"])
	if bagged > 0:
		_append_log("Predmety: %d" % bagged)
	if int(result["gold"]) > 0:
		_append_log("Zlato: %d" % int(result["gold"]))
	apply_levels()
	_state.save()


## applyLevelUp — 40 XP for level 2, then 80 per level, cap 60. Every level refills
## HP, grants 5 attribute points and a talent point.
func apply_levels() -> void:
	var hero: Dictionary = _state.hero()
	var levelled := false
	var safety := 0
	while safety < 100:
		safety += 1
		if int(hero["level"]) >= 60:
			hero["xp"] = 0
			break
		var need := int(hero["level"]) * 40 if int(hero["level"]) <= 2 else int(hero["level"]) * 80
		if int(hero.get("xp", 0)) < need:
			break
		hero["xp"] = int(hero["xp"]) - need
		hero["level"] = int(hero["level"]) + 1
		hero["maxHp"] = _gen.hero_max_hp(hero, _state.equip(), _find_item)
		hero["hp"] = hero["maxHp"]
		hero["attrPoints"] = int(hero.get("attrPoints", 0)) + 5
		_state.data["talentPoints"] = int(_state.data.get("talentPoints", 0)) + 1
		levelled = true
	if levelled:
		_append_log("Novy level: %d" % int(hero["level"]))


## Advance the stop when the zone is finished, then start the next fight.
func another_fight() -> bool:
	if battle == null:
		return false
	battle.advance_stop(_state)
	_state.save()
	return start(_state, _find_item)


func _load(path: String) -> Texture2D:
	if path == "":
		return null
	var full := path if path.begins_with("res://") else "res://" + path
	if not ResourceLoader.exists(full):
		return null
	return load(full)


# ============================================================================= portrait

## `#mbArena .monster-in-ring` — the monster image CROPPED TO A CIRCLE at 180x180, with
## the PWA's `.monster-ring-overlay` gradient darkening its top third. A plain TextureRect
## would show the square art the PWA deliberately hid; Jan flagged square black
## backgrounds on arena images specifically.
class CircularPortrait:
	extends Control

	var texture: Texture2D:
		set(value):
			texture = value
			queue_redraw()

	func _draw() -> void:
		if texture == null:
			return
		var r := minf(size.x, size.y) * 0.5
		var centre := size * 0.5
		draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, 1))

		# Circular crop by scanline: for every row, the circle's half-width is known, so
		# the two areas OUTSIDE it are painted back in the arena's colour. A wedge approach
		# (triangles to the corners) looked right on paper and wrong on screen — the corner
		# vertex jumps between segments and the triangles cut across the artwork.
		var bg := Color("#121212")
		var row_h := 1.0
		var rows := int(ceil(size.y / row_h))
		for i in rows:
			var y := float(i) * row_h + row_h * 0.5
			var dy := y - centre.y
			var inside := r * r - dy * dy
			if inside <= 0.0:
				# The row is entirely outside the circle.
				draw_rect(Rect2(0.0, float(i) * row_h, size.x, row_h), bg)
				continue
			var half := sqrt(inside)
			var left_edge := centre.x - half
			var right_edge := centre.x + half
			if left_edge > 0.0:
				draw_rect(Rect2(0.0, float(i) * row_h, left_edge, row_h), bg)
			if right_edge < size.x:
				draw_rect(Rect2(right_edge, float(i) * row_h, size.x - right_edge, row_h), bg)

		# `.monster-ring-overlay` — rgba(0,0,0,0.6) over the top 30%, then fading out.
		var overlay_rows := 40
		for i in overlay_rows:
			var t := float(i) / float(overlay_rows)
			var y := t * r * 0.9
			var dy2 := y
			var inside2 := r * r - dy2 * dy2
			if inside2 <= 0.0:
				continue
			var half2 := sqrt(inside2)
			var alpha := 0.6 * clampf(1.0 - t, 0.0, 1.0)
			if alpha <= 0.0:
				continue
			draw_rect(Rect2(centre.x - half2, centre.y - r + y, half2 * 2.0,
				(r * 0.9) / float(overlay_rows) + 1.0), Color(0, 0, 0, alpha))
