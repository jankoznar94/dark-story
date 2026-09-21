extends Control
class_name SkillsPanel
## SkillsPanel — the "Dovednosti" tab of CharacterModal.
##
## Ported from the PWA's `renderTalents()` and the `#talentsScreen` markup. Top to
## bottom, exactly as the PWA builds it:
##   1. the point line — the PWA's `<span id="talentsPts" style="color:#f1c40f">Body: N`
##   2. `.talent-school`   — the tree tabs, then the tiers of the chosen tree
##   3. `.skill-info-panel`— name, effect and the invest action for the selected skill
##   4. `.talents-reset-wrap` — the reset button, disabled when nothing is spent
##
## The tiers are gated on the hero's level exactly as the PWA gates them:
## `const tierUnlocked = [true, heroLv >= 6, heroLv >= 12]`. A locked tier still shows
## its skills — the player must see what they are working toward — but every cell is
## dimmed and investing is refused.
##
## This panel was split out of `hero_screen.gd`, which had fused the character sheet and
## the skill trees into one scroll. The PWA has them as two tabs of ONE modal; keeping
## them fused in a screen of their own is what made the port's Stats tab read as "a
## different game" — it showed the trees under the stat sheet.

const UIKit := preload("res://scripts/ui/ui_kit.gd")
const Talents := preload("res://scripts/items/talents.gd")

signal message(text: String)

const CELL := 64.0

## `const tierUnlocked = [true, heroLv >= 6, heroLv >= 12]`
const TIER_LEVELS := [1, 6, 12]

var _data: Node
var _state
var _find_item: Callable
var _talents: Talents

var _points_label: Label
var _reset_button: Button
var _tree_row: HBoxContainer
var _talent_grid: VBoxContainer
var _skill_info: VBoxContainer

var _tree_id := ""
var _selected_key := ""


func _init(game_data: Node, state, find_item: Callable) -> void:
	_data = game_data
	_state = state
	_find_item = find_item
	_talents = Talents.new(game_data)


func _ready() -> void:
	_build()


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(column)

	# `.flex-between { padding:8px 0 }` with `<span id="talentsPts" style="color:#f1c40f">`
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	column.add_child(head)
	_points_label = UIKit.label("", 14, UIKit.GOLD)
	_points_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_points_label)
	# `.talents-reset-wrap .btn.btn-secondary` — `.btn-secondary { background:#3a3a5a }`
	_reset_button = UIKit.secondary_button("Resetovat talenty (50 zlata)", 34.0)
	_reset_button.add_theme_font_size_override("font_size", 11)
	_reset_button.pressed.connect(_on_reset)
	head.add_child(_reset_button)

	_tree_row = HBoxContainer.new()
	_tree_row.add_theme_constant_override("separation", 4)
	column.add_child(_tree_row)

	_talent_grid = VBoxContainer.new()
	_talent_grid.add_theme_constant_override("separation", 8)
	_talent_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_talent_grid)

	_skill_info = VBoxContainer.new()
	_skill_info.add_theme_constant_override("separation", 4)
	column.add_child(_skill_info)


# --- refresh -----------------------------------------------------------------

func refresh() -> void:
	_refresh_talents()


func _refresh_talents() -> void:
	var hero_class := str(_state.data.get("heroClass", ""))
	var points := int(_state.data.get("talentPoints", 0))
	_points_label.text = "Body: %d" % points

	# `const hasSpent = Object.values(state.talentLevels).reduce((a,b)=>a+b,0) > 0`
	var spent := 0
	for key in (_state.data.get("talentLevels", {}) as Dictionary):
		spent += int(_state.data["talentLevels"][key])
	_reset_button.disabled = spent <= 0
	_reset_button.modulate = Color(1, 1, 1, 1.0) if spent > 0 else Color(1, 1, 1, 0.4)

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
		_tree_row.add_child(_tree_tab(str(tree_key), str(tree_data.get("name", tree_key))))

	var tiers: Array = tree.get("tiers", [])
	for tier_idx in tiers.size():
		_talent_grid.add_child(_tier_row(tier_idx, tiers[tier_idx]))

	_refresh_skill_info()


## A tier: the label saying whether it is open, then the skill cells.
func _tier_row(tier_idx: int, tier: Dictionary) -> Control:
	var hero_level := int(_state.hero().get("level", 1))
	var unlocked := Talents.tier_unlocked(tier_idx, hero_level)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var tier_name := "Tier %d" % (tier_idx + 1)
	if not unlocked:
		var need: int = int(TIER_LEVELS[tier_idx]) if tier_idx < TIER_LEVELS.size() else 1
		tier_name += " - odemkne se na levelu %d" % need
	box.add_child(UIKit.label(tier_name, 12, UIKit.TEXT if unlocked else UIKit.DIM))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for choice in tier.get("choices", []):
		var key := "%s_%s" % [str(_state.data.get("heroClass", "")), str(choice.get("k", ""))]
		row.add_child(_skill_cell(key, choice, unlocked))
	return box


func _tree_tab(tree_id: String, label_text: String) -> Button:
	var button := UIKit.flat_button(label_text, 0.0, 34.0, 14)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var active := tree_id == _tree_id
	var style := UIKit.panel_style(UIKit.GOLD if active else UIKit.BORDER, 2 if active else 1)
	_apply_all_states(button, style)
	button.pressed.connect(func(): _open_tree(tree_id))
	return button


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
	_apply_all_states(cell, style)

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
		var fallback := UIKit.label(str(choice.get("name", "?")), 10, UIKit.DIM,
			HORIZONTAL_ALIGNMENT_CENTER)
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


func _open_tree(tree_id: String) -> void:
	_tree_id = tree_id
	_selected_key = ""
	_refresh_talents()


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
	_skill_info.add_child(UIKit.label("%s   %d/%d" % [str(s.get("name", "?")), level,
		int(s.get("maxLv", 1))], 16))
	_skill_info.add_child(UIKit.label(_talents.effect_summary(_selected_key), 13,
		UIKit.MOD_BLUE))
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


## Jan's rule: NO hover or focus styling, state only on click. One style object for every
## state is how that is enforced — there is no second style to drift into a hover look.
func _apply_all_states(button: Button, style: StyleBoxFlat) -> void:
	for state_name in ["normal", "pressed", "hover", "focus", "disabled"]:
		button.add_theme_stylebox_override(state_name, style)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
