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
const ItemStats := preload("res://scripts/items/item_stats.gd")
const Battle := preload("res://scripts/combat/battle.gd")
const GaugeArc := preload("res://scripts/ui/ui_gauge.gd")
const UIFonts := preload("res://scripts/ui/ui_fonts.gd")

signal fight_over(won: bool)
signal leave_requested()
signal another_fight_requested()
## The result page's own destinations, which are NOT the in-fight ones: the PWA's victory
## page offers Map (after a cleared stop), Walk to Town, Town Portal (only while a scroll is
## carried) and Hero (opens the character modal) — a different set from "leave the arena".
signal map_requested()
signal portal_requested()
signal hero_requested()

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
## The icon on the result page's GOLD row — a real image, because the game has no emoji, and
## drawn by `tools/import/make_coin.py` so it is reproducible.
const COIN_ICON := "assets/items/coin_gold.png"
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
## `.result-tile { flex:1 1 60px; min-width:60px; max-width:90px; aspect-ratio:1 }` inside
## the PWA's 390px page with 12px padding and two 6px gaps: (390 - 24 - 18) / 4 ≈ 87, so a
## full row of four sits at 87 and the CSS's own 90px cap is what wins.
const RESULT_TILE := 84.0

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

# The result page (`#resultScreen`). It is a full-page layer of this screen rather than a
# screen of its own: the PWA's `showScreen('result')` swaps the page, and the fight's own
# nodes have to stay exactly as they are behind it so the next fight can reuse them.
var _result_layer: Control
var _result_bg_button: Button
## The artwork's own box: `.result-icon-img.stop-result` plus the two overlays drawn ON it.
## It is a plain Control child of the expanding `.result-top`, so its size is assigned in
## `_layout_result_page()` — a `PRESET_TOP_WIDE` TextureRect has zero height and the art
## would be invisible.
var _art_box: Control
var _result_art: TextureRect
## `.result-loot-scroll`'s margin box — kept as a field because `_layout_result_page()` puts
## it under the artwork rather than leaving it to a container.
var loot_pad: MarginContainer
## `.result-bottom`'s padding box, likewise positioned rather than laid out.
var _tiles_holder: MarginContainer
var _result_defeat_art: TextureRect
var _result_overlay: VBoxContainer
var _result_title: Label
var _result_sub: Label
var _result_stats: VBoxContainer
var _result_hp_line: Label
var _result_mana_line: Label
var _result_actions: HBoxContainer
## The loot the fight just handed over, as `.loot-scroll-item` rows.
var _loot_list: VBoxContainer
## The loot that did NOT fit in the bag: a button under the list, not a row in it.
var _loot_button: Button
## Where the result page's page-tap goes: town after a defeat, the map after a win. The PWA
## rewired `#resultScreen.onclick` per outcome.
var _result_tap_goes_to_map := false
## True once `_finish_fight` has settled this fight, so the page is built once and taps on
## it are accepted only after `_button_lock_ms` has run out.
var _result_built := false

var _log_lines: Array = []
## Loot that did not fit in the bag. Held here so a full bag never destroys a drop.
var _pending_loot: Array = []
## Everything this fight rolled, bagged or not, for the result page's loot list. Kept apart
## from the bag because the page has to show a drop the bag could not take.
var _result_loot_rows: Array = []
## The gold this fight PAID, for the result page's loot list. Gold is a row of its own — Jan
## asked for it, because a fight that paid only gold otherwise showed "Zadne predmety" over a
## purse that had just been filled. Zero on a defeat (`battle.gd`'s loss path pays a
## consolation that is not a drop), which is the same rule as the item rows.
var _result_gold_won := 0
## Milliseconds left before the end-of-fight buttons accept a tap. Counted in REAL time —
## see `BUTTON_LOCK_MS` — and decremented in `_process`, which is the only clock that runs
## once a fight is over.
var _button_lock_ms := 0
## Re-entrancy guard for `_on_actions_resized`: `_place_tiles` writes the tiles' sizes, which
## resizes the row, which fires the signal again.
var _resizing_tiles := false
## How many MILLISECONDS the end-of-fight buttons are up before they accept a tap. A tap
## that lands while the last damage frame is still drawing ends up on whichever button just
## appeared — the player asked to attack, not to walk away. 300 ms, as the PWA's own delay.
##
## It is counted in REAL time, not in fight ticks. The port first decremented this inside
## `step()` once per tick, which tied a tap guard to the FIGHT's clock: a tick is 100 ms of
## GAME time, and the screen's `_process` pumps ticks only while a fight is live — once the
## fight ends, `step()` returns early at `battle.ended` and `_process` stops pumping ticks
## entirely. The countdown therefore ran at whatever rate frames happened to deliver ticks
## and, on a frame that delivered more than one tick (a hitch, or the browser tab being
## backgrounded), two or three of them were spent at once. Read the report: "the Dalsi
## souboj button sometimes does not work and I have to tap it repeatedly" — the taps landed
## while the guard was still up. Real milliseconds cannot be spent faster than the player's
## clock.
const BUTTON_LOCK_MS := 300

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

# --- easing (the PWA's CSS transitions) ----------------------------------------
#
# A RULE is instant. What the player SEES eases — `public/style.css` gives every one of
# these a `transition: … 0.2s ease-out`, and the port wrote the new number the moment the
# tick settled it. So the enemy's HP dropped by a whole hit in one frame (Jan: "the
# enemy's and the player's HP are not smooth"), the hero's bar jumped 100 ms after the
# blow, and the enemy's timer stepped ten times a second instead of sweeping.
#
# Nothing here is a rule: the battle's HP already IS the new number, the swing interval
# already IS the weapon's interval. These are the values the SCREEN draws.
#
# The enemy's TIMER is deliberately not in this list: its clock is RESTARTED by the rules on
# every swing, so an eased value re-targeted ten times a second could never reach the end of
# the sweep (measured peaks: 87 % / 91 % / 93 % on 1 s / 1.5 s / 2 s swings). It is drawn
# straight from `battle.enemy_swing_elapsed`, like the two gold rings.
const EASE_HP_SECONDS := 0.2
const EASE_MANA_SECONDS := 0.2
## `.enemy-hp-ghost-ring { transition: stroke-dashoffset 0.6s ease-out }` — the ghost is
## the slow one, so a hit bites.
const EASE_GHOST_SECONDS := 0.6
## How long a hit's red wash takes to fade off the figure that took it. There is no CSS
## transition behind this one — it is the readout for "the blow landed HERE", which the
## PWA got from the figure's shake alone and which is easy to miss at 60 fps.
const EASE_HIT_SECONDS := 0.9
const HIT_TINT := Color(1.0, 0.35, 0.3)
const HIT_TINT_STRENGTH := 0.55

