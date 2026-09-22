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
var _gold_label: Label
var _potion_label: Label


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
	column.add_theme_constant_override("separation", 8)

	# `.shop-back-map` then `.page-header`, exactly the PWA's order.
	var back := UIKit.back_button()
	back.pressed.connect(func(): back_pressed.emit())
	column.add_child(back)

	var header := UIKit.page_header("assets/menu-icons/shop.png", "Obchod",
		"Nakup a prodej vybaveni", "0 zlata")
	_gold_label = header["right"]
	column.add_child(header["root"])

	# `.shop-tabs`
	var tabs := UIKit.tab_row(["Koupit", "Prodat"], 0, UIKit.MOD_BLUE)
	_tab_buttons = tabs["buttons"]
	_tab_buttons[0].pressed.connect(func(): _set_tab("buy"))
	_tab_buttons[1].pressed.connect(func(): _set_tab("sell"))
	column.add_child(tabs["root"])

	_potion_label = UIKit.label("", 13, UIKit.DIM)
	column.add_child(_potion_label)

	# `.shop-cat-tabs`
	_category_row = HBoxContainer.new()
	_category_row.add_theme_constant_override("separation", 4)
	column.add_child(_category_row)

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
		_potion_label.text = ""
		_render_sell()
	else:
		_render_buy()


func _rebuild_categories() -> void:
	_clear(_category_row)
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
		button.custom_minimum_size = Vector2(0, 36)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 13)
		var active := category == _category
		# `.shop-cat-tab.active { background:#111; border-color:#f1c40f; color:#f1c40f }`
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#111111") if active else Color("#000000")
		style.border_color = Color(UIKit.GOLD) if active else Color("#2a2a2a")
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
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

	if _category == "Misc":
		var total: int = int(_state.total_potion_slots(_find_item))
		var used := 0
		for pid in _state.equip().get("beltPotionSlots", []):
			if pid != null:
				used += 1
		var free := maxi(0, total - used)
		_potion_label.text = "Slotu na potiony: %d volnych (%d/%d)" % [free, used, total]
	else:
		_potion_label.text = ""

	var items := _visible_items(section)
	if items.is_empty():
		_list.add_child(UIKit.label("Nic k prodeji", 14, UIKit.DIM))
		return
	for item in items:
		_list.add_child(_buy_row(item))


## `.shop-item` — a black card, 8px radius and a 1px #2a2a2a border, with the icon, the
## name in its quality colour, the stat block and the price at the bottom right.
func _buy_row(item: Dictionary) -> Control:
	var row := PanelContainer.new()
	var style := UIKit.panel_style("#2a2a2a")
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	row.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	row.add_child(box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	box.add_child(top)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = UIKit.load_texture(ItemStats.icon_path(item))
	top.add_child(icon)

	var name_label := UIKit.label(ItemStats.socket_name(item), 15,
		ItemStats.quality_color(item).to_html(false))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(name_label)

	box.add_child(UIKit.item_tooltip(item, _data, 300.0))

	# `.shop-item-actions { border-top: 1px solid #2a2a2a; justify-content: flex-end }`
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)

	var cost := int(item.get("cost", 0))
	var can_afford := int(_state.hero().get("gold", 0)) >= cost
	var buy := UIKit.flat_button("%d zlata" % cost, 130.0, 40.0, 14)
	buy.add_theme_color_override("font_color", Color(UIKit.GOLD if can_afford else UIKit.BAD))
	buy.pressed.connect(func(): _on_buy(item))
	actions.add_child(buy)
	return row


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
	var row := PanelContainer.new()
	var style := UIKit.panel_style("#2a2a2a")
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	row.add_theme_stylebox_override("panel", style)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	row.add_child(box)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = UIKit.load_texture(ItemStats.icon_path(item))
	box.add_child(icon)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(column)
	column.add_child(UIKit.label(ItemStats.socket_name(item), 15,
		ItemStats.quality_color(item).to_html(false)))
	column.add_child(UIKit.item_tooltip(item, _data, 240.0))

	var price := int(round(float(int(item.get("cost", 0))) * 0.5))
	var sell := UIKit.flat_button("Prodat %d" % price, 130.0, 40.0, 14)
	sell.add_theme_color_override("font_color", Color(UIKit.GOLD))
	sell.pressed.connect(func(): _on_sell(item_id))
	box.add_child(sell)
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
