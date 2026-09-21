extends Control
class_name TownScreen
## TownScreen — the hub: rest, shop, chest, craft, gamble, and out to the wilds.
##
## Ported from the PWA's renderTown() + the townScreen markup. Three behaviours are
## the actual content of this screen and all three are easy to drop by accident:
##
##   1. Entering town FULLY heals the hero and recalibrates max HP/mana from gear.
##   2. Entering town resets the shop cache, so the stock is fresh every visit.
##   3. "Wilderness" is only offered while there is an act left to clear.
##
## Tiles are a flat grid of images with a label underneath — no cards, no panels.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")

signal tile_selected(screen_key: String)

const TILE_SIZE := Vector2(160, 120)

## tile key -> (icon, label). Order matches the PWA's town grid.
const TILES := [
	["chest", "assets/menu-icons/chest.png", "Truhla"],
	["gamble", "assets/menu-icons/gamble.png", "Gamble"],
	["shop", "assets/menu-icons/shop.png", "Obchod"],
	["craft", "assets/menu-icons/craft.png", "Craft"],
	["inventory", "assets/menu-icons/inventar.png", "Inventar"],
	["hero", "assets/menu-icons/talenty.png", "Hrdina"],
	["wilderness", "assets/map.webp", "Divocina"],
]

var _data: Node
var _gen: ItemGen
var _state
var _find_item: Callable

var _wilderness_button: Button
var _portal_row: Control
var _portal_label: Label
var _header_label: Label


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
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	# Banner: the town image with the title over it. Full-bleed, flat.
	var banner := PanelContainer.new()
	var banner_style := StyleBoxFlat.new()
	banner_style.bg_color = Color("#000000")
	banner_style.set_border_width_all(0)
	banner.add_theme_stylebox_override("panel", banner_style)
	banner.custom_minimum_size = Vector2(0, 150)
	root.add_child(banner)

	var banner_inner := Control.new()
	banner.add_child(banner_inner)

	var town_image := TextureRect.new()
	town_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	town_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	town_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	town_image.texture = _load("assets/town.webp")
	banner_inner.add_child(town_image)

	_header_label = Label.new()
	_header_label.position = Vector2(16, 12)
	_header_label.add_theme_font_size_override("font_size", 26)
	banner_inner.add_child(_header_label)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	root.add_child(grid)

	for tile in TILES:
		var button := _make_tile(tile[1], tile[2])
		var key: String = tile[0]
		button.pressed.connect(func(): tile_selected.emit(key))
		if key == "wilderness":
			_wilderness_button = button
		grid.add_child(button)

	# Town portal: only shown when a return position is stored.
	_portal_row = HBoxContainer.new()
	_portal_row.add_theme_constant_override("separation", 6)
	var portal_button := _make_tile("assets/items/town_portal_scroll.png", "Return")
	portal_button.pressed.connect(func(): tile_selected.emit("portal"))
	_portal_row.add_child(portal_button)
	_portal_label = Label.new()
	_portal_label.add_theme_font_size_override("font_size", 13)
	_portal_label.add_theme_color_override("font_color", Color("#888888"))
	_portal_row.add_child(_portal_label)
	root.add_child(_portal_row)


func _make_tile(icon_path: String, label_text: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = TILE_SIZE
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE

	# Flat black tile with a thin border. Same style object for every state so a tap
	# has no visual side effect beyond the press flash.
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#000000")
	style.border_color = Color("#333333")
	style.set_border_width_all(1)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("focus", style)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(box)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load(icon_path)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)

	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)

	return button


## Called every time the town is entered. This is where the PWA did its healing and
## shop reset, so the effects happen on ENTRY rather than in _ready() — re-entering
## the town must heal again.
func enter(on_shop_reset: Callable) -> void:
	var hero: Dictionary = _state.hero()
	# Recalibrate from gear FIRST: the hero's maxHP/maxMana depend on what is
	# equipped, so equipping a +HP item in town must raise the heal, not lag a visit
	# behind it.
	var max_hp := _gen.hero_max_hp(hero, _state.equip(), _find_item)
	var max_mana := _gen.hero_max_mana(hero, _state.equip(), str(_state.data.get("heroClass", "")), _find_item)
	hero["maxHp"] = max_hp
	hero["hp"] = max_hp
	hero["maxMana"] = max_mana
	hero["mana"] = max_mana
	_state.save()
	on_shop_reset.call()
	refresh()


func refresh() -> void:
	var hero: Dictionary = _state.hero()
	var cls: Dictionary = _data.class_by_id(str(_state.data.get("heroClass", "")))
	var class_name_text: String = str(cls.get("name", "Adventurer"))
	_header_label.text = "Mesto\n%s   Level %d   Zlato %d\nBody talentu: %d   Body atributu: %d   HP %d/%d" % [
		class_name_text, int(hero["level"]), int(hero.get("gold", 0)),
		int(_state.data.get("talentPoints", 0)), int(hero.get("attrPoints", 0)),
		int(hero.get("hp", 0)), int(hero.get("maxHp", 0))]

	# Wilderness is offered only while an act is still uncompleted — otherwise the
	# button is a dead end.
	_wilderness_button.visible = _first_uncompleted_act() >= 0

	var portal: Variant = _state.data.get("townPortalReturn")
	if portal == null:
		_portal_row.visible = false
	else:
		_portal_row.visible = true
		var acts: Array = _data.acts()
		var act_id := int(portal.get("actId", 0))
		var act_name: String = acts[act_id]["name"] if act_id < acts.size() else "Act %d" % (act_id + 1)
		_portal_label.text = "Return to %s, Area %d" % [act_name, int(portal.get("zoneId", 0)) + 1]


## The first act whose boss is still alive at the current difficulty, or -1.
func _first_uncompleted_act() -> int:
	var acts: Array = _data.acts()
	for i in acts.size():
		if not _state.is_boss_defeated(i):
			return i
	return -1


func _load(path: String) -> Texture2D:
	var full := "res://" + path
	if not ResourceLoader.exists(full):
		return null
	return load(full)
