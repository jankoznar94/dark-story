extends Control
class_name ChestScreen
## ChestScreen — 25 stash cells on top, the 20-cell bag underneath. Tapping a chest item
## moves it to the bag; tapping a bag item moves it to the chest.
##
## Ported from `renderChest` / `renderChestInventory`. Two rules from there are load
## bearing and are the reason this screen is not just "two grids":
##
##   1. Stackable items MERGE into an existing chest stack instead of taking a new cell.
##      Without it, 25 chest cells fill with 25 single rubies.
##   2. Moving a bag item to a full chest is refused with a message — it does not silently
##      vanish, which is the failure a player would actually notice.
##
## Layout is the PWA's, from `index.html`'s `#chestScreen` block and the `.chest-grid` /
## `.chest-cell` rules in its `<style>` block:
##
##   .chest-grid           5 columns, 6px gap, on a black box with a 1px #333 border and
##                         a 10px radius, 12px of padding
##   .chest-cell           aspect-ratio 1, radius 6, a #777 border, and 25% opacity empty
##   .chest-section-label  "Chest (25 slots)" / "Inventory" in 14px bold #aaa
##
## The whole page scrolls: 25 cells plus 20 cells plus two labels is taller than 844px,
## and the PWA scrolled `body` here. `.inv-grid-wrap` (a scroll box inside the page) is
## used only where the PWA used it — the bag in the inventory modal — because nested
## scroll areas on a phone steal each other's drags.

const UIKit := preload("res://scripts/ui/ui_kit.gd")
const ItemStats := preload("res://scripts/items/item_stats.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")

signal back_pressed()
signal message(text: String)

## `.chest-grid` in a 358px container with 12px padding and 6px gaps:
## (358 - 24 - 4*6) / 5 = 62px per cell.
const CELL := 62

var _data: Node
var _state
var _gen: ItemGen
var _find_item: Callable

var _chest_grid: GridContainer
var _bag_grid: GridContainer
var _gold_label: Label
var _tooltip_slot: Control
var _selected: Dictionary = {}


func _init(game_data: Node, gen: ItemGen, state, find_item: Callable) -> void:
	_data = game_data
	_gen = gen
	_state = state
	_find_item = find_item


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var page := UIKit.screen_page(self)
	var column: VBoxContainer = page["column"]
	column.add_theme_constant_override("separation", 8)

	var back := UIKit.back_button()
	back.pressed.connect(func(): back_pressed.emit())
	column.add_child(back)

	var header := UIKit.page_header("assets/menu-icons/chest.png", "Truhla",
		"Klepni na predmet a presun ho mezi truhlou a batohem.", "0 zlata")
	_gold_label = header["right"]
	column.add_child(header["root"])

	# `.chest-section-label`
	column.add_child(UIKit.section_label("Truhla (25 slotu)"))
	_chest_grid = _make_grid_box(5)
	column.add_child(_chest_grid.get_parent())

	column.add_child(UIKit.section_label("Batoh"))
	_bag_grid = _make_grid_box(5)
	column.add_child(_bag_grid.get_parent())

	_tooltip_slot = VBoxContainer.new()
	_tooltip_slot.add_theme_constant_override("separation", 4)
	column.add_child(_tooltip_slot)


## `.chest-grid` — a padded, bordered box holding a 5-column grid.
func _make_grid_box(columns: int) -> GridContainer:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#000000")
	style.border_color = Color("#333333")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	box.add_theme_stylebox_override("panel", style)

	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	return grid


func refresh() -> void:
	_gold_label.text = "%d zlata" % int(_state.hero().get("gold", 0))
	_refresh_chest()
	_refresh_bag()
	_refresh_tooltip()


