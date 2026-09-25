extends Control
class_name ItemInfoOverlay
## ItemInfoOverlay — the PWA's `#invItemOverlay`, the D2-style item detail.
##
## This is a WHOLE MISSING SCREEN in the port, not a styling detail: in the PWA every
## tap on a bag cell or an equipment slot opens it, and it is where a player reads an
## item's stats, compares it against what is worn, sees its sockets and equips it. The
## port equips on tap and shows a socket panel only, so stats and compare had no home.
##
## Measured on the LIVE PWA (`tools/import/probe_slots_live.py`, and the CSS below):
##
##   .inv-item-overlay       position:fixed; inset:0; z-index:1000;
##                           display:flex; align-items:center; justify-content:center
##   .inv-item-overlay-bg    background:rgba(0,0,0,0.4)     <- the dim, 40% not 80%
##   .inv-item-overlay-content
##                           background:#000; border:2px solid #3a3a3a; border-radius:8px;
##                           padding:20px 24px; min-width:220px; max-width:300px;
##                           max-height:80vh; flex column; gap:8px; overflow-y:auto
##                           (the border colour is REPLACED by the item's quality colour)
##   .inv-item-overlay-close 24x24 circle, top:6px right:6px, #888 on #1a1a1a, 1px #444
##   .inv-item-overlay-icon  renderItemIcon(item, 56)
##   .inv-item-overlay-name  font-size:15px; bold; centred; colour = quality
##   .inv-item-overlay-base  font-size:11px; #888; centred
##   .inv-item-overlay-stats .stat-row
##                           flex; justify-content:space-between; gap:12px;
##                           padding:2px 0; border-bottom:1px solid #1a1a1a
##                           label #888, value #e8e0e8, BOTH #4169E1 for a rolled mod
##   .socket-slot            48x48; border-radius:50%; border:2px solid #555;
##                           background:#1a1a1a
##   .inv-item-overlay-compare-divider
##                           "── Equipped ──" 10px #555 letter-spacing:2px centred
##   .inv-item-overlay-btn   padding:8px 16px; font-size:13px; bold; background:#2a2a2a;
##                           border:1px solid #555; border-radius:6px; flex:1
##
## The three compare shapes are the PWA's own branches and they differ by item type:
##   ring   -> "Ring 1" / "Ring 2", both worn rings, each printed as a block
##   weapon -> "Main Hand" / "Off Hand" in a bordered `.inv-compare-weapon-block`
##   other  -> the single item worn in that slot, with its icon
##
## Nothing here computes a stat: `ItemDetail` owns the text and `ItemStats` the colours,
## exactly as the shop and craft screens do. This file is layout.

const UIKit := preload("res://scripts/ui/ui_kit.gd")
const ItemDetail := preload("res://scripts/items/item_detail.gd")
const ItemStats := preload("res://scripts/items/item_stats.gd")

## A tap on a button in the overlay. `action` is one of:
##   "equip"      — equip the shown BAG item into its natural slot
##   "equip_mh" / "equip_oh"   — the two dual-wield buttons
##   "equip_r1" / "equip_r2"   — the two ring buttons
##   "unequip"    — take off the item in `slot`
signal action(action: String, slot: String)
## The overlay closed (X, or a tap on the dim). The caller clears its selection.
signal dismissed()
## A socket circle was tapped: arm it for the next gem tap.
signal socket_tapped(socket_index: int)
## A gem listed under the sockets was tapped: insert it into the armed socket.
signal gem_tapped(gem_id: String)

## `.inv-item-overlay-content { max-width:300px; min-width:220px }` and the pane is 390
## wide, so the panel is 300 unless the screen is narrower.
const MAX_WIDTH := 300.0
const MIN_WIDTH := 220.0
## `.inv-item-overlay-content { padding:20px 24px; gap:8px }`
const PAD_V := 20.0
const PAD_H := 24.0
const GAP := 8.0
const RADIUS := 8
## `.inv-item-overlay-stats { font-size:12px; line-height:1.7 }` — a 12px row in the live
## PWA measures **20.4px** (`line-height` 20.4px, `padding:2px 0`, 1px rule = 25.4 total).
## A Godot Label reports a 15px line box with no line spacing, so every row came out 16px
## and the whole stats block was 40 % short of the reference.
const ROW_LINE_HEIGHT := 20.4
## A Label's single-line minimum in Godot is its font's line box (measured: 15px at 12px
## size), so the PWA's 20.4px line box is asserted through the label's own minimum height.
const ROW_MIN_HEIGHT := 20.0
const ROW_PAD_V := 2.0
## `.stat-row { gap:12px }`
const ROW_GAP := 12.0
## `.inv-item-overlay-close { width:24px; height:24px }` — the PWA's own box, which is
## small. Jan's report was "the close button is so small it is hard to press", and the
## answer cannot be to grow the button past the reference: the TOUCH TARGET grows instead.
## `.inv-item-overlay-close` sits at `top:6px; right:6px` inside the panel, so its 24px
## circle is the middle of a 44x44 hit area, which is the standard minimum touch target
## and what a thumb actually finds.
const CLOSE_SIZE := 24.0
const CLOSE_TOUCH := 44.0
## `.inv-item-overlay-close { top:6px; right:6px }`
const CLOSE_INSET := 6.0

