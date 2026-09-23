extends RefCounted
class_name UIKit
## UIKit — the widgets every screen shares, and the PWA's own metrics.
##
## The PWA is the specification, not the inspiration: its `style.css` (2 401 lines) plus
## the `<style>` block in `index.html` define every size, colour and radius the port
## draws. The constants below are copied FROM those rules, with the rule named beside
## each one, so a layout bug is fixed by re-reading the CSS rather than by taste.
##
## The rules are Jan's and they are the same in every screen: black background, a thin
## grey border, no rounded corners unless the PWA has them, NO hover or focus styling
## (one style object for every state, so a tap has no visual side effect beyond the
## press), no emoji.
##
## Kept as static functions rather than a scene: a .tscn would be a second place for
## these styles to live and they would drift.

const ItemDetail := preload("res://scripts/items/item_detail.gd")
const ItemStats := preload("res://scripts/items/item_stats.gd")
const UIFonts := preload("res://scripts/ui/ui_fonts.gd")

const BG := "#000000"
const BORDER := "#333333"
const TEXT := "#d0d0d0"
const DIM := "#888888"
const GOLD := "#f1c40f"
const BAD := "#c0392b"
const MOD_BLUE := "#4a7dff"
## `.chest-cell { background:#aaa; border:1px solid #777 }` — the grid cell fill. It is
## LIGHT: at the PWA's `.empty { opacity:0.25 }` it renders as rgb(43,43,43) inside a
## #000 box, and a filled cell is a light grey tile. Both grids read as a light lattice
## in the reference frames, not as black holes.
const CELL_FILL := "#aaaaaa"
const CELL_BORDER_EMPTY := "#777777"

## `.container { padding: 16px 16px 70px 16px }` — the 70px bottom is where the PWA's
## fixed `.nav-bar` sits. Without it every screen hides its last row behind the nav.
const CONTAINER_PAD := 16.0
const NAV_RESERVE := 70.0
## `.btn { padding:12px; margin:6px 0 }` — a screen that LEADS with a full-width `.btn`
## (chest, shop, gamble, craft) has that button 6px lower than the container's own 16px
## padding, i.e. at y=22 in the live PWA. The 6px is the button's margin, so it belongs to
## the page that starts with one, not to `screen_page` itself (the town leads with a
## banner and starts at y=16).
const BACK_BTN_PAD := 22.0
## `body { background: #121212 }`
const PAGE_BG := "#121212"
## `.btn-secondary { background:#3a3a5a; color:#e0e0e0 }`, `.btn { padding:12px;
## border-radius:8px; font-size:15px; font-weight:bold }`.
const BTN_SECONDARY_BG := "#3a3a5a"