func _refresh_chest() -> void:
	_clear(_chest_grid)
	var chest: Array = _state.data.get("chest", [])
	for i in chest.size():
		var entry: Variant = chest[i]
		var item: Dictionary = {}
		if entry != null:
			var entry_id := str(entry.get("id", "")) if entry is Dictionary else str(entry)
			item = _find_item.call(entry_id)
			if not item.is_empty() and entry is Dictionary:
				item = item.duplicate()
				item["count"] = int(entry.get("count", 1))
		var cell := UIKit.item_cell(item, CELL)
		var index := i
		cell.pressed.connect(func(): _on_chest_tapped(index))
		cell.mouse_entered.connect(func(): _select(item))
		_chest_grid.add_child(cell)


func _refresh_bag() -> void:
	_clear(_bag_grid)
	var bag: Array = _state.inventory()
	for i in GameState.INVENTORY_CELLS:
		var item: Dictionary = {}
		if i < bag.size():
			var entry: Variant = bag[i]
			var entry_id := str(entry.get("id", "")) if entry is Dictionary else str(entry)
			item = _find_item.call(entry_id)
			if not item.is_empty() and entry is Dictionary:
				item = item.duplicate()
				item["count"] = int(entry.get("count", 1))
		var cell := UIKit.item_cell(item, CELL)
		if not item.is_empty() and not _can_equip(item):
			# The class restrictions are shown here rather than only in the bag screen:
			# a wrong-class item moved into the bag is a wasted chest cell.
			var style: StyleBoxFlat = cell.get_theme_stylebox("normal").duplicate()
			style.border_color = Color(UIKit.BAD)
			for state_name in ["normal", "pressed", "hover", "focus", "disabled"]:
				cell.add_theme_stylebox_override(state_name, style)
		var index := i
		cell.pressed.connect(func(): _on_bag_tapped(index))
		cell.mouse_entered.connect(func(): _select(item))
		_bag_grid.add_child(cell)


func _on_chest_tapped(index: int) -> void:
	var chest: Array = _state.data.get("chest", [])
	if index < 0 or index >= chest.size() or chest[index] == null:
		return
	var entry_id := str(chest[index].get("id", ""))
	var item: Dictionary = _find_item.call(entry_id)
	var reason: String = str(_state.take_from_chest(index, item))
	if reason != "":
		message.emit(reason)
	else:
		_state.save()
	_select(item)
	refresh()


func _on_bag_tapped(index: int) -> void:
	var bag: Array = _state.inventory()
	if index < 0 or index >= bag.size():
		return
	var entry: Variant = bag[index]
	var entry_id := str(entry.get("id", "")) if entry is Dictionary else str(entry)
	var item: Dictionary = _find_item.call(entry_id)
	if item.is_empty():
		return
	if _state.is_item_equipped(entry_id):
		message.emit("Predmet je nasazeny")
		return
	var reason: String = str(_state.stash_from_bag(index, item, ItemGen.is_stackable(item)))
	if reason != "":
		message.emit(reason)
	else:
		_state.save()
	_select(item)
	refresh()


## What the class may actually wear — the same two checks the PWA made before letting
## an item be dragged onto a slot.
func _can_equip(item: Dictionary) -> bool:
	var cls: Dictionary = _data.class_by_id(str(_state.data.get("heroClass", "")))
	if cls.is_empty():
		return true
	var item_type := str(item.get("type", ""))
	if item_type == "weapon" and cls.has("allowedWeapons"):
		return str(item.get("weaponType", "")) in cls.get("allowedWeapons", [])
	if item_type == "shield":
		return bool(cls.get("allowedShield", true))
	return true


## A long-press-free detail panel: the PWA put the item's stats in a fixed panel under
## the grids. Hovering is what feeds it here (a mouse), and a tap selects too — on a phone
## the tap that moves the item also selects it, so the panel always describes the last
## thing touched.
func _select(item: Dictionary) -> void:
	_selected = item
	_refresh_tooltip()


func _refresh_tooltip() -> void:
	_clear(_tooltip_slot)
	if _selected.is_empty():
		return
	_tooltip_slot.add_child(UIKit.item_tooltip(_selected, _data))


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
