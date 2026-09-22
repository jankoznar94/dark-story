extends Control
class_name CraftScreen
## CraftScreen — the five recipes and a workbench with four input slots.
##
## Ported from `renderCraft` / `craftOpenRecipe` / `renderCraftSlots` /
## `openCraftPicker` / `craftDo`. The screen collects WHICH inventory slot went into
## each craft slot; every rule (what may go in, whether the gem is good enough, what
## the craft produces) is in `scripts/items/craft.gd` so a headless test can drive a
## craft without a scene tree.
##
## Two things worth knowing before touching this:
##
##   * The inserted item is CONSUMED and the result is regenerated from its BASE item.
##     Nothing of the inserted item's own rolls survives.
##   * Only MAGIC quality items can go in the item slot, and the gem quality must match
##     the item's version (Normal -> Flawed, Nightmare -> Flawless, Hell -> Perfect).

const UIKit := preload("res://scripts/ui/ui_kit.gd")
const CraftSystem := preload("res://scripts/items/craft.gd")
const ItemStats := preload("res://scripts/items/item_stats.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")

signal back_pressed()
signal message(text: String)

const CELL := 64

var _data: Node
var _gen: ItemGen
var _state
var _find_item: Callable

var _recipe: Dictionary = {}
## slot key -> {idx, id}. The item itself is resolved on demand so a sold item cannot
## linger in a slot as a stale copy.
var _slots: Dictionary = {}
var _result: Dictionary = {}

var _recipe_list: VBoxContainer
var _gear_list: VBoxContainer
var _tabs: Dictionary = {}
var _active_tab := "recipes"
var _gold_label: Label
var _workbench: VBoxContainer
var _workbench_title: Label
var _slot_row: HBoxContainer
var _craft_button: Button
var _result_box: VBoxContainer
var _picker_slot := ""
var _picker: VBoxContainer


func _init(game_data: Node, gen: ItemGen, state, find_item: Callable) -> void:
	_data = game_data
	_gen = gen
	_state = state
	_find_item = find_item


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var page := UIKit.screen_page(self, UIKit.BACK_BTN_PAD)
	var column: VBoxContainer = page["column"]
	column.add_theme_constant_override("separation", 8)

	var back := UIKit.back_button()
	back.pressed.connect(func(): back_pressed.emit())
	column.add_child(back)

	var header := UIKit.page_header("assets/menu-icons/craft.png", "Craft",
		"Spoj gemy, predmety a runy ve vybaveni.", "0 zlata")
	_gold_label = header["right"]
	column.add_child(header["root"])

	column.add_child(UIKit.label(
		"Recepty: gem + predmet + runa + jewel. Gem musi odpovidat verzi predmetu.",
		12, UIKit.DIM))

	# `.craft-tab` — this screen's own tab colour is the purple #9b59b6, not the shop's
	# blue: the PWA gave each vendor family its own accent, and using the wrong one is
	# exactly the kind of drift the CSS is here to prevent.
	_tabs = UIKit.tab_row(["Recepty", "Vybava"], 0, "#9b59b6")
	_tabs["buttons"][0].pressed.connect(func(): _set_tab("recipes"))
	_tabs["buttons"][1].pressed.connect(func(): _set_tab("gear"))
	column.add_child(_tabs["root"])

	_recipe_list = VBoxContainer.new()
	_recipe_list.add_theme_constant_override("separation", 8)
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_recipe_list)

	_gear_list = VBoxContainer.new()
	_gear_list.add_theme_constant_override("separation", 8)
	_gear_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gear_list.visible = false
	column.add_child(_gear_list)

	_workbench = VBoxContainer.new()
	_workbench.add_theme_constant_override("separation", 8)
	_workbench.visible = false
	column.add_child(_workbench)

	_workbench_title = UIKit.label("", 18)
	_workbench.add_child(_workbench_title)

	_slot_row = HBoxContainer.new()
	_slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_row.add_theme_constant_override("separation", 8)
	_workbench.add_child(_slot_row)

	_result_box = VBoxContainer.new()
	_result_box.add_theme_constant_override("separation", 4)
	_workbench.add_child(_result_box)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	_workbench.add_child(actions)

	_craft_button = UIKit.flat_button("Vyrobit", 140.0, 44.0)
	_craft_button.pressed.connect(_on_craft)
	_craft_button.visible = false
	actions.add_child(_craft_button)

	var close := UIKit.flat_button("Zavrit", 140.0, 44.0)
	close.pressed.connect(_close_workbench)
	actions.add_child(close)

	_picker = VBoxContainer.new()
	_picker.add_theme_constant_override("separation", 6)
	_picker.visible = false
	column.add_child(_picker)

	# The recipe cards are built last so opening one can hide the list without racing the
	# build: `_open_recipe` flips `_recipe_list.visible`.
	for recipe in CraftSystem.RECIPES:
		_recipe_list.add_child(_recipe_row(recipe))