## The PWA's `slotMap` — item type -> the equipment slot it occupies. `ring` maps to
## ring1 because a ring's two compare entries are handled as a special case.
const SLOT_OF_TYPE := {
	"weapon": "weapon", "armor": "armor", "helmet": "helmet", "shield": "shield",
	"ring": "ring1", "belt": "belt", "amulet": "amulet", "gloves": "gloves",
	"boots": "boots",
}
## The PWA's `defaults` — an id that means "nothing is really worn here".
const SLOT_DEFAULTS := {
	"weapon": "fists", "armor": null, "helmet": null, "shield": null,
	"ring1": null, "ring2": null, "amulet": null, "belt": null,
	"gloves": null, "boots": null,
}

var _data: Node
var _gen
var _state
var _find_item: Callable
## Set by `bind_slots()`: the equipment slot names, in the order the doll draws them.
var _slots: Array = []

var _root: Control
var _panel: PanelContainer
var _content: VBoxContainer
var _dim: ColorRect
## `.inv-item-overlay-close` — a sibling of the panel, positioned in `_layout()`.
var _close_holder: Control

## What is currently shown, so a dismissal can clear the caller's selection without the
## caller having to remember it, and so the socket taps know their host.
var _item: Dictionary = {}
var _item_id: String = ""
## The socket block's rows, rebuilt by `refresh_sockets()`.
var _socket_row: HBoxContainer
var _gem_row: HBoxContainer
var _socket_hint: Label
## "bag" when the item came from the inventory grid, "equipped" when it came off the
## doll — this decides the BUTTON, which is the PWA's `_invSelectedIdx` vs
## `_invSelectedSlot` distinction.
var _origin := ""
var _origin_slot := ""
var _origin_index := -1


func _init(game_data: Node, gen, state, find_item: Callable,
		slots: Array) -> void:
	_data = game_data
	_gen = gen
	_state = state
	_find_item = find_item
	_slots = slots


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false


func _build() -> void:
	# `.inv-item-overlay-bg { background:rgba(0,0,0,0.4) }` and it CLOSES on a tap
	# (`ovBg.onclick = closeItemOverlay`). 40%, not the 70-80% the modal uses: the game
	# world stays readable under it.
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.4)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	# The width is fixed and the height is content-driven, so both offsets are recomputed
	# in `_layout()` from the panel's own minimum — a PanelContainer centred by anchors
	# with a content height cannot express itself, and `align-items:center` is exactly
	# that: centre the box on its own height, whatever the content turns out to be.
	add_child(_panel)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", int(GAP))
	_panel.add_child(_content)

	# The close button is a sibling of the PANEL, not a child of its content column,
	# because `.inv-item-overlay-close` is `position:absolute` — it reserves NO flow space
	# at all. Built here and placed in `_layout()`, beside the panel's own rect, which is
	# the one place that knows where the panel ended up.
	_build_close()


## The panel's size, from its content. `min-width:220px; max-width:300px; max-height:80vh`
## with `overflow-y:auto`, and a tap OUTSIDE it closes.
func _layout() -> void:
	var view := size
	if view.x <= 0.0:
		return
	var want_w: float = clampf(MAX_WIDTH, MIN_WIDTH, maxf(MIN_WIDTH, view.x - 16.0))
	var inner := _content.get_combined_minimum_size()
	var want_h: float = inner.y + PAD_V * 2.0
	var max_h := view.y * 0.8
	want_h = minf(want_h, max_h)
	var half_w := want_w * 0.5
	var half_h := want_h * 0.5
	_panel.offset_left = -half_w
	_panel.offset_right = half_w
	_panel.offset_top = -half_h
	_panel.offset_bottom = half_h
	_place_close(half_w, half_h)


# --- showing -----------------------------------------------------------------

## Open the overlay for an item taken from the INVENTORY GRID.
## `index` is the bag index, which the equip buttons need.
func show_for_bag(item: Dictionary, index: int) -> void:
	_origin = "bag"
	_origin_index = index
	_origin_slot = ""
	_show(item)