## A hit's wash, 1.0 on the blow and decayed in `_animate`. The monster's shake rides on it.
var _hero_flash := 0.0
var _monster_flash := 0.0

## One home for every eased number: id -> {value, src, target, elapsed, duration}. A screen
## that eases one bar and snaps the next is the bug this exists to prevent.
var _ease: Dictionary = {}

## What the bars and their labels draw. The battle's numbers are the RULES' (instant); these
## are the eased readout, seeded once per fight in `start()`.
var _hero_hp_shown := 0.0
var _hero_hp_max_shown := 1.0
var _mana_shown := 0.0
var _mana_max_shown := 1.0
var _enemy_hp_shown := 0.0
var _enemy_hp_max_shown := 1.0

## Swing animations: the HERO lunges on his own attack and flinches when he is hit. The
## monster has none — its dip-and-return on being hit read as its picture twitching and Jan
## asked for it gone; the hit wash and the ±2px shake are what say the blow landed on it.
var _hero_lunge := 0.0
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

	# There is no in-arena end-of-fight badge: the PWA's result page REPLACES the screen
	# (`#resultScreen { position:fixed; background:#000; height:100vh }`), and the port's
	# "Vitezstvi" label floating over a live fight was its own invention. Everything the
	# player sees at the end lives in `_build_result_layer()`, which covers this screen.
	_build_result_layer()
	_build_confirm()


## The PWA's victory page is a SCREEN, not a badge over the arena: the stop's artwork fills
## the page with "Victory!" and the location over it, the hero's status sits along its
## bottom edge, the loot list below that and the action tiles last. `#resultScreen` is
## `position:fixed` with `background:#000` and `height:100vh`, so it covers everything.
##
## It is built here and hidden; `_finish_fight` shows it. Keeping it a layer of this screen
## rather than a screen of its own is what lets the fight's own nodes (the arena, the bar)
## stay exactly as they are behind it.
func _build_result_layer() -> void:
	_result_layer = Control.new()
	_result_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_layer.visible = false
	add_child(_result_layer)

	var bg := ColorRect.new()
	bg.color = Color("#000000")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_layer.add_child(bg)
	# `.result-screen { cursor:pointer }` and a `#resultScreen` onclick that walks the hero
	# to town — so the whole page is the button. Kept as a full-rect Button UNDER the
	# tiles so a tap anywhere but a tile leaves the fight behind.
	_result_bg_button = Button.new()
	# NOT `flat = true`: on a Button that means "draw NO stylebox at all", and
	# `test_portrait_visual` reads every stylebox in this file to enforce the border contract
	# (`flat` hides the border silently). A transparent StyleBoxEmpty on every state is the
	# same invisible result and it keeps the check able to see the button.
	_result_bg_button.focus_mode = Control.FOCUS_NONE
	_result_bg_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	var empty_style := StyleBoxEmpty.new()
	for state_name in ["normal", "hover", "focus", "pressed", "disabled"]:
		_result_bg_button.add_theme_stylebox_override(state_name, empty_style)
	_result_bg_button.pressed.connect(func(): _on_result_clicked())
	_result_layer.add_child(_result_bg_button)

	# Everything below is positioned in `_layout_result_page()`. NOT a container: a container
	# OVERWRITES the rects of its children, and the artwork's box has no minimum height of its
	# own (a `Control` holding only texture children reports 0), so a container collapsed it
	# and the loot list landed on top of the art. This is the same class of failure as the
	# `.value` writes that queued no redraw: the screen was correct and simply never drawn.
	#
	# `.result-top` is a flex COLUMN that CONTAINS the loot list and `.result-bottom` is
	# `flex:0 0 auto`. That is why the port's victory page had a black hole in the middle: the
	# loot list was a sibling of the expanding block, so a `flex:1` top pushed it to the
	# bottom of the page. Measured on the live PWA, the loot row sits at y=399 — six px under
	# the artwork's own bottom edge (393) — not above the tiles.

	# The artwork's own box: the image plus the two overlays drawn ON it.
	_art_box = Control.new()
	_art_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.add_child(_art_box)

	_result_art = TextureRect.new()
	_result_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_result_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_result_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_box.add_child(_result_art)
	# A defeat has no artwork of its own: the PWA swaps in `result_defeat.png`
	# (`.result-icon-img.large { max-width:90vw; max-height:50vh }`), centred.
	_result_defeat_art = TextureRect.new()
	_result_defeat_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_result_defeat_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_result_defeat_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_defeat_art.visible = false
	_art_box.add_child(_result_defeat_art)

	# The overlay ON the art for a win (`.stop-result-overlay { top:10px }`), and UNDER it for
	# a defeat (the PWA's own page-level `.result-title` / `.result-sub`). Both cases place it
	# in `_layout_result_page()`, so it lives here rather than in a wrapper per outcome.
	_result_overlay = VBoxContainer.new()
	_result_overlay.add_theme_constant_override("separation", 2)
	_result_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.add_child(_result_overlay)
	_result_title = _label("", 26, Color("#ffffff"), HORIZONTAL_ALIGNMENT_CENTER, true)
	_result_overlay.add_child(_result_title)
	_result_sub = _label("", 14, Color("#dddddd"), HORIZONTAL_ALIGNMENT_CENTER, true)
	_result_overlay.add_child(_result_sub)

	# `.stop-result-stats` — the hero's status pinned to the ART's bottom edge.
	_result_stats = VBoxContainer.new()
	_result_stats.add_theme_constant_override("separation", 4)
	_result_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.add_child(_result_stats)
	_result_hp_line = _label("", 15, Color(C_ENEMY_HP), HORIZONTAL_ALIGNMENT_CENTER, true)
	_result_stats.add_child(_result_hp_line)
	_result_mana_line = _label("", 15, Color(C_MANA_FILL), HORIZONTAL_ALIGNMENT_CENTER, true)
	_result_stats.add_child(_result_mana_line)

	# `.result-loot-scroll { margin:6px auto; padding:4px 10px; width:100% }` — INSIDE
	# `.result-top`, directly under the artwork.
	loot_pad = MarginContainer.new()
	loot_pad.add_theme_constant_override("margin_left", 10)
	loot_pad.add_theme_constant_override("margin_right", 10)
	loot_pad.add_theme_constant_override("margin_top", 6)
	loot_pad.add_theme_constant_override("margin_bottom", 4)
	loot_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.add_child(loot_pad)
	_loot_list = VBoxContainer.new()
	_loot_list.add_theme_constant_override("separation", 0)
	_loot_list.visible = false
	loot_pad.add_child(_loot_list)
	# The overflow drops are offered by a BUTTON, not swallowed: a player who wins a rare
	# with a full bag has to be able to see that it exists.
	_loot_button = _make_button("Sebrat loot")
	_loot_button.pressed.connect(func(): _on_loot_pressed())
	_loot_button.visible = false
	_result_layer.add_child(_loot_button)

	# `.result-bottom { position:absolute; bottom:0; padding:10px 12px; gap:6px }`.
	_tiles_holder = MarginContainer.new()
	_tiles_holder.add_theme_constant_override("margin_left", 12)
	_tiles_holder.add_theme_constant_override("margin_right", 12)
	_tiles_holder.add_theme_constant_override("margin_top", 0)
	_tiles_holder.add_theme_constant_override("margin_bottom", 10)
	_tiles_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.add_child(_tiles_holder)
	# The row is the tapped part of the page, so it re-places itself whenever its own rect
	# changes rather than waiting for the one deferred layout pass per fight. See
	# `_on_actions_resized()`.
	_tiles_holder.resized.connect(_on_actions_resized)
	_result_actions = HBoxContainer.new()
	_result_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_actions.add_theme_constant_override("separation", 6)
	# `.result-bottom:empty { display:none }` — a defeat has NO action tiles at all; the
	# only way on is the page tap, which the PWA wired to "return to town".
	_tiles_holder.add_child(_result_actions)


