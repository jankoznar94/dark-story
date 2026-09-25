extends Control
class_name ShopScreen
## ShopScreen — buy and sell, laid out from the PWA's `.page-header` / `.shop-tabs` /
## `.shop-cat-tabs` / `.shop-item` rules.
##
## Source: `renderShop` / `buyItem` / `sellItem` plus `index.html`'s `#shopScreen` block.
## The PWA's shop is:
##
##   .shop-back-map      a full-width "Back to Town" button at the very top
##   .page-header        80px icon, "Shop", "Buy and sell equipment", gold on the right
##   .shop-tabs          Buy / Sell, the active one bordered #4a7dff
##   .shop-cat-tabs      Misc / Armor / Weapons / Jewelry, the active one #f1c40f
##   .shop-item          a black card, 8px radius, 64px icon, name, stat rows, and the
##                       price at the bottom right
##
## Two things this screen does NOT do, both deliberate:
##
##   * It owns no prices and no stock rules. `ShopStock` generates the offer and decides
##     what a purchase does; this file only draws it and reports taps.
##   * It does not cache the stock itself. The cache lives in `main.gd` and is cleared on
##     every town visit — the PWA reset its cache in `renderTown`, and re-entering town
##     must produce a new offer.
##
## Buying marks the item as bought and removes it from the list for this visit, except for
## consumables, crafting materials and gems, which stay buyable — the same rule the PWA
## had, and the reason a player can buy ten potions in one trip but only one sword.

const UIKit := preload("res://scripts/ui/ui_kit.gd")
const ShopStock := preload("res://scripts/items/shop_stock.gd")
const ItemStats := preload("res://scripts/items/item_stats.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")

signal back_pressed()
signal message(text: String)

const CATEGORIES := ["Misc", "Armor", "Weapons", "Jewelry"]

var _data: Node
var _gen: ItemGen
var _state
var _find_item: Callable
var _stock: Array = []

var _tab := "buy"
var _category := "Misc"
var _bought: Array[String] = []

var _list: VBoxContainer
var _tab_buttons: Array = []
var _category_row: HBoxContainer
## The wrapper that carries `.shop-cat-tabs { margin-bottom:4px }`. It is hidden TOGETHER
## with the strip, because the PWA sets `display:none` on the strip itself — a wrapper left
## visible would keep contributing its 4px and push the list down on the Sell tab.
var _category_wrap: Control
var _gold_label: Label


func _init(game_data: Node, gen: ItemGen, state, find_item: Callable) -> void:
	_data = game_data
	_gen = gen
	_state = state
	_find_item = find_item


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	# `.container` — 16px sides, 70px at the bottom for the nav bar. Every screen is built
	# on this, which is what makes "scroll works everywhere" one implementation.
	var page := UIKit.screen_page(self, UIKit.BACK_BTN_PAD)
	var column: VBoxContainer = page["column"]
	# ⚠️  `separation = 0` and every gap carried by the block that OWNS it, because the PWA's
	# screen is normal flow with COLLAPSING margins. Measured on the live PWA:
	#
	#   back       22-64   `.shop-back-map { margin:4px 0 8px }`, `.btn { margin:6px 0 }`
	#   header     72-186  `.page-header { margin:0 0 14px }` -> collapses with the tabs' 8
	#   tabs      200-238  `.shop-tabs { margin:8px 0 }` -> collapses with catTabs' 4
	#   catTabs   246-279  `.shop-cat-tabs { margin:4px 0 }`
	#   list      283-…    `#shopList` has no margin at all
	#
	# A single `separation` cannot express that: 8 everywhere gives the tabs at 194 instead of
	# 200 and the list at 287 instead of 283.
	column.add_theme_constant_override("separation", 0)

	# `.shop-back-map` then `.page-header`, exactly the PWA's order.
	var back := UIKit.back_button()
	back.pressed.connect(func(): back_pressed.emit())
	column.add_child(UIKit.margin_box(back, 0, 8))

	var header := UIKit.page_header("assets/menu-icons/shop.png", "Obchod",
		"Nakup a prodej vybaveni", "0 zlata")
	_gold_label = header["right"]
	# `.page-header { margin:0 0 14px }` — 14, not the 8 the column would give it.
	column.add_child(UIKit.margin_box(header["root"], 0, 14))

	# `.shop-tabs { margin:8px 0 }` — 8 under it, collapsing with the category strip's 4.
	var tabs := UIKit.tab_row(["Koupit", "Prodat"], 0, UIKit.MOD_BLUE)
	_tab_buttons = tabs["buttons"]
	_tab_buttons[0].pressed.connect(func(): _set_tab("buy"))
	_tab_buttons[1].pressed.connect(func(): _set_tab("sell"))
	column.add_child(UIKit.margin_box(tabs["root"], 0, 8))

	# `.shop-cat-tabs { margin:4px 0 }` — 4 under it, and NOTHING at all when it is hidden
	# (a bare `margin_box` would keep contributing its 4px on the Sell tab, where the PWA
	# has `display:none` and the list moves up to 246 instead of 283).
	_category_row = HBoxContainer.new()
	_category_row.add_theme_constant_override("separation", 4)
	_category_wrap = UIKit.margin_box(_category_row, 0, 4)
	column.add_child(_category_wrap)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_list)


