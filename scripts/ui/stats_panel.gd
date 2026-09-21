extends Control
class_name StatsPanel
## StatsPanel — the "Staty" tab of CharacterModal.
##
## Ported from the PWA's `renderHero()` and the `#heroScreen` markup in `index.html`.
## Four blocks, in the PWA's own order:
##   1. `.hero-header`   — a 100px round portrait, name, level, class and the record
##   2. `.hero-xp-wrap`  — XP label and value over a 6px bar, under a 1px top border
##   3. Attributes       — one `.hero-attr-row` per attribute, with its raise button
##   4. Character Details— a 2-column `.hero-detail-grid` of twelve stats
##
## Inside the modal the PWA overrides every `.card` to
## `background:transparent; border:none; padding:0; margin:0` (`.modal-content .card`),
## so the headings are the only thing separating the blocks. `.hero-detail-item` is NOT
## a `.card` and keeps its own `#1a1a1a` plate — that asymmetry is the PWA's, not a slip,
## and it is why the detail grid is the only part that looks boxed.
##
## The PWA's 💪/❤️/🎯/🧠 labels and its 🔄/✏️/⬆️ buttons are emoji; Jan's standing rule is
## no emoji in the game, so the attributes carry their names and the raise button reads
## "+1". Layout is unaffected — `.hero-attr-label` and `.hero-detail-label` are `flex:1`,
## so a shorter leading element only gives the label more room.
##
## Deviation, deliberate: the PWA's portrait frame has
## `box-shadow: 0 0 16px rgba(74,125,255,0.4)`. Jan's rule is flat toning and no glow,
## so the 2px #4a7dff ring is drawn and the glow is not.