## `_result_actions`'s tile size. `.result-tile { flex:1 1 60px; min-width:60px;
## max-width:90px; aspect-ratio:1 }` inside a 390px page with 12px padding and a 6px gap:
## (390 - 24 - 3*6) / 4 = 87, so a full row of four sits at 87 and the 90px cap only binds on
## a wider canvas. Measured on the live PWA as 87 — the 84 this used to be constant was 3px
## short of every tile, which is exactly the kind of drift that makes a page look "close but
## wrong". A short row's tiles are wider (flex-grow), so it follows the count.
func _tile_size() -> float:
	var count := maxi(_result_actions.get_child_count(), 1)
	var page_w := 390.0
	if _result_layer != null and _result_layer.size.x > 0.0:
		page_w = _result_layer.size.x
	var usable := page_w - 24.0 - 6.0 * float(count - 1)
	return clampf(usable / float(count), 60.0, 90.0)


## One `.result-tile`: an 87px square (see `_tile_size`), the art filling it, the label over
## the art's bottom in a 60 % black plate.
func _make_action_tile(icon_path: String, label_text: String, on_press: Callable) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(RESULT_TILE, RESULT_TILE)
	tile.focus_mode = Control.FOCUS_NONE
	var style := _flat_style("#000000", "#333333", 10)
	style.set_border_width_all(2)
	for state_name in ["normal", "hover", "focus", "disabled"]:
		tile.add_theme_stylebox_override(state_name, style)
	tile.add_theme_stylebox_override("pressed", _flat_style("#1a1a1a", C_GOLD, 10))
	tile.pressed.connect(on_press)

	var art := _load(icon_path)
	if art != null:
		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		icon.texture = art
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(icon)

	var caption := _label(label_text, 13, Color("#ffffff"), HORIZONTAL_ALIGNMENT_CENTER, true)
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -24
	caption.offset_bottom = -4
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0, 0, 0, 0.6)
	plate.set_corner_radius_all(3)
	caption.add_theme_stylebox_override("normal", plate)
	tile.add_child(caption)
	# The label lives on a CHILD, so `Button.text` is empty. A test that asks what the result
	# page offers has to be able to read it off the tile itself, and reading the caption's
	# children would be reaching into the tile's layout — the metadata is the tile's contract.
	tile.set_meta("label", label_text)
	return tile


## The tile row is REBUILT per fight, because which tiles exist is the fight's outcome: a
## cleared stop offers the map instead of another fight, a portal tile appears only while a
## scroll is carried, and a defeat offers none. A row built once would have to hide and show
## its members one by one, which is how the port ended up with the wrong destinations.
func _rebuild_result_actions(won: bool, stop_complete: bool, has_portal: bool) -> void:
	for child in _result_actions.get_children():
		_result_actions.remove_child(child)
		child.queue_free()
	if not won:
		return
	var act_id := battle.act_id
	if stop_complete:
		_result_actions.add_child(_make_action_tile("assets/map.webp", "Mapa",
			func(): map_requested.emit()))
	else:
		_result_actions.add_child(_make_action_tile("assets/items/weapon_broad_sword.png",
			"Dalsi souboj", func(): _on_next_pressed()))
	_result_actions.add_child(_make_action_tile("assets/menu-icons/mesto.png", "Do mesta",
		func(): _on_leave_pressed()))
	if has_portal:
		_result_actions.add_child(_make_action_tile("assets/items/town_portal_scroll.png",
			"Portal", func(): _on_portal_pressed()))
	_result_actions.add_child(_make_action_tile(_hero_face_path(), "Hrdina",
		func(): _on_hero_pressed()))


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


func _label(text: String, size: int, colour: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT,
		bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UIFonts.get_font(size, bold))
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

## Seed one eased value: it starts exactly where the RULES are, not at zero and not at the
## old bar's remainder. `start()` calls this for every eased number, so the first frame of a
## fight cannot show the previous fight's HP.
func _snap_ease(id: String, value: float) -> void:
	_ease[id] = {"value": value, "src": value, "target": value, "elapsed": 0.0, "duration": 0.0}


## Point an eased value at a new target. Re-targeting keeps the CURRENT value as the new
## start (no snap), which is what a CSS transition does when a hit lands mid-transition.
func _ease_to(id: String, target: float, duration: float) -> void:
	if not _ease.has(id):
		_snap_ease(id, target)
		return
	var rec: Dictionary = _ease[id]
	if is_equal_approx(float(rec["target"]), target):
		return
	rec["src"] = float(rec["value"])
	rec["target"] = target
	rec["elapsed"] = 0.0
	rec["duration"] = maxf(duration, 0.0001)


func _ease_value(id: String) -> float:
	if not _ease.has(id):
		return 0.0
	return float((_ease[id] as Dictionary)["value"])


## Advance every eased value by one real frame. Ease-OUT, matching the CSS's `ease-out`:
## fast off the mark, settling on the target.
func _advance_ease(delta: float) -> void:
	for id in _ease:
		var rec: Dictionary = _ease[id]
		var duration := float(rec["duration"])
		if duration <= 0.0:
			rec["value"] = float(rec["target"])
			continue
		rec["elapsed"] = float(rec["elapsed"]) + delta
		var t := clampf(float(rec["elapsed"]) / duration, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - t, 2.0)
		rec["value"] = float(rec["src"]) + (float(rec["target"]) - float(rec["src"])) * eased
		if t >= 1.0:
			rec["value"] = float(rec["target"])


