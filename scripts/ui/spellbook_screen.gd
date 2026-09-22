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

	var header := UIKit.card_header("Kouzla", "")
	_subtitle = header["subtitle"]
	column.add_child(header["root"])

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

	# `.spellbook-card { background:#1a1a1a; border:1px solid #2a2a2a; border-radius:10px;
	#                    padding:10px; margin-bottom:8px }` — the PWA's card, NOT a
	# near-black #0d0d0d panel with a 8px icon and a 16px name.
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1a1a1a")
	style.border_color = Color("#2a2a2a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
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

	# `.spellbook-icon { width:64px; height:64px; border-radius:8px; border:2px solid #2a2a2a }`
	var icon_box := PanelContainer.new()
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color("#000000")
	icon_style.border_color = Color("#2a2a2a")
	icon_style.set_border_width_all(2)
	icon_style.set_corner_radius_all(8)
	icon_box.add_theme_stylebox_override("panel", icon_style)
	icon_box.custom_minimum_size = Vector2(64, 64)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon_box)

	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	icon.texture = UIKit.load_texture("assets/spells/%s.png" % spell_id)
	icon_box.add_child(icon)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.custom_minimum_size = Vector2(0, 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)

	# `.spellbook-name { font-size:15px; color:#e8e0e8; font-weight:bold }` — the name
	# alone. The port used to add a "Nauceno x/y" badge the PWA never had; whether the
	# spell is LEARNED is shown by the card's own dimming, exactly as in the PWA.
	var name_label := UIKit.label(str(spell.get("name", spell_id)), 15, "#e8e0e8")
	name_label.custom_minimum_size = Vector2(0, 0)
	column.add_child(name_label)

	var desc_label := UIKit.label(str(spell.get("desc", "")), 12, "#aaaaaa")
	desc_label.custom_minimum_size = Vector2(0, 0)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(desc_label)

	# `.spellbook-stats { font-size:11px; color:#888; gap:8px }` — resource, cooldown,
	# GCD, in the PWA's order.
	var parts := PackedStringArray()
	parts.append("Mana: %d" % int(spell.get("cost", 0)))
	parts.append("CD: %s" % ("%ss" % str(spell.get("cooldown", 0)) if float(spell.get("cooldown", 0)) > 0.0 else "-"))
	parts.append("GCD: %s" % ("%ss" % str(spell.get("gcd", 0)) if float(spell.get("gcd", 0)) > 0.0 else "-"))
	if bool(spell.get("needsCombo", false)):
		parts.append("Combo")
	var stats := UIKit.label("   ".join(parts), 11, "#888888")
	stats.custom_minimum_size = Vector2(0, 0)
	column.add_child(stats)

	if not learned:
		var reason := _talents.blocked_reason(_state, key)
		if reason != "":
			var reason_label := UIKit.label(reason, 12, UIKit.BAD)
			reason_label.custom_minimum_size = Vector2(0, 0)
			reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			column.add_child(reason_label)
	return panel


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
