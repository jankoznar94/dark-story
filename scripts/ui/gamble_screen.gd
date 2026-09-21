extends Control
class_name GambleScreen
## GambleScreen — the D2 gamble vendor. Ported from `renderGamble` / `buyGambleItem`.
##
## The offer shows the base item's NAME and stats only, with "??? unidentified" where
## the rolled stats will go: the player is buying a chance, not an item. What they get
## is decided by two independent rolls at purchase time (quality and item version),
## both of which live in ShopStock and are asserted there.
##
## The sell tab is the same as the shop's, minus the shop's categories.

const UIKit := preload("res://scripts/ui/ui_kit.gd")
const ShopStock := preload("res://scripts/items/shop_stock.gd")
const ItemStats := preload("res://scripts/items/item_stats.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")

signal back_pressed()
signal message(text: String)

const CATEGORIES := ["Weapons", "Armor", "Jewelry"]

var _data: Node
var _gen: ItemGen
var _state
var _find_item: Callable
var _stock: Array = []

var _tab := "buy"
var _category := "Weapons"

var _list: VBoxContainer
var _tab_buttons: Array = []
var _category_row: HBoxContainer
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
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var header := UIKit.back_header("Gamble")
	header["back"].pressed.connect(func(): back_pressed.emit())
	_gold_label = header["right"]
	root.add_child(header["root"])

	var tabs := UIKit.tab_row(["Koupit", "Prodat"], 0)
	_tab_buttons = tabs["buttons"]
	_tab_buttons[0].pressed.connect(func(): _set_tab("buy"))
	_tab_buttons[1].pressed.connect(func(): _set_tab("sell"))
	root.add_child(tabs["root"])

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

	root.add_child(UIKit.label("Cena je pevna, obsah je kostka. Nikdy to neni normal kvalita.", 12, UIKit.DIM))


## Fresh offer. The gamble stock is level-gated rather than progress-gated, so it is
## rebuilt whenever the screen opens; a level change between visits changes the pool.
func reset_stock() -> void:
	_stock = []
	_ensure_stock()


func _ensure_stock() -> void:
	if _stock.is_empty():
		_stock = ShopStock.generate_gamble(_data, _state, _rng())


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

	_clear(_category_row)
	_clear(_list)
	if _tab == "sell":
		_category_row.visible = false
		_render_sell()
		return
	_category_row.visible = true
	for section in _stock:
		if (section.get("items", []) as Array).is_empty():
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
	_render_buy()


func _render_buy() -> void:
	var section: Dictionary = {}
	for s in _stock:
		if str(s["category"]) == _category:
			section = s
	if section.is_empty():
		_list.add_child(UIKit.label("Nic k dispozici", 14, UIKit.DIM))
		return
	var items: Array = section.get("items", [])
	if items.is_empty():
		_list.add_child(UIKit.label("Nic k dispozici", 14, UIKit.DIM))
		return
	for entry in items:
		_list.add_child(_gamble_row(entry))


func _gamble_row(entry: Dictionary) -> Control:
	var base: Dictionary = entry.get("baseItem", {})
	var price := int(entry.get("price", 0))

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIKit.panel_style())

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	row.add_child(box)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = UIKit.load_texture(ItemStats.icon_path(base))
	box.add_child(icon)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(column)
	# The base is shown grey and unidentified on purpose: the player does not get to
	# see what they are buying. Showing the rolled stats here would remove the gamble.
	column.add_child(UIKit.label(str(base.get("name", "?")), 15, UIKit.DIM))
	column.add_child(UIKit.label("??? neidentifikovano", 13, UIKit.DIM))
	var detail := "%s %s" % ["2H" if base.get("twoHand", false) else "1H", str(base.get("weaponType", ""))] \
		if str(base.get("type", "")) == "weapon" else str(base.get("type", ""))
	column.add_child(UIKit.label(detail, 12, "#666666"))

	var can_afford := int(_state.hero().get("gold", 0)) >= price
	var buy := UIKit.flat_button("%d zlata" % price, 120.0, 40.0, 14)
	buy.add_theme_color_override("font_color", Color(UIKit.GOLD if can_afford else UIKit.BAD))
	buy.pressed.connect(func(): _on_buy(entry))
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
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UIKit.panel_style())
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		row.add_child(box)

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = UIKit.load_texture(ItemStats.icon_path(item))
		box.add_child(icon)

		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(column)
		column.add_child(UIKit.label(ItemStats.socket_name(item), 15,
			ItemStats.quality_color(item).to_html(false)))

		var price := int(round(float(int(item.get("cost", 0))) * 0.5))
		var sell := UIKit.flat_button("Prodat %d" % price, 130.0, 40.0, 14)
		sell.add_theme_color_override("font_color", Color(UIKit.GOLD))
		sell.pressed.connect(func(): _on_sell(item_id))
		box.add_child(sell)
		_list.add_child(row)
	if not any:
		_list.add_child(UIKit.label("Nic k prodeji", 14, UIKit.DIM))


func _on_buy(entry: Dictionary) -> void:
	var result := ShopStock.buy_gamble(_state, entry, _gen, _data, _find_item, _rng())
	message.emit(str(result["message"]))
	refresh()


func _on_sell(item_id: String) -> void:
	var result := ShopStock.sell(_state, item_id, _find_item)
	message.emit(str(result["message"]))
	refresh()


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