func start(state, find_item: Callable) -> bool:
	_log_lines = []
	_log_box_clear()
	_loot_button.visible = false
	_loot_button.disabled = false
	_button_lock_ms = 0
	# The result page belongs to the PREVIOUS fight: left visible it would sit over the new
	# one, and left built it would accept a tap meant for the arena.
	_result_built = false
	_result_loot_rows = []
	_result_gold_won = 0
	_result_layer.visible = false
	_result_tap_goes_to_map = false
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
	_hero_flinch = 0.0
	_hero_flash = 0.0
	_monster_flash = 0.0
	_clear_floats()

	var seed_value := int(Time.get_ticks_usec()) & 0x7fffffff
	battle = Battle.new(_data, seed_value)
	battle.set_monster_seen(_monster_seen)
	var ok := battle.setup(state, find_item)
	_monster_seen = battle.monster_seen()
	if not ok:
		return false
	battle.apply_swing_timers(state, find_item)

	# Every eased number starts where the RULES are. Without this the first frame of a fight
	# would draw the previous fight's bars (or zeros) and then "catch up" over 0.2 s, which
	# reads as damage the player never took.
	_snap_ease("enemy_hp", battle.enemy_hp)
	_snap_ease("hero_hp", battle.hero_hp)
	var start_hero: Dictionary = state.hero()
	var start_max_mana := int(start_hero.get("maxMana", 0))
	if start_max_mana <= 0:
		start_max_mana = _gen.hero_max_mana(start_hero, state.equip(),
			str(state.data.get("heroClass", "")), find_item)
	_snap_ease("mana", float(start_hero.get("mana", 0)))
	_snap_ease("hero_hp_max", battle.hero_max_hp)
	_snap_ease("enemy_hp_max", battle.enemy_max_hp)
	_snap_ease("mana_max", float(maxi(start_max_mana, 1)))
	# The ghost starts FULL: a fresh enemy has taken no damage, so there is no trail to
	# carry over from the previous fight.
	_snap_ease("enemy_hp_ghost", 1.0)

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
	# The tap guard runs on REAL time and on every frame, because once the fight is over
	# `step()` returns early and ticks stop entirely — a guard counted in ticks would never
	# come down at all. See `BUTTON_LOCK_MS`.
	if _button_lock_ms > 0:
		_button_lock_ms = maxi(0, _button_lock_ms - int(round(delta * 1000.0)))
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
	_advance_ease(delta)
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
		#
		# The test is "is this a blow that landed on the hero", not the literal kind
		# "ENEMY HIT": a monster's melee, bolt, crit, drain and poison all carry their own
		# kind, and matching only the one name left the monster's spells with no reaction at
		# all. `_damage_taken` is what the arena's history shows the player already lost.
		if not on_player and kind.begins_with("HIT"):
			_hero_lunge = 1.0
			_monster_flash = 1.0
		elif is_player_blow(kind, amount, on_player):
			# The MONSTER does not lunge. Its own 20px dip-and-return on being hit read as
			# a twitch of its picture and Jan asked for it gone; the HIT wash is what says
			# the blow landed on it now. Only the hero lunges (his own attack) and flinches
			# (being hit).
			_hero_flinch = 1.0
			if amount > 0:
				_hero_flash = 1.0
	battle.log.clear()


