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
## `.tab-badge { background:#e94560 }` — the unspent-point pill on the modal's tab strip.
## The same red as `.map-*`'s accent, and NOT `BAD` (#c0392b): the PWA's own rule names it.
const TAB_BADGE_BG := "#e94560"
## `.chest-cell { background:#aaa; border:1px solid #777 }` — the grid cell fill. It is
## LIGHT: at the PWA's `.empty { opacity:0.25 }` it renders as rgb(43,43,43) inside a
## #000 box, and a filled cell is a light grey tile. Both grids read as a light lattice
## in the reference frames, not as black holes.
const CELL_FILL := "#aaaaaa"
const CELL_BORDER_EMPTY := "#777777"
## `.chest-cell.dimmed` — the PWA's inline `border-color:#e74c3c` for an item the hero's
## class cannot use. It is NOT `BD`/`BAD` (#c0392b); that is a different red used for other
## messages, and it is off the PWA's rendered border by ~25 levels per channel.
const CELL_DIM_BORDER := "#e74c3c"
## `.chest-cell.empty { opacity:0.25 }` and `.chest-cell.dimmed { opacity:0.3 }`. Kept as
## constants because the same pair is applied in three places and one of them (the bag)
## used to reach for `dimmed` with an ITEM instead of an emptiness flag.
const CELL_OPACITY_EMPTY := 0.25
const CELL_OPACITY_DIMMED := 0.35

## `.stat-row` — the item stat block, shared by the shop, chest and craft screens and the
## item-info overlay. `.stat-row { display:flex; justify-content:space-between; gap:12px;
## padding:2px 0; border-bottom:1px solid #1a1a1a }` with the block's own
## `font-size:12px; line-height:1.7`.
##
## `line-height:1.7` at 12px is 20.4px, and a Godot `Label` reports only its font's 15px
## line box — so the height is asserted through `custom_minimum_size.y`. Measured against
## the live PWA: 25.4px per row (2 + 20.4 + 2 padding, plus the 1px rule); the port then
## comes out at 25.
const STAT_ROW_GAP := 12
const STAT_ROW_MIN_HEIGHT := 20.0
const STAT_ROW_PAD_V := 2
const STAT_ROW_RULE := "#1a1a1a"

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