const UIKit := preload("res://scripts/ui/ui_kit.gd")
const Talents := preload("res://scripts/items/talents.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const Progression := preload("res://scripts/combat/progression.gd")

signal message(text: String)

## `.hero-portrait-lg-frame { width:100px; height:100px; border:2px solid #4a7dff }`.
## Measured off the reference frame the ring spans 104px, so the CSS box is content-box:
## 100px of art plus 2px of border on each side. 104 total is what the PWA actually draws.
const PORTRAIT := 104.0
const XP_HEIGHT := 6.0

## `.hero-attr-row`, in the PWA's order. [key, Czech label, state field]
const ATTRS := [
	["str", "Síla", "attrStr"],
	["vit", "Vitalita", "attrVit"],
	["dex", "Obratnost", "attrDex"],
	["int", "Intelekt", "attrInt"],
]

## `.hero-detail-grid`, in the PWA's exact markup order.
## `.hero-detail-label { color:#888; flex:1 }` inside a two-column grid on a 390px
## canvas gives each label about 70px, so these are the SHORT forms and they carry real
## diacritics — "Poskozeni" was clipped to "Poskozen" and unaccented Czech is not Czech.
const DETAIL_LABELS := [
	"Poškození", "Obrana", "Krit", "Blok", "Úhyb", "Zásah",
	"Životy", "Mana", "Oheň", "Chlad", "Blesk", "Jed",
]

var _data: Node
var _gen: ItemGen
var _state
var _find_item: Callable
var _talents: Talents
var _prog: Progression

var _portrait
var _name_label: Label
var _level_label: Label
var _class_label: Label
var _record_label: Label
var _xp_label: Label
var _xp_track: Control
var _xp_fill: ColorRect
var _attr_points: Label
var _attr_values: Dictionary = {}
var _attr_buttons: Dictionary = {}
var _detail_values: Array = []


func _init(game_data: Node, gen: ItemGen, state, find_item: Callable) -> void:
	_data = game_data
	_gen = gen
	_state = state
	_find_item = find_item
	_talents = Talents.new(game_data)
	_prog = Progression.new(game_data)


func _ready() -> void:
	_build()


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(column)

	column.add_child(_build_header())
	column.add_child(_build_xp())
	column.add_child(_build_attributes())
	column.add_child(_build_details())


## `.hero-header { display:flex; gap:14px; align-items:center }`
func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN

	# `.hero-portrait-lg-frame { width:100px; height:100px; border-radius:50%;
	#   border:2px solid #4a7dff; overflow:hidden; background:#000 }`.
	# The image is cropped to the circle with the shared scanline cropper — the same
	# component the arena uses, because `draw_texture_rect` has no clip and a square
	# `clip_contents` would show four corners of art outside the ring.
	_portrait = UIKit.CircularPortrait.new()
	_portrait.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	_portrait.ring_colour = Color(UIKit.MOD_BLUE)
	_portrait.ring_width = 2.0
	_portrait.backdrop = Color("#000000")
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_portrait)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	# `.hero-name-row { display:flex; align-items:center; gap:6px; flex-wrap:wrap }`
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	info.add_child(name_row)

	# `.hero-name { font-size:17px; font-weight:bold; color:#ddd }`
	_name_label = UIKit.label("", 17, "#dddddd")
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(_name_label)

	# `.hero-level { font-size:13px; color:#f1c40f; font-weight:bold; margin-left:auto }`
	_level_label = UIKit.label("", 13, UIKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(_level_label)

	# `.hero-subtitle { font-size:12px; color:#888; margin:2px 0 8px }`
	_class_label = UIKit.label("", 12, UIKit.DIM)
	info.add_child(_class_label)
	_record_label = UIKit.label("", 12, UIKit.DIM)
	info.add_child(_record_label)

	return row


## `.hero-xp-wrap { margin:8px 0 0; padding:6px 0; border-top:1px solid #1a1a1a }`
func _build_xp() -> Control:
	var wrap := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0)
	st.border_color = Color("#1a1a1a")
	st.set_border_width_all(0)
	st.border_width_top = 1
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	wrap.add_theme_stylebox_override("panel", st)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	wrap.add_child(box)

	# `.flex-between` — the label left, the value right.
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	box.add_child(line)

	# `.hero-xp-label { font-size:11px; color:#8888aa }`
	var label := UIKit.label("XP", 11, "#8888aa")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	# `.hero-xp-value { font-size:11px; color:#f1c40f }`
	_xp_label = UIKit.label("", 11, UIKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	line.add_child(_xp_label)

	# `.mb-xp-bar-bg { background:#1a1a1a; border-radius:4px }`, inline height:6px,
	# and `.mb-xp-bar-fill { background:#f1c40f }`.
	# A plain Control, NOT a PanelContainer: a PanelContainer forces every child to fill it
	# (that is what its layout does), so the fill rect would always be 100% wide no matter
	# what fraction the XP says — a full yellow bar at 0/1600.
	_xp_track = Control.new()
	_xp_track.custom_minimum_size = Vector2(0, XP_HEIGHT)
	_xp_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_xp_track)

	var track_bg := ColorRect.new()
	track_bg.color = Color("#1a1a1a")
	track_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	track_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_track.add_child(track_bg)

	# `.mb-xp-bar-fill { height:100%; background:#f1c40f }` with an inline `width:N%`.
	# Set as an anchor, not pixels: the track's final width is unknown until the modal
	# lays out, so `size.x * ratio` at refresh time reads a stale (often zero) width.
	_xp_fill = ColorRect.new()
	_xp_fill.color = Color(UIKit.GOLD)
	_xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_fill.anchor_top = 0.0
	_xp_fill.anchor_bottom = 1.0
	_xp_fill.anchor_left = 0.0
	_xp_fill.anchor_right = 0.0
	_xp_fill.offset_right = 0.0
	_xp_track.add_child(_xp_fill)

	return wrap