## Is this log entry a blow the MONSTER landed on the hero? The battle writes its own kind
## per attack (ENEMY HIT, ENEMY BOLT, ENEMY CRIT, ENEMY LIFESTEAL, ENEMY POISON, POISON from
## the enemy's DoT…), so a screen that only reacted to the literal "ENEMY HIT" ignored most
## of what the monster does. The exclusions are the enemy's HEAL (it is not damage to the
## hero) and "ENEMY CAST …" (the cast has STARTED, the effect has not landed yet — the
## effect's own line is what shakes the hero).
static func is_player_blow(kind: String, amount: int, on_player: bool) -> bool:
	if not on_player:
		return false
	if kind.begins_with("ENEMY HEAL") or kind.begins_with("ENEMY CAST"):
		return false
	if kind.begins_with("ENEMY"):
		return true
	# The enemy's DoT on the hero ("POISON") and the hero's own DoT on the enemy
	# ("HERO POISON") arrive with the damage in `amount`, so they can be told apart.
	return amount > 0 and kind == "POISON"


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
	_floats.append({"node": label, "life": 1.0, "dy": 0.0, "age": 0.0,
		"drift": (float(_floats.size() % 5) - 2.0) * 16.0})
	# Spawned SMALL — `_animate` grows it over the next 90 ms of real frames, so a number
	# that appears between two frames still reads as appearing rather than as a cut.
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(0.55, 0.55)


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
## The monster's own lunge (a 20px dip on being hit) is GONE — Jan read it as the enemy's
## picture twitching down and up on every blow, and the HIT wash already says where the blow
## landed. What stays is the walk-in tilt (`--monster-dy`, `closed * 8` px), which is part of
## the approach, and the shake when the hero's swing lands.
##
## The swing TIMER has no lunge to ride, so the ring is now the only countdown on screen:
## `_smooth_update` runs the bar itself and snaps the sweep at a restart. See the ease note
## there for why a 0.25 s ease could never reach 100%.
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
		f["age"] = float(f.get("age", 0.0)) + delta
		var age := float(f["age"])
		node.position = Vector2(round(mid.x - node.size.x * 0.5 + float(f["drift"])),
			round(mid.y - 40.0 + float(f["dy"])))
		node.modulate = Color(1, 1, 1, clampf(float(f["life"]), 0.0, 1.0))
		# POP, then shrink: a number that appears at full size is the same "instant" the
		# HP bars had. It grows past its size over the first 90 ms of real time and settles.
		var pop_t := clampf(age / 0.09, 0.0, 1.0)
		var pop := 0.55 + 0.45 * pop_t + 0.18 * sin(pop_t * PI)
		node.pivot_offset = node.size * 0.5
		node.scale = Vector2(pop, pop)
		if float(f["life"]) > 0.0:
			alive.append(f)
		else:
			node.queue_free()
	_floats = alive

	# Lunges decay over the PWA's 200 ms CSS animation.
	_hero_lunge = maxf(0.0, _hero_lunge - delta * 5.0)
	_hero_flinch = maxf(0.0, _hero_flinch - delta * 5.0)
	_hero_flash = maxf(0.0, _hero_flash - delta / EASE_HIT_SECONDS)
	_monster_flash = maxf(0.0, _monster_flash - delta / EASE_HIT_SECONDS)
	if is_instance_valid(_hero_sprite):
		var lift := 14.0 * _hero_lunge - 10.0 * _hero_flinch
		_place_hero(lift)
		# The blow lands HERE. A number that appears beside a figure which does not react
		# reads as a readout; a figure that takes a step back and goes red for a moment
		# reads as being hit. `modulate` multiplies into the TextureRect's own texture, so
		# this needs no second node.
		_hero_sprite.modulate = Color.WHITE.lerp(HIT_TINT, _hero_flash * HIT_TINT_STRENGTH)
	if is_instance_valid(_portrait):
		# The depth tilt the PWA applies as the hero walks in (`--monster-dy`,
		# `closed * 8` px) — a boss keeps its geometry and does not tilt, exactly as the
		# PWA's `if (monsterFig && !mb.isBoss)`.
		# Smoothed with the hero: the lean is part of the same walk-in and stepped with it.
		#
		# The monster's own 20px lunge used to be added here. It is gone (Jan: the enemy's
		# picture twitched on every blow); the tilt is the only vertical motion left, and
		# it belongs to the APPROACH, not to a hit.
		var tilt := 0.0
		if battle != null and not battle.is_boss:
			tilt = MONSTER_TILT_MAX * (1.0 - clampf(_gap_displayed(), 0.0, 1.0))
		# The monster SHAKES when the hero lands one: a ±2px wobble that decays with the
		# wash. Without it the portrait was the one thing on screen that never reacted to
		# its own damage — the ring and the bar moved and the figure did not.
		var shake: float = round(2.0 * _monster_flash * sin(_monster_flash * 32.0))
		_portrait.position.y = round(_arena.size.y * 0.5 - PORTRAIT_BOX * 0.5 + tilt)
		_portrait.position.x = round((_arena.size.x - _portrait.size.x) * 0.5 + shake)
		_portrait.modulate = Color.WHITE.lerp(HIT_TINT, _monster_flash * HIT_TINT_STRENGTH)
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

	# The eased HP / mana readout's TARGETS are read in `_smooth_update()`, every frame —
	# not here. `render()` runs on ticks only, and a mana potion writes `hero.mana` straight
	# from its button between ticks; a target set from here would miss it. What belongs here
	# is only what a tick decides: the arcs' visibility.
	# The enemy's mana ring appears only where the enemy actually casts: the PWA hid
	# `.enemy-mana-ring` for melee monsters. The ring's VALUE is in `_smooth_update()`.
	_arc_enemy_mana.visible = not battle.enemy_spells.is_empty()
	_arc_offhand.visible = battle.offhand_swing_ms > 0

	# The hero's resource bar. EVERY class uses mana in this game — the barbarian too
	# (CLASSES.json: resource 'mana', maxResource 100, baseMana 10, manaPerLevel 1) —
	# so the bar is never hidden. An earlier note claimed the barbarian ran on rage and
	# skipped his bar; that was wrong, and it hid the pool his own spells are paid from.
	var hero: Dictionary = _state.hero()
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
	# The targets are read HERE, every frame, from the battle's own numbers — the RULES'
	# values, which are already the new number the instant a tick settled them. Reading them
	# in `render()` instead (which runs on ticks) left every OTHER path that moved HP with
	# no way to reach the bars: a mana potion writes `hero.mana` from the button, and the
	# battle's `enemy_hp` can be changed by a test or a spell between ticks.
	#
	# `_ease_to` returns early when the target is unchanged, so calling it every frame is
	# free and no transition is ever restarted by a repeat call.
	var hero: Dictionary = _state.hero()
	var hero_class := str(_state.data.get("heroClass", ""))
	var max_mana := int(hero.get("maxMana", 0))
	if max_mana <= 0:
		max_mana = _gen.hero_max_mana(hero, _state.equip(), hero_class, _find_item)
	_ease_to("enemy_hp", battle.enemy_hp, EASE_HP_SECONDS)
	_ease_to("enemy_hp_max", battle.enemy_max_hp, EASE_HP_SECONDS)
	_ease_to("hero_hp", battle.hero_hp, EASE_HP_SECONDS)
	_ease_to("hero_hp_max", battle.hero_max_hp, EASE_HP_SECONDS)
	_ease_to("mana", float(hero.get("mana", 0)), EASE_MANA_SECONDS)
	_ease_to("mana_max", float(maxi(max_mana, 1)), EASE_MANA_SECONDS)

	# The eased readout is what everything below draws.
	_hero_hp_shown = _ease_value("hero_hp")
	_hero_hp_max_shown = _ease_value("hero_hp_max")
	_mana_shown = _ease_value("mana")
	_mana_max_shown = _ease_value("mana_max")
	_enemy_hp_shown = _ease_value("enemy_hp")
	_enemy_hp_max_shown = _ease_value("enemy_hp_max")

	# The player's two gold arcs: a full ring is a swing just landed and the arc fills as
	# the next one approaches. The off-hand shares the SAME elapsed clock, which is what the
	# PWA did (`_playerSwingPct` drove both rings); only the interval differs.
	var player_ms := maxf(float(battle.player_swing_ms), 1.0)
	_arc_player.set_value_ratio(clampf((battle.player_swing_elapsed + ahead) / player_ms, 0.0, 1.0))
	if battle.offhand_swing_ms > 0:
		_arc_offhand.set_value_ratio(clampf((battle.player_swing_elapsed + ahead)
			/ float(battle.offhand_swing_ms), 0.0, 1.0))
	# The enemy's timer is the ONE gauge that must NOT be eased, and easing it was the
	# whole of Jan's "the enemy's swing timer never finishes, it always resets at ~90 %".
	#
	# `_ease_to` re-targets on EVERY tick (the clock advances 100 ms ten times a second),
	# and a re-target drops the duration back to 0.25 s from wherever the value had got to.
	# Ten re-targets a second against a 0.25 s transition is an asymptotic crawl: measured
	# against the real clocks (100 ms tick, 60 fps frames) the arc peaked at 87.1 % on a
	# 1000 ms swing, 91.4 % on 1500 ms and 93.5 % on 2000 ms — never once full, and the
	# shorter the weapon the earlier it looked to give up. The DAMAGE was always correct
	# (it lands in the tick where `enemy_swing_elapsed` reaches `enemy_swing_ms`); only the
	# drawing lagged, so it read as "it hits before the ring is done".
	#
	# A clock the rules RESTART must be drawn from the rules' own number. Read it straight,
	# exactly like the two gold rings, which never had an ease for the same reason.
	var timer_target := clampf((battle.enemy_swing_elapsed + ahead)
		/ maxf(float(battle.enemy_swing_ms), 1.0), 0.0, 1.0)
	_arc_enemy_timer.set_value_ratio(timer_target)

	var enemy_ratio := clampf(_enemy_hp_shown / maxf(_enemy_hp_max_shown, 1.0), 0.0, 1.0)
	_arc_enemy_hp.set_value_ratio(enemy_ratio)
	if not battle.enemy_spells.is_empty():
		_arc_enemy_mana.set_value_ratio(clampf(
			battle.enemy_resource_cur / maxf(battle.enemy_max_resource, 1.0), 0.0, 1.0))

	# The PWA's damage ghost: `.enemy-hp-fill-ring` transitions in 0.2 s and
	# `.enemy-hp-ghost-ring` in 0.6 s, so the ghost TRAILS the fill and the hit reads as a
	# bite being taken. The port snapped the ghost to the fill in the same line, which made
	# the slower transition invisible and left a second identical red ring on screen.
	# Through `set_value_ratio`, not `.value`: the setter is what queues the redraw, and
	# writing the field directly drew nothing at all.
	_ease_to("enemy_hp_ghost", enemy_ratio, EASE_GHOST_SECONDS)
	_arc_enemy_hp_ghost.set_value_ratio(_ease_value("enemy_hp_ghost"))

	_set_bar(_hero_hp_track, _hero_hp_fill, _hero_hp_shown, _hero_hp_max_shown)
	_set_bar(_mana_track, _mana_fill, _mana_shown, _mana_max_shown)
	# The readouts are part of the same frame as the bars they label, so they can never say
	# 240/240 above a bar that is still emptying.
	_enemy_hp_label.text = "%d/%d" % [maxi(0, int(round(_enemy_hp_shown))),
		int(round(_enemy_hp_max_shown))]
	_hero_hp_bar_label.text = "%d/%d" % [maxi(0, int(round(_hero_hp_shown))),
		int(round(_hero_hp_max_shown))]
	_mana_label.text = "Mana %d / %d" % [int(round(_mana_shown)), int(round(_mana_max_shown))]