## Open the overlay for an item WORN in `slot`. The button is Unequip.
func show_for_equipped(item: Dictionary, slot: String) -> void:
	_origin = "equipped"
	_origin_slot = slot
	_origin_index = -1
	_show(item)


func _show(item: Dictionary) -> void:
	if item.is_empty():
		close()
		return
	_item = item
	_item_id = str(item.get("id", ""))
	_socket_row = null
	_gem_row = null
	_socket_hint = null
	_rebuild()
	visible = true
	set_process(true)
	_layout()
	# `set_process` is switched off again once the height has settled — the panel's height
	# depends on a layout pass that has not run yet on the frame it is shown, so one
	# `_process` tick re-runs `_layout()` with real numbers.
	_settle = 0


var _settle := 0


func _process(_delta: float) -> void:
	if _settle >= 2:
		set_process(false)
		return
	_settle += 1
	_layout()


func close() -> void:
	visible = false
	set_process(false)
	_item = {}
	_item_id = ""
	_origin = ""
	_origin_slot = ""
	_origin_index = -1
	dismissed.emit()


func current_item_id() -> String:
	return _item_id


## Re-run the socket fill-in for the item currently shown. The caller passes its own bag;
## kept separate from `_show()` so an insert can refresh the row without reopening.
func refresh_sockets_now(inventory: Array, armed: int = -1) -> void:
	if _socket_row == null:
		return
	refresh_sockets(_item_id, armed, inventory)


func origin() -> String:
	return _origin


func origin_slot() -> String:
	return _origin_slot


func origin_index() -> int:
	return _origin_index


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
	elif event is InputEventScreenTouch and event.pressed:
		close()


# --- the panel's contents ----------------------------------------------------

func _rebuild() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

	var quality := ItemStats.quality_color(_item)
	# `.inv-item-overlay-content { style.borderColor = getQualityColor(item) }`
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#000000")
	style.border_color = quality
	style.set_border_width_all(2)
	style.set_corner_radius_all(RADIUS)
	style.content_margin_left = PAD_H
	style.content_margin_right = PAD_H
	style.content_margin_top = PAD_V
	style.content_margin_bottom = PAD_V
	_panel.add_theme_stylebox_override("panel", style)

	_content.add_child(_build_icon(56.0))

	# `.inv-item-overlay-name { font-size:15px; font-weight:bold; text-align:center }`
	# in the item's quality colour, with the socket count in the name (getItemSocketName).
	_content.add_child(UIKit.label(ItemStats.socket_name(_item), 15, "#ffffff",
		HORIZONTAL_ALIGNMENT_CENTER, true))
	var name_label: Label = _content.get_child(_content.get_child_count() - 1)
	name_label.add_theme_color_override("font_color", quality)

	# `.inv-item-overlay-base { font-size:11px; color:#888 }` — the BASE item's name, and
	# only when the item has its own rolled name (a rare/unique), which is what
	# `getItemBaseLabel` checks. It is hidden entirely otherwise.
	var base := _base_label()
	if base != "":
		_content.add_child(UIKit.label(base, 11, "#888888", HORIZONTAL_ALIGNMENT_CENTER))

	# `.inv-item-overlay-stats` — the type block plus every rolled mod, blue for mods.
	_content.add_child(_build_stats(_item))

	# The socket circles, when the item has any. The CELLS are built here and the gems
	# that fit are filled in by `refresh_sockets()`, which the router calls with the live
	# bag — the overlay does not read the save's inventory itself.
	if int(_item.get("sockets", 0)) > 0:
		var socket_block := VBoxContainer.new()
		socket_block.add_theme_constant_override("separation", 6)
		socket_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_socket_row = HBoxContainer.new()
		_socket_row.add_theme_constant_override("separation", 6)
		_socket_row.alignment = BoxContainer.ALIGNMENT_CENTER
		socket_block.add_child(_socket_row)
		_gem_row = HBoxContainer.new()
		_gem_row.add_theme_constant_override("separation", 6)
		_gem_row.alignment = BoxContainer.ALIGNMENT_CENTER
		socket_block.add_child(_gem_row)
		_socket_hint = UIKit.label("", 11, "#888888", HORIZONTAL_ALIGNMENT_CENTER)
		socket_block.add_child(_socket_hint)
		_content.add_child(socket_block)

	# The compare block, when there is something to compare against.
	var compare := _build_compare()
	if compare != null:
		_content.add_child(compare)

	# The button row.
	_content.add_child(_build_buttons())


