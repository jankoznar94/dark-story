extends Control
class_name CharacterModal
## CharacterModal — the PWA's single modal with the Inventory / Skills / Stats tabs.
##
## This is the structure the port got wrong. In the PWA, `inventory`, `talents` and
## `hero` are NOT screens: `showScreen()` routes all three into `openModal()`, which
## builds ONE `.modal-content` holding a `.combined-tabs` strip and a `.modal-body`
## with three `.combined-screen` wrappers. Only the active wrapper is laid out
## (`.combined-screen { display:none }`, `.active { display:flex }`).
##
## The port had them as three separate screens behind the nav bar, so "the hero screen"
## showed the portrait, the attributes, the stat sheet AND the whole skill trees in one
## column — a shape the PWA never had, and the main reason the two read as different games.
##
## The overlay is `rgba(0,0,0,0.7)` with `backdrop-filter: blur(4px)`. Godot has no
## backdrop blur on a 2D canvas under the Compatibility renderer, so the dim is drawn and
## the blur is not — a deliberate deviation, and the reason the PWA's blurred game world
## behind the modal becomes a flat dark field here.

const UIKit := preload("res://scripts/ui/ui_kit.gd")
const InventoryScreen := preload("res://scripts/ui/inventory_screen.gd")
const SkillsPanel := preload("res://scripts/ui/skills_panel.gd")
const StatsPanel := preload("res://scripts/ui/stats_panel.gd")

signal back_pressed()
signal message(text: String)
signal item_tapped(inventory_index: int)
signal equip_slot_tapped(slot: String)
signal potion_slot_tapped(index: int)
signal socket_armed(host_id: String, socket_index: int)
signal gem_tapped(host_id: String, gem_id: String)
## A button inside the item-info overlay was pressed — see `ItemInfoOverlay.action`.
signal overlay_action(action: String, slot: String)

## The PWA's tab strip, in order: `{id:'inventory',label:'Inventory'}`,
## `{id:'talents',label:'Skills'}`, `{id:'hero',label:'Stats'}`.
const TABS := [
	["inventory", "Inventar"],
	["skills", "Dovednosti"],
	["stats", "Staty"],
]

## `.modal-content { width:98%; max-width:800px; min-height:85vh; max-height:90vh;
##   border-radius:14px; border:1px solid #333; background:#000 }` on a 390px canvas:
## 98% of 390 is 382, so the max-width never binds. The HEIGHT is 85vh — measured on the
## live PWA at 390x844 the dialog is y=63..780, which is 717px, exactly `min-height:85vh`;
## `min-height` wins because the panes fit inside it and `max-height:90vh` (760) never
## binds. `MAX_HEIGHT_RATIO` is kept as the documented ceiling for panes that overflow.
const WIDTH_RATIO := 0.98
const MIN_HEIGHT_RATIO := 0.85
const MAX_HEIGHT_RATIO := 0.90
const RADIUS := 14

var _data: Node
var _gen
var _state
var _find_item: Callable

var _panel: PanelContainer
var _tabs_wrap: Control
var _scroll: ScrollContainer
var _tab_buttons: Dictionary = {}
var _tab_labels: Dictionary = {}
var _tab_badges: Dictionary = {}
var _panes: Dictionary = {}
var _inventory
var _skills
var _stats
var _active := "inventory"


func _init(game_data: Node, gen, state, find_item: Callable) -> void:
	_data = game_data
	_gen = gen
	_state = state
	_find_item = find_item


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


## The dialog's height depends on the laid-out size of its panes, which is only known after
## a layout pass — `set_tab()` cannot clamp correctly on the very first call. Two frames are
## enough (one to lay out, one to apply), and the guard stops the loop after that.
var _height_settled := 0


func _process(_delta: float) -> void:
	if _height_settled >= 2:
		set_process(false)
		return
	_height_settled += 1
	_apply_panel_height()