## A member that just stepped up is a NEW enemy: the portrait, the name and the walk-in all
## have to move to it, and the walk-in restarts — the port used to keep the arena in
## contact, so pack member two was hit the instant it appeared.
func _on_pack_member_began() -> void:
	sync_enemy_display()
	battle.reset_gap()


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
	_button_lock_ms = BUTTON_LOCK_MS
	var stop_complete := int(_state.data["areaFightProgress"][battle.act_id]) >= Battle.FIGHTS_PER_ZONE
	if battle.won:
		_append_log("Vyhrano")
		award_loot()
	else:
		_append_log("Porazeno")
		# A defeat drops nothing (the PWA clears the list), and the consolation gold the
		# battle paid is not a DROP — it must not appear as a loot row either.
		_result_loot_rows = []
		_result_gold_won = 0
		_state.save()
	# The loot that did NOT fit in the bag is offered as a button rather than dropped
	# silently: a player who wins a rare with a full bag must be able to see it exists.
	_loot_button.visible = _pending_loot.size() > 0
	_show_result_page(stop_complete)
	fight_over.emit(battle.won)
	# The next fight's clock starts from the tap, not from the last frame of this fight:
	# a remainder carried over would hand the new fight's first swing a free tick.
	_tick_accumulator = 0.0


## Show the PWA's result page for the fight that just ended.
##
## This is the whole of "the win and the loss do not work": the port settled XP, gold and
## the fight counters correctly and then announced it with ONE word over a live arena, with
## no drops shown and no way on that matched the PWA. The page carries the stop's artwork,
## "Victory!" with the act and the fight count, the hero's HP/mana, the loot rows and the
## action tiles — and a defeat carries the defeat art and a page tap to town.
func _show_result_page(stop_complete: bool) -> void:
	_result_built = true
	var won := battle.won
	var hero: Dictionary = _state.hero()

	# `.result-icon-img.large` (defeat, 50vh) against the stop art (a win, 100vw).
	_result_art.visible = won
	_result_defeat_art.visible = not won
	_result_art.texture = _stop_result_art() if won else null
	_result_defeat_art.texture = _load("assets/result_defeat.png") if not won else null

	var act: Dictionary = _data.act_by_id(battle.act_id)
	_result_title.visible = won
	_result_sub.visible = won
	if won:
		_result_title.text = "Vitezstvi"
		_result_sub.text = "%s - %s%s" % [
			str(act.get("name", "ACT %d" % (battle.act_id + 1))).to_upper(),
			_stop_name(battle.act_id, battle.progress),
			" - zastavka dokoncena" if stop_complete else " - souboj %d/%d" % [
				mini(battle.area_fight + 1, Battle.FIGHTS_PER_ZONE), Battle.FIGHTS_PER_ZONE]]
		# A WIN: `.stop-result-overlay` draws the title and the sub ON the art, white bold
		# 26px over a 14px #ddd sub, both with a dark text shadow.
		_result_title.add_theme_font_size_override("font_size", 26)
		_result_title.add_theme_color_override("font_color", Color("#ffffff"))
		_result_sub.add_theme_font_size_override("font_size", 14)
		_result_sub.add_theme_color_override("font_color", Color("#dddddd"))
	else:
		# The PWA's defeat page is NOT the victory page's overlay: it is `.centered` with a
		# bare `.result-title` and `.result-sub` UNDER the artwork. Measured on the live PWA
		# (via `confirmSurrender`, the route a player takes): the title is "Forfeit" and it is
		# `.result-title { font-size:22px; font-weight:bold; margin:8px 0 }` — 22px BOLD —
		# and the sub is `.result-sub { font-size:16px; color:#888888 }`.
		_result_title.text = "Forfeit"
		_result_sub.text = "Návrat do města"
		_result_title.add_theme_font_size_override("font_size", 22)
		_result_title.add_theme_color_override("font_color", Color("#ffffff"))
		_result_sub.add_theme_font_size_override("font_size", 16)
		_result_sub.add_theme_color_override("font_color", Color("#888888"))
		_result_title.visible = true
		_result_sub.visible = true

	# `.stop-result-hpbar` — the hero's own readout as the fight left him, healed or not.
	_result_hp_line.text = "HP %d/%d" % [int(round(battle.hero_hp)), int(round(battle.hero_max_hp))]
	var max_mana := int(hero.get("maxMana", 0))
	if max_mana <= 0:
		max_mana = _gen.hero_max_mana(hero, _state.equip(),
			str(_state.data.get("heroClass", "")), _find_item)
	_result_mana_line.text = "Mana %d/%d" % [int(hero.get("mana", 0)), max_mana]

	_rebuild_result_actions(won, stop_complete,
		int(_state.data.get("townPortalCount", 0)) > 0)
	# The PWA clears the loot list on a defeat (`resultLootList.innerHTML = ''` — a defeat
	# drops nothing), so a defeat page must not show this fight's dead-enemy drops.
	_refresh_result_loot(won)
	_result_tap_goes_to_map = won and stop_complete
	_result_layer.visible = true
	_place_tiles(_result_layer.size, _result_actions_h())
	# The art's rect depends on the tiles' height, so a full layout pass has to follow any
	# rebuild — but it is the LAST resort, not the first. See `_on_actions_resized()`:
	# `_result_actions_h()` needs the tiles' `size.y`, which a container only assigns during
	# its own layout pass, and when the deferred call below did not run (the window being
	# resized, the tree mid-layout) every block kept the rect of the fight BEFORE this one.
	call_deferred("_layout_result_page")


