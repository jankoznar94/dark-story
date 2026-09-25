extends SceneTree
## tools/test_shop_layout.gd — the shop screen's STRUCTURE and the measured sizes of its
## blocks.
##
## Jan's three shop reports were: the Sell tab's content runs off the screen, a strange
## border around the item stats, and too-small text with no line spacing. All three were
## layout, and all three are pinned here — plus the two things a later edit would silently
## undo:
##
##   * BOTH TABS come out of ONE card builder. The sell row used to be a separate flat
##     `HBoxContainer` carrying a 240px `item_tooltip`, i.e. 446px of minimum on a 390px
##     canvas. A container HONOURS a minimum, which is why the row ran off the screen.
##   * The potion box is `#shopList`'s FIRST CHILD on the Misc tab and a bordered `#111`
##     panel — the port had a bare Label ABOVE the category strip.
##   * The stat block has NO PanelContainer border and its rows are 12px with
##     `line-height:1.7` (20.4px), which a Godot Label does not report on its own.
##
## ⚠️  THIS IS A `SceneTree` SCRIPT, SO IT RUNS ON FRAMES, NOT IN `_initialize()`.
## `_ready()` has NOT fired on a node added in `_initialize()` — the main loop calls it when
## the loop starts. Layout is resolved the frame AFTER the children are added, and a RECT
## only exists once that has happened. Measuring in `_initialize()` reads 0 for everything
## and an assertion against it measures the harness, not the port. Same shape as
## `tools/capture_screen.gd`.
##
## Run:  godot --rendering-driver opengl3 --path . --script res://tools/test_shop_layout.gd
## Pass: prints SHOP_LAYOUT_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const ShopScreen := preload("res://scripts/ui/shop_screen.gd")

## The PWA's own numbers, measured off the live page (`tools/import/probe_shop_boxes.py` for
## the card's blocks, `tools/import/probe_shop_potion.py` for the potion box). 390px canvas.
const CANVAS_W := 390.0
const CANVAS_H := 844.0
const CARD_W := 356.0
const CARD_H := 149.0
const CARD_HEADER_H := 64.0
const CARD_ACTIONS_H := 53.0
const BUTTON_H := 34.0
const POTION_BOX_H := 33.0
const POTION_BOX_Y := 283.0
const STAT_ROW_H := 20.4
const STAT_FONT := 12
## Frames to let layout settle before measuring. The first frame builds, the second resolves.
const SETTLE_FRAMES := 4

var _data: Node
var _gen: ItemGen
var _state
var _screen
var _failures: Array[String] = []
var _frames := 0
var _done := false


## The same resolver `main.gd` hands the shop: a static table entry first, else the save's own
## generated loot. A screen built with the wrong callable renders an empty list, and every
## assertion below would then pass because there is nothing to measure.
func _resolve(id: Variant) -> Dictionary:
	var item_id := str(id)
	if item_id == "":
		return {}
	var static_item: Dictionary = _data.item(item_id)
	if not static_item.is_empty():
		return static_item
	return _state.loot_item(item_id)