## Called by main on every town visit: a new offer, and nothing marked as bought.
func reset_stock() -> void:
	_stock = []
	_bought = []
	_tab = "buy"
	_category = "Misc"
	_ensure_stock()


func _ensure_stock() -> void:
	if _stock.is_empty():
		_stock = ShopStock.generate(_data, _gen, _state, _find_item, _rng())


func _set_tab(tab: String) -> void:
	_tab = tab
	refresh()


func _set_category(category: String) -> void:
	_category = category
	refresh()


func refresh() -> void:
	_ensure_stock()
	_gold_label.text = "%d zlata" % int(_state.hero().get("gold", 0))
	for i in _tab_buttons.size():
		var active := (_tab == "buy" and i == 0) or (_tab == "sell" and i == 1)
		var style := UIKit.panel_style(UIKit.MOD_BLUE if active else "#2a2a2a", 1)
		if active:
			style.bg_color = Color("#111111")
		style.set_corner_radius_all(8)
		for state_name in ["normal", "hover", "focus", "disabled"]:
			_tab_buttons[i].add_theme_stylebox_override(state_name, style)
		_tab_buttons[i].add_theme_color_override("font_color",
			Color("#ffffff") if active else Color("#cccccc"))

	_rebuild_categories()
	_clear(_list)
	if _tab == "sell":
		_render_sell()
	else:
		_render_buy()


func _rebuild_categories() -> void:
	_clear(_category_row)
	# The WRAPPER hides with the strip: `display:none` is on the strip itself, so on the Sell
	# tab it contributes neither its buttons nor its 4px margin.
	_category_wrap.visible = _tab == "buy"
	_category_row.visible = _tab == "buy"
	if _tab != "buy":
		return
	for section in _stock:
		var visible_items := _visible_items(section)
		if visible_items.is_empty():
			continue
		var category := str(section["category"])
		var button := Button.new()
		button.text = category
		# `.shop-cat-tab { padding:8px; border:1px; font-size:13px }` measures 33 in the live
		# PWA (8 + 8 + 15 line box + 1 + 1 border), not the port's 36. `box-sizing:border-box`
		# again: a Godot Button's stylebox border is drawn OUTSIDE `custom_minimum_size`, so
		# the minimum has to be 33 and the stylebox's own vertical padding must be 0 — a
		# Button centres its text itself, and any content margin here would double the 8.
		button.custom_minimum_size = Vector2(0, 33)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 13)
		var active := category == _category
		# `.shop-cat-tab.active { background:#111; border-color:#f1c40f; color:#f1c40f }`
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#111111") if active else Color("#000000")
		style.border_color = Color(UIKit.GOLD) if active else Color("#2a2a2a")
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(0)
		for state_name in ["normal", "hover", "focus", "disabled"]:
			button.add_theme_stylebox_override(state_name, style)
		button.add_theme_color_override("font_color",
			Color(UIKit.GOLD) if active else Color("#888888"))
		button.pressed.connect(func(): _set_category(category))
		_category_row.add_child(button)


