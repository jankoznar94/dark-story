extends RefCounted
class_name UIKit
## UIKit — the few widgets the item screens share: flat buttons, labels, an item tooltip
## and the back-header every full-page screen starts with.
##
## The rules are Jan's and they are the same in every screen: black background, a thin
## grey border, no rounded corners, NO hover or focus styling (one style object for
## every state, so a tap has no visual side effect beyond the press), no emoji.
##
## Kept as static functions rather than a scene: a .tscn would be a second place for
## these styles to live and they would drift.

const ItemDetail := preload("res://scripts/items/item_detail.gd")
const ItemStats := preload("res://scripts/items/item_stats.gd")

const BG := "#000000"
const BORDER := "#333333"
const TEXT := "#d0d0d0"
const DIM := "#888888"
const GOLD := "#f1c40f"
const BAD := "#c0392b"
const MOD_BLUE := "#4a7dff"


static func label(text: String, size: int = 14, colour: String = TEXT,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(colour))
	l.horizontal_alignment = align
	return l


## A flat button. Every interactive state gets the SAME style object — no hover, no
## focus ring, nothing that lights up before the tap lands.
static func flat_button(text: String, width: float = 160.0, height: float = 44.0,
		font_size: int = 15) -> Button:
	var b := Button.new()
	b.text = text
	if width > 0.0:
		b.custom_minimum_size = Vector2(width, height)
	b.focus_mode = Control.FOCUS_NONE
	var style := panel_style()
	for state_name in ["normal", "pressed", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(state_name, style)
	b.add_theme_color_override("font_color", Color(TEXT))
	b.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	b.add_theme_font_size_override("font_size", font_size)
	return b


static func panel_style(border_colour: String = BORDER, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(BG)
	style.border_color = Color(border_colour)
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	return style


static func coloured_panel(border_colour: Color) -> StyleBoxFlat:
	var style := panel_style()
	style.border_color = border_colour
	style.set_border_width_all(2)
	return style


## Back-header: a flat button on the left, a title beside it, and an optional right
## slot for gold or a stat line. Returns {root, right}.
static func back_header(title: String, back_text: String = "Zpet") -> Dictionary:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)

	var back := flat_button(back_text, 120.0, 40.0)
	header.add_child(back)

	var title_label := label(title, 20)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var right := label("", 15, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(right)

	return {"root": header, "back": back, "title": title_label, "right": right}


## A flat row of tab buttons. `active_index` gets the brighter border — state is shown
## by the border colour, never by a hover effect.
static func tab_row(tabs: Array, active_index: int) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var buttons: Array = []
	for i in tabs.size():
		var b := flat_button(str(tabs[i]), 0.0, 34.0, 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := panel_style(GOLD if i == active_index else BORDER, 2 if i == active_index else 1)
		for state_name in ["normal", "pressed", "hover", "focus", "disabled"]:
			b.add_theme_stylebox_override(state_name, style)
		row.add_child(b)
		buttons.append(b)
	return {"root": row, "buttons": buttons}


## An item tooltip: a black box with the item's detail text. Lines that came from a
## rolled affix are drawn blue, the way the PWA distinguished mods from fixed stats.
static func item_tooltip(item: Dictionary, data: Node, width: float = 380.0) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", panel_style())
	box.custom_minimum_size = Vector2(width, 0)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	box.add_child(column)

	if item.is_empty():
		column.add_child(label("Zadny predmet", 13, DIM))
		return box

	var text := ItemDetail.build_text(item, data, false)
	for raw in text.split("\n"):
		var line := str(raw)
		if line == "":
			continue
		if line.begins_with(ItemDetail.MOD_PREFIX):
			column.add_child(label(line.substr(ItemDetail.MOD_PREFIX.length()), 13, MOD_BLUE))
		else:
			column.add_child(label(line, 13, TEXT))
	return box


## One grid cell holding an item icon, with a border in the item's quality colour and
## an optional stack count. `empty_placeholder` is drawn dimmed when there is no item.
static func item_cell(item: Dictionary, size: float, dimmed: bool = false,
		placeholder: String = "") -> Button:
	var cell := Button.new()
	cell.custom_minimum_size = Vector2(size, size)
	cell.focus_mode = Control.FOCUS_NONE
	var border := Color(BORDER)
	if not item.is_empty():
		border = ItemStats.quality_color(item)
	elif dimmed:
		border = Color("#3a3a3a")
	var style := panel_style()
	style.border_color = border
	for state_name in ["normal", "pressed", "hover", "focus", "disabled"]:
		cell.add_theme_stylebox_override(state_name, style)

	var icon_path := ""
	if not item.is_empty():
		icon_path = ItemStats.icon_path(item)
	elif placeholder != "":
		icon_path = placeholder
	if icon_path != "":
		var texture := load_texture(icon_path)
		if texture != null:
			var icon := TextureRect.new()
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture = texture
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if item.is_empty():
				icon.modulate = Color(1, 1, 1, 0.22)
			cell.add_child(icon)

	var count := int(item.get("count", 0)) if not item.is_empty() else 0
	if count > 1:
		var badge := label(str(count), 11, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
		badge.position = Vector2(size - 24, size - 18)
		badge.custom_minimum_size = Vector2(22, 14)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(badge)
	return cell


static func load_texture(path: String) -> Texture2D:
	if path == "":
		return null
	var full := path if path.begins_with("res://") else "res://" + path
	if not ResourceLoader.exists(full):
		return null
	return load(full)


## Strip a prefix like "assets/items/" so paths in log lines stay short.
static func short_path(path: String) -> String:
	var parts := path.split("/")
	return str(parts[parts.size() - 1]) if parts.size() > 0 else path