## Each pane carries its OWN padding, measured with `probe_pane_pwa.py`. The port applied
## one uniform 4px body margin to all three, which made the talents tree 34px too wide
## (its cells came out 118 against the PWA's 106.7) and left the inventory's bag grid
## sitting 12px too low.
##
## [tab, top, right, bottom, left] — the `container` div's own `padding`, per `style.css`:
##   `#inventoryScreen`  `.container` overridden to `padding:0 4px`
##   `#talentsScreen`    `.container { padding:16px 16px 70px }`
##   `#heroScreen`       `.container` overridden to `padding:0 4px 16px`
const PANE_PADDING := {
	"inventory": [0.0, 4.0, 0.0, 4.0],
	"skills": [16.0, 16.0, 70.0, 16.0],
	"stats": [0.0, 4.0, 16.0, 4.0],
}


func _build() -> void:
	# `.modal-overlay { background:rgba(0,0,0,0.7); align-items:center; justify-content:center }`
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# A tap on the overlay itself closes the modal, as the PWA's
	# `onclick="game.closeModal()"` does.
	dim.gui_input.connect(_on_overlay_input)
	add_child(dim)

	var centre := Control.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	# IGNORE means this node is itself transparent to input but its CHILDREN are still
	# hit-tested — which is exactly what is needed: a tap on the panel is the panel's, a
	# tap on the dim margin falls through to `dim` and closes the modal, as the PWA's
	# `onclick="game.closeModal()"` on the overlay does.
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#000000")
	style.border_color = Color("#333333")
	style.set_border_width_all(1)
	style.set_corner_radius_all(RADIUS)
	# ⚠️ `content_margin_all(0)` PUT THE TABS ON TOP OF THE BORDER. A `StyleBoxFlat`'s
	# content margin is where the children go and it is INDEPENDENT of where the border is
	# drawn: with 0 the child starts at the panel's own top-left and the 1px border is
	# painted over. MEASURED against the live PWA, whose `.modal-content` box INCLUDES its
	# 1px border (`box-sizing:border-box`), the port's tabs sat at y=42.2 against the PWA's
	# 43.2 — a 1px offset inherited by EVERY block in the dialog, on top of the 1px the tab
	# strip itself was short (below). The content margin is the border width, which is what
	# the default would have been if the override had not zeroed it.
	style.set_content_margin_all(1)
	_panel.add_theme_stylebox_override("panel", style)
	# `.modal-content { width:98%; min-height:85vh; max-height:90vh; height:auto }` centred by
	# `.modal-overlay { align-items:center }`. The height is CONTENT-DRIVEN and bounded at
	# both ends, which a fixed anchor ratio cannot express — measured on the live PWA the
	# Stats dialog is 717px (exactly `min-height:85vh`, its content fits) while the Inventory
	# one is taller, because its content is. A fixed 85vh made the Stats tab right and the
	# Inventory tab 25px short; a fixed 90vh did the opposite. `_apply_panel_height()` does
	# the clamp and is called whenever the visible pane changes.
	_panel.anchor_left = 0.01
	_panel.anchor_right = 0.99
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	centre.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_panel.add_child(box)

	_tabs_wrap = _build_tabs()
	box.add_child(_tabs_wrap)

	# `.modal-body { flex:1; overflow-y:auto; padding:0 4px }` — the scroll belongs to the
	# body, not to the dialog, so the tab strip stays put while a long pane scrolls.
	# The body's own `padding` here is 0: the PWA's `0 4px` is the `#inventoryScreen`
	# override, and each pane brings its OWN padding (`PANE_PADDING`). Applying 4px to all
	# three panes was the bug — a `MarginContainer` under the scroll cannot vary per child.
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Same as every page: no scrollbar drawn, the finger does the scrolling.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.scroll_deadzone = 8
	box.add_child(scroll)

	var swipe := ScrollSwipe.new()
	swipe.setup(scroll)
	box.add_child(swipe)

	var body := MarginContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("margin_left", 4)
	body.add_theme_constant_override("margin_right", 4)
	body.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(body)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(stack)

	_inventory = InventoryScreen.new(_data, _gen, _state)
	_inventory.back_pressed.connect(_on_inner_back)
	_inventory.item_tapped.connect(func(i): item_tapped.emit(i))
	_inventory.equip_slot_tapped.connect(func(s): equip_slot_tapped.emit(s))
	_inventory.potion_slot_tapped.connect(func(i): potion_slot_tapped.emit(i))
	_inventory.socket_armed.connect(func(h, i): socket_armed.emit(h, i))
	_inventory.gem_tapped.connect(func(h, g): gem_tapped.emit(h, g))
	_inventory.overlay_action.connect(func(a, s): overlay_action.emit(a, s))
	_skills = SkillsPanel.new(_data, _state, _find_item)
	_skills.message.connect(func(t): message.emit(t))
	_stats = StatsPanel.new(_data, _gen, _state, _find_item)
	_stats.message.connect(func(t): message.emit(t))

	for entry in TABS:
		var key := str(entry[0])
		# A `MarginContainer` per pane carrying that pane's OWN CSS padding. The 4px body
		# margin it replaces was uniform across all three tabs, which is why the talents
		# tree was 34px too wide and the stats content sat 4px off.
		var pad: Array = PANE_PADDING.get(key, [0.0, 4.0, 0.0, 4.0])
		var pane_margin := MarginContainer.new()
		pane_margin.add_theme_constant_override("margin_top", int(pad[0]))
		pane_margin.add_theme_constant_override("margin_right", int(pad[1]))
		pane_margin.add_theme_constant_override("margin_bottom", int(pad[2]))
		pane_margin.add_theme_constant_override("margin_left", int(pad[3]))
		pane_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# The pane is the margin box: `set_tab()` toggles visibility on THIS node, and its
		# minimum is the padded content, which `_apply_panel_height()` reads.
		var pane := VBoxContainer.new()
		pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pane_margin.add_child(pane)
		pane_margin.visible = false
		stack.add_child(pane_margin)
		_panes[key] = pane_margin

	# The inventory screen is built as a full page (its own back button and title) because
	# it predates the modal. Inside the modal the PWA's tab strip replaces that chrome, so
	# the page is embedded and its own header is dropped — the panel's `hide_chrome()`
	# removes the "Zpet do mesta"/"Inventar" row rather than leaving a second title under
	# the tab that already says which tab this is.
	_inventory.hide_chrome()
	# `_panes` holds the PADDING box (a `MarginContainer`); the panel goes into its inner
	# column, or the padding would be applied to the wrong node and the panels would each be
	# laid out inside a box the size of the padding rather than the body.
	(_panes["inventory"] as MarginContainer).get_child(0).add_child(_inventory)
	# `#invItemOverlay { position:fixed; inset:0; z-index:1200 }` — OUTSIDE the inventory
	# pane, covering the whole dialog. Its own layer is inside `_panel`, so it cannot be
	# clipped by the pane it belongs to. Mounted after the pane so it paints on top.
	_inventory.mount_overlay(self)
	(_panes["skills"] as MarginContainer).get_child(0).add_child(_skills)
	(_panes["stats"] as MarginContainer).get_child(0).add_child(_stats)

	set_tab(_active)