## The tile row's rect, re-placed on EVERY change it reports.
##
## The tiles are the only things on the result page that are TAPPED, so a stale row is a
## page whose buttons are dead to the finger. In the port the row was placed only from
## `_layout_result_page()`, which runs deferred once per fight, while a `Control` sibling
## laid over the page can sit on top of the tiles and swallow taps that were aimed at them
## (the PWA's `#resultScreen` is the whole page's click target, and its own tiles are
## z-indexed above it; a Godot `Button` does not have z-index, only tree order).
##
## The row's own height comes from the `HBoxContainer`, which resizes as it is populated,
## so this fires exactly when the row has become the size the layout pass will use.
func _on_actions_resized() -> void:
	if _result_layer == null or not _result_layer.visible or _resizing_tiles:
		return
	_resizing_tiles = true
	_place_tiles(_result_layer.size, _result_actions_h())
	_resizing_tiles = false


## Place the artwork and the two overlays that sit ON it.
##
## `_result_art` is a plain Control child, so nothing lays it out: the rect is computed from
## the texture's aspect against `.result-icon-img.stop-result { max-width:100vw;
## max-height:calc(100vh - 160px) }`. A defeat's image is `.large` — 90vw / 50vh — and it is
## CENTRED, since `.result-screen.centered` puts the whole top block in the middle.
func _layout_result_page() -> void:
	if _result_layer == null or not _result_layer.visible:
		return
	var page := _result_layer.size
	if page.x <= 0.0 or page.y <= 0.0:
		page = Vector2(390.0, 844.0)
	# `.result-bottom { position:absolute; bottom:0 }` — the tiles own the page's bottom edge
	# whether or not they have any children (the PWA keeps the padding; only its background
	# is `#000` so a 20px strip is invisible either way).
	var tiles_h := _result_actions_h()
	_place_tiles(page, tiles_h)
	var top_h := page.y - tiles_h
	if _result_defeat_art.visible:
		var tex: Texture2D = _result_defeat_art.texture
		if tex == null:
			return
		# `max-width:90vw; max-height:50vh` NEVER UPSCALES — the image draws at its intrinsic
		# size and only SHRINKS if it exceeds the cap. Measured on the live PWA, the 256x256
		# defeat art draws 256 wide (not 351, which is what 90vw would be), which is why the
		# title lands at y=510 rather than 100px higher.
		var cap := Vector2(page.x * 0.90, page.y * 0.50)
		var scale := minf(1.0, minf(cap.x / float(tex.get_width()), cap.y / float(tex.get_height())))
		var size := Vector2(float(tex.get_width()), float(tex.get_height())) * scale
		# The PWA's defeat page is `.centered`: the artwork, the title and the sub are ONE
		# centred block, and the title/sub are page-level siblings UNDER the art rather than an
		# overlay on it. Measured on the live PWA (a real forfeit): the art at y=246, the title
		# at y=510 and the sub at y=543.
		_result_defeat_art.size = size
		# Local to the box: the BOX carries the centring, so the image sits at its origin.
		_result_defeat_art.position = Vector2.ZERO
		var text_h := _result_overlay.get_combined_minimum_size().y
		_result_overlay.size = Vector2(page.x - 24.0, text_h)
		# 8px under the art, which is `.result-title { margin:8px 0 }`'s own top margin.
		_result_overlay.position = Vector2(12.0, round(size.y + 8.0))
		_result_stats.visible = false
		loot_pad.visible = false
		var block := size.y + 8.0 + text_h
		var lift := maxf(0.0, round((top_h - block) * 0.5))
		_art_box.position = Vector2(round((page.x - size.x) * 0.5), lift)
		_art_box.size = size
		_result_overlay.position += Vector2(0.0, lift)
		return
	var tex2: Texture2D = _result_art.texture
	if tex2 == null:
		return
	# `.result-icon-img.stop-result { max-width:100vw; max-height:calc(100vh - 160px) }` keeps
	# its aspect; a 512x512 stop art on a 390x844 page is therefore 390 wide and 390 tall —
	# measured on the live PWA as 390x392 at (0, 1).
	var scale2 := minf(page.x / float(tex2.get_width()), top_h / float(tex2.get_height()))
	var size2 := Vector2(float(tex2.get_width()), float(tex2.get_height())) * scale2
	_result_art.size = size2
	_result_art.position = Vector2.ZERO
	_art_box.size = size2
	_art_box.position = Vector2(round((page.x - size2.x) * 0.5), 1.0)
	# `.stop-result-overlay { top:10px }` over the art's top.
	_result_overlay.size = Vector2(size2.x - 24.0, 0.0)
	_result_overlay.position = Vector2(round(_art_box.position.x + 12.0), round(_art_box.position.y + 10.0))
	# `.stop-result-stats { bottom:10px }` along the art's bottom.
	_result_stats.visible = true
	var stats_h := _result_stats.get_combined_minimum_size().y
	_result_stats.size = Vector2(size2.x, stats_h)
	_result_stats.position = Vector2(round(_art_box.position.x),
		round(_art_box.position.y + size2.y - stats_h - 10.0))
	# `.result-loot-scroll` under the art, inside `.result-top`.
	loot_pad.visible = true
	var loot_h := loot_pad.get_combined_minimum_size().y
	loot_pad.size = Vector2(page.x, loot_h)
	loot_pad.position = Vector2(0.0, round(_art_box.position.y + size2.y))


## Place `.result-bottom` on the page's bottom edge and size its tiles off `_tile_size()`.
## A tile's `custom_minimum_size` cannot be set at build time — how wide it should be depends
## on how MANY tiles there are, and the row is rebuilt per outcome — so it is set here.
func _place_tiles(page: Vector2, tiles_h: float) -> void:
	var width := maxf(page.x, 1.0)
	_tiles_holder.size = Vector2(width, tiles_h)
	_tiles_holder.position = Vector2(0.0, round(page.y - tiles_h))
	var side := _tile_size()
	for child in _result_actions.get_children():
		if child is Control:
			(child as Control).custom_minimum_size = Vector2(side, side)