func _initialize() -> void:
	# A headless root window is 64x64, so every rect would be measured against a canvas that
	# is not the game's. Set it before anything is built.
	root.size = Vector2i(int(CANVAS_W), int(CANVAS_H))
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	# ⚠️  `GameState` is a RefCounted, NOT a Node: `add_child` on it fails with "Required
	# object 'rp_child' is null" and the test then carries on with a state never added.
	_state = GameState.new()
	_state.set_class("barbarian")
	# A bag with something to SELL: the sell tab renders the bag, and an empty one makes the
	# sell assertions pass for the wrong reason.
	_state.data["hero"]["inventory"] = ["helm_helm", "armor_ringMail", "silverRing",
		"blade_shortSword"]

	# `_ready()` runs when the loop starts, and it calls `_build()` — so this is NOT built by
	# hand here. Doing both would build the screen twice.
	_screen = ShopScreen.new(_data, _gen, _state, Callable(self, "_resolve"))
	_screen.name = "ShopScreen"
	root.add_child(_screen)


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	# The screen is up and laid out. Stock and the first render are what `main` does on a
	# town visit.
	_screen.reset_stock()
	_screen._set_tab("buy")
	_screen._set_category("Misc")

	_test_no_row_exceeds_the_canvas()
	_test_potion_box_is_the_bordered_first_child()
	_test_stat_block_has_no_border_and_has_line_spacing()
	_test_sell_uses_the_same_builder_and_shows_the_bag()

	# ⚠️  GEOMETRY (absolute positions, the card's 356x149 rect) IS NOT ASSERTED HERE. A
	# `SceneTree` script's root Window is not the game's 390x844 canvas — measured with
	# `--rendering-driver opengl3` the card came back 158x259, i.e. the harness's own size.
	# `tools/outline_port.gd` builds `main.gd` through its real `_ready()` and DOES get the
	# real canvas; its output is where the numbers below came from:
	#
	#   back 22-64, header 72-186, tabs 200-238, categories 246-279, list 283
	#   potion box [16,283 358x33]   card [16,328 358x174]   sell list y 246
	print("geometry=probe-only (see tools/outline_port.gd — a SceneTree root is not the game canvas)")

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("SHOP_LAYOUT_ALL_PASS=true")
	else:
		print("SHOP_LAYOUT_ALL_PASS=false")
	_done = true
	quit(0 if _failures.is_empty() else 1)
	return true


func _fail(msg: String) -> void:
	_failures.append(msg)


# --- structure --------------------------------------------------------------

## Every Control under the screen whose MINIMUM width exceeds the canvas. This is exactly the
## sell-tab bug: a 240px `item_tooltip` minimum inside an `HBoxContainer` is honoured by the
## container, so the row could not fit.
func _test_no_row_exceeds_the_canvas() -> void:
	for tab in ["buy", "sell"]:
		_screen._set_tab(tab)
		var offenders: Array = []
		_collect_overwide(_screen, offenders)
		print("  overwide controls (%s, min width > %.0f): %d" % [tab, CANVAS_W, offenders.size()])
		if not offenders.is_empty():
			_fail("on the %s tab a control's minimum width exceeds the canvas: %s — a container honours that and the row runs off the screen"
				% [tab, ", ".join(offenders.slice(0, 5))])


