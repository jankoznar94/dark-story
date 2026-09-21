extends Control
class_name TownScreen
## TownScreen — the hub, laid out from the PWA's own markup and CSS.
##
## Source is `index.html`'s `#townScreen` block plus the `.town-banner` / `.town-grid` /
## `.town-tile` rules in `public/style.css`. The PWA's town is EXACTLY this and nothing
## else:
##
##   .town-banner      full-bleed `assets/town.webp`, aspect-ratio 1/1, object-fit cover,
##                     with the title and subtitle CENTRED OVER the image
##   .town-grid        2 columns, 10px gap — five tiles, NO labels under them
##   .town-tile        aspect-ratio 4/3, border #333 on black, radius 0, image at 70%
##   .town-action-card the town portal row, shown only while a return position is stored
##
## An earlier version of this screen also carried a stat line and a difficulty selector,
## plus two extra tiles for inventory and hero. NONE of that is in the PWA:
##
##   * the stat line belongs to the hero sheet (`renderHero`),
##   * the difficulty selector belongs at the TOP OF THE MAP (`renderMap` builds
##     `.diff-selector` into `#mapScroll`), which is why it now lives on the map screen,
##   * inventory and hero are reached from the fixed bottom `.nav-bar`, not from tiles.
##
## Inventing layout is what made the port read as a different game, so those are gone
## rather than restyled.
##
## The wilderness tile does NOT jump straight into the first act: the PWA's
## `enterCurrentAct()` shows the map and lets the player pick a stop
## (`enterStop(actId, stop)`). That call site is now the map screen.
##
## Measured against the shipping PWA frame (`tools/reference/pwa/town.png`, shot at
## 390x844 by tools/import/shoot_pwa.py): the banner runs to y=390, the grid's first row
## of edges is at y=410 and each tile is 130px tall with a 10px gap, and the tiles are
## 174px wide starting at x=16. Those numbers are what TILE_SIZE below encodes.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const UIKit := preload("res://scripts/ui/ui_kit.gd")

signal tile_selected(screen_key: String)
signal stop_requested(act_id: int, stop: int)

## `.town-tile { aspect-ratio: 4/3 }` inside a 2-column grid with a 10px gap and the PWA's
## 16px container padding. 390 - 32 = 358; (358 - 10) / 2 = 174 wide, 174 * 3/4 = 130.5.
const TILE_SIZE := Vector2(174, 130)

## `.town-banner-img { aspect-ratio:1/1; object-fit:cover }` on a 100vw banner = 390 of
## image, plus `border-top` and `border-bottom` of 2px = 394. Measured off the shipping
## PWA frame: the grid's first row of `.town-tile` borders sits at y=410, i.e. 394 plus
## the banner's own 16px `margin-bottom`.
const BANNER_IMAGE := 390.0
const BANNER_HEIGHT := BANNER_IMAGE + 4.0

## The PWA's five tiles, in the PWA's order. `wilderness` is NOT a screen: it enters the
## current act through the map, exactly like `game.enterCurrentAct()`.
const TILES := [
	["chest", "assets/menu-icons/chest.png", "Truhla"],
	["gamble", "assets/menu-icons/gamble.png", "Gamble"],
	["shop", "assets/menu-icons/shop.png", "Obchod"],
	["craft", "assets/menu-icons/craft.png", "Craft"],
	["wilderness", "assets/map.webp", "Divocina"],
]

var _data: Node
var _gen: ItemGen
var _state
var _find_item: Callable

var _wilderness_button: Button
var _portal_row: Control
var _portal_label: Label


func _init(game_data: Node, gen: ItemGen, state, find_item: Callable) -> void:
	_data = game_data
	_gen = gen
	_state = state
	_find_item = find_item


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	# `.container` for this screen is NOT UIKit.screen_page: the PWA's `.town-banner`
	# breaks OUT of the container (`width:100vw; margin-left:calc(50% - 50vw)`) and
	# cancels the container's top padding with `margin-top:-16px`. Putting the banner
	# in a padded column instead laid the whole grid ON TOP OF the banner — the tiles
	# were in the tree, sized right, and painted underneath the full-bleed image, which
	# is why the town rendered as a banner over an empty box.
	var bg := ColorRect.new()
	bg.color = Color(UIKit.PAGE_BG)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 8
	add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	scroll.add_child(column)

	column.add_child(_build_banner())

	# `.town-grid { display:grid; grid-template-columns:repeat(2,1fr); gap:10px;
	#              margin:0 0 10px 0 }` inside the container's 16px side padding.
	var grid_pad := MarginContainer.new()
	grid_pad.add_theme_constant_override("margin_left", 16)
	grid_pad.add_theme_constant_override("margin_right", 16)
	grid_pad.add_theme_constant_override("margin_top", 16)
	grid_pad.add_theme_constant_override("margin_bottom", 10)
	column.add_child(grid_pad)

	# `.town-grid` — 2 columns, 10px gap. Exactly the PWA's, not an approximation.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid_pad.add_child(grid)

	for tile in TILES:
		var button := _make_tile(str(tile[1]), str(tile[2]))
		var key: String = tile[0]
		button.pressed.connect(func(): _on_tile(key))
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

	# `.container { padding: 16px 16px 70px 16px }` — the bottom 70px is where the fixed
	# nav bar sits, so the last tile must not hide behind it.
	var nav_reserve := Control.new()
	nav_reserve.custom_minimum_size = Vector2(0, UIKit.NAV_RESERVE)
	nav_reserve.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(nav_reserve)


## `.town-banner` — full-bleed town.webp, square, cover-cropped, with the title centred
## over it. 390 wide at aspect-ratio 1/1 = 390 of image, plus the PWA's 2px top and
## bottom borders = 394 of screen; the grid's first row of borders lands on y=410, which
## is 394 + the banner's own 16px margin-bottom.
func _build_banner() -> Control:
	var banner := PanelContainer.new()
	banner.custom_minimum_size = Vector2(0, BANNER_HEIGHT)
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
	inner.custom_minimum_size = Vector2(0, BANNER_IMAGE)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var title := UIKit.UILabel.new()
	title.text = "Mesto"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#ffffff"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(title)

	var sub := UIKit.UILabel.new()
	sub.text = "Odpocivej, nakupuj a planuj dalsi vypravu."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color("#dddddd"))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(sub)
	return banner


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


## One tap, one meaning: the four town tiles open their screen, the wilderness tile asks
## the router for the map (where the player picks a stop). The PWA's `enterCurrentAct()`
## did exactly that — it showed the map rather than starting a fight.
func _on_tile(key: String) -> void:
	if key == "wilderness":
		stop_requested.emit(-1, -1)
		return
	tile_selected.emit(key)


## Called every time the town is entered. This is where the PWA did its healing and
## shop reset (`renderTown` set maxHp/hp/mana and called `_resetShopCache`), so the
## effects happen on ENTRY rather than in _ready() — re-entering the town must heal again.
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
	# Wilderness is offered only while an act is still uncompleted — otherwise the
	# button is a dead end. Same rule as the PWA's `canEnter` in renderTown.
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


## The first act whose boss is still alive at the current difficulty, or -1.
func _first_uncompleted_act() -> int:
	return _state.first_uncompleted_act()


func _load(path: String) -> Texture2D:
	var full := "res://" + path
	if not ResourceLoader.exists(full):
		return null
	return load(full)