func _set_tab(tab: String) -> void:
	_active_tab = tab
	_recipe_list.visible = tab == "recipes"
	_gear_list.visible = tab == "gear"
	if tab == "gear":
		_render_gear()
	for i in (_tabs["buttons"] as Array).size():
		var active := (tab == "recipes" and i == 0) or (tab == "gear" and i == 1)
		var button: Button = _tabs["buttons"][i]
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#111111") if active else Color("#000000")
		style.border_color = Color("#9b59b6") if active else Color("#2a2a2a")
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		for state_name in ["normal", "hover", "focus", "disabled"]:
			button.add_theme_stylebox_override(state_name, style)
		button.add_theme_color_override("font_color",
			Color("#ffffff") if active else Color("#cccccc"))


## A list of the candidate items at the top of the gear tab: the items a recipe's item
## slot will accept. The PWA picked the item from the bag inside the workbench; showing
## them up front makes "what can I even craft with" answerable before opening a recipe.
func _render_gear() -> void:
	_clear(_gear_list)
	var shown := 0
	var bag: Array = _state.inventory()
	for i in bag.size():
		var entry: Variant = bag[i]
		var item_id := str(entry.get("id", "")) if entry is Dictionary else str(entry)
		if item_id == "":
			continue
		var item: Dictionary = _find_item.call(item_id)
		if item.is_empty():
			continue
		var item_type := str(item.get("type", ""))
		if not (item_type in ["weapon", "armor", "helmet", "shield", "ring", "amulet",
				"gloves", "boots", "belt", "gem", "jewel", "crafting"]):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var cell := UIKit.item_cell(item, 48)
		row.add_child(cell)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		column.add_child(UIKit.label(ItemStats.socket_name(item), 14,
			ItemStats.quality_color(item).to_html(false)))
		column.add_child(UIKit.label("%s   %d zlata" % [
			ItemStats.item_version(item) if item.has("version") else item_type,
			int(item.get("cost", 0))], 12, UIKit.DIM))
		_gear_list.add_child(row)
		shown += 1
	if shown == 0:
		_gear_list.add_child(UIKit.label("Batoh je prazdny.", 14, UIKit.DIM))


func _recipe_row(recipe: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIKit.panel_style())

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	row.add_child(box)
	box.add_child(UIKit.label(str(recipe["name"]), 16))
	box.add_child(UIKit.label(str(recipe["desc"]), 12, UIKit.DIM))

	var pick := Button.new()
	# No `flat = true`: `flat` stops the Button drawing its stylebox at all, which is
	# the same visual result as the transparent style below but hides every FUTURE
	# border this button might get. One rule instead of an exception.
	pick.set_anchors_preset(Control.PRESET_FULL_RECT)
	pick.focus_mode = Control.FOCUS_NONE
	var style := UIKit.panel_style()
	style.bg_color = Color(0, 0, 0, 0)
	for state_name in ["normal", "pressed", "hover", "focus", "disabled"]:
		pick.add_theme_stylebox_override(state_name, style)
	pick.pressed.connect(func(): _open_recipe(str(recipe["id"])))
	row.add_child(pick)
	return row


# --- workbench ---------------------------------------------------------------

func _open_recipe(recipe_id: String) -> void:
	_recipe = CraftSystem.recipe_by_id(recipe_id)
	if _recipe.is_empty():
		return
	_slots = {}
	_result = {}
	_recipe_list.visible = false
	_workbench.visible = true
	_picker.visible = false
	_workbench_title.text = str(_recipe["name"])
	_rebuild_workbench()


func _close_workbench() -> void:
	_recipe = {}
	_slots = {}
	_result = {}
	_workbench.visible = false
	_picker.visible = false
	_recipe_list.visible = true


func _slot_keys() -> Array:
	if _recipe.get("isGemUpgrade", false):
		return ["gem1", "gem2", "gem3"]
	return ["gem", "item", "rune", "jewel"]


