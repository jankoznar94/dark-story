extends Control
class_name MapScreen
## MapScreen — the dungeon map: three difficulties, one card per act, and the row of stop
## cards (`.stop-card`) for the act the player has expanded.
##
## This is where the port was MISSING AN ENTIRE SCREEN. The PWA's difficulty selector is
## not in the town: `renderMap` builds `.diff-selector` into `#mapScroll`, and the town
## only ever showed the banner, the five tiles and the portal row. The previous port put
## the selector and a stat line in the town because it had no map to put them on.
##
## Source: `renderMap` / `buildDotPath` / `toggleActExpand` / `setDifficulty` in
## `src/game.ts`, plus these rules from `public/style.css`:
##
##   .diff-selector      flex, 6px gap, centred;  .diff-btn padding 6px 14px, radius 6,
##                       #111 on #333 border, active #f1c40f border+text on #1a1a1a
##   .map-scroll         a column, 8px gap, 20px top padding
##   .map-location       aspect-ratio 3/1, radius 10, 1.5px themed border, the theme's
##                       dungeon art at 65% opacity behind it, name 20px bold, and a
##                       badge on the right reading Play / Done / Locked
##   .map-loc-gate       a locked act draws its gate art over the card at 60% black
##   .stop-card          aspect-ratio 1/1, radius 10, 2.5px border, the stop's own art,
##                       a bottom-gradient label (19px bold white) and a corner badge
##   .stop-arrow         a CSS triangle between two stops, grey until the next one opens
##
## Stop names come from `data/STOP_NAMES_EN.json`, extracted from the PWA's own
## STOP_NAMES_EN table by tools/import/convert.mjs. Stop art: act 0 and act 1 have
## generated images (`stop_actN_M.webp`), the rest fall back to a per-act placeholder —
## the PWA's own `getStopImage` rule, kept rather than "improved".

const GameData := preload("res://scripts/data/game_data.gd")
const UIKit := preload("res://scripts/ui/ui_kit.gd")

signal back_pressed()
signal difficulty_selected(difficulty: int)
signal enter_stop(act_id: int, stop: int)
## `.map-actions`' second button — the PWA's "Town Portal", shown only when the hero
## actually carries a scroll.
signal portal_requested()

## 390 - 32 = 358 wide. `.stop-card` is a square, so the art is 358 tall; the label sits
## over the bottom of it.
const STOP_CARD := Vector2(358, 358)

var _data: Node
var _state
var _find_item: Callable

var _list: VBoxContainer
var _difficulty_row: HBoxContainer
var _actions: HBoxContainer
var _portal_button: Button
## Which act's stop path is open. The PWA kept this on the save (`_expandedAct`) and
## initialised it to -1: on first open the map shows the act CARDS ONLY, collapsed, and
## the stop path appears when the player taps one. The port used to auto-expand the first
## unfinished act, which is a different screen from the one the reference frame shows.
var _expanded_act := -1