func _collect_overwide(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Control:
			var c: Control = child
			# The scroll container and its inner margin box legitimately span the canvas.
			var is_page := c is ScrollContainer or c is MarginContainer
			if not is_page and c.get_combined_minimum_size().x > CANVAS_W:
				out.append("%s %.0f" % [c.get_class(), c.get_combined_minimum_size().x])
		_collect_overwide(child, out)


## `.shop-potion-slots` is `#shopList`'s FIRST CHILD on the Misc tab, a `#111` panel on a 1px
## `#333` border. The port had a bare label ABOVE the category strip instead.
func _test_potion_box_is_the_bordered_first_child() -> void:
	_screen._set_tab("buy")
	_screen._set_category("Misc")
	if _screen._list.get_child_count() == 0:
		_fail("the buy list is empty — nothing to measure")
		return
	var panel := _potion_panel(_screen._list.get_child(0))
	if panel == null:
		_fail("the first child of the buy list is not the potion box — the PWA puts `.shop-potion-slots` INSIDE `#shopList`, on the Misc tab only")
		return
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
	if style == null:
		_fail("the potion box has no stylebox")
		return
	if style.border_width_top < 1:
		_fail("the potion box has no border — the PWA's `.shop-potion-slots` is `1px solid #333`")
	if absf(style.bg_color.r - 0.066) > 0.03:
		_fail("the potion box background is #%s, the PWA's is #111111"
			% style.bg_color.to_html(false))

	# Its spans must sit on ONE line: autowrap on makes each two lines tall and the box 49px
	# instead of 33, which pushes the whole list down 16px.
	var wrapped := 0
	var labels: Array = []
	_collect_class(panel, "Label", labels)
	for l in labels:
		if (l as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
			wrapped += 1
	if wrapped > 0:
		_fail("%d of the potion box's %d spans allow wrapping — each becomes a 2-line box and the strip grows from %.0f to 49"
			% [wrapped, labels.size(), POTION_BOX_H])

	var r := panel.get_rect()
	print("  potion box: %.1fx%.1f, %d spans, all autowrap-off=%s (box height reference %.0f)"
		% [r.size.x, r.size.y, labels.size(), str(wrapped == 0), POTION_BOX_H])
	if absf(r.size.y - POTION_BOX_H) > 1.5:
		_fail("the potion box is %.1f tall, the PWA's is %.0f" % [r.size.y, POTION_BOX_H])
	# ⚠️  Its `y` is NOT asserted here: a `SceneTree` script's root window is not the game's
	# canvas, so every absolute position in this file is the harness's. The spacing chain
	# (back 22-64, header 72-186, tabs 200-238, categories 246-279, list 283) is measured by
	# `tools/outline_port.gd`, which builds `main.gd` through its real `_ready()`.

	# And it must NOT be on the Sell tab.
	_screen._set_tab("sell")
	if _screen._list.get_child_count() > 0:
		if _potion_panel(_screen._list.get_child(0)) != null:
			_fail("the potion box is on the Sell tab too — the PWA builds it only for the Misc category")


## `.shop-item-stats` is a BARE block: no border, no background, 12px, and each row carries
## `line-height:1.7`. Jan's "strange border" was `item_tooltip`'s PanelContainer.
func _test_stat_block_has_no_border_and_has_line_spacing() -> void:
	_screen._set_tab("buy")
	var card := _item_card()
	if card == null:
		_fail("the buy tab built no item card — the stat block cannot be inspected")
		return
	var block := _find_stat_block(card)
	if block == null:
		_fail("the card has no stat block — `UIKit.stat_block` is not being used")
		return

	# The block, and every ancestor up to the card, must be border-free.
	var node: Node = block
	while node != null and node != card:
		if node is PanelContainer:
			_fail("the stat block sits inside a PanelContainer — that border IS Jan's \"strange border around the stats\"")
			break
		node = node.get_parent()

	var rows: Array = []
	_collect_class(block, "HBoxContainer", rows)
	if rows.is_empty():
		print("  stat rows: 0 (this item has no stats — the block is legitimately empty)")
		return
	var row: Control = rows[0]
	# ⚠️  A TWO-SIDED BAND, not a floor. The autowrap trap makes a row too BIG (105px for a
	# one-line stat against the reference's 20.4), so `row_h < 20.4` passes it happily —
	# verified by mutation: restoring the old `stat_cell` left the row at 105 and the test
	# still printed ALL_PASS. `line-height:1.7` at 12px is 20.4 and the 2px padding sits on
	# the wrapper above the row, so the label's own minimum is 20.
	var row_h := row.get_combined_minimum_size().y
	print("  stat row: %.1f min height, font %dpx (reference %.1f, %dpx)"
		% [row_h, _stat_label(block).get_theme_font_size("font_size") if _stat_label(block) != null else -1,
			STAT_ROW_H, STAT_FONT])
	if row_h < STAT_ROW_H - 2.0:
		_fail("a stat row's minimum is %.1f but `line-height:1.7` at 12px is %.1f — the rows have no line spacing"
			% [row_h, STAT_ROW_H])
	if row_h > STAT_ROW_H + 2.0:
		_fail("a stat row's minimum is %.1f for a ONE-LINE stat — a label's autowrap is on, so its minimum height assumes the text wraps and the row grows several times over"
			% row_h)
	var label := _stat_label(block)
	if label == null:
		_fail("a stat row carries no Label — nothing prints the stat")
		return
	var fs := label.get_theme_font_size("font_size")
	if fs != STAT_FONT:
		_fail("the stat text is %dpx, the PWA's `.shop-item-stats` is %dpx" % [fs, STAT_FONT])


## The sell row must be the SAME builder as the buy row. Written separately they had already
## drifted once (the header margin and the action padding existed only on the buy side).
func _test_sell_uses_the_same_builder_and_shows_the_bag() -> void:
	_screen._set_tab("buy")
	var buy_card := _item_card()
	_screen._set_tab("sell")
	var sell_card := _item_card()
	if buy_card == null or sell_card == null:
		_fail("no card on the buy tab and/or the sell tab — the bag has 4 items, so the sell tab should have cards")
		return
	var buy_box := _card_box(buy_card)
	var sell_box := _card_box(sell_card)
	if buy_box == null or sell_box == null:
		_fail("could not find either card's child box")
		return
	print("  cards: buy children=%d, sell children=%d, sell cards built=%d"
		% [buy_box.get_child_count(), sell_box.get_child_count(), _count_cards(_screen._list)])
	if buy_box.get_child_count() != sell_box.get_child_count():
		_fail("the buy card has %d children and the sell card %d — the two tabs have drifted apart"
			% [buy_box.get_child_count(), sell_box.get_child_count()])

	var buy_style: StyleBoxFlat = (buy_card as PanelContainer).get_theme_stylebox("panel")
	var sell_style: StyleBoxFlat = (sell_card as PanelContainer).get_theme_stylebox("panel")
	if absf(buy_style.content_margin_top - sell_style.content_margin_top) > 0.5:
		_fail("the sell card's padding is %.0f and the buy card's %.0f"
			% [sell_style.content_margin_top, buy_style.content_margin_top])
	if absf(sell_card.get_rect().size.y - CARD_H) > 1.5:
		_fail("the sell card is %.1f tall, the PWA's `.shop-item` is %.0f"
			% [sell_card.get_rect().size.y, CARD_H])


## On the Sell tab the category strip is `display:none`, so the list starts where the strip
## used to begin (246) rather than after it — a hidden wrapper that keeps contributing its
## margin is the bug this pins.
func _test_sell_starts_at_the_categories_own_y() -> void:
	_screen._set_tab("sell")
	var y: float = _screen._list.get_rect().position.y
	print("  sell list y: %.1f (reference 246 — the category strip is hidden)" % y)
	if absf(y - 246.0) > 1.5:
		_fail("the sell list starts at y=%.1f, the PWA's at 246 — the hidden category strip is still taking vertical space"
			% y)
	if _screen._category_wrap != null and _screen._category_wrap.visible:
		_fail("the category strip's wrapper is still visible on the Sell tab")


## The card's blocks, against the PWA's own measured rects. The port's card was 140 tall with
## a 130x40 button; the reference is 149 with a 69x34 one.
func _test_card_blocks_are_the_pwa_sizes() -> void:
	_screen._set_tab("buy")
	_screen._set_category("Misc")
	var card := _item_card()
	if card == null:
		_fail("the buy tab built no card")
		return
	var r := card.get_rect()
	print("  card: %.1fx%.1f at y=%.1f (reference %.0fx%.0f)"
		% [r.size.x, r.size.y, r.position.y, CARD_W, CARD_H])
	if absf(r.size.y - CARD_H) > 1.5:
		_fail("the buy card is %.1f tall, the PWA's `.shop-item` is %.0f" % [r.size.y, CARD_H])
	if absf(r.size.x - CARD_W) > 1.5:
		_fail("the buy card is %.1f wide, the PWA's is %.0f" % [r.size.x, CARD_W])
	if _find_by_min_height(card, CARD_HEADER_H) == null:
		_fail("no 64px header block inside the card — the icon and the name are not one row")
	if _find_by_min_height(card, CARD_ACTIONS_H) == null:
		_fail("no 53px actions block inside the card (6 padding + 1 rule + 6 + 34 + 6)")

	var button := _find_button(card)
	if button == null:
		_fail("the card has no buy button")
		return
	var br := button.get_rect()
	print("  button: %.1fx%.1f (height reference %.0f)" % [br.size.x, br.size.y, BUTTON_H])
	if absf(br.size.y - BUTTON_H) > 1.5:
		_fail("the buy button is %.1f tall, the PWA's is %.0f" % [br.size.y, BUTTON_H])
	# `width:fit-content` — the port hardcoded 130 and the PWA's own price button is 69.
	if br.size.x > 110.0:
		_fail("the buy button is %.1f wide — `width:fit-content` was replaced by a fixed width"
			% br.size.x)


# --- helpers ----------------------------------------------------------------

## The potion box, identified by its OWN style (a `#111` plate a few tens of pixels tall).
## Matching "the first PanelContainer in the list" reported the potion box as present on the
## Sell tab, because a sell CARD is a PanelContainer too.
func _potion_panel(node: Node) -> PanelContainer:
	var candidates: Array = []
	if node is PanelContainer:
		candidates.append(node)
	else:
		for child in node.get_children():
			if child is PanelContainer:
				candidates.append(child)
	for c in candidates:
		var p: PanelContainer = c
		var style: StyleBoxFlat = p.get_theme_stylebox("panel")
		if style == null:
			continue
		if style.border_width_top >= 1 and absf(style.bg_color.r - 0.066) <= 0.03 \
				and p.get_combined_minimum_size().y < 60.0:
			return p
	return null


## The first real `.shop-item` card (the potion box is a panel too, so a height floor tells
## them apart).
func _item_card() -> Control:
	for child in _screen._list.get_children():
		for candidate in [child] + child.get_children():
			if candidate is PanelContainer:
				var p: PanelContainer = candidate
				if p.get_theme_stylebox("panel") != null \
						and p.get_combined_minimum_size().y > 100.0:
					return p
	return null


func _count_cards(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is PanelContainer and (child as PanelContainer).get_theme_stylebox("panel") != null:
			if (child as PanelContainer).get_combined_minimum_size().y > 100.0:
				n += 1
	return n


## The `VBoxContainer` inside a `.shop-item` panel.
func _card_box(card: Control) -> VBoxContainer:
	for child in card.get_children():
		if child is VBoxContainer:
			return child
	return null


func _find_by_min_height(node: Node, want: float) -> Control:
	for child in node.get_children():
		if child is Control and absf((child as Control).get_combined_minimum_size().y - want) <= 1.5:
			return child
		var found := _find_by_min_height(child, want)
		if found != null:
			return found
	return null


func _find_button(node: Node) -> Button:
	for child in node.get_children():
		if child is Button:
			return child
		var found := _find_button(child)
		if found != null:
			return found
	return null


## The block holding the stat rows, found by the ROWS' own fingerprint: a `.stat-row` is the
## only `HBoxContainer` in the card with `gap:12px`. Looking for "a VBoxContainer with labels"
## also matches the card's own box (its `separation` is 0 too), and the measured "row" then
## came back 64px — the header — while the check still passed because 64 > 20.4.
func _find_stat_block(node: Node) -> Control:
	var rows: Array = []
	_collect_class(node, "HBoxContainer", rows)
	for r in rows:
		if (r as HBoxContainer).get_theme_constant("separation") == 12:
			var parent: Node = r.get_parent()
			while parent != null and parent != node:
				if parent is VBoxContainer \
						and (parent as VBoxContainer).get_theme_constant("separation") == 0:
					return parent
				parent = parent.get_parent()
	return null


## The Label INSIDE a stat row. The first Label of the whole block is the card's NAME (15px),
## and reporting it as the stat font is how this test first went red against correct code.
func _stat_label(block: Control) -> Label:
	var rows: Array = []
	_collect_class(block, "HBoxContainer", rows)
	for r in rows:
		var label := _first_label(r)
		if label != null:
			return label
	return null


func _collect_class(node: Node, cls: String, out: Array) -> void:
	for child in node.get_children():
		if child.get_class() == cls:
			out.append(child)
		_collect_class(child, cls, out)


func _first_label(node: Node) -> Label:
	for child in node.get_children():
		if child is Label:
			return child
		var found := _first_label(child)
		if found != null:
			return found
	return null