## `.combined-tabs { display:flex; gap:4px; padding:12px 16px 8px;
##                    border-bottom:1px solid #2a2a2a; align-items:center }` plus the
## `.modal-close` circle at the end of the row.
## `.tab-badge` — the red unspent-points pill, and the ONLY marker the player has that a
## talent or attribute point is waiting. The PWA's own condition, verbatim:
##
##   `if (t.id === 'talents' && talentPts > 0) badge = ...`
##   `if (t.id === 'hero' && attrPts > 0) badge = ...`
##
## `attrPoints` lives on the HERO while `talentPoints` lives on the state root — the two
## are read from different places on purpose, because that is where the save puts them.
func _tab_badge_text(key: String) -> String:
	var points := 0
	match key:
		"skills":
			points = int(_state.data.get("talentPoints", 0))
		"stats":
			points = int(_state.hero().get("attrPoints", 0))
	if points <= 0:
		return ""
	return str(points)


func _build_tabs() -> Control:
	var wrap := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0)
	st.border_color = Color("#2a2a2a")
	st.set_border_width_all(0)
	st.border_width_bottom = 1
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 12
	# ⚠️ 8 + 1, NOT 8. `StyleBoxFlat`'s content margin does NOT include the border, while
	# the PWA's `padding:8px` sits INSIDE its `border-bottom:1px` — so the faithful value is
	# padding + border. Measured: the strip came out **54** tall against the PWA's **55**,
	# and its bottom edge is exactly where `#inventoryScreen` starts, so every block in the
	# pane sat 1px high. The 1px of overlap is invisible (the border draws in that margin).
	st.content_margin_bottom = 9
	wrap.add_theme_stylebox_override("panel", st)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	wrap.add_child(row)

	for entry in TABS:
		var key := str(entry[0])
		# `.combined-tab { flex:1; padding:8px 6px; border:1px solid #2a2a2a; border-radius:8px;
		#   font-size:12px; font-weight:bold; display:flex; align-items:center;
		#   justify-content:center }`
		#
		# ⚠️ THE TAB IS **34** px TALL, NOT 32, and the 2px difference moves the WHOLE modal.
		# MEASURED on the live PWA: the active tab is [20.9, 56.2, 101.4, **32**] but the two
		# INACTIVE ones are [126.3, 55.2, 101.4, **34**] — same `padding:8px 6px`, same
		# `font-size:12px`, different height. The active tab is `.combined-tab.active` and the
		# difference is its CONTENT: an active tab also renders a `.tab-badge` (the red count
		# pill), whose `line-height:16px` is what the flex row centres in the 8px+8px padding.
		# An inactive tab has no badge, so nothing bounds its line box below the padding's
		# 32 and the browser falls back to the font's own `line-height:normal` (~1.2em of 12px
		# plus ascender/descender slack), landing on 34.
		#
		# The strip's own height is `12 + max(child) + 8` + 1px border = **55**, and the port's
		# 32-tall tabs made it 52 — so `#inventoryScreen` and every block under it sat 3px high,
		# and the dialog came out 3px short. The doll alone was then 4px high because its own
		# 12px top margin landed on a body already 3px up.
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 34)
		button.focus_mode = Control.FOCUS_NONE
		# `.combined-tab { display:flex; align-items:center; justify-content:center; gap:4px }`
		# — the label and the badge are SIBLINGS in a centred flex row, and a `Button`'s own
		# text cannot carry a second colour. A badge drawn as part of the text is one colour
		# for both, so the pill becomes its own child and the button's text is emptied.
		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 4)
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		button.add_child(inner)
		var label := UIKit.label(str(entry[1]), 12, "#888888")
		label.add_theme_font_size_override("font_size", 12)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(label)
		var badge_text := _tab_badge_text(key)
		var badge: Label = null
		if badge_text != "":
			# `.tab-badge { margin-left:4px; padding:0 5px; background:#e94560; color:#fff;
			#   border-radius:8px; font-size:10px; line-height:16px }`. MEASURED on the live
			# PWA: the Skills pill is 24 x 16 at x 187-210 and the Stats one 31 x 16 at
			# x 289-319, both rows 64-79 — 16 tall, which its `line-height` sets and which is
			# what makes the whole tab 34 rather than 32.
			badge = UIKit.label(badge_text, 10, "#ffffff")
			badge.add_theme_font_size_override("font_size", 10)
			badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# ⚠️  THE PILL'S BACKGROUND MUST LIVE ON THE BOX AROUND THE TEXT, not on the text
			# itself. `padding:0 5px` is part of the pill: putting the stylebox on the Label
			# drew the red only behind the glyphs — MEASURED, the Skills pill came out 13 wide
			# against the PWA's 24, i.e. the 10px of padding was missing on both sides, and a
			# `MarginContainer` around it cannot carry a background at all. A `PanelContainer`
			# with `content_margin_left/right = 5` is the shape that does both.
			var pill := PanelContainer.new()
			var bs := StyleBoxFlat.new()
			bs.bg_color = Color(UIKit.TAB_BADGE_BG)
			bs.set_corner_radius_all(8)
			bs.content_margin_left = 5
			bs.content_margin_right = 5
			pill.add_theme_stylebox_override("panel", bs)
			# ⚠️  THE PILL IS 16 TALL, NOT THE TAB'S INNER HEIGHT. `.tab-badge`'s own
			# `line-height:16px` is what sizes it, and the PWA's flex row centres that 16px
			# line in the tab's 8px+8px padding — 16 + 16 = 32... but the INACTIVE tabs
			# measure 34, because a tab with no badge has no line box bounding it and the
			# browser falls back to `line-height:normal`. MEASURED before this fix: the port
			# drew the pill 33 tall (the tab's whole inner box) and 22 wide at y 55, against
			# the PWA's 16 at y 64 — 2 216 of the 3 032 differing pixels in the tab band, the
			# largest single block of diff left on the screen. `SHRINK_CENTER` refuses the
			# row's height; `custom_minimum_size.y` states the 16 the CSS declares.
			badge.custom_minimum_size = Vector2(0, 16)
			pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			# `.tab-badge { margin-left:4px }` sits ON TOP of the flex row's own `gap:4px`,
			# so the gap between the label and the pill is 8 — measured on the live PWA: the
			# "Skills" glyphs end at x=177 and the pill starts at 187.
			pill.add_theme_constant_override("margin_left", 4)
			pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pill.add_child(badge)
			inner.add_child(pill)
		button.pressed.connect(func(): set_tab(key))
		row.add_child(button)
		_tab_buttons[key] = button
		_tab_labels[key] = label
		_tab_badges[key] = badge

	# `.modal-close { width:32px; height:32px; border-radius:50%; font-size:16px;
	#   color:#888; background:#000; border:1px solid #333 }`
	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(32, 32)
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 13)
	close.add_theme_color_override("font_color", Color("#888888"))
	close.add_theme_color_override("font_color_pressed", Color("#ffffff"))
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color("#000000")
	cs.border_color = Color("#333333")
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(16)
	cs.set_content_margin_all(0)
	for state_name in ["normal", "hover", "focus", "disabled"]:
		close.add_theme_stylebox_override(state_name, cs)
	close.add_theme_stylebox_override("pressed", cs)
	close.pressed.connect(func(): back_pressed.emit())
	row.add_child(close)

	_style_tabs()
	return wrap