func _init(game_data: Node, state, find_item: Callable) -> void:
	_data = game_data
	_state = state
	_find_item = find_item


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var page := UIKit.screen_page(self)
	var column: VBoxContainer = page["column"]
	column.add_theme_constant_override("separation", 8)

	# The PWA's map has NO header at all — no title, no "Back to Town". It opens on the
	# difficulty selector (`.map-scroll` starts at y=16 with 20px of top padding) and
	# leaves the way out to the nav bar and the `.map-actions` row at the bottom. The
	# port used to lead with an invented `back_header("Mapa")`, which pushed every real
	# element 100px down and made the screen read as a different layout.
	#
	# PWA geometry, measured on the live build: `#mapScreen` has 16px padding, so the
	# column starts at y=16; `#mapScroll` then adds its own `padding-top:20px`, so
	# `.diff-selector` sits at y=36, is 29px tall, has `margin-bottom:10px`, then the
	# `.map-scroll` flex gap of 8px puts the first `.map-location` at y=83. Exactly:
	# 16 + 20 + 29 + 10 + 8 = 83. Every one of those gaps is an explicit spacer, so the
	# column's own separation is zero — a VBox separation would add itself to each.
	column.add_theme_constant_override("separation", 0)
	var scroll_top := Control.new()
	scroll_top.custom_minimum_size = Vector2(0, 20)
	scroll_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(scroll_top)

	# `.diff-selector { display:flex; gap:6px; margin-bottom:10px; justify-content:center }`
	_difficulty_row = HBoxContainer.new()
	_difficulty_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_difficulty_row.add_theme_constant_override("separation", 6)
	_difficulty_row.custom_minimum_size = Vector2(0, 29)
	column.add_child(_difficulty_row)

	var diff_gap := Control.new()
	diff_gap.custom_minimum_size = Vector2(0, 10)
	diff_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(diff_gap)

	# `.map-scroll { display:flex; flex-direction:column; gap:8px; padding-top:20px }`
	var list_top := Control.new()
	list_top.custom_minimum_size = Vector2(0, 8)
	list_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(list_top)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.custom_minimum_size = Vector2(0, 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_list)

	# `.map-actions { display:flex; gap:8px; padding:8px 12px 12px }` with equal-width
	# `.map-action-btn` buttons. `.btn` is full width, so "Walk to Town" is always there;
	# the town portal only appears once a scroll is actually in the bag (the PWA toggled
	# `display:none` on it the same way).
	#
	# Measured: `.map-actions` is 358x62 with 8px top and 12px bottom padding, so the
	# 30px button sits at y=352 with 8px of gap above the row. `.map-action-btn` is
	# `flex:1` — but `display:none` on the portal leaves the visible button full width
	# (334px), so equality is the PWA's flex doing its job, not a fixed split.
	var actions_top := Control.new()
	actions_top.custom_minimum_size = Vector2(0, 8)
	actions_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(actions_top)

	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	_actions.custom_minimum_size = Vector2(0, 62)
	_actions.add_theme_constant_override("margin_top", 8)
	column.add_child(_actions)

	var walk := UIKit.secondary_button("Walk to Town", 30)
	walk.add_theme_font_size_override("font_size", 12)
	walk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	walk.pressed.connect(func(): back_pressed.emit())
	_actions.add_child(walk)

	_portal_button = UIKit.secondary_button("Town Portal", 30)
	_portal_button.add_theme_font_size_override("font_size", 12)
	_portal_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_portal_button.visible = false
	_portal_button.pressed.connect(func(): portal_requested.emit())
	_actions.add_child(_portal_button)


func refresh() -> void:
	_refresh_difficulty()
	_clear(_list)
	_build_acts()


