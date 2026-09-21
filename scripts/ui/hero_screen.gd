extends Control
class_name HeroScreen
## HeroScreen — the character sheet, the attribute points and the skill trees.
##
## Ported from `renderHero` + `renderTalents` + `upgradeAttr`, with the PWA's modal tab
## strip replaced by one scroll: a phone screen shows one column, not tabs inside a
## dialog. Everything is a pure read of the state except three actions — spend an
## attribute point, invest a talent point, reset the talents — and all three are
## delegated to `scripts/items/talents.gd` so they are testable headlessly.
##
## The portrait comes from `assets/monsters/<face>.png` because that is where the PWA
## kept the hero faces (HERO_FACES reuses the monster art). No emoji anywhere: a skill
## with no generated icon shows its name instead of its data icon character.

const UIKit := preload("res://scripts/ui/ui_kit.gd")
const Talents := preload("res://scripts/items/talents.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const Progression := preload("res://scripts/combat/progression.gd")

signal back_pressed()
signal message(text: String)

const CELL := 64

var _data: Node
var _gen: ItemGen
var _state
var _find_item: Callable
var _talents: Talents
var _prog: Progression

## Which tree of the class is open, and which skill's info is shown.
var _tree_id := ""
var _selected_key := ""

var _name_label: Label
var _class_label: Label
var _xp_label: Label
var _xp_fill: ColorRect
var _stats_box: VBoxContainer
var _attr_box: VBoxContainer
var _stats_card: PanelContainer
var _attr_card: PanelContainer
var _gold_label: Label
var _talent_points_label: Label
var _tree_row: HBoxContainer
var _talent_grid: VBoxContainer
var _skill_info: VBoxContainer
var _reset_button: Button


func _init(game_data: Node, gen: ItemGen, state, find_item: Callable) -> void:
	_data = game_data
	_gen = gen
	_state = state
	_find_item = find_item
	_talents = Talents.new(game_data)
	_prog = Progression.new(game_data)


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

	var header := UIKit.page_header("assets/monsters/hero.png", "Hrdina",
		"Atributy, vybava a talenty.", "")
	_gold_label = header["right"]
	column.add_child(header["root"])

	var page_box := VBoxContainer.new()
	page_box.add_theme_constant_override("separation", 10)
	page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(page_box)

	page_box.add_child(_card(_build_identity()))
	_stats_card = _card(_build_stats())
	page_box.add_child(_stats_card)
	_attr_card = _card(_build_attrs())
	page_box.add_child(_attr_card)
	page_box.add_child(_card(_build_talents()))


## `.card { background:#1a1a1a; border:1px solid #2a2a2a; border-radius:10px;
##          padding:14px; margin:8px 0 }` — the PWA's own block. Jan's rule about "no
## cards" is about FORM elements in CFSB (flat, machine design); this game's hero sheet
## has been cards since the PWA, and the CSS is the specification here.
func _card(content: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1a1a1a")
	style.border_color = Color("#2a2a2a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(content)
	return panel


func _build_identity() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(110, 110)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.name = "Portrait"
	row.add_child(portrait)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)

	_name_label = UIKit.label("", 22)
	column.add_child(_name_label)
	_class_label = UIKit.label("", 14, UIKit.DIM)
	column.add_child(_class_label)

	var xp_track := ColorRect.new()
	xp_track.color = Color("#1a1a1a")
	xp_track.custom_minimum_size = Vector2(300, 12)
	_xp_fill = ColorRect.new()
	_xp_fill.color = Color("#6b5aa0")
	_xp_fill.position = Vector2.ZERO
	xp_track.add_child(_xp_fill)
	column.add_child(xp_track)
	_xp_label = UIKit.label("", 12, UIKit.DIM)
	column.add_child(_xp_label)

	return row


## The stat block inside its `.card`: a heading and the lines `_refresh_stats()` writes.
## The box is rebuilt on every refresh (the numbers all change), so the builder only has
## to make it exist and give it a heading.
func _build_stats() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(UIKit.section_label("Vlastnosti"))
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 2)
	box.add_child(_stats_box)
	return box


## The attribute block: heading, then the four attribute columns with their `+1` buttons,
## written by `_refresh_attrs()`.
func _build_attrs() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_attr_box = VBoxContainer.new()
	_attr_box.add_theme_constant_override("separation", 2)
	box.add_child(_attr_box)
	return box


func _build_talents() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_talent_points_label = UIKit.label("", 16, UIKit.GOLD)
	head.add_child(_talent_points_label)
	_reset_button = UIKit.flat_button("Reset (50 zlata)", 160.0, 34.0, 13)
	_reset_button.pressed.connect(_on_reset)
	head.add_child(_reset_button)
	box.add_child(head)

	_tree_row = HBoxContainer.new()
	_tree_row.add_theme_constant_override("separation", 4)
	box.add_child(_tree_row)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_talent_grid = VBoxContainer.new()
	_talent_grid.add_theme_constant_override("separation", 6)
	_talent_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_talent_grid)

	_skill_info = VBoxContainer.new()
	_skill_info.add_theme_constant_override("separation", 2)
	box.add_child(_skill_info)

	return box


