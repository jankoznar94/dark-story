extends Control
class_name ShopScreen
## ShopScreen — buy and sell. Ported from `renderShop` / `buyItem` / `sellItem`.
##
## Two things this screen does NOT do, both deliberate:
##
##   * It owns no prices and no stock rules. `ShopStock` generates the offer and
##     decides what a purchase does; this file only draws it and reports taps.
##   * It does not cache the stock itself. The cache lives in `main.gd` and is cleared
##     on every town visit — the PWA reset its cache in `renderTown`, and re-entering
##     town must produce a new offer.
##
## Buying marks the item as bought and removes it from the list for this visit, except
## for consumables, crafting materials and gems, which stay buyable — the same rule the
## PWA had, and the reason a player can buy ten potions in one trip but only one sword.

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
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var header := UIKit.back_header("Obchod")
	header["back"].pressed.connect(func(): back_pressed.emit())
	_gold_label = header["right"]
	root.add_child(header["root"])

	var tabs := UIKit.tab_row(["Koupit", "Prodat"], 0)
	_tab_buttons = tabs["buttons"]
	_tab_buttons[0].pressed.connect(func(): _set_tab("buy"))
	_tab_buttons[1].pressed.connect(func(): _set_tab("sell"))
	root.add_child(tabs["root"])

	_potion_label = UIKit.label("", 13, UIKit.DIM)
	root.add_child(_potion_label)

	_category_row = HBoxContainer.new()
	_category_row.add_theme_constant_override("separation", 4)
	root.add_child(_category_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


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
	_gold_label.text = "Zlato %d" % int(_state.hero().get("gold", 0))
	for i in _tab_buttons.size():
		var active := (_tab == "buy" and i == 0) or (_tab == "sell" and i == 1)
		var style := UIKit.panel_style(UIKit.GOLD if active else UIKit.BORDER, 2 if active else 1)
		for state_name in ["normal", "pressed", "hover", "focus", "disabled"]:
			_tab_buttons[i].add_theme_stylebox_override(state_name, style)

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
		var button := UIKit.flat_button(category, 0.0, 34.0, 14)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var active := category == _category
		var style := UIKit.panel_style(UIKit.GOLD if active else UIKit.BORDER, 2 if active else 1)
		for state_name in ["normal", "pressed", "hover", "focus", "disabled"]:
			button.add_theme_stylebox_override(state_name, style)
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
	elif _category != "Misc":
		_potion_label.text = ""

	var items := _visible_items(section)
	if items.is_empty():
		_list.add_child(UIKit.label("Nic k prodeji", 14, UIKit.DIM))
		return
	for item in items:
		_list.add_child(_buy_row(item))


func _buy_row(item: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIKit.panel_style())

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
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

	var name_label := UIKit.label(ItemStats.socket_name(item), 15,
		ItemStats.quality_color(item).to_html(false))
	column.add_child(name_label)
	column.add_child(UIKit.item_tooltip(item, _data, 300.0))

	var cost := int(item.get("cost", 0))
	var can_afford := int(_state.hero().get("gold", 0)) >= cost
	var buy := UIKit.flat_button("%d zlata" % cost, 120.0, 40.0, 14)
	buy.add_theme_color_override("font_color", Color(UIKit.GOLD if can_afford else UIKit.BAD))
	buy.pressed.connect(func(): _on_buy(item))
	box.add_child(buy)
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
	row.add_theme_stylebox_override("panel", UIKit.panel_style())

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
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
	column.add_child(UIKit.item_tooltip(item, _data, 300.0))

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