## `.diff-selector` — three buttons. A LOCKED one is drawn dim with the lock reason in
## its tooltip rather than hidden, because "what am I working towards" is the point.
##
## The PWA draws NOTHING under the selector. The port used to put a stat line there
## ("Obtiznost 1 z 3 - uroven monster 1-15..."), which is invented: measured on the live
## build the column between the `.diff-selector` (y 36) and the first `.map-location`
## (y 83) is empty, and those the 47px are just `margin-bottom:10px` plus the scroll's
## 20px top padding and an 8px gap.
func _refresh_difficulty() -> void:
	_clear(_difficulty_row)
	var diffs: Array = _data.difficulties()
	var current := int(_state.data.get("difficulty", 0))

	for i in diffs.size():
		var d: Dictionary = diffs[i]
		var name := str(d.get("name", "Difficulty %d" % (i + 1)))
		var is_active := i == current
		var unlocked: bool = _state.is_difficulty_unlocked(i)

		var button := Button.new()
		button.text = name
		button.custom_minimum_size = Vector2(0, 29)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 13)
		# `.diff-btn { padding:6px 14px; border:1px solid #333; border-radius:6px }` —
		# 15px of text + 12px of padding + 2px of border = the 29px the live build
		# measures. The port drew 34px, which pushed the row 5px deep.
		#
		# A locked button is `${locked?'🔒 ':''}${d.name}` in the PWA, i.e. a lock glyph
		# then the name. DejaVu cannot draw the glyph, so it is the generated lock icon.
		if not unlocked:
			button.icon = UIKit.load_texture("assets/menu-icons/lock.png")
			button.expand_icon = true
			# `Button` has NO `icon_max_width` property — assigning it raises at runtime
			# ("Invalid assignment of property or key 'icon_max_width'"), and the icon then
			# draws at its native 256px and blows the 29px row apart. It is a THEME
			# constant:
			button.add_theme_constant_override("icon_max_width", 12)
			button.add_theme_constant_override("h_separation", 8)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#111111")
		style.border_color = Color("#333333")
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		style.content_margin_left = 14
		style.content_margin_right = 14
		if is_active:
			# `.diff-btn.active { border-color:#f1c40f; color:#f1c40f; background:#1a1a1a }`
			style.border_color = Color(UIKit.GOLD)
			style.bg_color = Color("#1a1a1a")
		for state_name in ["normal", "hover", "focus", "disabled"]:
			button.add_theme_stylebox_override(state_name, style)
		var pressed := style.duplicate()
		pressed.bg_color = Color("#222222")
		button.add_theme_stylebox_override("pressed", pressed)
		if not unlocked:
			# `.diff-btn.locked { opacity:0.4; cursor:default }`
			button.modulate = Color(1, 1, 1, 0.4)
			button.tooltip_text = _difficulty_lock_reason(i)
		elif is_active:
			button.add_theme_color_override("font_color", Color(UIKit.GOLD))
		else:
			button.add_theme_color_override("font_color", Color("#888888"))

		# EVERY unlocked button is wired — the active one INCLUDED. The PWA's markup is
		# `onclick="${locked?'':`game.setDifficulty(${di})`}"`, so the active difficulty is
		# not excluded from the handler: tapping it re-enters the map, which collapses the
		# stop path. The port only wired the two inactive ones, so tapping the active
		# difficulty was a dead button.
		#
		# The ROUTE matters: `setDifficulty` in the PWA resets `_expandedAct` before
		# re-rendering, so this goes through `select_difficulty` rather than emitting
		# straight at the router. Emitting directly left the stop path open across a
		# difficulty switch and made `select_difficulty` unreachable code.
		if unlocked:
			var index := i
			button.pressed.connect(func(): select_difficulty(index))
		_difficulty_row.add_child(button)


## `setDifficulty` in the PWA resets `_expandedAct` to -1 before re-rendering the map, so
## switching difficulty always collapses the stop path. The button above calls THIS, not
## `difficulty_selected` — the reset has to happen on the way in.
func select_difficulty(index: int) -> void:
	_expanded_act = -1
	difficulty_selected.emit(index)


func _difficulty_lock_reason(index: int) -> String:
	var prev_row: Array = (_state.data["bossesDefeated"] as Array)[index - 1]
	var remaining := 0
	for defeated in prev_row:
		if not bool(defeated):
			remaining += 1
	return "Zamceno - poraz jeste %d aktu na predchozi obtiznosti" % remaining


## One card per act, and for the expanded one the row of stop cards. Rendering matches
## the PWA's rule: a locked act is drawn only when it is the FIRST locked one, so the map
## never shows a wall of gates the player cannot reach anyway.
func _build_acts() -> void:
	var acts: Array = _data.acts()
	var difficulty := int(_state.data.get("difficulty", 0))
	var boss_row: Array = (_state.data["bossesDefeated"] as Array)[difficulty]
	var themes: Array = _data.table("DUNGEON_THEMES", [])

	var first_locked := -1
	for act_id in acts.size():
		var prev_done: bool = act_id == 0 or bool(boss_row[act_id - 1])
		if not prev_done:
			first_locked = act_id
			break

	for act_id in acts.size():
		var act: Dictionary = acts[act_id]
		var prev_done: bool = act_id == 0 or bool(boss_row[act_id - 1])
		var unlocked := act_id == 0 or prev_done
		var completed := bool(boss_row[act_id])
		if not unlocked and act_id != first_locked:
			continue
		var theme: Dictionary = themes[int(act.get("theme", 0))] if int(act.get("theme", 0)) < themes.size() else {}
		_list.add_child(_act_card(act_id, act, theme, unlocked, completed))
		# `renderMap` puts the dot scroll inside the SAME `.map-location-wrap` as the
		# card. The wrap is only emitted for an act that is unlocked and not completed —
		# and the port must not add an EMPTY box for a collapsed one either, because the
		# list's 8px separation applies between every child: two extra empty boxes pushed
		# the next card 16px down (PWA card 2 starts at y=210, the port at y=218).
		if unlocked and not completed and _expanded_act == act_id:
			_list.add_child(_stop_path(act_id, act, theme))