# --- refresh -----------------------------------------------------------------

func refresh() -> void:
	var hero: Dictionary = _state.hero()
	var hero_class := str(_state.data.get("heroClass", ""))
	var cls: Dictionary = _data.class_by_id(hero_class)

	_name_label.text = str(hero.get("name", "Dobrodruh"))
	_class_label.text = "%s   Level %d   Zlato %d   Vitezstvi %d / Smrti %d" % [
		str(cls.get("name", "Dobrodruh")), int(hero.get("level", 1)),
		int(hero.get("gold", 0)), int(_state.data.get("wins", 0)), int(_state.data.get("deaths", 0))]

	var portrait: TextureRect = _find_child(self, "Portrait")
	if portrait != null:
		var face := str(hero.get("face", "hero"))
		portrait.texture = UIKit.load_texture("assets/monsters/%s.png" % face)

	# XP: the bar shows progress toward the NEXT level, capped like the PWA's.
	var level := int(hero.get("level", 1))
	var need := _prog.xp_needed(level)
	var xp := int(hero.get("xp", 0))
	var ratio := clampf(float(xp) / float(maxi(need, 1)), 0.0, 1.0)
	var width := 300.0
	_xp_fill.size = Vector2(width * ratio, 12)
	_xp_label.text = "%d / %d XP" % [xp, need]

	_refresh_stats()
	_refresh_attrs(hero)
	_refresh_talents()


func _refresh_stats() -> void:
	_clear(_stats_box)
	var hero: Dictionary = _state.hero()
	var equip: Dictionary = _state.equip()
	var weapon: Dictionary = _find_item.call(equip.get("weapon"))
	if weapon.is_empty():
		weapon = _data.item("fists")
	var spec := _talents.weapon_spec(_state, weapon)
	var dmg: Dictionary = Progression.hero_dmg(hero, equip, _find_item, _talents.shield_spec_dmg_mult(_state))
	var def := _talents.total_defense(_state, _find_item)
	var attrs := _gen.equip_attr_sum(equip, _find_item, ["dex"])
	var dex := int(hero.get("attrDex", 0)) + int(attrs["dex"])
	var crit := int(weapon.get("critChance", 0)) + int(spec["critBonus"])
	var block := _talents.player_block_chance(_state, _find_item, _gen)
	var max_hp := _gen.hero_max_hp(hero, equip, _find_item)
	var max_mana := _gen.hero_max_mana(hero, equip, str(_state.data.get("heroClass", "")), _find_item)

	var lines := [
		"Poskozeni: %d-%d" % [int(dmg["min"]), int(dmg["max"])],
		"Obrana: %d (%d%%)" % [def, Talents.defense_percent(def)],
		"Crit: %d%% (x2.0)   Block: %d%%" % [crit, block],
		"Uhyb: %d%%   Zasah: %d%%" % [Talents.dodge_percent(dex), Talents.hit_percent(dex)],
		"HP: %d / %d   Mana: %d / %d" % [maxi(0, int(hero.get("hp", 0))), max_hp,
			int(hero.get("mana", 0)), max_mana],
		"Resisty: ohen %d%%   chlad %d%%   blesk %d%%   jed %d%%" % [
			Talents.player_resist(_state, "fire", _find_item),
			Talents.player_resist(_state, "ice", _find_item),
			Talents.player_resist(_state, "lightning", _find_item),
			Talents.player_resist(_state, "nature", _find_item)],
	]
	for line in lines:
		_stats_box.add_child(UIKit.label(line, 14))


