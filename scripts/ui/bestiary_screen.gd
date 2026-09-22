extends Control
class_name BestiaryScreen
## BestiaryScreen — every monster in the game, grouped by act, with the ones the hero has
## actually met shown and the rest drawn as locked cards.
##
## Ported from `renderBestiary`. Two rules from there carry the screen:
##
##   1. A monster is "seen" when its FACE ART is in `state.encounteredMonsters` — the
##      battle adds it when a fight starts. Unseen entries are not hidden: they are drawn
##      greyed with `???` where the name and the traits go, because the point of a
##      bestiary is to show there is something left to find.
##   2. `MONSTER_DB` is grouped by THEME and the acts are in a DIFFERENT order
##      (`MONSTER_DB` is [forest, desert, undead, hell, frost], ACTS is
##      [forest, desert, frost, undead, hell]), so the section title comes from the act
##      whose `theme` matches, not from the index. Getting that wrong labels the wrong
##      act — the PWA carried a comment about exactly this mistake.
##
## No emoji: the PWA marked a monster's type with a glyph and its attack type with a
## sword/orb. Here both are written words, and the portrait is the real generated art
## cropped to a circle (`.bestiary-portrait-frame`: 64px, 2px #3a3a5a border).

const UIKit := preload("res://scripts/ui/ui_kit.gd")

signal back_pressed()

const PORTRAIT := 64.0

var _data: Node
var _state

var _list: VBoxContainer


func _init(game_data: Node, state) -> void:
	_data = game_data
	_state = state


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var page := UIKit.screen_page(self)
	var column: VBoxContainer = page["column"]
	column.add_theme_constant_override("separation", 8)

	# `.card` + `.card-title` with the PWA's 32px `.page-icon`, and NO "Back to Town"
	# button: the live bestiary measured `div.card [16,24 358x86]` directly under the
	# container's padding, with the nav bar as the only way out.
	var header := UIKit.card_header("Bestiar",
		"Vsechny monstra, jejich typy a utocne vzorce.", "assets/menu-icons/bestiar.png")
	column.add_child(header["root"])

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_list)


func refresh() -> void:
	_clear(_list)
	var seen: Array = _state.data.get("encounteredMonsters", [])
	var themes: Array = _data.table("DUNGEON_THEMES", [])
	var acts: Array = _data.acts()
	var monster_db: Array = _data.table("MONSTER_DB", [])
	var types: Dictionary = _data.table("MONSTER_TYPES", {})
	var attack_types: Dictionary = _data.table("ATTACK_TYPES", {})

	for theme_idx in monster_db.size():
		var theme: Dictionary = themes[theme_idx] if theme_idx < themes.size() else {}
		var act := _act_for_theme(acts, theme_idx)
		var title := UIKit.UILabel.new()
		title.text = str(act.get("name", "Oblast %d" % (theme_idx + 1)))
		title.add_theme_font_size_override("font_size", 17)
		title.add_theme_color_override("font_color", Color(str(theme.get("border", "#dddddd"))))
		_list.add_child(title)

		var monsters: Array = monster_db[theme_idx]
		for monster in monsters:
			_list.add_child(_card(monster, theme, seen, types, attack_types))

		# The boss card closes the section, as in the PWA — it is the last thing in the
		# act and the only entry with more than one type.
		if not act.is_empty() and act.has("boss"):
			_list.add_child(_boss_card(act["boss"], theme, seen, types, attack_types))


## The act whose `theme` matches, or an empty dictionary. The order of ACTS does not
## match the order of MONSTER_DB, so this lookup is the only correct way to title a
## section.
func _act_for_theme(acts: Array, theme_idx: int) -> Dictionary:
	for act in acts:
		if int((act as Dictionary).get("theme", -1)) == theme_idx:
			return act
	return {}