func _act_card(act_id: int, act: Dictionary, theme: Dictionary, unlocked: bool,
		completed: bool) -> Control:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 119)  # aspect-ratio 3/1 at 358 wide
	card.focus_mode = Control.FOCUS_NONE
	var border := Color(str(theme.get("border", "#666666")))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#000000")
	style.border_color = border if unlocked else Color("#2a2a2a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	for state_name in ["normal", "hover", "focus", "disabled"]:
		card.add_theme_stylebox_override(state_name, style)
	# `.map-location.completed` -> `opacity:0.7`; `.map-location.locked` -> `opacity:0.6`.
	# The locked value was MISSING here, and a locked card therefore came out at full
	# opacity while the reference dims it — measured on the live PWA's own computed style.
	if completed:
		card.modulate = Color(1, 1, 1, 0.7)
	elif not unlocked:
		card.modulate = Color(1, 1, 1, 0.6)

	# The card's own WASH, which the port used to draw as flat black and which is the reason
	# the unlocked act read as "not lit": the PWA's inline style is
	#   background:linear-gradient(135deg, ${theme.bg}cc, ${theme.bg}99 80%)
	# i.e. the THEME's colour at 80 % alpha fading to 60 % along the top-left -> bottom-right
	# diagonal. A `#000000` plate instead of it darkened the whole card, and it is the one
	# layer that sits UNDER `.map-loc-bg` (z-index 0), so it shows through the artwork's 35 %
	# of transparency.
	var wash := TextureRect.new()
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	var wash_colour := Color(str(theme.get("bg", "#000000")))
	var ramp := Gradient.new()
	ramp.set_color(0, Color(wash_colour.r, wash_colour.g, wash_colour.b, 0.8))
	ramp.set_color(1, Color(wash_colour.r, wash_colour.g, wash_colour.b, 0.6))
	var ramp_tex := GradientTexture2D.new()
	ramp_tex.gradient = ramp
	ramp_tex.fill = GradientTexture2D.FILL_LINEAR
	ramp_tex.fill_from = Vector2(0.0, 0.0)
	ramp_tex.fill_to = Vector2(1.0, 1.0)
	wash.texture = ramp_tex
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(wash)

	# `.map-loc-bg` — the act's dungeon art behind the card at 65% opacity.
	var art := TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = _theme_art(act_id, act, "dungeons")
	art.modulate = Color(1, 1, 1, 0.65)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(art)

	# `.map-loc-gate` — the locked act's gate art over the card.
	#
	# The PWA's rule is
	#   .map-loc-gate { position:absolute; inset:0; background-size:CONTAIN;
	#                   background-position:center; background-repeat:NO-REPEAT;
	#                   background-color:rgba(0,0,0,0.6); z-index:2 }
	# and the port drew it wrong in TWO ways, both of which darken the card:
	#
	#   1. `background-size:contain` is the whole point. The gate art is a 900x300 image and
	#      the card's content box is 356x117.3 — RATIOS 3.000 vs 3.036, so it fits almost
	#      exactly and only a sliver of the edges is bare. The port stretched instead.
	#   2. **The `background-color` and the image are not two visible layers.** Measured: the
	#      gate art has NO alpha channel (`mode=RGB`, both `.webp` and `.png`), so the art
	#      COVERS the 60 % black behind it and that colour is never seen. The port drew a
	#      `ColorRect(0, 0, 0, 0.6)` ON TOP of the art as a separate layer, so the locked
	#      card got the gate dimmed by 60 % AND the card dimmed again by the 0.6 modulate —
	#      measured against the live PWA as 13 against 27, i.e. 0.6 x 0.8.
	#
	# So: the veil goes UNDER the art (which is what `background-color` means in CSS) and the
	# card's own modulate carries the locked dimming.
	if not unlocked:
		var veil := ColorRect.new()
		veil.color = Color(0, 0, 0, 0.6)
		veil.set_anchors_preset(Control.PRESET_FULL_RECT)
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(veil)
		var gate := TextureRect.new()
		gate.set_anchors_preset(Control.PRESET_FULL_RECT)
		gate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gate.texture = _theme_art(act_id, act, "gates")
		gate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(gate)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -14
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	# `.map-loc-name` — 20px bold, and that is ALL the card carries. The PWA's
	# `.map-loc-info` holds the name alone; the port added a "N/10 zastavek" line the
	# reference does not have (measured: `.map-loc-info` is 258x24, exactly one 24px line
	# inside a 119px card, while the port's is 330px wide with 43px of content).
	var name_box := VBoxContainer.new()
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_box)
	var name_label := UIKit.UILabel.new()
	name_label.text = _act_name(act_id, act)
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color("#f0f0f0"))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_box.add_child(name_label)

	# `.map-loc-badge` — Play / Done / Locked on the theme's fill colour.
	row.add_child(_act_badge(theme, unlocked, completed))

	if unlocked and not completed:
		var id := act_id
		card.pressed.connect(func(): _toggle_act(id))
	elif unlocked and completed:
		card.pressed.connect(func(): _toggle_act(act_id))
	return card