## `.inv-item-overlay-close { position:absolute; top:6px; right:6px; width:24px;
## height:24px; border-radius:50% }` with the `X` glyph inside it.
##
## ⚠️  IT IS **ABSOLUTE**, AND THAT IS THE POINT. The port drew it as the first row of the
## content column, so it reserved 24px of flow plus a `gap:8px` — 32px of dead space that
## the reference does not have, pushing the icon, the name, the base label and every stat
## row down. `.inv-item-overlay-content` is `display:flex; align-items:center; gap:8px`
## with the button taken OUT of the flow, so the icon is the first thing in it. Built here
## as a sibling of the panel and placed beside the panel's own rect in `_layout()`.
##
## The visible circle is the PWA's 24px. A 24px circle is not a touch target, though, and
## Jan's "the close button is so small it is hard to press" is about the TARGET — so the
## circle grows an invisible 44x44 hit area on top of it (`CLOSE_TOUCH`). That overhang is
## free: `_place_close` sizes the holder to 24px and the hit button is an absolutely
## positioned child, so nothing about the layout moves.
func _build_close() -> void:
	_close_holder = Control.new()
	_close_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close_holder.custom_minimum_size = Vector2(CLOSE_SIZE, CLOSE_SIZE)
	add_child(_close_holder)

	# NOT named `close`: the local would shadow this class's own `close()` method, and
	# `pressed.connect(close)` then passes a BUTTON where a Callable belongs — a parse
	# error that names the wrong line and reads like a signal-connection bug.
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.add_theme_color_override("font_color", Color("#888888"))
	close_btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#1a1a1a")
	st.border_color = Color("#444444")
	st.set_border_width_all(1)
	st.set_corner_radius_all(int(CLOSE_SIZE * 0.5))
	st.set_content_margin_all(0)
	for state_name in ["normal", "hover", "focus", "disabled"]:
		close_btn.add_theme_stylebox_override(state_name, st)
	close_btn.add_theme_stylebox_override("pressed", st)
	close_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	close_btn.pressed.connect(_on_close_pressed)
	_close_holder.add_child(close_btn)

	# The touch target: a transparent Button centred on the circle, 44x44, so a thumb that
	# lands beside the X still closes the panel. Absolutely positioned, so its overhang
	# never enters the layout.
	var hit := Button.new()
	hit.focus_mode = Control.FOCUS_NONE
	_blank_style(hit)
	var over := (CLOSE_TOUCH - CLOSE_SIZE) * 0.5
	hit.offset_left = -over
	hit.offset_top = -over
	hit.offset_right = CLOSE_SIZE + over
	hit.offset_bottom = CLOSE_SIZE + over
	hit.pressed.connect(_on_close_pressed)
	_close_holder.add_child(hit)


## Place the close button at the PANEL's top-right corner, 6px inside it, in the overlay's
## own coordinates. `half_w` / `half_h` are the panel's half-extents as `_layout()` computed
## them, so this needs no second source of truth for where the panel is.
func _place_close(half_w: float, half_h: float) -> void:
	if _close_holder == null:
		return
	_close_holder.position = Vector2(
		size.x * 0.5 + half_w - CLOSE_INSET - CLOSE_SIZE,
		size.y * 0.5 - half_h + CLOSE_INSET)
	_close_holder.size = Vector2(CLOSE_SIZE, CLOSE_SIZE)


func _on_close_pressed() -> void:
	close()


## A square icon in a black box, `size` px on a side. In the PWA this is
## `renderItemIcon(item, 56)`: an inline-block span of exactly 56x56 containing an
## object-fit:contain image. The port's other icons are `TextureRect`s, and the black
## box is what keeps the icon's own black background from meeting a different fill.
func _build_icon(icon_size: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(icon_size, icon_size)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bg := ColorRect.new()
	bg.color = Color("#000000")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bg)
	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load_texture(ItemStats.icon_path(_item))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	return holder