func _card(monster: Dictionary, theme: Dictionary, seen: Array, types: Dictionary,
		attack_types: Dictionary) -> Control:
	var face := str(monster.get("face", ""))
	var is_seen := seen.has(face)
	var panel := PanelContainer.new()
	# `.bestiary-card { border-left:3px solid <theme> }`
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0d0d0d")
	style.border_color = Color(str(theme.get("border", "#333333"))) if is_seen else Color("#333333")
	style.set_border_width_all(0)
	style.border_width_left = 3
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	if not is_seen:
		# `.bestiary-card` for an unseen one: opacity 0.5 and grayscale.
		panel.modulate = Color(0.75, 0.75, 0.75, 0.5)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var portrait := UIKit.CircularPortrait.new()
	portrait.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	portrait.size = Vector2(PORTRAIT, PORTRAIT)
	portrait.backdrop = Color("#0d0d0d")
	portrait.ring_colour = Color("#3a3a5a")
	portrait.ring_width = 2.0
	# Unseen monsters have no art drawn at all: the circle is there, the face is not.
	portrait.texture = UIKit.load_texture(face) if is_seen else null
	row.add_child(portrait)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)

	if is_seen:
		column.add_child(UIKit.label(str(monster.get("name", "?")), 16, "#f0f0f0"))
		column.add_child(UIKit.label(
			"%s   %s" % [_type_name(monster, types), _attack_name(monster, attack_types)],
			12, UIKit.DIM))
	else:
		column.add_child(UIKit.label("???", 16, "#555555"))
		column.add_child(UIKit.label("???   ???", 12, "#444444"))
	return panel


## The boss is a bigger card: its own ring colour (`#5fa87a` in the arena) and one line
## per type, because a boss carries several.
func _boss_card(boss: Dictionary, theme: Dictionary, seen: Array, types: Dictionary,
		attack_types: Dictionary) -> Control:
	var face := str(boss.get("face", ""))
	var is_seen := seen.has(face)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0d0d0d")
	style.border_color = Color("#5fa87a") if is_seen else Color("#333333")
	style.set_border_width_all(0)
	style.border_width_left = 3
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	if not is_seen:
		panel.modulate = Color(0.75, 0.75, 0.75, 0.5)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var portrait := UIKit.CircularPortrait.new()
	portrait.custom_minimum_size = Vector2(80, 80)
	portrait.size = Vector2(80, 80)
	portrait.backdrop = Color("#0d0d0d")
	portrait.ring_colour = Color("#5fa87a")
	portrait.ring_width = 2.0
	portrait.texture = UIKit.load_texture(face) if is_seen else null
	row.add_child(portrait)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)

	var heading := UIKit.UILabel.new()
	heading.text = ("Boss: " + str(boss.get("name", "?"))) if is_seen else "Boss: ???"
	heading.add_theme_font_size_override("font_size", 17)
	heading.add_theme_color_override("font_color", Color("#f0f0f0"))
	column.add_child(heading)

	if is_seen:
		column.add_child(UIKit.label(_attack_name(boss, attack_types), 12, UIKit.DIM))
		var type_names := PackedStringArray()
		for t in (boss.get("types", []) as Array):
			type_names.append(_type_label(str(t)))
		if type_names.size() > 0:
			column.add_child(UIKit.label(", ".join(type_names), 12, UIKit.DIM))
	else:
		column.add_child(UIKit.label("???", 12, "#444444"))
	return panel


## A monster's own type. `MONSTER_TYPES` maps NAME -> value (`{"LIFESTEALER":
## "lifestealer"}`), so the value a monster carries is already the display word and only
## needs capitalising. No hardcoded list of traits is kept here — a monster's type comes
## from the tables, and the port's rule is that it never comes from the screen again.
func _type_name(monster: Dictionary, _types: Dictionary) -> String:
	return _type_label(str(monster.get("type", "")))


func _type_label(raw: String) -> String:
	if raw == "":
		return "?"
	return raw.substr(0, 1).to_upper() + raw.substr(1)


## `ATTACK_TYPES` maps `{"MELEE": "melee", "CASTER": "caster"}`. The Czech gloss is added
## because "Caster" alone does not tell a player the thing does not walk up to them.
func _attack_name(monster: Dictionary, _attack_types: Dictionary) -> String:
	var raw := str(monster.get("attackType", ""))
	match raw.to_lower():
		"caster":
			return "Caster (kouzli)"
		"melee":
			return "Melee (na blizko)"
		"":
			return "Melee (na blizko)"
		_:
			return raw


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