func _act_badge(theme: Dictionary, unlocked: bool, completed: bool) -> Control:
	var badge := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(str(theme.get("border", "#666666")))
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	badge.add_theme_stylebox_override("panel", style)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var text := "Play"
	if completed:
		text = "Done"
	elif not unlocked:
		text = "Locked"
	var label := UIKit.UILabel.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(str(theme.get("bg", "#000000"))))
	badge.add_child(label)
	return badge


## `toggleActExpand` in the PWA — a pure view toggle. It does NOT call `saveGame()`;
## the only thing that moves `_expandedAct` on disk is `setDifficulty`, which resets it
## to -1. The port used to write the save here, which is a save write per tap.
func _toggle_act(act_id: int) -> void:
	_expanded_act = -1 if _expanded_act == act_id else act_id
	_clear(_list)
	_build_acts()


## The expanded act, reset on a difficulty switch.
##
## The PWA keeps `_expandedAct` on its save and persists it; the port does not. It used
## to (`_state.data["_expandedAct"]` plus a `save()` on every tap) and that was removed
## as not-the-PWA's-behaviour — `toggleActExpand` is a pure view toggle, and the only
## thing that moves the value on disk is `setDifficulty`, which zeroes it. This is the
## port's half of that: called from `select_difficulty` on the way in.
func reset_expanded() -> void:
	_expanded_act = -1


