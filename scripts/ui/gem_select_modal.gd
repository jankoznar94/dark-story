extends Control
class_name GemSelectModal
## GemSelectModal — the PWA's `#gemSelectModal`: pick a gem or a jewel out of the bag for
## one socket.
##
## This is a SEPARATE modal from the item detail on purpose, and the port had it wrong the
## other way round: it listed every gem from the bag UNDER the socket circles, inside the
## item detail. The reference does not — `.inv-item-overlay-sockets` holds the circles and
## nothing else, and an empty circle closes the item overlay and opens this list.
##
## Measured from the live PWA (`public/style.css`):
##
##   .gem-select-modal           fixed inset:0; background:rgba(0,0,0,0.8); centred
##   .gem-select-modal-content   background:#000; border:1px solid #444; radius 12;
##                               padding:20px; max-width:340px; width:90%; max-height:80vh
##   .gem-select-modal-title     18px bold #ddd
##   .gem-select-modal-close     20px #888
##   .gem-select-modal-grid      grid-template-columns:repeat(4,1fr); gap:8px
##   .gem-select-item            column; centred; padding:8px 4px; border:1px solid #333;
##                               radius 8; background:#0a0a0a
##   .gem-select-item-icon       28px (an icon image here, not a glyph)
##   .gem-select-item-name       11px #aaa centred
##   gem stats                   10px, the Weapon / Armor+Helm / Shield family blocks
##   .gem-select-modal-empty     "No gems in inventory." 14px #666
##
## No hover state anywhere (Jan's rule for this mobile PWA); the only feedback is the
## button's own pressed style.

const UIKit := preload("res://scripts/ui/ui_kit.gd")
const ItemDetail := preload("res://scripts/items/item_detail.gd")
const ItemStats := preload("res://scripts/items/item_stats.gd")

## A gem cell was tapped. The caller does the actual insert, so this modal stays pure UI.
signal gem_chosen(gem_id: String)
## The modal closed without a choice (the X or a tap on the dim).
signal dismissed

const MAX_WIDTH := 340.0
const PAD := 20.0
const GRID_GAP := 8.0
const COLS := 4
const CELL_MIN := Vector2(64, 78)
const RADIUS := 12
## One finger is delivered twice (the synthesised mouse event plus the touch), and this
## modal is opened BY a tap — so a second `pressed` inside the same gesture would insert a
## gem into the next socket as well. Ignore a repeat choice inside this window.
const CHOOSE_GUARD_MS := 300

var _data: Node
var _find_item: Callable

var _dim: ColorRect
var _panel: PanelContainer
var _grid: GridContainer
var _empty: Label
var _content: VBoxContainer

var _bag: Array = []
var _armed_socket := -1
var _settle := 0
var _last_choose_msec := -1