## `.combined-tab { background:#1a1a1a; color:#888; border:1px solid #2a2a2a }`
## `.combined-tab.active { background:#2a2a2a; border-color:#4a7dff; color:#fff }`
func _style_tabs() -> void:
	for key in _tab_buttons:
		var button: Button = _tab_buttons[key]
		var active := str(key) == _active
		var st := StyleBoxFlat.new()
		st.bg_color = Color("#2a2a2a") if active else Color("#1a1a1a")
		st.border_color = Color(UIKit.MOD_BLUE) if active else Color("#2a2a2a")
		st.set_border_width_all(1)
		st.set_corner_radius_all(8)
		st.content_margin_left = 6
		st.content_margin_right = 6
		st.content_margin_top = 8
		st.content_margin_bottom = 8
		# One style for every state: Jan's rule is no hover/focus styling, so there is no
		# second style that could drift into a hover look.
		for state_name in ["normal", "pressed", "hover", "focus", "disabled"]:
			button.add_theme_stylebox_override(state_name, st)
		var colour := "#ffffff" if active else "#888888"
		button.add_theme_color_override("font_color", Color(colour))
		button.add_theme_color_override("font_color_pressed", Color(colour))
		# The button's own text is EMPTY; the visible label is a child, so its colour is set
		# here. The badge keeps `color:#fff` in both states — the PWA's `.tab-badge` rule has
		# no `.active` variant, so a red pill is white whether its tab is up or not.
		if _tab_labels.has(key):
			(_tab_labels[key] as Label).add_theme_color_override("font_color", Color(colour))