## `buildDotPath` — one `.stop-card` per zone with an arrow between them, plus the corner
## badge: a check when done, the fight counter while current, a lock when locked.
func _stop_path(act_id: int, act: Dictionary, theme: Dictionary) -> Control:
	if _expanded_act != act_id:
		return Control.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var total := int(act.get("zones", 10))
	var current := int(_state.data["locationProgress"][act_id])
	var fight := int(_state.data["areaFightProgress"][act_id])
	# The state accessors return Variant, and Godot treats an inferred-Variant as a parse
	# error here — everything read off the save needs an explicit type.
	var boss_defeated: bool = _state.is_boss_defeated(act_id)
	# Unlocking reads the HIGHEST stop ever reached, never `locationProgress` — farming an
	# earlier stop lowers the latter and must not lock the player out of what they reached.
	var reached: int = _state.max_progress(act_id)
	var names: Dictionary = _stop_names()

	for stop in total:
		var done: bool = boss_defeated or stop < reached
		var is_current: bool = not boss_defeated and stop == current
		var locked: bool = not boss_defeated and stop > reached
		var unlocked: bool = not locked and not done

		if stop > 0:
			box.add_child(_stop_arrow(theme, boss_defeated or stop <= reached))

		var card := Button.new()
		card.custom_minimum_size = STOP_CARD
		card.focus_mode = Control.FOCUS_NONE
		var border := Color(str(theme.get("border", "#888888")))
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#0a0a0a")
		style.border_color = Color("#333333") if locked else (Color(UIKit.GOLD) if is_current else border)
		# `.stop-card { border:2.5px solid #444 }` — 2.5px, not the 3px the port drew.
		style.set_border_width_all(2)
		style.set_corner_radius_all(10)
		for state_name in ["normal", "hover", "focus", "disabled"]:
			card.add_theme_stylebox_override(state_name, style)
		var pressed := style.duplicate()
		pressed.bg_color = Color("#1a1a1a")
		card.add_theme_stylebox_override("pressed", pressed)
		if locked:
			# `.stop-wrap.stop-locked { opacity:0.45 }` and `.stop-locked .stop-card
			# { filter:grayscale(1) }` — dim and desaturated, and not tappable.
			card.modulate = Color(0.75, 0.75, 0.75, 0.45)

		var art := TextureRect.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.texture = _stop_art(act_id, stop)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(art)

		# `.stop-label` — a bottom-anchored label over a gradient. The gradient is drawn
		# as a stack of black strips rather than a shader: same visual job, no shader.
		var veil := Control.new()
		veil.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		veil.offset_top = -90
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(veil)
		for step in 18:
			var t := float(step) / 18.0
			var strip := ColorRect.new()
			strip.color = Color(0, 0, 0, 0.85 * (1.0 - t) + 0.15)
			strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
			strip.offset_top = t * 90.0
			strip.offset_bottom = (t + 1.0 / 18.0) * 90.0
			strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			veil.add_child(strip)

		var name_label := UIKit.UILabel.new()
		name_label.text = _stop_name(names, act_id, stop)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		name_label.offset_top = -46
		name_label.offset_bottom = -6
		name_label.offset_left = 10
		name_label.offset_right = -10
		name_label.add_theme_font_size_override("font_size", 19)
		name_label.add_theme_color_override("font_color", Color("#ffffff"))
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name_label)

		card.add_child(_stop_badge(done, is_current, locked, fight, boss_defeated, reached, stop))

		if not locked:
			var id := act_id
			var index := stop
			card.pressed.connect(func(): enter_stop.emit(id, index))
		box.add_child(card)
	return box


func _stop_badge(done: bool, is_current: bool, locked: bool, fight: int,
		boss_defeated: bool, reached: int, stop: int) -> Control:
	# `.stop-badge { min-width:26px; height:22px; padding:0 5px; border-radius:11px;
	#                font-size:12px }` — a SMALL pill that hugs its content. The port used
	# to write the words "Hotovo"/"Zamceno" into a fixed 74px box; the PWA's badge is
	# 26px wide because its content is a glyph, a counter, or a lock. Keep the PWA's
	# vocabulary and let the pill size itself: a word would not fit the shape at all.
	var text := "%d/10" % mini(fight, 10)
	var colour := UIKit.GOLD
	var lock_icon := false
	if done:
		# `.stop-badge-done` — a check mark, drawn as text. It is the PWA's own glyph and
		# DejaVu HAS it; the emoji below it does not.
		text = "\u2713"
		colour = "#2ecc71"
	elif locked:
		# The PWA writes 🔒 here. DejaVu has no emoji, so the raw codepoint painted as
		# garbage; a generated padlock icon carries the same meaning in the port's style.
		text = ""
		colour = "#666666"
		lock_icon = true
	elif is_current:
		text = "%d/10" % mini(fight, 10)
	else:
		# A stop behind the player is complete, so it shows a full counter rather than a
		# partial one.
		text = "%d/10" % (10 if stop < reached else mini(fight, 10))

	var badge := PanelContainer.new()
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_top = 6
	badge.offset_right = -6
	badge.offset_bottom = 28
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size = Vector2(26, 22)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_END
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.75)
	style.border_color = Color(colour)
	style.set_border_width_all(1)
	style.set_corner_radius_all(11)
	style.content_margin_left = 5
	style.content_margin_right = 5
	badge.add_theme_stylebox_override("panel", style)
	var label := UIKit.UILabel.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(colour))
	badge.add_child(label)
	if lock_icon:
		# A 22px pill with a real icon in it, centred. The PWA's 🔒 is 12px of glyph; the
		# generated icon is a 256px square, so it is scaled into a 12px box.
		var icon := TextureRect.new()
		icon.texture = UIKit.load_texture("assets/menu-icons/lock.png")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(12, 12)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_child(icon)
	return badge