## `.inv-item-overlay-stats` with the `.stat-row` styling: label left in #888, value
## right in #e8e0e8, both #4169E1 when the row is a rolled affix.
##
## The text comes from `ItemDetail.build_text(item, data, false)` — the ONE place that
## knows how to render an item, shared with the shop and craft screens. A mod line is
## prefixed with `MOD_PREFIX`, which is how the blue is decided without a second parser.
func _build_stats(item: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var text := ItemDetail.build_text(item, _data, false)
	for raw in text.split("\n"):
		var line := str(raw)
		if line == "":
			continue
		var is_mod := line.begins_with(ItemDetail.MOD_PREFIX)
		if is_mod:
			line = line.substr(ItemDetail.MOD_PREFIX.length())
		box.add_child(_stat_row(line, is_mod))
	return box


## `.inv-item-overlay-stats { line-height:1.7 }` — one row's line box.
static func row_line_height() -> float:
	return ROW_LINE_HEIGHT


## One `.stat-row`. The PWA splits label and value on the LAST colon it printed, which is
## visible in the text: "Damage: 12-30 (1H)  [8.5 DPS]" is one row whose label is
## "Damage" and whose value is the rest. A line with no colon is a section heading (the
## gem blocks) and gets no rule.
##
## ⚠️  THE ALIGNMENT IS `space-between`, NOT A RIGHT-ALIGNED LABEL. The row is
## `display:flex; justify-content:space-between; gap:12px` with `.stat-label` and
## `.stat-value` as two natural-width inline blocks: the label sits at the row's left edge
## and the value at its right, and whichever text is longer is measured at its true width.
## The port made the LEFT label `SIZE_EXPAND_FILL` and right-aligned the value, which is a
## different mechanism with two visible consequences:
##
##   * a label long enough to fill the row squeezes the value into a **1px box** (measured
##     on a 252px row: label 239px, value 1px), so the value is drawn ON TOP of the label
##     instead of beside it;
##   * the whole stats block overflows its own panel, because the label's minimum is its
##     last word and the sum no longer fits.
##
## A spacer between the two blocks says `space-between` with no minimum of its own, and
## both ends keep their natural size — the browser's own rule.
func _stat_row(line: String, is_mod: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(ROW_GAP))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label_text := line
	var value_text := ""
	var split := line.find(": ")
	if split > 0:
		label_text = line.substr(0, split)
		value_text = line.substr(split + 2)
	else:
		# A mod row has no colon — `ItemDetail` builds it as ONE string ("Fire Resist +11%",
		# "Mana Steal +3%  [3 - 4]") while the PWA emitted two spans. Splitting on the last
		# " +" is what recovers the reference's two columns; without it every mod line sat
		# as a single blob at the row's left edge and the block read as "weirdly aligned".
		# A flag row ("Knockback") has no " +" and stays one label, which is the honest
		# rendering of a stat that has no magnitude.
		var plus := line.rfind(" +")
		if plus > 0:
			label_text = line.substr(0, plus)
			value_text = line.substr(plus + 1)
	var colour := UIKit.MOD_BLUE if is_mod else "#888888"
	var value_colour := UIKit.MOD_BLUE if is_mod else "#e8e0e8"
	# The two ends of a `space-between` row, expressed in the ONE way Godot can hold it:
	# the LEFT label expands into whatever the right label does not use, and the RIGHT label
	# is pinned to its own full text width. (A spacer between them does NOT work — with the
	# labels' minimums zeroed, `HBoxContainer` hands them exactly 0 and both texts wrap one
	# word per line; measured: rows came out 60-80px tall with the values split across two
	# lines. A `SIZE_EXPAND_FILL` left label gets the same arithmetic with no such trap.)
	row.add_child(_row_label(label_text, colour, true))
	if value_text != "":
		row.add_child(_row_label(value_text, value_colour, false))
	# `.stat-row { padding:2px 0 }` — the row's own vertical padding, inside the rule.
	var padded := MarginContainer.new()
	padded.add_theme_constant_override("margin_top", int(ROW_PAD_V))
	padded.add_theme_constant_override("margin_bottom", int(ROW_PAD_V))
	padded.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padded.add_child(row)
	# `.stat-row { border-bottom:1px solid #1a1a1a }` — a 1px hairline under every row.
	# Drawn as a wrapper so the rule spans the row's full width.
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(padded)
	var rule := ColorRect.new()
	rule.color = Color("#1a1a1a")
	rule.custom_minimum_size = Vector2(0, 1)
	wrap.add_child(rule)
	return wrap


## One end of a stat row, on the PWA's 1.7 line-height. A `Label` has no line spacing, so
## the height comes from `line_spacing` — measured: a 12px row is 15px without it and
## 20.4px with it, which is the reference's own line box.
##
## ⚠️  `custom_minimum_size.x = 0` AS WELL. `UIKit.label` sets the minimum to the LONGEST
## WORD (the browser's `min-width:auto`), which is right when a container has to make room
## for it — but here the row's own arithmetic decides the split, and a stale minimum makes
## a label refuse to give ground. In the browser both ends sit on ONE line
## (`display:flex` does not wrap here), so the minimum is what has to give.
##
## `expands` is the pair's own asymmetry: `space-between` = the left end takes the slack.
##
## ⚠️  THE RIGHT LABEL MUST NOT WRAP. A `Label`'s minimum width is its longest WORD once
## `custom_minimum_size` has been zeroed, so a two-word value like `+3%  [3 - 4]` was handed
## ~30px and broke across two lines — measured: rows 60-80px tall against the reference's
## 25.4. `display:flex` does not wrap here, so `AUTOWRAP_OFF` is the honest setting: the
## minimum becomes the full text width, the label gets exactly that, and the LEFT label
## expands into whatever is left. It is the left end that gives ground when a row is narrow.
func _row_label(text: String, colour: String, expands: bool) -> Label:
	var l := UIKit.label(text, 12, colour)
	# ⚠️  `line_spacing` does NOT raise a SINGLE-LINE label's minimum — it is only inserted
	# BETWEEN lines, so a one-line row stayed 15px tall (measured) while the reference's
	# line box is 20.4. The height therefore comes from `custom_minimum_size.y`. Rows then
	# measure 25 against the PWA's 25.4 (2+20+2 padding, plus the 1px rule).
	l.custom_minimum_size = Vector2(0, ROW_MIN_HEIGHT)
	if expands:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


## `.inv-item-overlay-sockets { display:flex; gap:6px; justify-content:center }` with
## `.socket-slot { width:48px; height:48px; border-radius:50%; border:2px solid #555;
## background:#1a1a1a }`, and under it the gems and jewels in the bag that could go in.
##
## Called by `InventoryScreen` whenever the selection or the bag changes, so the overlay
## never reads the save itself — the caller owns the state and this owns the drawing.
func refresh_sockets(host_id: String, armed: int, inventory: Array) -> void:
	if _socket_row == null or _gem_row == null:
		return
	for child in _socket_row.get_children():
		_socket_row.remove_child(child)
		child.queue_free()
	for child in _gem_row.get_children():
		_gem_row.remove_child(child)
		child.queue_free()

	var host: Dictionary = _find_item.call(host_id) if host_id != "" else _item
	if host.is_empty():
		if _socket_hint != null:
			_socket_hint.text = "Klepni na predmet pro vlozeni gemu."
		return
	var count := int(host.get("sockets", 0))
	var filled: Array = host.get("socketedGems", [])
	for i in count:
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(48, 48)
		var record: Variant = filled[i] if i < filled.size() else null
		# An armed socket reads as chosen; an occupied one is a refusal, not an overwrite.
		var border := Color("#f1c40f") if i == armed else Color("#555555")
		cell.add_child(_circle(Color("#1a1a1a"), border))
		if record != null:
			var gem := _gem_of(record)
			if not gem.is_empty():
				var icon := TextureRect.new()
				icon.set_anchors_preset(Control.PRESET_FULL_RECT)
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.texture = _load_texture(ItemStats.icon_path(gem))
				icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cell.add_child(icon)
		var socket_index := i
		var button := Button.new()
		# NOT `flat = true`: on a Button that means "draw NO stylebox at all", and
		# `test_portrait_visual` reads every stylebox in `scripts/ui` to enforce the border
		# contract (`flat` hides the border silently). A transparent StyleBoxEmpty on every
		# state is the same invisible result and the check can still see the button.
		button.focus_mode = Control.FOCUS_NONE
		_blank_style(button)
		button.set_anchors_preset(Control.PRESET_FULL_RECT)
		button.pressed.connect(func(): socket_tapped.emit(socket_index))
		cell.add_child(button)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_socket_row.add_child(cell)

	# The gems and jewels in the bag, so the player can see what fits. A 40px cell, as the
	# socket panel had — the PWA reached these through a separate modal.
	var shown := 0
	for entry in inventory:
		var item_id: String = str(entry.get("id", "")) if entry is Dictionary else str(entry)
		var item: Dictionary = _find_item.call(item_id)
		if str(item.get("type", "")) not in ["gem", "jewel"]:
			continue
		var gem_cell := Control.new()
		gem_cell.custom_minimum_size = Vector2(40, 40)
		gem_cell.add_child(_circle(Color("#1a1a1a"), Color("#3a3a3a")))
		var gem_icon := TextureRect.new()
		gem_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		gem_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gem_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gem_icon.texture = _load_texture(ItemStats.icon_path(item))
		gem_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gem_cell.add_child(gem_icon)
		var gid := item_id
		var gem_button := Button.new()
		# Same reason as the socket button above — never `flat = true`.
		gem_button.focus_mode = Control.FOCUS_NONE
		_blank_style(gem_button)
		gem_button.set_anchors_preset(Control.PRESET_FULL_RECT)
		gem_button.pressed.connect(func(): gem_tapped.emit(gid))
		gem_cell.add_child(gem_button)
		_gem_row.add_child(gem_cell)
		shown += 1
	if _socket_hint != null:
		if count <= 0:
			_socket_hint.text = ""
		elif shown == 0:
			_socket_hint.text = "V batohu neni zadny gem."
		elif armed >= 0:
			_socket_hint.text = "Socket %d pripraven - klepni na gem." % armed
		else:
			_socket_hint.text = "Klepni na prazdny socket, pak na gem."


## A transparent, borderless stylebox for every Button state — the invisible equivalent of
## `flat = true` that `test_portrait_visual` can still SEE. The gate scans `scripts/ui` for
## `.flat = true` because a flat Button silently loses its stylebox; this keeps an
## invisible button invisible without hiding it from the check.
func _blank_style(button: Button) -> void:
	var blank := StyleBoxEmpty.new()
	for state_name in ["normal", "hover", "focus", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state_name, blank)


## A round plate: `border-radius:50%` on a 48px box. Godot has no circular stylebox, so
## the circle is a StyleBoxFlat with a corner radius of half the size — which at 48px is
## exactly a circle.
func _circle(fill: Color, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = fill
	st.border_color = border
	st.set_border_width_all(2)
	st.set_corner_radius_all(24)
	st.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", st)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


## The gem or jewel recorded in a socket. The PWA stored two shapes: a jewel as
## `{type:'jewel', jewelId}` and a gem as `{type:<gemType>, quality}`.
func _gem_of(record: Variant) -> Dictionary:
	if not (record is Dictionary):
		return {}
	var entry: Dictionary = record
	if str(entry.get("type", "")) == "jewel":
		return _find_item.call(str(entry.get("jewelId", "")))
	return _find_item.call(str(entry.get("id", "")))


## `── Equipped ──` followed by the worn item(s). Returns null when there is nothing to
## compare against, which is the PWA's `hasCompare` guard: a bag item whose slot is empty
## shows NO compare block at all.
func _build_compare() -> Control:
	var slot := str(SLOT_OF_TYPE.get(str(_item.get("type", "")), ""))
	if slot == "":
		return null

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	match str(_item.get("type", "")):
		"ring":
			# Both worn rings, each a labelled block, skipping the one that IS this item.
			for entry in [["Ring 1", "ring1"], ["Ring 2", "ring2"]]:
				var worn: Dictionary = _worn_item(str(entry[1]))
				if worn.is_empty() or str(worn.get("id", "")) == _item_id:
					continue
				_add_divider(box, str(entry[0]))
				_add_item_block(box, worn, false)
		"weapon":
			# `.inv-compare-weapon-block` — a bordered plate per hand. The off hand is a
			# weapon only when the shield slot holds something with a `weaponType`.
			var mh: Dictionary = _worn_item("weapon")
			var oh: Dictionary = _worn_item("shield")
			if not oh.is_empty() and not oh.has("weaponType"):
				oh = {}
			for entry in [["Main Hand", mh], ["Off Hand", oh]]:
				var worn: Dictionary = entry[1]
				if worn.is_empty() or str(worn.get("id", "")) == _item_id:
					continue
				_add_weapon_block(box, str(entry[0]), worn)
		_:
			var worn: Dictionary = _worn_item(slot)
			if worn.is_empty() or str(worn.get("id", "")) == _item_id:
				return null
			# `renderItemIcon(equipped, 40)` — the compare icon is 40px, not 56.
			box.add_child(_build_icon_of(worn, 40.0))
			box.add_child(_build_stats(worn))
	return box if box.get_child_count() > 0 else null


## `.inv-item-overlay-compare-divider` — the PWA prints `── Equipped ──` as a static
## HTML line, and the per-slot blocks below it replace it with "Ring 1" / "Main Hand".
func _add_divider(box: VBoxContainer, text: String) -> void:
	var label := UIKit.label(text, 10, "#555555", HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(label)


## One compared item: name in its quality colour, then the base label, then the stats.
func _add_item_block(box: VBoxContainer, item: Dictionary, with_icon: bool) -> void:
	if with_icon:
		box.add_child(_build_icon_of(item, 40.0))
	var quality := ItemStats.quality_color(item)
	var name_label := UIKit.label(str(item.get("name", "?")), 13, "#ffffff", HORIZONTAL_ALIGNMENT_LEFT, true)
	name_label.add_theme_color_override("font_color", quality)
	box.add_child(name_label)
	var base := _base_label_of(item)
	if base != "":
		box.add_child(UIKit.label(base, 11, "#888888"))
	box.add_child(_build_stats(item))


## `.inv-compare-weapon-block { border:1px solid #3a3a3a; border-radius:6px;
## padding:6px 8px; background:#141414 }` with `.inv-compare-weapon-header` above the
## weapon's name.
func _add_weapon_block(box: VBoxContainer, header: String, item: Dictionary) -> void:
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#141414")
	st.border_color = Color("#3a3a3a")
	st.set_border_width_all(1)
	st.set_corner_radius_all(6)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", st)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	column.add_child(UIKit.label(header.to_upper(), 10, "#aaaaaa"))
	var quality := ItemStats.quality_color(item)
	var name_label := UIKit.label(str(item.get("name", "?")), 13, "#ffffff", HORIZONTAL_ALIGNMENT_LEFT, true)
	name_label.add_theme_color_override("font_color", quality)
	column.add_child(name_label)
	var base := _base_label_of(item)
	if base != "":
		column.add_child(UIKit.label(base, 11, "#888888"))
	column.add_child(_build_stats(item))
	box.add_child(panel)


func _build_icon_of(item: Dictionary, icon_size: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(icon_size, icon_size)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bg := ColorRect.new()
	bg.color = Color("#000000")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bg)
	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load_texture(ItemStats.icon_path(item))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	return holder


## The item worn in `slot`, or {} when the slot is empty (or holds 'fists', which is the
## implicit unarmed pseudo-item and reads as empty).
func _worn_item(slot: String) -> Dictionary:
	if slot == "":
		return {}
	var held: Variant = _state.equip().get(slot)
	if held == null or str(held) == "" or str(held) == SLOT_DEFAULTS.get(slot, ""):
		return {}
	return _find_item.call(str(held))


## getItemBaseLabel — the base item's name, and only for a rare/unique/crafted item whose
## own name was rolled. A plain item's name IS the base name and the line is dropped.
func _base_label() -> String:
	return _base_label_of(_item)


func _base_label_of(item: Dictionary) -> String:
	var rareish: bool = item.get("rare", false) or item.get("unique", false) \
		or item.get("crafted", false) or str(item.get("quality", "")) == "rare" \
		or str(item.get("rarity", "")) == "rare" or str(item.get("rarity", "")) == "unique"
	if not rareish:
		return ""
	var ref := str(item.get("baseId", ""))
	if ref == "":
		ref = str(item.get("id", ""))
	var base: Dictionary = _find_item.call(ref)
	if base.is_empty():
		return ""
	var base_name := str(base.get("name", ""))
	if base_name == "" or base_name == str(item.get("name", "")):
		return ""
	return base_name


## `.inv-item-overlay-btn-row { display:flex; gap:6px; margin-top:10px; width:100% }`.
##
## The branch is the PWA's own and it is decided by WHERE the item came from plus its
## type: a dual-wielding class gets two buttons for a one-handed weapon, a ring gets two,
## anything else gets one, and an item that came off the doll gets Unequip.
func _build_buttons() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if _origin == "equipped":
		row.add_child(_button("Sundat", "unequip", _origin_slot))
		return row
	if _origin != "bag":
		# No selection — the PWA hides both buttons (`classList.add('hidden')`).
		return row

	var item_type := str(_item.get("type", ""))
	# A gem is not equippable and the PWA's `item.type !== 'gem'` guard is why.
	if item_type == "gem":
		return row

	var is_weapon := item_type == "weapon"
	var is_one_hand := is_weapon and not bool(_item.get("twoHand", false))
	var cls: Dictionary = _data.class_by_id(str(_state.data.get("heroClass", "")))
	var can_dual: bool = bool(cls.get("dualWield", false)) and is_one_hand

	if can_dual:
		row.add_child(_button("Do main ruky", "equip_mh", "weapon"))
		row.add_child(_button("Do off ruky", "equip_oh", "shield"))
	elif item_type == "ring":
		row.add_child(_button("Prsten 1", "equip_r1", "ring1"))
		row.add_child(_button("Prsten 2", "equip_r2", "ring2"))
	else:
		row.add_child(_button("Nasadi", "equip", str(SLOT_OF_TYPE.get(item_type, ""))))
	return row


func _button(text: String, action_key: String, slot: String) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 33)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#2a2a2a")
	st.border_color = Color("#555555")
	st.set_border_width_all(1)
	st.set_corner_radius_all(6)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	for state_name in ["normal", "hover", "focus", "disabled"]:
		button.add_theme_stylebox_override(state_name, st)
	# `:active` only — Jan's rule: no hover styling, a tap is the only feedback.
	var pressed := st.duplicate()
	pressed.bg_color = Color("#3a3a3a")
	pressed.border_color = Color("#f1c40f")
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color("#eeeeee"))
	button.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	button.pressed.connect(func(): action.emit(action_key, slot))
	return button


func _load_texture(path: String) -> Texture2D:
	if path == "":
		return null
	var full := path if path.begins_with("res://") else "res://" + path
	if not ResourceLoader.exists(full):
		return null
	return load(full)