## A label that can always shrink. A Godot Label reports its whole UNWRAPPED text as its
## minimum width and a container honours that minimum, so a single long line was widening
## whole screens past the 390px canvas (measured: the craft screen built 447px wide and
## the chest 554px, i.e. 60-160px of every screen sat off the right edge). In a browser a
## long line wraps inside its parent — this makes `label()` behave the same way, so no
## screen can be pushed off-canvas by its own copy. Callers that want a wider label give
## it SIZE_EXPAND_FILL, which still works.
##
## `bold` is the CSS `font-weight: bold` — a real face (see `UIFonts`), not an embolden
## pass, because DejaVu's bold is 13% wider and the reference frames are drawn with it.
static func label(text: String, size: int = 14, colour: String = TEXT,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UIFonts.get_font(size, bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(colour))
	l.horizontal_alignment = align
	l.custom_minimum_size = Vector2(0, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A flat button. Every interactive state gets the SAME style object — no hover, no
## focus ring, nothing that lights up before the tap lands. The optional `pressed_style`
## models the PWA's `:active`, which is the only feedback a tap is allowed to have.
static func flat_button(text: String, width: float = 160.0, height: float = 44.0,
		font_size: int = 15, fill: String = BG, border: String = BORDER,
		pressed_style: StyleBoxFlat = null) -> Button:
	var b := Button.new()
	b.text = text
	if width > 0.0:
		b.custom_minimum_size = Vector2(width, height)
	b.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	for state_name in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(state_name, style)
	b.add_theme_stylebox_override("pressed", pressed_style if pressed_style != null else style)
	b.add_theme_color_override("font_color", Color(TEXT))
	b.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	b.add_theme_font_size_override("font_size", font_size)
	return b


## `.btn.btn-secondary` — the full-width "Back to Town" button every PWA sub-screen has
## at the very top. Blue-grey fill, 8px radius, 15px bold. It is NOT the flat bordered
## button; using the wrong one is why the port's screens read as a different game.
##
## `.btn { padding:12px; font-size:15px; font-weight:700 }` measures 42px tall in the
## live PWA, not 44 — the port's extra 2px pushed every element below it down.
static func secondary_button(text: String, height: float = 42.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(BTN_SECONDARY_BG)
	style.border_color = Color(BTN_SECONDARY_BG)
	style.set_border_width_all(0)
	style.set_corner_radius_all(8)
	# `:active` — `.btn` has `transition: 0.2s` and no active rule, so the pressed look is
	# the same box; a brightness change is what a tap reads as without a hover state.
	var pressed := style.duplicate()
	pressed.bg_color = Color("#4a4a70")
	pressed.border_color = Color("#4a4a70")
	for state_name in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(state_name, style)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", Color("#e0e0e0"))
	b.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	b.add_theme_font_size_override("font_size", 15)
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


# --- the PWA's page chrome ---------------------------------------------------

## A screen root: the PWA's `.container` — a scrolling column with 16px side padding and
## 70px at the bottom for the fixed nav bar. EVERY screen is built on this, which is what
## makes "scroll works everywhere" one implementation instead of seven.
##
##   var page := UIKit.screen_page(self)
##   page["column"].add_child(...)
##
## `page["swipe"]` is the `ScrollSwipe` node driving the drag where Godot's own one is off —
## see `scroll_swipe.gd`. The port draws NO scrollbar (`SCROLL_MODE_SHOW_NEVER`): the PWA is
## scrolled by the finger and draws nothing, and a grey bar down the right edge is chrome the
## original never had. SHOW_NEVER is also the one value that keeps the page's full width —
## AUTO and RESERVE both reserve the bar's space.
##
## Returns {root, column, scroll, swipe}.
static func screen_page(host: Control, top_pad: float = CONTAINER_PAD,
		bottom_pad: float = NAV_RESERVE) -> Dictionary:
	var bg := ColorRect.new()
	bg.color = Color(PAGE_BG)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# No visible vertical bar. The scroll itself is unchanged — the bar is still moved by
	# `ScrollSwipe` and by the wheel; only its drawing is off. SHOW_NEVER is the one value
	# that keeps the full page width (AUTO and RESERVE both reserve the bar's space).
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.scroll_deadzone = 8
	host.add_child(scroll)

	var swipe := ScrollSwipe.new()
	swipe.setup(scroll)
	host.add_child(swipe)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", int(CONTAINER_PAD))
	pad.add_theme_constant_override("margin_right", int(CONTAINER_PAD))
	pad.add_theme_constant_override("margin_top", int(top_pad))
	pad.add_theme_constant_override("margin_bottom", int(bottom_pad))
	scroll.add_child(pad)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	pad.add_child(column)

	return {"root": scroll, "column": column, "scroll": scroll, "swipe": swipe}


## `.shop-back-map` — the full-width "Back to Town" button at the top of every sub-screen.
static func back_button(text: String = "Back to Town") -> Button:
	return secondary_button(text)


## The header every full-page screen starts with: the PWA's full-width back button, then
## the title beside it, then an optional right slot for gold or a stat line. The PWA put
## the back button ABOVE the title (`.shop-back-map` then `.page-header`); this keeps both
## in one row because a 390px screen has no room to stack them and the order a player
## reads them in is unchanged.
##
## Returns {root, back, title, right}.
static func back_header(title: String, back_text: String = "Back to Town") -> Dictionary:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)

	var back := secondary_button(back_text)
	column.add_child(back)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)

	var title_label := label(title, 20)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)

	var right := label("", 15, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A non-wrapping label reports its whole text as its MINIMUM width, and a container
	# honours that minimum — so one long line silently widened every screen past the
	# 390px canvas (measured: the chest built 554px wide, 204px of it off-screen). Zero
	# the minimums and let the text wrap or clip instead of pushing the layout.
	right.custom_minimum_size = Vector2(0, 0)
	right.clip_text = true
	row.custom_minimum_size = Vector2(0, 0)
	column.custom_minimum_size = Vector2(0, 0)

	return {"root": column, "back": back, "title": title_label, "right": right}


## A label with a hard drop shadow over artwork. Godot's Label has an outline, not a
## shadow; the outline is the mechanism and does the same job.
class UILabel:
	extends Label

	func _init() -> void:
		add_theme_constant_override("outline_size", 8)
		add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))