## `.stop-arrow` — a CSS triangle between two stops. `.stop-arrow { width:100%; height:
## 20px (border-top) ; margin:2px 0; opacity:0.35; filter:grayscale(1) }`, an active one
## is the act's colour at full opacity. Drawn rather than emoji, per Jan's rule.
##
## The triangle's own height is its `border-top` (20px); the 2px top and bottom margins
## are what a VBoxContainer cannot express, so they are added to the reserve instead.
func _stop_arrow(theme: Dictionary, active: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 24)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var arrow := Triangle.new()
	arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	arrow.offset_top = 2
	arrow.offset_bottom = -2
	arrow.colour = Color(str(theme.get("border", "#888888"))) if active else Color("#888888")
	arrow.dim = not active
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(arrow)
	return holder


class Triangle:
	extends Control

	var colour := Color("#888888")
	var dim := false

	func _draw() -> void:
		var centre := size * 0.5
		var half := minf(14.0, size.x * 0.5)
		var height := minf(20.0, size.y)
		var top := centre.y - height * 0.5
		var bottom := centre.y + height * 0.5
		var points := PackedVector2Array([
			Vector2(centre.x - half, top),
			Vector2(centre.x + half, top),
			Vector2(centre.x, bottom),
		])
		var fill := colour
		if dim:
			# `.stop-arrow { opacity:0.35; filter:grayscale(1) }` — a dimmed arrow is a
			# GREY arrow, not a faded coloured one.
			fill = Color("#888888", 0.35)
		draw_colored_polygon(points, fill)


## Stop art, `getStopImage` in the PWA: acts 0 and 1 have generated images, the rest use
## a per-act placeholder. Falls back to the placeholder rather than showing nothing.
func _stop_art(act_id: int, stop: int) -> Texture2D:
	var generated := "assets/stops/stop_act%d_%d.webp" % [act_id, stop]
	var loaded := UIKit.load_texture(generated)
	if loaded != null:
		return loaded
	return UIKit.load_texture("assets/stops/placeholder_act%d.png" % act_id)


func _theme_art(act_id: int, act: Dictionary, folder: String) -> Texture2D:
	# The PWA keyed the art off the THEME NAME, not the act id: ACTS order is
	# [forest, desert, frost, undead, hell] while MONSTER_DB is a different order, and
	# the file names follow the theme.
	var theme_names := ["forest", "desert", "frost", "undead", "hell"]
	var theme := int(act.get("theme", act_id))
	var name: String = theme_names[theme] if theme >= 0 and theme < theme_names.size() else "forest"
	var path := "assets/%s/%s.webp" % [folder, name] if folder == "dungeons" else "assets/gates/gate_%s.webp" % name
	var loaded := UIKit.load_texture(path)
	if loaded != null:
		return loaded
	# `.png` copies exist for both folders next to the `.webp` originals.
	var png := path.replace(".webp", ".png")
	return UIKit.load_texture(png)


## The act's display name. The PWA's ACTS carry an English `name`; the port keeps it
## rather than translating, since monster and location names stay English by Jan's rule.
func _act_name(act_id: int, act: Dictionary) -> String:
	return str(act.get("name", "Act %d" % (act_id + 1)))


## `STOP_NAMES_EN` from the PWA — an OBJECT keyed by act id, not an array. Its keys are
## strings ("0".."4") once they come through JSON, so an `int` index finds nothing and
## every stop falls back to "Zastavka N". Typing the return as `Array` here was worse
## than useless: the Dictionary is not an Array, so the call ABORTED and the map built
## no stop labels at all.
func _stop_names() -> Dictionary:
	var raw: Variant = _data.table("STOP_NAMES_EN", {})
	return raw if raw is Dictionary else {}


func _stop_name(names: Dictionary, act_id: int, stop: int) -> String:
	var per_act: Variant = names.get(str(act_id), null)
	if per_act is Array and stop < (per_act as Array).size():
		return str(per_act[stop])
	return "Zastavka %d" % (stop + 1)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
