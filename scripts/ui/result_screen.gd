extends Control
class_name ResultScreen
## ResultScreen — the END-OF-FIGHT page, for the survivor run.
##
## The arena's result page (`arena_screen.gd`: `#resultScreen` in the PWA) is the reference
## this is built from: black page, the act's artwork across the top with VITEZSTVI / the act's
## name over it, the hero's HP readout on the art's bottom edge, the loot rows directly under
## the art, and the action tiles on the page's bottom. Every rect below is the SAME measured
## geometry as the arena's (`_layout_result_page()`, `_make_loot_row()`, `_make_action_tile()`)
## — Jan's ask was "identicky jako u předešlého soubojového systému", and the arena's numbers
## are the ones measured against the PWA.
##
## ⚠️  This is a SECOND implementation of that page, not a refactor of it. The arena's page is
## entangled with `battle` and 86 test assertions read its `_result_*` fields, so extracting it
## in the same slice as the survivor result would have risked the fight that already works.
## If the two ever disagree, `arena_screen.gd` is the source of truth (its comments carry the
## measured values) — fix this file to match, never the other way round.
##
## Everything is DATA IN: `present(payload)` takes what the finished fight paid out and who
## won. The screen owns no rules.

const UIKit := preload("res://scripts/ui/ui_kit.gd")
const UIFonts := preload("res://scripts/ui/ui_fonts.gd")
const ItemStats := preload("res://scripts/items/item_stats.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")

const COIN_ICON := "assets/items/coin_gold.png"
## `.result-tile { min-width:60px; max-width:90px; aspect-ratio:1 }` — 87 on a 390px page with
## four tiles, and the cap only binds on a wider canvas.
const RESULT_TILE := 84.0
const LOOT_ROW_FONT := 17
const LOOT_ROW_PAD := 5
const LOOT_ROW_RULE := 1

const C_TEXT := Color("#ffffff")
const C_SUB := Color("#dddddd")
const C_ENEMY_HP := Color("#d4524a")

signal closed(action: String)

var _state = null
var _resolve: Callable
var _payload: Dictionary = {}

var _bg_button: Button
var _art_box: Control
var _art: TextureRect
var _defeat_art: TextureRect
var _overlay: VBoxContainer
var _title: Label
var _sub: Label
var _stats: VBoxContainer
var _hp_line: Label
var _stat_line: Label
var _loot_pad: MarginContainer
var _loot_list: VBoxContainer
var _tiles_holder: MarginContainer
var _tiles: HBoxContainer
var _cache: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


# ============================================================================ build

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#000000")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# The whole page is the tap target (the PWA's `#resultScreen` has its own onclick): a tap
	# that misses a tile closes the page the way "back" does.
	_bg_button = Button.new()
	_bg_button.focus_mode = Control.FOCUS_NONE
	_bg_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	var empty := StyleBoxEmpty.new()
	for state_name in ["normal", "hover", "focus", "pressed", "disabled"]:
		_bg_button.add_theme_stylebox_override(state_name, empty)
	_bg_button.pressed.connect(func(): _close("back"))
	add_child(_bg_button)

	_art_box = Control.new()
	_art_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art_box)

	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_box.add_child(_art)

	_defeat_art = TextureRect.new()
	_defeat_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_defeat_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_defeat_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_defeat_art.visible = false
	_art_box.add_child(_defeat_art)

	_overlay = VBoxContainer.new()
	_overlay.add_theme_constant_override("separation", 2)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_title = _label("", 26, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
	_overlay.add_child(_title)
	_sub = _label("", 14, C_SUB, HORIZONTAL_ALIGNMENT_CENTER)
	_overlay.add_child(_sub)

	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override("separation", 4)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stats)
	_hp_line = _label("", 15, C_ENEMY_HP, HORIZONTAL_ALIGNMENT_CENTER)
	_stats.add_child(_hp_line)
	_stat_line = _label("", 15, Color("#9ad0e8"), HORIZONTAL_ALIGNMENT_CENTER)
	_stats.add_child(_stat_line)

	_loot_pad = MarginContainer.new()
	_loot_pad.add_theme_constant_override("margin_left", 10)
	_loot_pad.add_theme_constant_override("margin_right", 10)
	_loot_pad.add_theme_constant_override("margin_top", 6)
	_loot_pad.add_theme_constant_override("margin_bottom", 4)
	_loot_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_loot_pad)
	_loot_list = VBoxContainer.new()
	_loot_list.add_theme_constant_override("separation", 0)
	_loot_pad.add_child(_loot_list)

	_tiles_holder = MarginContainer.new()
	_tiles_holder.add_theme_constant_override("margin_left", 12)
	_tiles_holder.add_theme_constant_override("margin_right", 12)
	_tiles_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tiles_holder)
	_tiles = HBoxContainer.new()
	_tiles.alignment = BoxContainer.ALIGNMENT_CENTER
	_tiles.add_theme_constant_override("separation", 6)
	_tiles_holder.add_child(_tiles)