func _init(game_data: Node, find_item: Callable) -> void:
	_data = game_data
	_find_item = find_item


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	set_process(false)


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.8)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#000000")
	style.border_color = Color("#444444")
	style.set_border_width_all(1)
	style.set_corner_radius_all(RADIUS)
	style.set_content_margin_all(PAD)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	_panel.add_child(_content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_content.add_child(header)
	var title := UIKit.label("Vyber gem", 18, "#dddddd", HORIZONTAL_ALIGNMENT_LEFT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_build_close())

	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", int(GRID_GAP))
	_grid.add_theme_constant_override("v_separation", int(GRID_GAP))
	_content.add_child(_grid)

	_empty = UIKit.label("V batohu neni zadny gem.", 14, "#666666", HORIZONTAL_ALIGNMENT_CENTER)
	_content.add_child(_empty)


## `.gem-select-modal-close { color:#888; font-size:20px; padding:2px 6px }`, with a 44px
## touch target around it — the visible glyph is deliberately the PWA's own size.
func _build_close() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(28, 28)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.add_theme_color_override("font_color", Color("#888888"))
	close_btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	var blank := StyleBoxEmpty.new()
	for state_name in ["normal", "hover", "focus", "pressed", "disabled"]:
		close_btn.add_theme_stylebox_override(state_name, blank)
	close_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	close_btn.pressed.connect(close)
	holder.add_child(close_btn)

	var hit := Button.new()
	hit.focus_mode = Control.FOCUS_NONE
	for state_name in ["normal", "hover", "focus", "pressed", "disabled"]:
		hit.add_theme_stylebox_override(state_name, blank)
	var over := 8.0
	hit.offset_left = -over
	hit.offset_top = -over
	hit.offset_right = 28.0 + over
	hit.offset_bottom = 28.0 + over
	hit.pressed.connect(close)
	holder.add_child(hit)
	return holder


## Show the picker for the bag as it is NOW. `socket_index` only decides the log/armed
## state; the insert itself is the caller's `gem_chosen` handler.
func open(inventory: Array, socket_index: int) -> void:
	_bag = inventory
	_armed_socket = socket_index
	_last_choose_msec = Time.get_ticks_msec()
	_rebuild()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	_layout()
	_settle = 0


func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	dismissed.emit()


func armed_socket() -> int:
	return _armed_socket


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
	elif event is InputEventScreenTouch and event.pressed:
		close()


func _rebuild() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	var shown := 0
	for entry in _bag:
		var item_id: String = str(entry.get("id", "")) if entry is Dictionary else str(entry)
		var item: Dictionary = _find_item.call(item_id)
		if str(item.get("type", "")) not in ["gem", "jewel"]:
			continue
		_grid.add_child(_gem_cell(item, item_id))
		shown += 1
	_empty.visible = shown == 0


## `.gem-select-item`: icon, name, then the stat block the PWA prints for that gem family
## (`buildGemStatsHtml`) or the jewel's affix list.
func _gem_cell(item: Dictionary, item_id: String) -> Control:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = CELL_MIN
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#0a0a0a")
	normal.border_color = Color("#333333")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	normal.set_content_margin_all(0)
	var pressed := normal.duplicate()
	pressed.bg_color = Color("#111111")
	pressed.border_color = Color("#ffd700")
	# NO hover and no focus style: the PWA's `:hover` is a desktop-only cue and this game
	# is a phone PWA first. Every state shares the normal box.
	for state_name in ["normal", "hover", "focus", "disabled"]:
		button.add_theme_stylebox_override(state_name, normal)
	button.add_theme_stylebox_override("pressed", pressed)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 4)
	button.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var icon_holder := Control.new()
	icon_holder.custom_minimum_size = Vector2(32, 32)
	icon_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load_texture(ItemStats.icon_path(item))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(icon)
	box.add_child(icon_holder)

	var lines: Array = ItemDetail.build_text(item, _data, true).split("\n")
	var name_text := str(lines[0]) if lines.size() > 0 else str(item.get("name", "Gem"))
	var name_label := UIKit.label(name_text, 11, "#aaaaaa", HORIZONTAL_ALIGNMENT_CENTER)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	if lines.size() > 1:
		var stats := "\n".join(lines.slice(1))
		var stats_label := UIKit.label(stats, 9, "#888888", HORIZONTAL_ALIGNMENT_CENTER)
		stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(stats_label)

	var gem_id := item_id
	button.pressed.connect(func(): _choose(gem_id))
	return button


func _choose(gem_id: String) -> void:
	var now := Time.get_ticks_msec()
	if _last_choose_msec >= 0 and now - _last_choose_msec < CHOOSE_GUARD_MS:
		return
	_last_choose_msec = now
	close()
	gem_chosen.emit(gem_id)


## `.gem-select-modal-content { max-width:340px; width:90% }`, height content-driven.
func _layout() -> void:
	var view := size
	if view.x <= 0.0:
		return
	var want_w: float = minf(MAX_WIDTH, maxf(240.0, view.x * 0.9))
	var inner := _content.get_combined_minimum_size()
	var want_h: float = minf(inner.y + PAD * 2.0, view.y * 0.8)
	_panel.offset_left = -want_w * 0.5
	_panel.offset_right = want_w * 0.5
	_panel.offset_top = -want_h * 0.5
	_panel.offset_bottom = want_h * 0.5


func _process(_delta: float) -> void:
	if _settle >= 2:
		set_process(false)
		return
	_settle += 1
	_layout()


func _load_texture(path: String) -> Texture2D:
	if path == "":
		return null
	var full := path if path.begins_with("res://") else "res://" + path
	if not ResourceLoader.exists(full):
		return null
	return load(full)
