extends Control
class_name TownScreen
## TownScreen — the hub, laid out from the PWA's own markup and CSS.
##
## Source is `index.html`'s `#townScreen` block plus the `.town-banner` / `.town-grid` /
## `.town-tile` rules in `public/style.css`. The PWA's town is:
##
##   .town-banner      full-bleed `assets/town.webp`, aspect-ratio 1/1, object-fit cover,
##                     with the title and subtitle CENTRED OVER the image
##   .town-grid        2 columns, 10px gap — five tiles, NO labels under them
##   .town-tile        aspect-ratio 4/3, border #333 on black, radius 0, image at 70%
##
## The previous port had three columns, labels under every tile, extra tiles (inventory,
## hero) and the stat line in the header. None of that is in the PWA, and inventing layout
## is what made the port read as a different game.
##
## The navigation the PWA did with its fixed bottom `.nav-bar` now lives on this screen's
## grid — inventory and hero have no town tile in the PWA, but the port has no bottom nav
## yet, and dropping them would remove access to two whole screens. They are added as
## tiles rather than as a nav bar on purpose: a nav bar is a bigger, separate piece of work
## (badges, active state, every screen).

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const UIKit := preload("res://scripts/ui/ui_kit.gd")

signal tile_selected(screen_key: String)
signal difficulty_selected(difficulty: int)

## `.town-tile { aspect-ratio: 4/3 }` inside a 2-column grid with a 10px gap and the PWA's
## 16px container padding. 390 - 32 = 358; (358 - 10) / 2 = 174 wide, 174 * 3/4 = 130.5.
const TILE_SIZE := Vector2(174, 130)

## tile key -> (icon, label). The PWA's five come first, in the PWA's order.
const TILES := [
	["chest", "assets/menu-icons/chest.png", "Truhla"],
	["gamble", "assets/menu-icons/gamble.png", "Gamble"],
	["shop", "assets/menu-icons/shop.png", "Obchod"],
	["craft", "assets/menu-icons/craft.png", "Craft"],
	["wilderness", "assets/map.webp", "Divocina"],
	["inventory", "assets/menu-icons/inventar.png", "Inventar"],
	["hero", "assets/menu-icons/talenty.png", "Hrdina"],
]

var _data: Node
var _gen: ItemGen
var _state
var _find_item: Callable

var _wilderness_button: Button
var _portal_row: Control
var _portal_label: Label
var _title_label: Label
var _sub_label: Label
var _stat_label: Label
var _difficulty_row: HBoxContainer
var _difficulty_label: Label


func _init(game_data: Node, gen: ItemGen, state, find_item: Callable) -> void:
	_data = game_data
	_gen = gen
	_state = state
	_find_item = find_item


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#121212")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)

	column.add_child(_build_banner())

	# The stat line and the difficulty selector are the port's own: the PWA put the
	# character readout on the hero screen and the difficulty on the map. They stay here
	# because this port has no map screen and no bottom nav, and a player who cannot see
	# their level or change difficulty is worse off than one seeing it in the wrong place.
	var stats := MarginContainer.new()
	stats.add_theme_constant_override("margin_left", 16)
	stats.add_theme_constant_override("margin_right", 16)
	column.add_child(stats)
	# The stat line is one long string at 390px wide, so it is allowed to WRAP rather
	# than run off the right edge — a value the player cannot read is worse than two lines.
	_stat_label = UIKit.label("", 13, "#cccccc")
	_stat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.add_child(_stat_label)

	var diffs := MarginContainer.new()
	diffs.add_theme_constant_override("margin_left", 16)
	diffs.add_theme_constant_override("margin_right", 16)
	column.add_child(diffs)
	var diff_box := VBoxContainer.new()
	diff_box.add_theme_constant_override("separation", 6)
	diffs.add_child(diff_box)
	_difficulty_row = HBoxContainer.new()
	_difficulty_row.add_theme_constant_override("separation", 6)
	diff_box.add_child(_difficulty_row)
	_difficulty_label = UIKit.label("", 12, "#888888")
	diff_box.add_child(_difficulty_label)

	var grid_pad := MarginContainer.new()
	grid_pad.add_theme_constant_override("margin_left", 16)
	grid_pad.add_theme_constant_override("margin_right", 16)
	grid_pad.add_theme_constant_override("margin_bottom", 16)
	column.add_child(grid_pad)

	# `.town-grid` — 2 columns, 10px gap. Exactly the PWA's, not an approximation.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid_pad.add_child(grid)

	for tile in TILES:
		var button := _make_tile(tile[1], tile[2])
		var key: String = tile[0]
		button.pressed.connect(func(): tile_selected.emit(key))
		if key == "wilderness":
			_wilderness_button = button
		grid.add_child(button)

	# Town portal: `.town-action-card`, a full-width row with the scroll icon, shown only
	# when a return position is stored.
	_portal_row = MarginContainer.new()
	_portal_row.add_theme_constant_override("margin_left", 16)
	_portal_row.add_theme_constant_override("margin_right", 16)
	_portal_row.add_theme_constant_override("margin_bottom", 16)
	column.add_child(_portal_row)
	var portal_card := _make_action_card()
	portal_card["button"].pressed.connect(func(): tile_selected.emit("portal"))
	_portal_row.add_child(portal_card["root"])
	_portal_label = portal_card["label"]