## The height `.result-bottom` takes off the page's bottom. The PWA's is
## `flex:0 0 auto` under a `flex:1` top, so the art gets the remainder. The loot list is
## INSIDE `.result-top` (measured: it sits at y=399, six px under the art) and must NOT be
## counted here — counting it was what pushed the loot to the bottom of the page.
##
## A defeat's `.result-bottom:empty { display:none }` — and the live PWA confirms it: the
## strip still measures 20px (`padding:10px 12px` with no children still leaves the padding),
## it is simply invisible because its background is `#000` on a `#000` page.
func _result_actions_h() -> float:
	var h := 20.0
	if _result_actions.get_child_count() > 0:
		h += _tile_size()
	if _loot_button.visible:
		h += 46.0
	return h


## `.result-loot-scroll` — the drops the fight just handed over, one row per item, rarity
## coloured, with its icon. A fight with no drops says so rather than showing nothing, which
## is how the PWA's own list reads.
##
## GOLD IS A ROW TOO, on Jan's request: a fight that paid only gold used to leave the list
## saying "Zadne predmety" over a purse that had just been filled, which reads as the fight
## having paid nothing. It is drawn exactly like an item — same 32px icon slot, same row
## shape — with `Zlato xN` in the game's own gold colour. The icon is a real asset
## (`assets/items/coin_gold.png`, made by `tools/import/make_coin.py`); the game has no emoji.
##
## A row that is not an item is marked with a `gold` key, so one row builder handles both
## without a second list to keep in step.
##
## The PWA CLEARS this list on a defeat (`$('resultLootList').innerHTML = ''` — a defeat
## drops nothing at all), so `show` is passed in rather than inferred: a defeat page showing
## the drops of a monster that never died is worse than showing nothing.
func _refresh_result_loot(show: bool = true) -> void:
	for child in _loot_list.get_children():
		_loot_list.remove_child(child)
		child.queue_free()
	if not show:
		_loot_list.visible = true
		return
	# The rows are the items the fight rolled, bagged OR pending: `_pending_loot` is the
	# overflow, and a list that showed only what fit would hide exactly the drop the player
	# needs to know about. The gold row is appended here rather than stored with them, so
	# the two lists cannot drift.
	var rows: Array = _loot_rows_with_gold()
	if rows.is_empty():
		_loot_list.add_child(_label("Zadne predmety", 12, Color("#555555"),
			HORIZONTAL_ALIGNMENT_CENTER))
		_loot_list.visible = true
		return
	for row_data in rows:
		_loot_list.add_child(_make_loot_row(row_data))
	_loot_list.visible = true


## The fight's loot rows plus the gold row, if this fight paid any. The gold row is a
## dictionary of its own shape so it cannot be mistaken for a real item:
##   {"gold": <amount>, "name": "Zlato x<amount>"}
func _loot_rows_with_gold() -> Array:
	var rows: Array = _result_loot_rows.duplicate()
	if _result_gold_won > 0:
		rows.append({"gold": _result_gold_won, "name": "Zlato x%d" % _result_gold_won,
			"id": "gold", "iconImg": COIN_ICON})
	return rows


## One row of `.result-loot-scroll`: a 32px icon, a rarity-coloured name, clipped to the row.
## An item and the gold row differ ONLY in which icon and which colour they take, which is
## what makes the gold read as "another thing this fight gave me".
func _make_loot_row(row_data: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_path := COIN_ICON if row_data.has("gold") else ItemStats.icon_path(row_data)
	icon.texture = _load(icon_path) if icon_path != "" else null
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var colour := Color(UIKit.GOLD) if row_data.has("gold") else ItemStats.quality_color(row_data)
	var name_label := _label(str(row_data.get("name", row_data.get("id", ""))), 15,
		colour, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)
	return row


## The stop's own art, the PWA's `getStopImage`: generated images for the acts that have
## them, a per-act placeholder otherwise. Shares `map_screen.gd`'s rule rather than
## inventing a second one.
func _stop_result_art() -> Texture2D:
	var stop := clampi(battle.progress, 0, 9)
	var generated := "assets/stops/stop_act%d_%d.webp" % [battle.act_id, stop]
	var loaded := _load(generated)
	if loaded != null:
		return loaded
	return _load("assets/stops/placeholder_act%d.png" % battle.act_id)


## The hero's own portrait for the result page's Hero tile — the PWA used `state.hero.face`.
func _hero_face_path() -> String:
	var face := str(_state.hero().get("face", "hero"))
	if face == "":
		face = "hero"
	return "assets/monsters/%s.png" % face


func _stop_name(act_id: int, stop: int) -> String:
	var raw: Variant = _data.table("STOP_NAMES_EN", {})
	var names: Dictionary = raw if raw is Dictionary else {}
	var per_act: Variant = names.get(str(act_id), null)
	if per_act is Array and stop < (per_act as Array).size():
		return str(per_act[stop])
	return "Zastavka %d" % (stop + 1)


## The page tap. The PWA rewired `#resultScreen.onclick` per outcome: a defeat goes to town
## (and the town heals), a cleared stop goes to the MAP so the next stop is chosen there.
func _on_result_clicked() -> void:
	if _button_lock_ms > 0 or not _result_built:
		return
	if _result_tap_goes_to_map:
		map_requested.emit()
	else:
		leave_requested.emit()


func _on_portal_pressed() -> void:
	if _button_lock_ms > 0:
		return
	portal_requested.emit()


func _on_hero_pressed() -> void:
	if _button_lock_ms > 0:
		return
	hero_requested.emit()


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
	if _button_lock_ms > 0:
		return
	another_fight_requested.emit()


func _on_leave_pressed() -> void:
	if _button_lock_ms > 0:
		return
	leave_requested.emit()


## Take the loot that did not fit. It stays in `_pending_loot` until a slot frees up, so
## nothing is destroyed by a full bag.
func _on_loot_pressed() -> void:
	if _button_lock_ms > 0:
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
	# The result page shows what the fight rolled, so the rows are kept BEFORE the bag has
	# its say — a drop the bag refused is the one the player most needs to see.
	_result_loot_rows = result["items"].duplicate()
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
	# The result page shows the gold as a row of its own, so the amount is kept here. Every
	# other gold source (the kill gold inside `battle._finish`, a boss's reward) is settled
	# before this and is not part of the drop list.
	_result_gold_won = int(result["gold"])
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