func _visible_items(section: Dictionary) -> Array:
	var out: Array = []
	for item in section.get("items", []):
		if not _bought.has(str(item.get("id", ""))):
			out.append(item)
	return out


func _render_buy() -> void:
	var section: Dictionary = {}
	for s in _stock:
		if str(s["category"]) == _category:
			section = s
	if section.is_empty():
		_list.add_child(UIKit.label("Nic k prodeji", 14, UIKit.DIM))
		return

	# ⚠️  THE POTION BOX IS THE LIST'S FIRST CHILD, not a label sitting above the category
	# strip. `.shop-potion-slots` is `#shopList`'s own content on the Misc tab only:
	#
	#   <div class="shop-potion-slots" style="display:flex;align-items:center;gap:8px;
	#        padding:8px 12px;margin-bottom:8px;background:#111;border:1px solid #333;
	#        border-radius:8px;font-size:13px;color:#ddd">
	#
	# Measured on the live PWA: `[16,283 358x33]`, margin-bottom 8. The port had a bare 13px
	# Label above the strip, which moved everything below it and had no plate.
	if _category == "Misc":
		_list.add_child(_potion_slot_box())

	var items := _visible_items(section)
	if items.is_empty():
		_list.add_child(UIKit.label("Nic k prodeji", 14, UIKit.DIM))
		return
	for item in items:
		_list.add_child(_buy_row(item))


## `.shop-potion-slots` — a `#111` box on a 1px `#333` border, 8px/12px padding, radius 8,
## holding three spans with a `gap:8px`: the label, the free count (green when positive,
## red at zero) and `(used/total used)` in grey.
func _potion_slot_box() -> Control:
	var total: int = int(_state.total_potion_slots(_find_item))
	var used := 0
	for pid in _state.equip().get("beltPotionSlots", []):
		if pid != null:
			used += 1
	var free := maxi(0, total - used)

	var panel := PanelContainer.new()
	var style := UIKit.panel_style("#333333")
	style.bg_color = Color("#111111")
	style.set_corner_radius_all(8)
	# ⚠️  `box-sizing:border-box` again: the PWA's 12/8 padding is measured from INSIDE the
	# 1px border, and `StyleBoxFlat.get_margin()` returns `max(border_width, content_margin)` —
	# so a content margin of 12 next to a 1px border is still 12 and the box ships 2px narrow
	# (31 against 33) with its spans at x=28 against the reference's 29. The padding has to
	# carry the border: 12+1 and 8+1. Same rule as `page_header`'s 21.
	style.content_margin_left = 13
	style.content_margin_right = 13
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	panel.add_child(row)

	row.add_child(UIKit.label("Potion slots:", 13, "#dddddd"))
	# `color:${free > 0 ? '#2ecc71' : '#e74c3c'};font-weight:bold`
	row.add_child(UIKit.label("%d free" % free, 13, "#2ecc71" if free > 0 else "#e74c3c", 
		HORIZONTAL_ALIGNMENT_LEFT, true))
	row.add_child(UIKit.label("(%d/%d used)" % [used, total], 13, "#888888"))

	# ⚠️  AUTOWRAP OFF ON EVERY SPAN, and the box's height is the proof: measured through the
	# real route the strip came out 49 tall against the PWA's 33, because a FlexLabel's
	# minimum WIDTH is its widest word ("slots:") and its minimum HEIGHT assumes it may wrap.
	# The `HBoxContainer` handed it exactly that width, the text did not fit on one line, and
	# every span rendered TWO lines — 8+8 padding + 2 border + 31 of text instead of 15.
	#
	# A CSS flex span with `white-space:normal` still does not wrap here: it is a flex item
	# whose width is its content, so there is nothing to wrap against. That is what the PWA
	# measures (33 = 16 padding + 2 border + a 15px line box).
	for child in row.get_children():
		if child is Label:
			(child as Label).autowrap_mode = TextServer.AUTOWRAP_OFF

	# `margin-bottom:8px`, and it COLLAPSES with the `.shop-category { margin:12px 0 }` that
	# wraps the cards: `max(8, 12) = 12`. The list's own separation is already 8, so the
	# wrapper contributes the remaining 4 — a plain 8 here put the first card at 332 against
	# the reference's 328.
	return UIKit.margin_box(panel, 0, 4)