## `.town-banner` — full-bleed town.webp, square, cover-cropped, with the title centred
## over it. The PWA's banner breaks out of the container with `width:100vw`.
func _build_banner() -> Control:
	var banner := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0a0a0a")
	style.border_color = Color("#555555")
	style.set_border_width_all(0)
	# `border-top/bottom: 2px solid #555`, no side borders.
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.set_corner_radius_all(0)
	banner.add_theme_stylebox_override("panel", style)

	var inner := Control.new()
	inner.custom_minimum_size = Vector2(0, 390)
	banner.add_child(inner)

	var image := TextureRect.new()
	image.set_anchors_preset(Control.PRESET_FULL_RECT)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# `.town-banner-img { aspect-ratio:1/1; object-fit:cover }`
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.texture = _load("assets/town.webp")
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(image)

	var centre := VBoxContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_theme_constant_override("separation", 2)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(centre)

	# `.town-banner-title` — 30px, weight 800, white, letterspacing 2px, with a hard
	# shadow so it reads over the artwork.
	_title_label = UILabel.new()
	_title_label.text = "Mesto"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 30)
	_title_label.add_theme_color_override("font_color", Color("#ffffff"))
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(_title_label)

	_sub_label = UILabel.new()
	_sub_label.text = "Odpočívej, nakupuj a plánuj další výpravu."
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.add_theme_font_size_override("font_size", 13)
	_sub_label.add_theme_color_override("font_color", Color("#dddddd"))
	_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(_sub_label)
	return banner


## A label with a hard drop shadow, which is what makes the PWA's title readable over the
## artwork. Godot's Label has an outline, not a shadow, so the outline is the mechanism —
## it is the same visual job.
class UILabel:
	extends Label

	func _init() -> void:
		add_theme_constant_override("outline_size", 8)
		add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))


## `.town-tile` — a 4:3 black tile with a 1px #333 border, radius 0, and the icon at 70%
## of the tile. No label: the PWA's tiles have none, and adding them is what made the
## previous port's town look like a menu rather than the PWA's grid.
func _make_tile(icon_path: String, label_text: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = TILE_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = label_text

	# One style object for EVERY state, per Jan's rule: no hover, no focus ring, and the
	# press only darkens to #111 and brightens the border to #555, as the PWA's :active.
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#000000")
	style.border_color = Color("#333333")
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color("#111111")
	pressed.border_color = Color("#555555")
	pressed.set_border_width_all(1)
	pressed.set_corner_radius_all(0)
	for state_name in ["normal", "hover", "focus", "disabled"]:
		button.add_theme_stylebox_override(state_name, style)
	button.add_theme_stylebox_override("pressed", pressed)

	var icon := TextureRect.new()
	# `.town-tile img { width:70%; height:70%; object-fit:contain }`
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = TILE_SIZE.x * 0.15
	icon.offset_top = TILE_SIZE.y * 0.15
	icon.offset_right = -TILE_SIZE.x * 0.15
	icon.offset_bottom = -TILE_SIZE.y * 0.15
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load(icon_path)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)

	return button


