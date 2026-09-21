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

## 390 - 32 = 358 wide. `.stop-card` is a square, so the art is 358 tall; the label sits
## over the bottom of it.
const STOP_CARD := Vector2(358, 358)

var _data: Node
var _state
var _find_item: Callable

var _list: VBoxContainer
var _difficulty_row: HBoxContainer
var _difficulty_note: Label
## Which act's stop path is open. The PWA kept this on the save (`_expandedAct`); here it
## is screen state, because it is a view setting and a save field per view is noise.
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

	var header := UIKit.back_header("Mapa")
	header["back"].pressed.connect(func(): back_pressed.emit())
	column.add_child(header["root"])

	# `.diff-selector` — the port's own note line sits under it so a locked difficulty
	# says what it is waiting for.
	_difficulty_row = HBoxContainer.new()
	_difficulty_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_difficulty_row.add_theme_constant_override("separation", 6)
	column.add_child(_difficulty_row)
	_difficulty_note = UIKit.label("", 12, UIKit.DIM)
	_difficulty_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_difficulty_note)

	# `.map-scroll`
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_list)


func refresh() -> void:
	_refresh_difficulty()
	_clear(_list)
	var acts: Array = _data.acts()
	_read_expanded(acts)
	_build_acts()


## `.diff-selector` — three buttons. A LOCKED one is drawn dim with the lock reason in
## its tooltip rather than hidden, because "what am I working towards" is the point.
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
		button.custom_minimum_size = Vector2(0, 34)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 13)
		# `.diff-btn { padding:6px 14px; border:1px solid #333; border-radius:6px;
		#             background:#111; color:#888 }`
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
			var index := i
			button.pressed.connect(func(): difficulty_selected.emit(index))
		_difficulty_row.add_child(button)

	var cur: Dictionary = diffs[current] if current < diffs.size() else {}
	var act_id: int = _state.first_uncompleted_act()
	if act_id < 0:
		_difficulty_note.text = "Obtiznost %d z %d - vsechny akty dokoncene, prepni vys." % [current + 1, diffs.size()]
	else:
		_difficulty_note.text = "Obtiznost %d z %d - uroven monster %d-%d, sila monster x%s" % [
			current + 1, diffs.size(),
			int(cur.get("monsterLvMin", 1)), int(cur.get("monsterLvMax", 1)),
			str(cur.get("mult", 1.0))]


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
		if unlocked and not completed:
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
	card.modulate = Color(1, 1, 1, 0.7) if completed else Color(1, 1, 1, 1)

	# `.map-loc-bg` — the act's dungeon art behind the card at 65% opacity.
	var art := TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = _theme_art(act_id, act, "dungeons")
	art.modulate = Color(1, 1, 1, 0.65)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(art)

	# `.map-loc-gate` — a locked act gets its gate art over the top, on 60% black.
	if not unlocked:
		var gate := TextureRect.new()
		gate.set_anchors_preset(Control.PRESET_FULL_RECT)
		gate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gate.texture = _theme_art(act_id, act, "gates")
		gate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(gate)
		var veil := ColorRect.new()
		veil.color = Color(0, 0, 0, 0.6)
		veil.set_anchors_preset(Control.PRESET_FULL_RECT)
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(veil)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -14
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	# `.map-loc-name` — 20px bold.
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
	var sub := UIKit.UILabel.new()
	sub.text = "%d/%d zastavek" % [int(_state.max_progress(act_id)), int(act.get("zones", 10))]
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color("#cccccc"))
	name_box.add_child(sub)

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


func _toggle_act(act_id: int) -> void:
	# `state._expandedAct = actId` in the PWA — saved, so returning to the map reopens the
	# act the player was working on instead of collapsing everything.
	_state.data["_expandedAct"] = -1 if _expanded_act == act_id else act_id
	_state.save()
	_expanded_act = int(_state.data["_expandedAct"])
	_clear(_list)
	_build_acts()


## The expanded act, kept on the save the way the PWA's `_expandedAct` was. A new save
## expands the first act that is not finished, so the map is useful on first open.
func _read_expanded(acts: Array) -> void:
	var stored: Variant = _state.data.get("_expandedAct", null)
	if stored != null:
		_expanded_act = int(stored)
		return
	var difficulty := int(_state.data.get("difficulty", 0))
	var boss_row: Array = (_state.data["bossesDefeated"] as Array)[difficulty]
	for act_id in acts.size():
		if not bool(boss_row[act_id]):
			_expanded_act = act_id
			return
	_expanded_act = -1


## `buildDotPath` — one `.stop-card` per zone with an arrow between them, plus the corner
## badge: a check when done, the fight counter while current, a lock when locked.
func _stop_path(act_id: int, act: Dictionary, theme: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _expanded_act != act_id:
		return box

	var total := int(act.get("zones", 10))
	var current := int(_state.data["locationProgress"][act_id])
	var fight := int(_state.data["areaFightProgress"][act_id])
	# The state accessors return Variant, and Godot treats an inferred-Variant as a parse
	# error here — everything read off the save needs an explicit type.
	var boss_defeated: bool = _state.is_boss_defeated(act_id)
	# Unlocking reads the HIGHEST stop ever reached, never `locationProgress` — farming an
	# earlier stop lowers the latter and must not lock the player out of what they reached.
	var reached: int = _state.max_progress(act_id)
	var names: Array = _stop_names()

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
		style.set_border_width_all(3)
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
	var text := "%d/10" % (mini(fight, 10) if is_current else 10)
	var colour := UIKit.GOLD
	if done:
		text = "Hotovo"
		colour = "#2ecc71"
	elif locked:
		text = "Zamceno"
		colour = "#666666"
	if not done and not is_current and not locked:
		text = "%d/10" % (10 if stop < reached else mini(fight, 10))

	var badge := PanelContainer.new()
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -80
	badge.offset_top = 6
	badge.offset_right = -6
	badge.offset_bottom = 30
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.75)
	style.border_color = Color(colour)
	style.set_border_width_all(1)
	style.set_corner_radius_all(11)
	badge.add_theme_stylebox_override("panel", style)
	var label := UIKit.UILabel.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(colour))
	badge.add_child(label)
	return badge


## `.stop-arrow` — a CSS triangle between two stops. Grey until the next stop is
## reachable, then in the act's colour. Drawn rather than emoji, per Jan's rule.
func _stop_arrow(theme: Dictionary, active: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 20)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var arrow := Triangle.new()
	arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
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


## `STOP_NAMES_EN` from the PWA, one array per act.
func _stop_names() -> Array:
	return _data.table("STOP_NAMES_EN", [])


func _stop_name(names: Array, act_id: int, stop: int) -> String:
	if act_id < names.size():
		var per_act = names[act_id]
		if per_act is Array and stop < (per_act as Array).size():
			return str(per_act[stop])
	return "Zastavka %d" % (stop + 1)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