## `.shop-item` — a black card, 8px radius and a 1px #2a2a2a border, with the icon, the
## name in its quality colour, the stat block and the price at the bottom right.
##
## Measured on the live PWA for a static `helm_helm` (no stats at all — a static armour item
## has `defenseMin`/`defenseMax` and no `defense` value, which only a GENERATED item gets):
##
##   card        358x149   (12px padding + 1px border, box-sizing:border-box)
##   header       64 tall  with `margin-bottom:6px`
##   stats         0 tall  (empty block; the 6px margin is still there)
##   actions      53 tall  = `padding-top:6px` + `border-top:1px` + the 34px button's 6px
##                           margins (`.btn { margin:6px 0 }`)
##   button       69x34    `width:fit-content`, `padding:8px 16px`, `line-height:1`,
##                           content = a 16px icon + a 14px price with `gap:6px`
##
## The port had a hardcoded 130x40 button and NO `margin-bottom` on the header, and both are
## visible: a 140px card where the reference is 149, and a 148px rhythm where the reference
## is 157.
##
## ⚠️  BOTH TABS COME OUT OF `_item_card` — the PWA's sell row is the same `.shop-item`
## markup, and the two rows had already drifted once while they were written separately (the
## header margin and the action padding existed only on the buy side). A measurement of one
## said nothing about the other.
func _buy_row(item: Dictionary) -> Control:
	return _item_card(item, int(item.get("cost", 0)), false, func(): _on_buy(item))


func _render_sell() -> void:
	var bag: Array = _state.inventory()
	var any := false
	for i in bag.size():
		var entry: Variant = bag[i]
		var item_id := str(entry.get("id", "")) if entry is Dictionary else str(entry)
		if item_id == "" or _state.is_item_equipped(item_id):
			continue
		var item: Dictionary = _find_item.call(item_id)
		if item.is_empty():
			continue
		any = true
		_list.add_child(_sell_row(item_id, item))
	if not any:
		_list.add_child(UIKit.label("Nic k prodeji", 14, UIKit.DIM))


func _sell_row(item_id: String, item: Dictionary) -> Control:
	# ⚠️  THE PWA'S SELL ROW IS THE SAME MARKUP AS ITS BUY ROW — `.shop-item-header`
	# (64px icon + name), `.shop-item-stats`, `.shop-item-actions` — so the port builds the
	# same shape. It used to be one flat `HBoxContainer` of icon + a text column + a 130px
	# button, with `item_tooltip` inside the text column:
	#
	#   * `item_tooltip` sets `custom_minimum_size.x = 240`, and a MINIMUM inside an
	#     `HBoxContainer` is honoured — 56 + 10 + 240 + 10 + 130 = 446 on a 390px canvas, so
	#     the row genuinely could not fit and the content ran off the screen;
	#   * the vertical stack is what lets the block be as wide as the row instead of being
	#     forced to a fixed width.
	#
	# Both cards now come out of ONE builder: the two were written separately once and had
	# drifted (the buy card's header margin and action padding existed only there), so a
	# measurement of one said nothing about the other.
	var price := int(round(float(int(item.get("cost", 0))) * 0.5))
	return _item_card(item, price, true, func(): _on_sell(item_id))