## `.hero-attr-row { display:flex; align-items:center; gap:8px; padding:6px 0;
##                   border-bottom:1px solid #1a1a1a; font-size:14px }` — `:last-child`
## drops the border.
func _build_attributes() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)

	# `.card-title` — inside the modal `{ font-size:18px }`.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	box.add_child(head)
	var title := UIKit.label("Atributy", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	# `.hero-attr-pts { font-size:12px; color:#f1c40f }`
	_attr_points = UIKit.label("", 12, UIKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_attr_points.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_attr_points)

	for index in ATTRS.size():
		var entry: Array = ATTRS[index]
		var attr := str(entry[0])

		var row := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0, 0, 0, 0)
		st.set_border_width_all(0)
		if index < ATTRS.size() - 1:
			st.border_color = Color("#1a1a1a")
			st.border_width_bottom = 1
		st.content_margin_top = 6
		st.content_margin_bottom = 6
		row.add_theme_stylebox_override("panel", st)
		box.add_child(row)

		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		row.add_child(line)

		var name_label := UIKit.label(str(entry[1]), 14)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(name_label)

		# `.hero-attr-val { font-weight:bold; color:#f1c40f; min-width:24px;
		#                   text-align:center }`
		var value := UIKit.label("0", 14, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
		value.custom_minimum_size = Vector2(44, 0)
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(value)
		_attr_values[attr] = value

		# `.btn.btn-primary.hero-attr-btn`: `.btn-primary { background:#4a7dff; color:#fff }`
		# and `.hero-attr-btn { width:auto; padding:4px 10px; font-size:11px }`.
		var button := Button.new()
		button.text = "+1"
		button.custom_minimum_size = Vector2(46, 28)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 11)
		button.add_theme_color_override("font_color", Color("#ffffff"))
		button.add_theme_color_override("font_color_pressed", Color("#ffffff"))
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(UIKit.MOD_BLUE)
		bs.set_corner_radius_all(8)
		bs.content_margin_left = 10
		bs.content_margin_right = 10
		bs.content_margin_top = 4
		bs.content_margin_bottom = 4
		for state_name in ["normal", "hover", "focus", "disabled"]:
			button.add_theme_stylebox_override(state_name, bs)
		button.add_theme_stylebox_override("pressed", bs)
		button.pressed.connect(func(): _on_attr(attr))
		line.add_child(button)
		_attr_buttons[attr] = button

	return box


## `.hero-detail-grid { display:grid; grid-template-columns:1fr 1fr; gap:6px }` and
## `.hero-detail-item { display:flex; align-items:center; gap:6px; background:#1a1a1a;
##                     padding:6px 10px; border-radius:6px; font-size:13px }`.
func _build_details() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(UIKit.label("Vlastnosti postavy", 18))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)

	for detail_name in DETAIL_LABELS:
		var item := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color("#1a1a1a")
		st.set_corner_radius_all(6)
		st.content_margin_left = 10
		st.content_margin_right = 10
		st.content_margin_top = 6
		st.content_margin_bottom = 6
		item.add_theme_stylebox_override("panel", st)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(item)

		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		item.add_child(line)

		# `.hero-detail-label { color:#888; flex:1 }`
		var name_label := UIKit.label(str(detail_name), 13, UIKit.DIM)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		line.add_child(name_label)

		# `.hero-detail-val { font-weight:bold; color:#e8e0e8; text-align:right }`
		var value := UIKit.label("", 13, "#e8e0e8", HORIZONTAL_ALIGNMENT_RIGHT)
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(value)
		_detail_values.append(value)

	return box


# --- refresh -----------------------------------------------------------------