## `.town-action-card` — a full-width black row with a 44px icon slot and a label.
func _make_action_card() -> Dictionary:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 68)
	button.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#000000")
	style.border_color = Color("#333333")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color("#111111")
	pressed.border_color = Color("#555555")
	pressed.set_border_width_all(1)
	pressed.set_corner_radius_all(10)
	for state_name in ["normal", "hover", "focus", "disabled"]:
		button.add_theme_stylebox_override(state_name, style)
	button.add_theme_stylebox_override("pressed", pressed)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -16
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load("assets/items/town_portal_scroll.png")
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var label := UIKit.label("", 14, "#dddddd")
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	return {"root": button, "button": button, "label": label}


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
	_stat_label.text = "%s   Level %d   Zlato %d   |   Talenty %d   Atributy %d   HP %d/%d" % [
		class_name_text, int(hero["level"]), int(hero.get("gold", 0)),
		int(_state.data.get("talentPoints", 0)), int(hero.get("attrPoints", 0)),
		int(hero.get("hp", 0)), int(hero.get("maxHp", 0))]

	_refresh_difficulty()

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
		_portal_label.text = "Navrat do %s, oblast %d" % [act_name, int(portal.get("zoneId", 0)) + 1]


## One button per difficulty — active, locked, or tappable. The active one carries no
## handler: tapping it would be a no-op, and a button that looks tappable and does
## nothing is worse than a button that looks settled.
##
## The LOCKED ones stay visible with the reason in their label rather than being hidden,
## because "what am I working towards" is the whole point of a difficulty selector.
func _refresh_difficulty() -> void:
	for child in _difficulty_row.get_children():
		_difficulty_row.remove_child(child)
		child.queue_free()

	var diffs: Array = _data.difficulties()
	var current := int(_state.data.get("difficulty", 0))

	for i in diffs.size():
		var d: Dictionary = diffs[i]
		var name := str(d.get("name", "Difficulty %d" % (i + 1)))
		var is_active := i == current
		var is_unlocked: bool = _state.is_difficulty_unlocked(i)
		var label := name
		if not is_unlocked and i > 0:
			# Name how much of the PREVIOUS difficulty is still standing, so the lock is
			# actionable rather than just a wall.
			var prev_row: Array = (_state.data["bossesDefeated"] as Array)[i - 1]
			var remaining := 0
			for defeated in prev_row:
				if not bool(defeated):
					remaining += 1
			label = "%s (zamceno - %d aktu)" % [name, remaining]

		var button := _make_diff_button(label, is_active, is_unlocked)
		var index := i
		if is_unlocked and not is_active:
			button.pressed.connect(func(): difficulty_selected.emit(index))
		_difficulty_row.add_child(button)

	# Where the player actually is, and what the difficulty they are on does to the
	# numbers. Without this line the selector is three buttons and a guess.
	var cur_diff: Dictionary = diffs[current] if current < diffs.size() else {}
	var act_id: int = _first_uncompleted_act()
	if act_id < 0:
		_difficulty_label.text = "Obtiznost %d z %d - vsechny akty dokoncene, prepni vys" % [current + 1, diffs.size()]
	else:
		_difficulty_label.text = "Obtiznost %d z %d - akt %d, uroven monster %d-%d, sila monster x%s" % [
			current + 1, diffs.size(), act_id + 1,
			int(cur_diff.get("monsterLvMin", 1)), int(cur_diff.get("monsterLvMax", 1)),
			str(cur_diff.get("mult", 1.0))]


func _make_diff_button(text: String, is_active: bool, is_unlocked: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 34)
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 11)
	button.clip_text = true
	# Three buttons share 358px, so a locked label like "Nightmare (zamceno - 5 aktu)"
	# does not fit. It wraps to two lines rather than being cut mid-word.
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Flat, same object for every state (no hover/focus effects — mobile heritage). The
	# three variants differ only in colour, and read as: settled / available / locked.
	var style := StyleBoxFlat.new()
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	if is_active:
		style.bg_color = Color("#2a2418")
		style.border_color = Color("#c8a24a")
	elif is_unlocked:
		style.bg_color = Color("#000000")
		style.border_color = Color("#666666")
	else:
		style.bg_color = Color("#000000")
		style.border_color = Color("#2a2a2a")
	for state_name in ["normal", "pressed", "hover", "focus", "disabled"]:
		button.add_theme_stylebox_override(state_name, style)
	if is_active:
		button.add_theme_color_override("font_color", Color("#e8c86a"))
	elif is_unlocked:
		button.add_theme_color_override("font_color", Color("#d0d0d0"))
	else:
		button.add_theme_color_override("font_color", Color("#5a5a5a"))
	return button


## The first act whose boss is still alive at the current difficulty, or -1.
func _first_uncompleted_act() -> int:
	return _state.first_uncompleted_act()


func _load(path: String) -> Texture2D:
	var full := "res://" + path
	if not ResourceLoader.exists(full):
		return null
	return load(full)