func _rebuild_workbench() -> void:
	_clear(_slot_row)
	_clear(_result_box)
	if _recipe.is_empty():
		return

	for key in _slot_keys():
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		_slot_row.add_child(column)
		column.add_child(UIKit.label(_slot_label(str(key)), 12, UIKit.DIM))

		var slot: Variant = _slots.get(key)
		var item: Dictionary = {} if slot == null else _find_item.call(str(slot.get("id", "")))
		var cell := UIKit.item_cell(item, CELL)
		var slot_key := str(key)
		cell.pressed.connect(func(): _open_picker(slot_key))
		column.add_child(cell)

		var clear := UIKit.flat_button("Vynulovat", 0.0, 26.0, 11)
		clear.pressed.connect(func(): _clear_slot(slot_key))
		column.add_child(clear)

	# Result: for the gem upgrade it can be previewed before the craft (three identical
	# gems determine the result), for the standard recipes only after crafting.
	var preview := _preview_result()
	var result_column := VBoxContainer.new()
	result_column.add_theme_constant_override("separation", 2)
	_slot_row.add_child(result_column)
	result_column.add_child(UIKit.label("Vysledek", 12, UIKit.DIM))
	result_column.add_child(UIKit.item_cell(preview, CELL))
	if not preview.is_empty():
		_result_box.add_child(UIKit.label(ItemStats.socket_name(preview), 15,
			ItemStats.quality_color(preview).to_html(false)))
		_result_box.add_child(UIKit.item_tooltip(preview, _data, 420.0))

	_craft_button.visible = not preview.is_empty() and not _recipe.get("isGemUpgrade", false)
	if _recipe.get("isGemUpgrade", false):
		_craft_button.visible = not preview.is_empty()


## The item the result slot shows: the finished craft if one has been made, otherwise
## the gem-upgrade preview.
func _preview_result() -> Dictionary:
	if not _result.is_empty():
		return _result
	if not _recipe.get("isGemUpgrade", false):
		return {}
	return CraftSystem.gem_upgrade_result(_slots, _find_item)


func _slot_label(key: String) -> String:
	match key:
		"gem":
			return "Gem (%s)" % str(_recipe.get("gemType", ""))
		"item":
			return "Predmet (magic)"
		"rune":
			return "Runa"
		"jewel":
			return "Jewel"
		_:
			return "Gem %s" % key.substr(3, 1)


func _clear_slot(key: String) -> void:
	_slots.erase(key)
	_result = {}
	_rebuild_workbench()


# --- picker ------------------------------------------------------------------

## Which bag entries may fill this slot. Ported from the PWA's openCraftPicker,
## including the magic-only rule for the item slot — a common or rare item is refused
## by the picker AND by the validator, so the rule cannot be bypassed by a stale list.
func _eligible(slot_key: String) -> Array:
	var out: Array = []
	var bag: Array = _state.inventory()
	for i in bag.size():
		var entry: Variant = bag[i]
		var item_id := str(entry.get("id", "")) if entry is Dictionary else str(entry)
		if item_id == "":
			continue
		var item: Dictionary = _find_item.call(item_id)
		if item.is_empty():
			continue
		var item_type := str(item.get("type", ""))
		var count: int = int(entry.get("count", 1)) if entry is Dictionary else 1
		var ok := false
		if slot_key == "gem":
			ok = item_type == "gem" and str(item.get("gemType", "")) == str(_recipe.get("gemType", ""))
		elif slot_key == "item":
			ok = item_type in _recipe.get("itemTypes", []) \
				and str(item.get("quality", item.get("rarity", ""))) == "magic"
		elif slot_key == "rune":
			ok = item_type == "crafting"
		elif slot_key == "jewel":
			ok = item_type == "jewel"
		elif slot_key.begins_with("gem"):
			ok = item_type == "gem"
		if ok:
			out.append({"idx": i, "id": item_id, "item": item, "count": count})
	return out


func _open_picker(slot_key: String) -> void:
	_picker_slot = slot_key
	_picker.visible = true
	_clear(_picker)
	_picker.add_child(UIKit.label("Vyber do slotu: %s" % _slot_label(slot_key), 14, UIKit.DIM))

	var options := _eligible(slot_key)
	if options.is_empty():
		_picker.add_child(UIKit.label("Nic vhodneho v batohu", 13, UIKit.BAD))
		var close := UIKit.flat_button("Zavrit", 120.0, 34.0, 13)
		close.pressed.connect(func(): _picker.visible = false)
		_picker.add_child(close)
		return

	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for option in options:
		var cell := UIKit.item_cell(option["item"], 56)
		cell.tooltip_text = ItemStats.socket_name(option["item"])
		var index: int = int(option["idx"])
		var item_id: String = str(option["id"])
		cell.pressed.connect(func(): _pick(index, item_id))
		grid.add_child(cell)
	_picker.add_child(grid)

	var close_button := UIKit.flat_button("Zavrit", 120.0, 34.0, 13)
	close_button.pressed.connect(func(): _picker.visible = false)
	_picker.add_child(close_button)


func _pick(bag_index: int, item_id: String) -> void:
	_slots[_picker_slot] = {"idx": bag_index, "id": item_id}
	_result = {}
	_picker.visible = false
	_rebuild_workbench()


# --- crafting ----------------------------------------------------------------

func _on_craft() -> void:
	if _recipe.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var result := CraftSystem.do_craft(_state, _recipe, _slots, _gen, rng, _data, _find_item)
	message.emit(str(result["message"]))
	if not result["ok"]:
		_rebuild_workbench()
		return
	_result = result["item"]
	_slots = {}
	_rebuild_workbench()


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