## `.card` — the PWA's plain card, used as a PAGE HEADER by the bestiary and the spellbook.
## It is not the `page-header`: no 80px icon, no border on a #444, no 10px radius on
## #000. It is `background:#1a1a1a; border:1px solid #2a2a2a; border-radius:10px;
## padding:14px`, with a 16px bold title (and an optional 32px `.page-icon` inside it)
## and a #888 12px subtitle. Both screens measured this shape in the live PWA:
##   div.card [16,24 358x86] bg=#1a1a1a bd=1px #2a2a2a r=10 pad=14
##   div.card-title: 16px/700, .card-subtitle: 12px #888
## Neither has a "Back to Town" button — the nav bar is the way out.
static func card_header(title: String, subtitle: String = "", icon_path: String = "") -> Dictionary:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1a1a1a")
	style.border_color = Color("#2a2a2a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.custom_minimum_size = Vector2(0, 0)
	panel.add_child(column)

	# `.card-title` is one row so the `.page-icon` (32px, 4px radius) sits inline with
	# the text; the bestiary's title row measured 32px tall for exactly that reason.
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	title_row.custom_minimum_size = Vector2(0, 0)
	column.add_child(title_row)

	if icon_path != "":
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = load_texture(icon_path)
		title_row.add_child(icon)

	var title_label := label(title, 16, "#d0d0d0")
	title_label.custom_minimum_size = Vector2(0, 0)
	title_row.add_child(title_label)

	var sub_label := label(subtitle, 12, "#888888")
	sub_label.custom_minimum_size = Vector2(0, 0)
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(sub_label)

	return {"root": panel, "title": title_label, "subtitle": sub_label}


## `.page-header` — an 80px icon, a 22px bold title, a 13px #999 subtitle, on a black box
## with a 1px #444 border and a 10px radius. `right_text` is the gold readout the PWA put
## at `margin-left:auto` (e.g. "0 gold"/"0 zlata").
##
## `.page-header { padding:16px 20px }` content-box, so the box is 114px tall over a 358px
## content width — the port's 20/20/16/16 plus a 112px-tall row came out 2px short.
static func page_header(icon_path: String, title: String, subtitle: String = "",
		right_text: String = "") -> Dictionary:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(BG)
	style.border_color = Color("#444444")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 17
	style.content_margin_bottom = 17
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(80, 80)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load_texture(icon_path)
	row.add_child(icon)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(column)

	var title_label := label(title, 22, "#f0f0f0")
	title_label.custom_minimum_size = Vector2(0, 0)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title_label)
	var sub_label := label(subtitle, 13, "#999999")
	sub_label.custom_minimum_size = Vector2(0, 0)
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(sub_label)

	var right := label(right_text, 14, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A Label reports its UNWRAPPED text as its minimum width and a container honours it,
	# so one long subtitle widened the whole screen: the chest built 554px wide inside a
	# 390px canvas, i.e. a third of every screen sat off the right edge. Every text node
	# in a horizontal row must be allowed to shrink.
	right.custom_minimum_size = Vector2(0, 0)
	right.clip_text = true
	row.custom_minimum_size = Vector2(0, 0)
	# `.card { margin:8px 0 }`, `.btn { margin:6px 0 }`, `.map-actions { padding:8px 12px 12px }`.
	# A VBoxContainer has ONE separation for every child, so a per-element margin cannot be
	# expressed in the container — each screen adds a `Spacer` of the right height before
	# the element that needs it. Returns a zero-height container unless a margin is given.
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	return {"root": panel, "right": right, "title": title_label, "subtitle": sub_label}


## A vertical gap of exactly `height` pixels. CSS gives every card and button its own
## margin; a container gives all children the same separation, so the difference is added
## explicitly at the one place the measurement says it belongs.
static func gap(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


## `.shop-tabs` / `.shop-tab` — equal-width tabs, 10px padding, 8px radius, the active one
## with a 1px coloured border and a bold label. `active_colour` is #4a7dff for the shop,
## #f1c40f for the category strip, #9b59b6 for craft.
static func tab_row(tabs: Array, active_index: int, active_colour: String = MOD_BLUE) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var buttons: Array = []
	for i in tabs.size():
		var b := Button.new()
		b.text = str(tabs[i])
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(BG)
		style.border_color = Color("#2a2a2a")
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		var active := i == active_index
		if active:
			style.bg_color = Color("#111111")
			style.border_color = Color(active_colour)
		for state_name in ["normal", "hover", "focus", "disabled"]:
			b.add_theme_stylebox_override(state_name, style)
		var pressed := style.duplicate()
		pressed.bg_color = Color("#1a1a1a")
		b.add_theme_stylebox_override("pressed", pressed)
		b.add_theme_color_override("font_color", Color("#ffffff") if active else Color("#cccccc"))
		b.add_theme_font_size_override("font_size", 14)
		row.add_child(b)
		buttons.append(b)
	return {"root": row, "buttons": buttons}


## A section heading: `.chest-section-label` (14px bold #aaa) and
## `.shop-category-title` (#f0f0f0 on a #333 underline) are the same idea.
static func section_label(text: String, underlined: bool = false) -> Control:
	if not underlined:
		return label(text, 14, "#aaaaaa")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(label(text, 16, "#f0f0f0"))
	var rule := ColorRect.new()
	rule.color = Color(BORDER)
	rule.custom_minimum_size = Vector2(0, 1)
	box.add_child(rule)
	return box


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


## One grid cell holding an item icon, matching the PWA's `.chest-cell`.
##
## `.chest-cell { aspect-ratio:1; background:#aaa; border:1px solid #777; border-radius:6px }`
## and `.chest-cell.empty { opacity:0.25 }` — so an EMPTY cell is a LIGHT grey box at 25%
## opacity (measured in the reference frames: interior rgb(43,43,43), border rgb(14,14,14))
## and a FILLED one is the same light box at full opacity with the quality colour on the
## border. The port drew both as a black box, which is why the two grids differed on ~45%
## of their pixels — the single largest visual difference in the whole port, and invisible
## to every gameplay test.
##
## `dimmed` is the port's own extra: a filled cell the hero CANNOT equip. The PWA wrote
## `border-color:#e74c3c; opacity:0.35` inline for it.
static func item_cell(item: Dictionary, size: float, dimmed: bool = false,
		placeholder: String = "") -> Button:
	var cell := Button.new()
	cell.custom_minimum_size = Vector2(size, size)
	cell.focus_mode = Control.FOCUS_NONE
	var is_empty := item.is_empty()
	var border := Color(CELL_BORDER_EMPTY)
	if not is_empty:
		border = ItemStats.quality_color(item)
	var style := panel_style()
	style.bg_color = Color(CELL_FILL)
	style.border_color = border
	style.set_corner_radius_all(6)
	# `.chest-cell:active { background:#aaa }` — the cell lights up on the press only.
	var pressed := style.duplicate()
	pressed.bg_color = Color("#cccccc")
	for state_name in ["normal", "hover", "focus", "disabled"]:
		cell.add_theme_stylebox_override(state_name, style)
	cell.add_theme_stylebox_override("pressed", pressed)

	# `.chest-cell.empty { opacity:0.25 }` — a CSS opacity is inherited by the whole box,
	# not just the icon, so it has to be applied to the cell's own modulate. Godot
	# multiplies a parent's modulate into its children, so the icon dims with it and does
	# NOT get a second alpha of its own.
	if is_empty and not dimmed:
		cell.modulate = Color(1, 1, 1, 0.25)
	elif is_empty and dimmed:
		cell.modulate = Color(1, 1, 1, 0.35)

	var icon_path := ""
	if not is_empty:
		icon_path = ItemStats.icon_path(item)
	elif placeholder != "":
		icon_path = placeholder
	if icon_path != "":
		var texture := load_texture(icon_path)
		if texture != null:
			var icon := TextureRect.new()
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon.offset_left = size * 0.1
			icon.offset_top = size * 0.1
			icon.offset_right = -size * 0.1
			icon.offset_bottom = -size * 0.1
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture = texture
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(icon)

	var count := int(item.get("count", 0)) if not is_empty else 0
	if count > 1:
		cell.add_child(count_badge(str(count)))
	return cell


## `.cell-count` — a gold-bordered pill in the bottom-right of a cell.
static func count_badge(text: String) -> Label:
	var badge := Label.new()
	badge.text = text
	badge.add_theme_font_size_override("font_size", 10)
	badge.add_theme_color_override("font_color", Color(GOLD))
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.offset_left = -22
	badge.offset_top = -16
	badge.offset_right = -1
	badge.offset_bottom = -1
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#111111")
	style.border_color = Color(GOLD)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	badge.add_theme_stylebox_override("normal", style)
	return badge


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


## `.nav-bar` — the PWA's FIXED bottom navigation, and the reason every screen reserves
## 70px at the bottom of its container. It is the port's only global chrome: the PWA
## showed it on every screen except classSelect, mapBattle and result, and hid the two
## screens it could not reach any other way (inventory, hero) behind it rather than
## inventing town tiles for them.
##
## The PWA's bar had eight entries, most of them its own dev tooling (music toggle, test
## mode, clear save) or emoji glyphs. What is ported is the NAVIGATION: the five screens
## a player can actually leave town for, each with a real generated icon — no emoji, per
## Jan's rule. `active_key` brightens the current entry; there are no hover effects.
class NavBar:
	extends PanelContainer

	signal nav_selected(key: String)

	## key -> Button, so the active entry can be moved without rebuilding the bar.
	var _buttons: Dictionary = {}
	var _active_key := ""

	## key -> [icon path, tooltip, emoji, font size, colour]. Mirrors the PWA's
	## `<nav class="nav-bar">` EXACTLY, entry for entry and in the same order — 8 items,
	## not a curated subset.
	##
	## The PWA's bar is: town, hero, bestiary, musicToggle, testToggle, clearSave,
	## spellbook, items. Three are toggles rather than screens, and dropping them silently
	## changes the bar's rhythm: the icons after them slide left and no longer sit under
	## the PWA's. `map`, `inventory` and `shop` were entries the PWA does NOT have — the
	## map is entered from the town tile, the bag from the character modal.
	##
	## The last three are EMOJI in the PWA (🗑️ 📖 📦) and in a browser they render as
	## colour glyphs. Godot's DejaVu has no emoji coverage, so the port was painting the
	## raw codepoints as garbage (`ǵD1`, `ǴD6`, `ǴE` — the surrogate halves), which is
	## what the reference diff saw in the nav band. They are now real generated icons in
	## the same style as the other five, per Jan's no-emoji rule.
	##
	## Every entry is a triple and every entry HAS an icon. The old six-slot shape
	## (emoji, its font size, its colour) is gone because after the emoji were replaced
	## those three slots were carried by all eight rows as empties that nothing read —
	## a construction that documented a mechanism the bar no longer has.
	const ENTRIES := [
		["town", "assets/menu-icons/mesto.png", "Mesto"],
		["hero", "assets/monsters/hero_barbarian_m.png", "Hrdina"],
		["bestiary", "assets/menu-icons/bestiar.png", "Bestiar"],
		["music", "assets/menu-icons/music.png", "Hudba"],
		["testmode", "assets/menu-icons/testmode.png", "Testovaci rezim"],
		["clearsave", "assets/menu-icons/clearsave.png", "Smazat ulozenou hru"],
		["spellbook", "assets/menu-icons/spellbook.png", "Kouzla"],
		["items", "assets/menu-icons/items.png", "Predmety"],
	]

	static func build(active_key: String = "") -> NavBar:
		var bar := NavBar.new()
		bar.name = "NavBar"
		bar._active_key = active_key
		bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		# `.nav-bar { padding:8px 10px }` + a 44px item + `border-top:1px` = 61px, and the
		# live PWA bar measures y=783..844. 56 left the bar 5px short, which pushed every
		# icon down and put the top border 5px too low.
		var bar_h := 61
		bar.offset_top = -bar_h
		bar.offset_bottom = 0
		bar.custom_minimum_size = Vector2(0, bar_h)
		# `.nav-bar { background:#000; border-top:1px solid #222; padding:8px 10px }`
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#000000")
		style.border_color = Color("#222222")
		style.set_border_width_all(0)
		style.border_width_top = 1
		style.set_corner_radius_all(0)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		bar.add_theme_stylebox_override("panel", style)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		bar.add_child(row)

		for entry in ENTRIES:
			var key := str(entry[0])
			var icon_path := str(entry[1])
			var button := Button.new()
			# `.nav-bar a { width:44px; height:44px; border-radius:6px }`
			button.custom_minimum_size = Vector2(44, 44)
			button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			button.focus_mode = Control.FOCUS_NONE
			button.tooltip_text = str(entry[2])
			# All eight entries now carry a real icon. The last three were emoji in the
			# PWA (🗑️ 📖 📦) and DejaVu has no emoji coverage, so the port painted the raw
			# codepoints as garbage — the reference diff read them in the nav band as
			# `ǵD1`, `ǴD6`, `ǴE`. They are generated assets now, in the port's own style,
			# which is also Jan's no-emoji rule.
			#
			# `.nav-icon { width:100%; height:100%; object-fit:contain; border-radius:4px }`
			# — the image fills the 44px box and the ICON carries the background on its own.
			var plate := ColorRect.new()
			plate.color = Color("#1a1a1a")
			plate.set_anchors_preset(Control.PRESET_FULL_RECT)
			plate.offset_left = 4
			plate.offset_top = 4
			plate.offset_right = -4
			plate.offset_bottom = -4
			plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(plate)
			var icon := TextureRect.new()
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture = UIKit.load_texture(icon_path)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(icon)
			button.pressed.connect(func(): bar.nav_selected.emit(key))
			row.add_child(button)
			bar._buttons[key] = button
		bar.set_active(active_key)
		return bar

	## `.nav-bar a.active { background:#1a1a1a }` — the active entry is the only one with
	## a filled background. No hover state, per Jan's rule: on a phone a tap has no
	## hover to have.
	func set_active(key: String) -> void:
		_active_key = key
		for entry_key in _buttons:
			var button: Button = _buttons[entry_key]
			var normal := StyleBoxFlat.new()
			normal.bg_color = Color("#000000")
			normal.set_corner_radius_all(6)
			var active := StyleBoxFlat.new()
			active.bg_color = Color("#1a1a1a")
			active.set_corner_radius_all(6)
			var use := active if str(entry_key) == key else normal
			for state_name in ["normal", "hover", "focus", "disabled"]:
				button.add_theme_stylebox_override(state_name, use)
			button.add_theme_stylebox_override("pressed", active)


## `.monster-in-ring` / `.hero-portrait-lg-frame` — a CIRCULAR crop of a square image at
## a given diameter, with an optional ring border and its glow.
##
## `draw_texture_rect` has no clip, so the crop is a scanline: for each row the circle's
## half-width is computed and everything outside it is repainted in the background
## colour. The wedge approach looks right on paper and cuts across the art on screen.
##
## An optional `top_fade` reproduces the PWA's `.monster-ring-overlay` gradient, which
## darkens the top third of the arena portrait.
class CircularPortrait:
	extends Control

	var texture: Texture2D:
		set(value):
			texture = value
			queue_redraw()
	## Drawn as a ring around the disc, e.g. "#5fa87a" for a boss, "#4a7dff" for the hero.
	var ring_colour := Color(0, 0, 0, 0)
	var ring_width := 0.0
	## The colour outside the circle — the screen's own background, since there is no clip.
	var backdrop := Color("#121212")
	## 0.0 = none, 0.45 = the PWA's `.monster-ring-overlay`.
	var top_fade := 0.0

	func _draw() -> void:
		var diameter := minf(size.x, size.y)
		var radius := diameter * 0.5
		var centre := size * 0.5
		var inset := ring_width * 0.5
		if texture != null:
			draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)
			# Scanline crop: repaint everything outside the circle in the backdrop colour.
			var rows := int(ceil(size.y))
			for row in rows:
				var dy := float(row) + 0.5 - centre.y
				var half_sq := radius * radius - dy * dy
				if half_sq <= 0.0:
					draw_rect(Rect2(0, float(row), size.x, 1.0), backdrop)
					continue
				var half := sqrt(half_sq)
				var left := centre.x - half
				var right := centre.x + half
				if left > 0.0:
					draw_rect(Rect2(0, float(row), left, 1.0), backdrop)
				if right < size.x:
					draw_rect(Rect2(right, float(row), size.x - right, 1.0), backdrop)
			if top_fade > 0.0:
				# A vertical fade over the top third, clipped to the disc by the same
				# scanline: the PWA's overlay darkened the art, not the background.
				var fade_h := size.y * 0.34
				var steps := 24
				for step in steps:
					var t := float(step) / float(steps)
					var row0 := fade_h * t
					var alpha := top_fade * (1.0 - t)
					var dy2 := row0 + (fade_h / float(steps)) * 0.5 - centre.y
					var half_sq2 := radius * radius - dy2 * dy2
					if half_sq2 <= 0.0:
						continue
					var half2 := sqrt(half_sq2)
					var x0 := maxf(0.0, centre.x - half2)
					var x1 := minf(size.x, centre.x + half2)
					draw_rect(Rect2(x0, row0, x1 - x0, fade_h / float(steps)),
						Color(0, 0, 0, alpha))
		if ring_width > 0.0:
			draw_arc(centre, radius - inset, 0.0, TAU, 96, ring_colour, ring_width, true)