func set_tab(key: String) -> void:
	if not _panes.has(key):
		return
	_active = key
	for pane_key in _panes:
		(_panes[pane_key] as Control).visible = str(pane_key) == key
	_style_tabs()
	refresh()
	# The dialog's height follows its content, so switching tab re-clamps it.
	_apply_panel_height()


## `.modal-content { height:auto; min-height:85vh; max-height:90vh }`.
##
## A fixed anchor ratio cannot say this. Measured on the live PWA at 390x844: the Stats
## dialog is 717px tall — exactly `min-height:85vh`, because its content fits inside the
## minimum — while the Inventory dialog is 742px, because its content is taller than the
## minimum and the box grew to fit. Pinning the port to either end got one tab right and
## the other one wrong (85vh: talents 6.9% but inventory 25.9%; 90vh: inventory better,
## stats 29%).
##
## The clamp needs the pane's real laid-out height, which is not known at build time, so
## this runs from `set_tab()` and from `_process` until the panel has settled once. The
## panel is positioned by its CENTRE (`anchor_top == anchor_bottom == 0.5`) and offset by
## half the height — that is `align-items:center` expressed without knowing the height in
## advance, which is what the PWA's flexbox does.
func _apply_panel_height() -> void:
	if _panel == null or _panes.is_empty() or _tabs_wrap == null:
		return
	var view := size.y
	if view <= 0.0:
		# No layout pass has happened yet; `_process` retries.
		return
	var min_h := view * MIN_HEIGHT_RATIO
	var max_h := view * MAX_HEIGHT_RATIO

	# The content's own height: the tab strip plus the visible pane's minimum. Asking the
	# pane for `get_combined_minimum_size()` is what the browser does with `height:auto`.
	var content := _tabs_wrap.get_combined_minimum_size().y
	for pane_key in _panes:
		var pane: Control = _panes[pane_key]
		if pane.visible:
			content += pane.get_combined_minimum_size().y
	var want: float = clampf(content, min_h, max_h)
	if is_equal_approx(want, _panel.size.y):
		return
	var half := want * 0.5
	_panel.offset_top = -half
	_panel.offset_bottom = half


func refresh() -> void:
	match _active:
		"inventory":
			_inventory.refresh()
		"skills":
			_skills.refresh()
		"stats":
			_stats.refresh()


## The inventory screen is embedded as a tab rather than being a screen of its own, so
## callers that used to reach `_screens["inventory"]` — the equip/unequip/socket handlers
## in `main.gd` — reach it through here. Kept as a getter rather than a public field so
## there is one name for "the inventory" in both the modal and the router.
func inventory() -> Control:
	return _inventory


func _on_inner_back() -> void:
	# The inventory screen's own back button asks to leave the town-ward; inside the modal
	# the only sensible reading of that is "close the dialog".
	back_pressed.emit()


## A tap on the dim area outside the panel closes the modal, as the PWA's overlay
## `onclick` does. `_panel` swallows its own input, so this only fires on the margin.
func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		back_pressed.emit()
	elif event is InputEventScreenTouch and event.pressed:
		back_pressed.emit()