# ============================================================================ present

## Show the page for a finished fight.
##
## paylooad keys:
##   won        bool
##   title      the page's big line ("Vitezstvi" / "Prohra")
##   sub        the line under it
##   art        res:// path of the win artwork (ignored on a defeat: the game's own
##              `result_defeat.png` is used, exactly as the arena does)
##   hp_line    e.g. "HP 148/160"
##   stat_line  the second readout (the survivor run has no mana: it reports the area)
##   rows       Array of item dictionaries, plus {"gold": n, "name": "Zlato xN"} appended here
##   gold       int
##   tiles      Array of {label, icon, action} — `action` is the signal's payload
func present(state, resolve: Callable, payload: Dictionary) -> void:
	_state = state
	_resolve = resolve
	_payload = payload
	var won := bool(payload.get("won", false))

	_art.visible = won
	_defeat_art.visible = not won
	_art.texture = _load(str(payload.get("art", ""))) if won else null
	_defeat_art.texture = _load("assets/result_defeat.png") if not won else null

	_title.text = str(payload.get("title", "Vitezstvi" if won else "Prohra"))
	_sub.text = str(payload.get("sub", ""))
	_hp_line.text = str(payload.get("hp_line", ""))
	_stat_line.text = str(payload.get("stat_line", ""))

	_fill_loot(payload)
	_fill_tiles(payload)

	visible = true
	_place_tiles(size, _tiles_h())
	call_deferred("_layout_page")


func _fill_loot(payload: Dictionary) -> void:
	for child in _loot_list.get_children():
		_loot_list.remove_child(child)
		child.queue_free()
	var rows: Array = (payload.get("rows", []) as Array).duplicate()
	var gold := int(payload.get("gold", 0))
	if gold > 0:
		rows.append({"gold": gold, "name": "Zlato x%d" % gold, "id": "gold", "iconImg": COIN_ICON})
	if rows.is_empty():
		_loot_list.add_child(_label("Zadne predmety", 15, Color("#777777"), HORIZONTAL_ALIGNMENT_CENTER))
		return
	for row in rows:
		_loot_list.add_child(_loot_row(row))


## `.loot-scroll-item { padding:5px 8px; font-size:15px; gap:10px; border-bottom:1px solid
## #1a1a1a }` — the hairline lives in the VBox, not a MarginContainer (a MarginContainer
## forces every child to the full box and would draw the 1px line over the whole row).
func _loot_row(row_data: Dictionary) -> Control:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", LOOT_ROW_PAD)
	pad.add_theme_constant_override("margin_bottom", LOOT_ROW_PAD)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	pad.add_child(column)
	var sides := MarginContainer.new()
	sides.add_theme_constant_override("margin_left", 8)
	sides.add_theme_constant_override("margin_right", 8)
	column.add_child(sides)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	sides.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_path: String = COIN_ICON if row_data.has("gold") else ItemStats.icon_path(row_data)
	icon.texture = _load(icon_path) if icon_path != "" else null
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var colour: Color = Color(UIKit.GOLD) if row_data.has("gold") else ItemStats.quality_color(row_data)
	var name_label := _label(str(row_data.get("name", row_data.get("id", ""))),
		LOOT_ROW_FONT, colour, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)
	var line := ColorRect.new()
	line.color = Color("#1a1a1a")
	line.custom_minimum_size = Vector2(0, LOOT_ROW_RULE)
	line.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)
	return pad


func _fill_tiles(payload: Dictionary) -> void:
	for child in _tiles.get_children():
		_tiles.remove_child(child)
		child.queue_free()
	for tile in (payload.get("tiles", []) as Array):
		var data: Dictionary = tile
		_tiles.add_child(_action_tile(str(data.get("icon", "")), str(data.get("label", "")),
			str(data.get("action", ""))))


## One `.result-tile`: a square, the art filling it, the label on a 60 % black plate along the
## bottom. `SHRINK_CENTER` vertically, because an HBoxContainer would otherwise stretch the
## tile to the row's height and the squares would read as tall rectangles.
func _action_tile(icon_path: String, label_text: String, action: String) -> Button:
	var tile := Button.new()
	tile.add_to_group("no_click_sfx")
	tile.custom_minimum_size = Vector2(RESULT_TILE, RESULT_TILE)
	tile.focus_mode = Control.FOCUS_NONE
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := _flat_style("#000000", "#333333", 10)
	style.set_border_width_all(2)
	for state_name in ["normal", "hover", "focus", "disabled"]:
		tile.add_theme_stylebox_override(state_name, style)
	tile.add_theme_stylebox_override("pressed", _flat_style("#1a1a1a", UIKit.GOLD, 10))
	tile.pressed.connect(func(): _close(action))

	var art := _load(icon_path)
	if art != null:
		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		icon.texture = art
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(icon)

	var caption := _label(label_text, 13, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -24
	caption.offset_bottom = -4
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0, 0, 0, 0.6)
	plate.set_corner_radius_all(3)
	caption.add_theme_stylebox_override("normal", plate)
	tile.add_child(caption)
	tile.set_meta("label", label_text)
	return tile