## A label that can always shrink — but never below its LONGEST WORD.
##
## A Godot Label reports its whole UNWRAPPED text as its minimum width and a container
## honours that minimum, so a single long line was widening whole screens past the 390px
## canvas (measured: the craft screen built 447px wide and the chest 554px, i.e. 60-160px
## of every screen sat off the right edge). In a browser a long line wraps inside its
## parent — this makes `label()` behave the same way.
##
## ⚠️ The wrapping mode decides the label's minimum WIDTH, and the naive fix is worse than
## the bug. `AUTOWRAP_WORD_SMART` (and WORD, and ARBITRARY) report a minimum of **ONE
## CHARACTER**, measured: every one of "Dobrodruh", "Smrti 0   Vítězství 0", "Poškození"
## comes back `min=(1.0, 23.0)`. A container hands a child that does not EXPAND exactly
## that minimum, so every such label was given a 1px-wide box and wrapped one character
## per line — the vertical "ribbon of letters" Jan reported on the Stats tab, and the
## reason the panel's content came out 1931px tall instead of 591. Only `AUTOWRAP_OFF`
## reports the real width (86px for "Dobrodruh"), and turning wrapping off brings the
## off-canvas screens straight back.
##
## Three ways to override that minimum were measured and only the third works:
##   * `_get_minimum_size()` on a Label subclass — never called (Label overrides it in C++);
##   * shadowing the native `text` property — a parse error;
##   * overriding `get_minimum_size()` — "overrides a method from native class" and, here,
##     that warning is treated as an error.
## What DOES work is `custom_minimum_size`, plus a recompute that runs on every path that
## can change the text:
##   * `label()` computes it at construction;
##   * `write()` sets the text and recomputes — use it, not `.text =`, on any label whose
##     text changes later;
##   * the `minimum_size_changed` signal is connected as well — it fires when the label is
##     a plain child of a Control, but **measured: NOT when a container owns its size**
##     (inside an `HBoxContainer` the signal never arrived for a `text` write, which is
##     exactly where the 1px minimum bites). That is why `write()` exists instead of
##     relying on the signal alone.
##
## (`set_text()` would be the natural name and is a PARSE ERROR here: it overrides
## `Label.set_text()` and this project treats that warning as an error.)
##
## The minimum is the width of the LONGEST WORD — what a browser uses for `min-width:auto`
## on a flex item, i.e. what the PWA's CSS does — so the label still wraps at spaces when a
## container gives it less room. Callers that want a wider label give it SIZE_EXPAND_FILL,
## which still works.
##
## ⚠️ `clip_text = true` collapses the minimum HEIGHT to 1 PIXEL, measured:
## "Poškození" is `min=(64.0, 23.0)` without it and `min=(64.0, 1.0)` with it. A container
## hands a non-expanding child exactly its minimum, so every `.hero-detail-item` row came
## out 1px tall — six details in a 198px grid collapsed into a 30px strip. It was added as
## a width workaround (`right.clip_text = true` in `screen_page`/`page_header`) BEFORE the
## longest-word minimum existed, and it is now redundant: the width is already capped.
## Do not use `clip_text` on a label inside a row that has to have a height.
class FlexLabel extends Label:
	## Guards the recursion: `custom_minimum_size` is itself a minimum, so writing it
	## re-emits `minimum_size_changed`.
	var _fixing := false

	func _init() -> void:
		minimum_size_changed.connect(_recompute)

	## Set the text AND keep the minimum correct. Prefer this over `.text =` on any label
	## whose text changes after construction — a stale minimum is the 1px bug.
	## Not named `set_text`: that overrides `Label.set_text()` and the warning is an error.
	func write(value: String) -> void:
		text = value
		_recompute()

	func _recompute() -> void:
		if _fixing:
			return
		var f: Font = get_theme_font("font")
		var fs: int = get_theme_font_size("font_size")
		if f == null:
			return
		var widest := 0.0
		for word in text.split(" ", false):
			widest = maxf(widest, f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if is_equal_approx(custom_minimum_size.x, widest):
			return
		_fixing = true
		custom_minimum_size.x = widest
		_fixing = false


## `bold` is the CSS `font-weight: bold` — a real face (see `UIFonts`), not an embolden
## pass, because DejaVu's bold is 13% wider and the reference frames are drawn with it.
static func label(text: String, size: int = 14, colour: String = TEXT,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, bold: bool = false) -> Label:
	var l := FlexLabel.new()
	l.text = text
	l.add_theme_font_override("font", UIFonts.get_font(size, bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(colour))
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# The signal fires on a re-shape, which can happen before the font is in place; this
	# is the one guaranteed measurement.
	l._recompute()
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
	# `.page-header { padding:16px 20px; border:1px solid #444; box-sizing:border-box }`.
	# `box-sizing:border-box` means the 20px padding is measured from INSIDE the border, so
	# the PWA's icon sits at x = 16 (container) + 1 (border) + 20 (padding) = 37. In Godot a
	# PanelContainer's stylebox border is drawn inside the panel's own rect, so a content
	# margin of 20 puts the icon at 36 — one pixel left of the reference on all four screens
	# that use this header. The top/bottom margin already carries the +1 (17); the sides must
	# carry it too.
	style.content_margin_left = 21
	style.content_margin_right = 21
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


## `.btn.btn-shop-buy` — the item card's price button. NOT a `.btn`: it is
## `display:inline-flex; width:fit-content; padding:8px 16px; border:1px solid #555;
## border-radius:6px; background:#333; font-size:14px; line-height:1`, holding a 16px coin
## icon and a bold 14px price with a 6px gap.
##
## Measured on the live PWA: **69x34** for the price `15`. The port hardcoded 130x40 — the
## button is right-aligned, so the extra 61px is invisible against the card's right edge
## until the price is short, and the 6px of extra height pushed the card's bottom down.
## `can_afford` is the PWA's `opacity:0.5` on the whole button, applied here as a dimmed
## fill rather than an opacity so the price's own colour survives.
static func shop_buy_button(cost: int, can_afford: bool, font_size: int = 14) -> Button:
	var coin := load_texture("res://assets/items/coin_gold.png")
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	# `.btn { margin:6px 0 }` — carried by the caller's `margin_box`, so only the vertical
	# size is stated here. The WIDTH is set at the end, from the content.
	b.size_flags_horizontal = Control.SIZE_SHRINK_END

	# The icon and the price as two children of an HBoxContainer, because a Godot Button
	# cannot put a texture and a label side by side with a gap on its own.
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)

	if coin != null:
		var icon := TextureRect.new()
		icon.texture = coin
		icon.custom_minimum_size = Vector2(16, 16)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(icon)

	var price := label("%d" % cost, font_size, GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(price)
	b.add_child(inner)

	# ⚠️  `width:fit-content`, and a Godot Button derives its minimum from its own `text` and
	# `icon` only, NEVER from child CONTROLS: measured, this button reported a minimum of
	# **2x34** (2 = the stylebox's two 1px borders) whatever was inside it, and the card's
	# `HBoxContainer` handed it exactly that — every Buy and every Sell button was laid out
	# **2 px wide at x=359**, with the coin and the price drawn outside its own rect and past
	# the card's right edge. Jan's report was "the Buy and Sell buttons are not in the shop
	# at all", and a 2px button IS that.
	#
	# A `MarginContainer` cannot carry the CSS `padding:8px 16px` either — measured, it
	# reported `min=(19, 23)` for a 19px label, i.e. it does not add its own margins into the
	# minimum at all. So the padding is added to the measured CONTENT here and the content is
	# centred inside the box: 16 on each side, exactly what the CSS padding does.
	#
	# Read AFTER the children are in — a container's combined minimum counts its children
	# only once they are added. Measured 15+16+6+16+16 = 69 for the price `15`, which is the
	# PWA's own button width to the pixel.
	b.custom_minimum_size = Vector2(inner.get_combined_minimum_size().x + 32.0, 34)

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#333333") if can_afford else Color("#333333", 0.5)
	style.border_color = Color("#555555")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	for state_name in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(state_name, style)
	var pressed := style.duplicate()
	pressed.bg_color = Color("#444444")
	b.add_theme_stylebox_override("pressed", pressed)
	# `.btn-shop-buy { color:#eee }` — the text lives in child Labels, so the theme colour
	# does not reach them; the price keeps its own `#f1c40f`.
	if not can_afford:
		price.modulate = Color(1, 1, 1, 0.5)
	return b


## A vertical gap of exactly `height` pixels. CSS gives every card and button its own
## margin; a container gives all children the same separation, so the difference is added
## explicitly at the one place the measurement says it belongs.
static func gap(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


## A wrapper that adds `top` / `bottom` pixels OUTSIDE its child, so one element can carry
## its own CSS margin inside a container that has a single separation for every child.
##
## `.shop-item-header { margin-bottom:6px }` is the case that needs it: the card's box uses
## `separation = 6`, which applies BETWEEN children, so the gap under the LAST child (the
## header, when the item has no stats) has to be added rather than inherited.
##
## The inner box reports `child + top + bottom` as its minimum and fits the child into the
## box minus those margins — the one shape Godot calls for both.
static func margin_box(child: Control, top: float, bottom: float) -> Control:
	var box := MarginBox.new()
	box.setup(child, top, bottom)
	return box


class MarginBox extends Container:
	var _child: Control = null
	var _top := 0.0
	var _bottom := 0.0

	func setup(c: Control, t: float, b: float) -> void:
		_child = c
		_top = t
		_bottom = b
		add_child(c)

	func _get_minimum_size() -> Vector2:
		if _child == null:
			return Vector2.ZERO
		var m := _child.get_combined_minimum_size()
		return Vector2(m.x, m.y + _top + _bottom)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN and _child != null:
			fit_child_in_rect(_child, Rect2(Vector2(0, _top), Vector2(size.x,
				maxf(0.0, size.y - _top - _bottom))))


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
		# `.shop-tab / .craft-tab { padding:10px; font-size:14px; border:1px }` measures 38px
		# in the live PWA, not 40 — 10 + 10 + a 14px line box + the 1px borders, and the
		# port's extra 2px pushed the whole list below it down.
		b.custom_minimum_size = Vector2(0, 38)
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


## The item STAT BLOCK, as the PWA's `.stat-row` list — the shared renderer for the shop,
## the chest and the craft screen.
##
## ⚠️  This is NOT `item_tooltip`. The PWA's `.shop-item-stats` is a bare block of rows with
## NO border, no background and no padding:
##
##   .shop-item .shop-item-stats { font-size:12px; color:#ccc; line-height:1.7;
##                                 text-align:left; width:100% }
##   .stat-row { display:flex; justify-content:space-between; gap:12px;
##               padding:2px 0; border-bottom:1px solid #1a1a1a }
##   .stat-label { color:#888 }  .stat-value { color:#e8e0e8 }
##   .stat-value.mod, .stat-label.mod { color:#4169E1 }
##
## The port used `item_tooltip` here, which is a `PanelContainer` with `panel_style()` —
## i.e. a black box with a 1px `#333` border around the whole block, plus 13px text and a
## 1px separation between lines. That container border IS Jan's "a strange border around
## them", and the 13px-vs-12px with no line box is the "too-small text, no line spacing".
##
## `size` defaults to the PWA's own 12px, and each row carries `line-height:1.7`'s 20.4px
## line box, which a Godot Label does NOT report on its own (measured: 15px).
static func stat_block(item: Dictionary, data: Node, size: int = 12) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if item.is_empty():
		return box
	var text := ItemDetail.build_text(item, data, false)
	for raw in text.split("\n"):
		var line := str(raw)
		if line == "":
			continue
		var is_mod := line.begins_with(ItemDetail.MOD_PREFIX)
		if is_mod:
			line = line.substr(ItemDetail.MOD_PREFIX.length())
		box.add_child(stat_row(line, is_mod, size))
	return box


## `.craft-result-stats { background:#141414; border:1px solid #3a3a3a; border-radius:8px;
## padding:10px; font-size:12px; color:#ccc; line-height:1.7; width:100%;
## box-sizing:border-box }` with `.stat-row:last-child { border-bottom:none }`.
##
## ⚠️  ITS OWN WRAPPER, and the difference from `stat_block` is not decoration: the craft
## result genuinely has a `#141414` plate, while the SHOP's `.shop-item-stats` has none.
## A port that gives the shop the bordered box is the one Jan reported ("a strange border
## around them"); a port that gives the craft none loses the plate the reference has.
##
## ⚠️  The width is `100%` + `box-sizing:border-box`, so the box never exceeds its parent —
## `item_tooltip`'s `custom_minimum_size.x` is a MINIMUM a container must honour, and 420
## of them on a 390px canvas is what pushed this block off the screen.
static func stat_panel(item: Dictionary, data: Node, size: int = 12) -> Control:
	var panel := PanelContainer.new()
	var style := panel_style("#3a3a3a")
	style.bg_color = Color("#141414")
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	if item.is_empty():
		return panel
	var text := ItemDetail.build_text(item, data, false)
	var lines: Array = []
	for raw in text.split("\n"):
		var line := str(raw)
		if line != "":
			lines.append(line)
	for i in lines.size():
		var line := str(lines[i])
		var is_mod := line.begins_with(ItemDetail.MOD_PREFIX)
		if is_mod:
			line = line.substr(ItemDetail.MOD_PREFIX.length())
		# `.stat-row:last-child { border-bottom:none }`
		box.add_child(stat_row(line, is_mod, size, i < lines.size() - 1))
	return panel


## `.stat-row { padding:2px 0; border-bottom:1px solid #1a1a1a }` — the rule spans the row's
## full width, so it is drawn as a wrapper. `show_rule` is false for the LAST row of the
## item-info overlay, whose CSS has `.stat-row:last-child { border-bottom:none }`; the
## shop's block has no such exclusion and keeps every rule.
static func stat_row(line: String, is_mod: bool, size: int = 12,
		show_rule: bool = true) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", STAT_ROW_GAP)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# The PWA emitted a label and a value as two SPANS. `ItemDetail` renders one string per
	# row, so the split is recovered here: on ": " when the type block used one, else on the
	# last " +" for a mod line ("Fire Resist +11%"). A flag row with no magnitude
	# ("Knockback") stays a single label, which is the honest rendering.
	var label_text := line
	var value_text := ""
	var split := line.find(": ")
	if split > 0:
		label_text = line.substr(0, split)
		value_text = line.substr(split + 2)
	else:
		var plus := line.rfind(" +")
		if plus > 0:
			label_text = line.substr(0, plus)
			value_text = line.substr(plus + 1)

	row.add_child(stat_cell(label_text, MOD_BLUE if is_mod else "#888888", size, true))
	if value_text != "":
		row.add_child(stat_cell(value_text, MOD_BLUE if is_mod else "#e8e0e8", size, false))

	var padded := MarginContainer.new()
	padded.add_theme_constant_override("margin_top", STAT_ROW_PAD_V)
	padded.add_theme_constant_override("margin_bottom", STAT_ROW_PAD_V)
	padded.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padded.add_child(row)
	if not show_rule:
		return padded

	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(padded)
	var rule := ColorRect.new()
	rule.color = Color(STAT_ROW_RULE)
	rule.custom_minimum_size = Vector2(0, 1)
	wrap.add_child(rule)
	return wrap


## One end of a `space-between` row.
##
## ⚠️  AUTOWRAP OFF ON BOTH ENDS, and the row's own minimum is the proof: with wrap left on,
## a `FlexLabel`'s minimum width is its widest word, its minimum HEIGHT then assumes the text
## breaks across that width, and `.stat-row` came back **105px** tall for a one-line stat.
## In the PWA a `.stat-label` is a flex item sized by its content, so there is nothing to wrap
## against — that is what `line-height:1.7`'s single 20.4px line box assumes. Same trap as the
## potion box's spans.
static func stat_cell(text: String, colour: String, size: int, expands: bool) -> Label:
	var l := label(text, size, colour)
	l.custom_minimum_size = Vector2(0, STAT_ROW_MIN_HEIGHT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	if expands:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


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
## ⚠️ THE PWA ALSO SETS `background:#000` ON THE ICON ITSELF, and that is what makes a
## FILLED cell read as BLACK in the reference frames (`renderItemIcon`'s `size === 0`
## branch: `<img style="…;background:#000">`). A filled cell therefore never shows the
## `#aaa` at all — the icon covers it edge to edge. The port's icon was inset by
## `size * 0.1` (`.cell-icon img { width:80% }`, which is only true for the `size !== 0`
## branch the bag does NOT use), so every filled cell kept a grey ring of `#aaa` around its
## icon. Measured: the port had 3 546 pixels of `#aaa` in the bag band against the PWA's 2.
##
## `is_empty` must be the EMPTINESS of the slot, never a property of the item. This
## function's third parameter is `dimmed`, an item the hero's class cannot use; an earlier
## caller passed `item.is_empty()` into it, so every empty bag cell took the `.dimmed`
## branch (opacity 0.35 -> rgb(59,59,59)) instead of `.empty` (0.25 -> rgb(43,43,43)).
static func item_cell(item: Dictionary, size: float, dimmed: bool = false,
		placeholder: String = "") -> Button:
	var cell := Button.new()
	cell.custom_minimum_size = Vector2(size, size)
	cell.focus_mode = Control.FOCUS_NONE
	var is_empty := item.is_empty()
	var border := Color(CELL_BORDER_EMPTY)
	if not is_empty:
		border = ItemStats.quality_color(item)
		if dimmed:
			# `.chest-cell.dimmed` inline: `border-color:#e74c3c` — the RED replaces the
			# quality colour, it does not sit beside it.
			border = Color(CELL_DIM_BORDER)
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
	# NOT get a second alpha of its own. Only an EMPTY cell dims; a filled one is opaque.
	if is_empty:
		cell.modulate = Color(1, 1, 1, CELL_OPACITY_EMPTY)
	elif dimmed:
		cell.modulate = Color(1, 1, 1, CELL_OPACITY_DIMMED)

	var icon_path := ""
	if not is_empty:
		icon_path = ItemStats.icon_path(item)
	elif placeholder != "":
		icon_path = placeholder
	if icon_path != "":
		var texture := load_texture(icon_path)
		if texture != null:
			# ⚠️ `background:#000` ON THE ICON IS PART OF THE SPEC, but ONLY for a real item.
			# `renderItemIcon`'s `size === 0` branch writes it inline on the `<img>`, and it
			# is what fills the two bands beside a NON-square icon (measured: a 73x108 slot
			# draws a 73x73 icon with black bands above and below). Without it those bands
			# are transparent and the `#aaa` tile shows through them, which reads as "the
			# bag cells are grey" — the same symptom as the inverted `dimmed` flag, from the
			# other side. Measured in the bag band: 6 049 pixels of `#aaa` the PWA lacks.
			#
			# An EMPTY cell never gets it: the PWA writes `<div class="chest-cell empty">`
			# with no icon at all, and the tile is supposed to show through.
			if not is_empty:
				var backing := ColorRect.new()
				backing.color = Color("000000")
				backing.set_anchors_preset(Control.PRESET_FULL_RECT)
				backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cell.add_child(backing)
			var icon := TextureRect.new()
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			# ⚠️ FULL BLEED, no inset. The bag renders its icon with `size === 0`, whose
			# `<img>` is `width:100%; height:100%; background:#000` — it covers the whole
			# cell. `.cell-icon img { width:80% }` in style.css is overridden by that inline
			# style, exactly as `object-fit:cover` is, and reading the stylesheet instead of
			# the inline style is what put an 80% icon in a 100% cell.
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