func _refresh_attrs(hero: Dictionary) -> void:
	_clear(_attr_box)
	var equips := _gen.equip_attr_sum(_state.equip(), _find_item, ["str", "vit", "dex", "int"])
	var points := int(hero.get("attrPoints", 0))
	_attr_box.add_child(UIKit.label("Atributy   body: %d" % points, 15, UIKit.GOLD if points > 0 else UIKit.DIM))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_attr_box.add_child(row)
	for entry in [
		["str", "Sila", "attrStr"], ["vit", "Vitalita", "attrVit"],
		["dex", "Obratnost", "attrDex"], ["int", "Intelekt", "attrInt"],
	]:
		var attr := str(entry[0])
		var base := int(hero.get(str(entry[2]), 0))
		var bonus := int(equips[attr])
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		row.add_child(column)
		var text := "%s %d" % [str(entry[1]), base]
		if bonus > 0:
			text += " (+%d)" % bonus
		column.add_child(UIKit.label(text, 14, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		var button := UIKit.flat_button("+1", 110.0, 36.0, 14)
		# The PWA dimmed the button when there were no points; here the label says so and
		# the border dims, but the button stays tappable so it can explain itself.
		if points <= 0:
			button.add_theme_color_override("font_color", Color(UIKit.BAD))
		button.pressed.connect(func(): _on_attr(attr))
		column.add_child(button)


func _on_attr(attr: String) -> void:
	var result := _talents.spend_attr(_state, attr, _find_item, _gen)
	message.emit(str(result["message"]))
	refresh()


func _refresh_talents() -> void:
	var hero_class := str(_state.data.get("heroClass", ""))
	var points := int(_state.data.get("talentPoints", 0))
	_talent_points_label.text = "Body talentu: %d" % points

	var spent := 0
	for key in (_state.data.get("talentLevels", {}) as Dictionary):
		spent += int(_state.data["talentLevels"][key])
	_reset_button.visible = spent > 0

	_clear(_tree_row)
	_clear(_talent_grid)
	_clear(_skill_info)

	var trees := _talents.tree_ids(hero_class)
	if trees.is_empty():
		_talent_grid.add_child(UIKit.label("Nejdriv si vyber classu.", 14, UIKit.DIM))
		return
	if not (_tree_id in trees):
		_tree_id = str(trees[0])

	var cls := _talents.class_tree(hero_class)
	var tree: Dictionary = cls.get("trees", {}).get(_tree_id, {})
	for tree_key in trees:
		var tree_data: Dictionary = cls.get("trees", {}).get(tree_key, {})
		var button := UIKit.flat_button(str(tree_data.get("name", tree_key)), 0.0, 34.0, 14)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var active := str(tree_key) == _tree_id
		var style := UIKit.panel_style(UIKit.GOLD if active else UIKit.BORDER, 2 if active else 1)
		for state_name in ["normal", "pressed", "hover", "focus", "disabled"]:
			button.add_theme_stylebox_override(state_name, style)
		var target := str(tree_key)
		button.pressed.connect(func(): _open_tree(target))
		_tree_row.add_child(button)

	var tiers: Array = tree.get("tiers", [])
	for tier_idx in tiers.size():
		_talent_grid.add_child(_tier_row(tier_idx, tiers[tier_idx]))

	_refresh_skill_info()


func _open_tree(tree_id: String) -> void:
	_tree_id = tree_id
	_selected_key = ""
	_refresh_talents()


## One tier: a label saying whether it is open, then the skill cells. A locked tier
## still shows its skills — the player must be able to see what they are working
## toward — but every cell is dimmed and investing is refused.
func _tier_row(tier_idx: int, tier: Dictionary) -> Control:
	var hero_level := int(_state.hero().get("level", 1))
	var unlocked := Talents.tier_unlocked(tier_idx, hero_level)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var tier_name := "Tier %d" % (tier_idx + 1)
	if not unlocked:
		tier_name += " - odemkne se na levelu %d" % (6 if tier_idx == 1 else 12)
	box.add_child(UIKit.label(tier_name, 12, UIKit.DIM if not unlocked else UIKit.TEXT))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for choice in tier.get("choices", []):
		var key := "%s_%s" % [str(_state.data.get("heroClass", "")), str(choice.get("k", ""))]
		row.add_child(_skill_cell(key, choice, unlocked))
	return box


func _skill_cell(key: String, choice: Dictionary, tier_open: bool) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)

	var level := _talents.talent_level(_state, key)
	var max_level := int(choice.get("maxLv", 1))
	var available := tier_open and _talents.prerequisites_met(_state, key)

	var cell := Button.new()
	cell.custom_minimum_size = Vector2(CELL, CELL)
	cell.focus_mode = Control.FOCUS_NONE
	var border := Color(UIKit.BORDER)
	if _selected_key == key:
		border = Color(UIKit.GOLD)
	elif available:
		border = Color("#6b6b6b")
	var style := UIKit.panel_style()
	style.border_color = border
	style.set_border_width_all(2 if _selected_key == key else 1)
	for state_name in ["normal", "pressed", "hover", "focus", "disabled"]:
		cell.add_theme_stylebox_override(state_name, style)

	var icon_path := _talents.icon_path(key)
	var texture := UIKit.load_texture(icon_path)
	if texture != null:
		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = texture
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not available:
			icon.modulate = Color(1, 1, 1, 0.3)
		cell.add_child(icon)
	else:
		var fallback := UIKit.label(str(choice.get("name", "?")), 10, UIKit.DIM, HORIZONTAL_ALIGNMENT_CENTER)
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(fallback)

	cell.pressed.connect(func(): _select_skill(key))
	column.add_child(cell)
	column.add_child(UIKit.label("%d/%d" % [level, max_level], 11,
		UIKit.GOLD if level > 0 else UIKit.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	return column


## A no-op kept as the hook for a future single-column layout: the tier grid owns the
## rows today, so a cell builder has nothing to attach to.
func row_owner_guard(_node: Node) -> void:
	pass


func _select_skill(key: String) -> void:
	_selected_key = key
	_refresh_talents()


func _refresh_skill_info() -> void:
	_clear(_skill_info)
	if _selected_key == "":
		return
	var s := _talents.skill(_selected_key)
	if s.is_empty():
		return
	var level := _talents.talent_level(_state, _selected_key)
	_skill_info.add_child(UIKit.label("%s   %d/%d" % [str(s.get("name", "?")), level, int(s.get("maxLv", 1))], 16))
	_skill_info.add_child(UIKit.label(_talents.effect_summary(_selected_key), 13, UIKit.MOD_BLUE))
	var reason := _talents.blocked_reason(_state, _selected_key)
	if reason != "":
		_skill_info.add_child(UIKit.label(reason, 13, UIKit.BAD))
	else:
		var invest := UIKit.flat_button("Pridat bod", 160.0, 36.0, 14)
		invest.pressed.connect(_on_invest)
		_skill_info.add_child(invest)


func _on_invest() -> void:
	var result := _talents.invest(_state, _selected_key)
	message.emit(str(result["message"]))
	_refresh_talents()


func _on_reset() -> void:
	var result := Talents.reset(_state)
	message.emit(str(result["message"]))
	refresh()


func _find_child(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := _find_child(child, target_name)
		if found != null:
			return found
	return null


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