func _close(action: String) -> void:
	visible = false
	closed.emit(action)


# ============================================================================ layout

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_place_tiles(size, _tiles_h())
		_layout_page()


## `.result-bottom { padding:10px 12px }` + a tile: the row's own height, tile included.
func _tiles_h() -> float:
	var h := 20.0
	if _tiles.get_child_count() > 0:
		h += _tile_size()
	return h


func _tile_size() -> float:
	var count := maxi(_tiles.get_child_count(), 1)
	var page_w := size.x if size.x > 0.0 else 390.0
	var usable := page_w - 24.0 - 6.0 * float(count - 1)
	return clampf(usable / float(count), 60.0, 90.0)


func _place_tiles(page: Vector2, tiles_h: float) -> void:
	_tiles_holder.size = Vector2(maxf(page.x, 1.0), tiles_h)
	_tiles_holder.position = Vector2(0.0, round(page.y - tiles_h))
	var side := _tile_size()
	for child in _tiles.get_children():
		if child is Control:
			(child as Control).custom_minimum_size = Vector2(side, side)


## The same geometry as `arena_screen._layout_result_page()`: the win art takes the full width
## and up to `page - tiles - 160` of height, its title overlays its top, the HP readout sits on
## its bottom edge and the loot list starts exactly at the art's bottom edge.
func _layout_page() -> void:
	if not visible:
		return
	var page := size
	if page.x <= 0.0 or page.y <= 0.0:
		page = Vector2(390.0, 844.0)
	var tiles_h := _tiles_h()
	_place_tiles(page, tiles_h)
	var top_h := page.y - tiles_h

	if _defeat_art.visible:
		var tex: Texture2D = _defeat_art.texture
		if tex == null:
			return
		# `max-width:90vw; max-height:50vh` never upscales: the 256px art draws at 256.
		var cap := Vector2(page.x * 0.90, page.y * 0.50)
		var scale := minf(1.0, minf(cap.x / float(tex.get_width()), cap.y / float(tex.get_height())))
		var box := Vector2(float(tex.get_width()), float(tex.get_height())) * scale
		_defeat_art.size = box
		_defeat_art.position = Vector2.ZERO
		var text_h := _overlay.get_combined_minimum_size().y
		_overlay.size = Vector2(page.x - 24.0, text_h)
		_stats.visible = false
		_loot_pad.visible = false
		var block := box.y + 8.0 + text_h
		var lift := maxf(0.0, round((top_h - block) * 0.5))
		_art_box.position = Vector2(round((page.x - box.x) * 0.5), lift)
		_art_box.size = box
		_overlay.position = Vector2(12.0, round(box.y + 8.0 + lift))
		return

	var tex2: Texture2D = _art.texture
	if tex2 == null:
		return
	var scale2 := minf(page.x / float(tex2.get_width()), top_h / float(tex2.get_height()))
	var box2 := Vector2(float(tex2.get_width()), float(tex2.get_height())) * scale2
	_art.size = box2
	_art.position = Vector2.ZERO
	_art_box.size = box2
	_art_box.position = Vector2(round((page.x - box2.x) * 0.5), 1.0)
	_overlay.size = Vector2(box2.x - 24.0, 0.0)
	_overlay.position = Vector2(round(_art_box.position.x + 12.0), round(_art_box.position.y + 10.0))
	_stats.visible = true
	var stats_h := _stats.get_combined_minimum_size().y
	_stats.size = Vector2(box2.x, stats_h)
	_stats.position = Vector2(round(_art_box.position.x),
		round(_art_box.position.y + box2.y - stats_h - 10.0))
	_loot_pad.visible = true
	var loot_h := _loot_pad.get_combined_minimum_size().y
	_loot_pad.size = Vector2(page.x, loot_h)
	_loot_pad.position = Vector2(0.0, round(_art_box.position.y + box2.y))


# ============================================================================ helpers

## The arena's own `_label()`: a plain `Label` with a font + colour override and no
## interaction. NOT `UIKit.label()` here — that returns a `FlexLabel`, whose minimum width is
## decided on its own reshape pass, and inside an `HBoxContainer` row it came out 0 wide with
## `clip_text` on, so every loot row drew its icon and NOTHING beside it.
func _label(text: String, size: int, colour: Color,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UIFonts.get_font(size, bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _flat_style(bg: String, border: String, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(bg)
	style.border_color = Color(border)
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	return style


## Cached, and a missing file is reported rather than silently blank.
func _load(path: String) -> Texture2D:
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		push_warning("ResultScreen: missing texture '%s'" % path)
	_cache[path] = tex
	return tex
