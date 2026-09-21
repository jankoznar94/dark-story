extends Control
class_name SpellbookScreen
## SpellbookScreen — every spell the hero's class has, with its cost, cooldown and GCD,
## and whether it has been learned.
##
## Ported from `renderSpellbook`. The PWA showed the whole class list; here the entries
## the hero has NOT bought are drawn dim with the reason, because "the spell exists and
## you have not paid for it" is exactly what a spellbook is for. The gate is the invested
## talent point — an unbought talent is not a weak spell, it is no spell — and that rule
## lives in `scripts/items/talents.gd`, not here.
##
## The icon is `assets/spells/<id>.png`, the PWA's own path. An entry with no generated
## icon shows its name rather than a glyph: no emoji anywhere, per Jan's rule.

const UIKit := preload("res://scripts/ui/ui_kit.gd")
const Talents := preload("res://scripts/items/talents.gd")

signal back_pressed()

var _data: Node
var _state
var _talents: Talents

var _list: VBoxContainer
var _subtitle: Label


func _init(game_data: Node, state) -> void:
	_data = game_data
	_state = state
	_talents = Talents.new(game_data)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var page := UIKit.screen_page(self)
	var column: VBoxContainer = page["column"]
	column.add_theme_constant_override("separation", 8)

	var header := UIKit.back_header("Kouzla")
	header["back"].pressed.connect(func(): back_pressed.emit())
	column.add_child(header["root"])

	_subtitle = UIKit.label("", 13, UIKit.DIM)
	column.add_child(_subtitle)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_list)


func refresh() -> void:
	_clear(_list)
	var hero_class := str(_state.data.get("heroClass", ""))
	var cls: Dictionary = _data.class_by_id(hero_class)
	if cls.is_empty():
		_subtitle.text = "Nejdriv si vyber povolani."
		return
	_subtitle.text = "Kouzla povolani: %s" % str(cls.get("name", hero_class))

	var spells: Array = cls.get("spells", [])
	if spells.is_empty():
		_list.add_child(UIKit.label("Tato classa nema zadna kouzla.", 14, UIKit.DIM))
		return
	for spell in spells:
		_list.add_child(_card(spell, hero_class))


func _card(spell: Dictionary, hero_class: String) -> Control:
	var spell_id := str(spell.get("id", ""))
	# The talent key is `<class>_<spell id>`, the same one the bar and the tree use.
	var key := "%s_%s" % [hero_class, spell_id]
	var level: int = _talents.talent_level(_state, key)
	var learned := level > 0

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0d0d0d")
	style.border_color = Color("#2a2a2a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	if not learned:
		panel.modulate = Color(0.8, 0.8, 0.8, 0.55)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(52, 52)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = UIKit.load_texture("assets/spells/%s.png" % spell_id)
	row.add_child(icon)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	column.add_child(name_row)
	var name_label := UIKit.label(str(spell.get("name", spell_id)), 16, "#f0f0f0")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	# "learned" is the only state with a colour; everything else is dim, which is how the
	# PWA showed a locked entry without hiding it.
	name_row.add_child(UIKit.label(
		"Nauceno %d/%d" % [level, int(spell.get("maxLv", 1))] if learned else "Nenauceno",
		12, UIKit.GOLD if learned else UIKit.DIM))

	column.add_child(UIKit.label(str(spell.get("desc", "")), 12, "#aaaaaa"))

	# The cost line, in the PWA's order: resource, cooldown, GCD, and whether it needs
	# combo points.
	var parts := PackedStringArray()
	parts.append("Mana: %d" % int(spell.get("cost", 0)))
	parts.append("CD: %s" % ("%ss" % str(spell.get("cooldown", 0)) if float(spell.get("cooldown", 0)) > 0.0 else "-"))
	parts.append("GCD: %s" % ("%ss" % str(spell.get("gcd", 0)) if float(spell.get("gcd", 0)) > 0.0 else "-"))
	if bool(spell.get("needsCombo", false)):
		parts.append("Combo")
	column.add_child(UIKit.label("   ".join(parts), 12, UIKit.DIM))

	if not learned:
		var reason := _talents.blocked_reason(_state, key)
		if reason != "":
			column.add_child(UIKit.label(reason, 12, UIKit.BAD))
	return panel


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