func refresh() -> void:
	var hero: Dictionary = _state.hero()
	var hero_class := str(_state.data.get("heroClass", ""))
	var cls: Dictionary = _data.class_by_id(hero_class)
	var equip: Dictionary = _state.equip()

	_name_label.text = str(hero.get("name", "Dobrodruh"))
	_level_label.text = "Lv.%d" % int(hero.get("level", 1))
	_class_label.text = str(cls.get("name", "Dobrodruh"))
	_record_label.text = "Smrti %d   Vítězství %d" % [
		int(_state.data.get("deaths", 0)), int(_state.data.get("wins", 0))]

	var face := str(hero.get("face", "hero"))
	_portrait.texture = UIKit.load_texture("assets/monsters/%s.png" % face)

	# `const xpNeeded = h.level * 80` in the PWA; the port reads the same value from the
	# progression table so one curve serves the arena, the level-up and this bar.
	var level := int(hero.get("level", 1))
	var need := _prog.xp_needed(level)
	var xp := int(hero.get("xp", 0))
	var ratio := clampf(float(xp) / float(maxi(need, 1)), 0.0, 1.0)
	_xp_label.text = "%d/%d" % [xp, need]
	_xp_fill.anchor_right = ratio
	_xp_fill.offset_right = 0.0

	_refresh_attributes(hero, equip)
	_refresh_details(hero, equip)


func _refresh_attributes(hero: Dictionary, equip: Dictionary) -> void:
	var equips := _gen.equip_attr_sum(equip, _find_item, ["str", "vit", "dex", "int"])
	var points := int(hero.get("attrPoints", 0))
	_attr_points.text = "(body: %d)" % points
	for entry in ATTRS:
		var attr := str(entry[0])
		var base := int(hero.get(str(entry[2]), 0))
		var bonus := int(equips[attr])
		var text := str(base)
		if bonus > 0:
			text += " (+%d)" % bonus
		var value: Label = _attr_values[attr]
		value.text = text
		# The PWA set `opacity = 0.3` on a locked button. The button stays tappable so it
		# can explain itself rather than silently doing nothing.
		var button: Button = _attr_buttons[attr]
		button.modulate = Color(1, 1, 1, 1.0) if points > 0 else Color(1, 1, 1, 0.35)


func _refresh_details(hero: Dictionary, equip: Dictionary) -> void:
	var weapon: Dictionary = _find_item.call(equip.get("weapon"))
	if weapon.is_empty():
		weapon = _data.item("fists")
	var spec := _talents.weapon_spec(_state, weapon)
	var dmg: Dictionary = Progression.hero_dmg(hero, equip, _find_item,
		_talents.shield_spec_dmg_mult(_state))
	var total_def := _talents.total_defense(_state, _find_item)
	var attrs := _gen.equip_attr_sum(equip, _find_item, ["dex"])
	var dex := int(hero.get("attrDex", 0)) + int(attrs["dex"])
	var crit := int(weapon.get("critChance", 0)) + int(spec["critBonus"])
	var block := _talents.player_block_chance(_state, _find_item, _gen)
	var max_hp := _gen.hero_max_hp(hero, equip, _find_item)
	var max_mana := _gen.hero_max_mana(hero, equip, str(_state.data.get("heroClass", "")),
		_find_item)

	var crit_text := "0%"
	if crit > 0:
		crit_text = "%d%% (x2.0)" % crit

	var values := [
		"%d-%d" % [int(dmg["min"]), int(dmg["max"])],
		"%d (%d%%)" % [total_def, Talents.defense_percent(total_def)],
		crit_text,
		"%d%%" % block,
		"%d%%" % Talents.dodge_percent(dex),
		"%d%%" % Talents.hit_percent(dex),
		"%d/%d" % [maxi(0, int(hero.get("hp", 0))), max_hp],
		"%d/%d" % [maxi(0, int(hero.get("mana", 0))), max_mana],
		"%d%%" % Talents.player_resist(_state, "fire", _find_item),
		"%d%%" % Talents.player_resist(_state, "ice", _find_item),
		"%d%%" % Talents.player_resist(_state, "lightning", _find_item),
		"%d%%" % Talents.player_resist(_state, "nature", _find_item),
	]
	for index in values.size():
		if index >= _detail_values.size():
			break
		var value: Label = _detail_values[index]
		value.text = str(values[index])


func _on_attr(attr: String) -> void:
	var result := _talents.spend_attr(_state, attr, _find_item, _gen)
	message.emit(str(result["message"]))
	refresh()