## The shared `.shop-item` card. `sell` picks the price's own button route: the buy card
## greys the price out when the hero cannot afford it (the PWA's `opacity:0.5`), and the
## sell card never can.
func _item_card(item: Dictionary, price: int, _is_sell: bool, on_press: Callable) -> Control:
	var row := PanelContainer.new()
	var style := UIKit.panel_style("#2a2a2a")
	style.set_corner_radius_all(8)
	# `.shop-item { padding:12px; border:1px }` with `box-sizing:border-box` — the 12 is
	# measured from inside the border, so the content margin carries it: 13. Without this the
	# card's header sits at x=28 against the reference's 29.
	style.content_margin_left = 13
	style.content_margin_right = 13
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	row.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	# ⚠️  `separation = 0`, and every gap is carried by the block that owns it. The PWA's
	# card is NORMAL FLOW: `.shop-item-header { margin-bottom:6px }` then `.shop-item-stats`
	# then `.shop-item-actions`. A `VBoxContainer` separation of 6 would ADD to the header's
	# own 6px margin and give 12 — measured on the live PWA the header's bottom edge to the
	# stats' top edge is exactly 6 (405 -> 411).
	box.add_theme_constant_override("separation", 0)
	row.add_child(box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	# `.shop-item-header { margin-bottom:6px }` — the box's 6px separation applies BETWEEN
	# children, so the gap under the last one has to be added rather than inherited.
	box.add_child(UIKit.margin_box(top, 0, 6))

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = UIKit.load_texture(ItemStats.icon_path(item))
	top.add_child(icon)

	var name_label := UIKit.label(ItemStats.socket_name(item), 15,
		ItemStats.quality_color(item).to_html(false))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A Label reports its UNWRAPPED text as its minimum and a container honours it, so a
	# long rare name would widen the row past the canvas. Let it wrap instead.
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(name_label)

	box.add_child(UIKit.stat_block(item, _data))

	# `.shop-item-actions { padding-top:6px; border-top:1px solid #2a2a2a }` — the 6px sits
	# between the rule and the button, and the button brings its own `.btn { margin:6px 0 }`
	# on top of it. That pair is the whole 53px block around a 34px button.
	#
	# ⚠️  THE BUTTON'S TOP MARGIN COLLAPSES WITH THE BLOCK ABOVE IT, as in any CSS flow. The
	# card's children are in normal flow: `.shop-item-stats` (0 tall here) then
	# `.shop-item-actions` with `padding-top:6px`. The button's `margin-top:6px` touches that
	# 6px padding — a PADDING does not collapse, but a MARGIN inside it does, against the
	# button's own margin inside the box? No: the margin sits INSIDE the actions box, past
	# the padding edge, so the actions box is `padding-top 6 + max(button margin 6) ...`.
	# Measured on the live PWA: the button's box starts at 449.4, the actions box at 436.4 —
	# a 13px gap, i.e. 1 rule + 6 padding + 6 button margin. The port's margin_box gave the
	# actions box only 6 + 6 with the margin OUTSIDE, so it came out 47 tall against 53.
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	# `align-items:center` gives the 34px button a 6px margin on BOTH sides inside the box,
	# so the block is 1 (rule) + 6 (padding-top) + 6 + 34 + 6 = 53.
	var padded := UIKit.margin_box(actions, 6, 6)
	var ruled := VBoxContainer.new()
	ruled.add_theme_constant_override("separation", 0)
	ruled.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rule := ColorRect.new()
	rule.color = Color("#2a2a2a")
	rule.custom_minimum_size = Vector2(0, 1)
	ruled.add_child(rule)
	ruled.add_child(UIKit.gap(6.0))
	ruled.add_child(padded)
	box.add_child(ruled)

	# `.btn-shop-buy { opacity:0.5 }` when the hero cannot afford it — and the SELL card is
	# never greyed, because its price is always payable. The parameter is what says which.
	var can_afford := true if _is_sell else int(_state.hero().get("gold", 0)) >= price
	var buy := UIKit.shop_buy_button(price, can_afford)
	buy.pressed.connect(on_press)
	actions.add_child(buy)
	return row


func _on_buy(item: Dictionary) -> void:
	var result := ShopStock.buy(_state, item, _find_item)
	if not result["ok"]:
		message.emit(str(result["message"]))
		refresh()
		return
	# Gear disappears from the offer once bought. Consumables, crafting materials and
	# gems stay — otherwise a player could buy exactly one potion per town visit.
	var item_type := str(item.get("type", ""))
	if not (item_type in ["consumable", "crafting", "gem"]):
		_bought.append(str(item.get("id", "")))
	message.emit(str(result["message"]))
	_rebuild_categories()
	refresh()


func _on_sell(item_id: String) -> void:
	var result := ShopStock.sell(_state, item_id, _find_item)
	message.emit(str(result["message"]))
	refresh()


## A fresh RNG per stock generation: the shop is meant to differ every visit, and a
## shared generator would make it a fixed sequence after a reload.
func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
