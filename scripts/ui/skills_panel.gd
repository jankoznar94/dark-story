extends MinSizeBox
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

## `.talent-tier-row { grid-template-columns:repeat(3, 1fr); gap:10px }` measured on the
## live PWA at 340px of row width: three 106.7px columns. `.talent-btn-icon` is
## `width:100%; aspect-ratio:1`, so the ICON is 106.7 - 2 - 2 = 102.7 square — the border is
## INSIDE it (`box-sizing:border-box`) — and the cell column is icon + a 2px gap + the
## 14px `/5` line = 123. Measured on the port after the fix: `tier-cell 107x123`,
## `cell_btn 107x107`, `cell_lv 107x14`.
const TALENT_CELL := 106.7
## `.talent-btn-icon` is a SQUARE that is the column's full width, and in Godot a Button's
## stylebox border is drawn OUTSIDE `custom_minimum_size` — so `custom_minimum_size.y` has
## to subtract the two 2px borders or every icon ships 4px taller than it is wide, and each
## tier's row grows by 4px. Measured: cell 107 wide against 111 tall before this.
const ICON_BORDER := 2.0
## `.talent-btn { gap:2px }` between the icon and the `/N` line.
const CELL_GAP := 2
## `.talent-tree-content { gap:16px }` appears at style.css:1276 and a SECOND
## `.talent-tree-content { gap:0; align-items:flex-start; justify-content:center }` at
## style.css:1322 — the later rule WINS in CSS, so the tiers are ADJACENT with NO gap.
## Measured on the live pane: tier rows at y 205 (h 120) and y 325 (h 249), i.e.
## 205 + 120 = 325 exactly. Porting the first rule alone puts 16px between every tier,
## which is 16px per tier of drift — the same "two rules, read the later one" trap as the
## `#talentsScreen` flex override.
const TIER_GAP := 0
## `.talent-tree { margin-top:8px }`, on top of `.talent-tree-tabs { margin-bottom:8px }`.
## The two margins TOUCH and CSS COLLAPSES them, so the gap is 8, not 16 — the same trap
## the inventory pane had. The tabs strip carries `margin_bottom` and the tree `margin_top`.
const TREE_MT := 8
## `.tree-tab { padding:6px 12px; font-size:13px }` — the port drew 14px text in a 34px box.
const TREE_TAB_FS := 13
## `.tree-tab { border-radius:6px }`.
const TREE_TAB_RADIUS := 6
## `.talents-reset-wrap .btn { width:100% }`, `.btn` is 15px bold with `padding:12px`.
const RESET_FS := 15
## `.talent-btn-lv { font-size:10px }`.
const CELL_LV_FS := 10
## `.talent-schools { background:#111; border:1px solid #333; border-radius:10px;
##                    padding:12px }` is what `#talentsScreen .talent-schools` resolves to.
const SCHOOL_BG := "#111111"
const SCHOOL_PAD := 12
const SCHOOL_RADIUS := 10

var _data: Node
var _state
var _find_item: Callable
var _talents: Talents

var _points_label: Label
var _reset_button: Button
var _reset_rule: ColorRect
var _schools: VBoxContainer
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
	# `#talentsScreen { display:flex; flex-direction:column; height:100% }` with
	# `.talent-schools { flex:1 }` and `.talents-reset-wrap { margin-top:auto }` — so the
	# reset block is pinned to the BOTTOM of the pane and the tree area takes the slack.
	# ⚠️  separation 0, not 8. In the PWA the three blocks are ADJACENT: measured
	# `.flex-between` 133..168, `.talent-schools` 168..574, `.talents-reset-wrap`
	# 574..637 — every boundary is exact, so the gaps are all INSIDE the blocks and the
	# column contributes none. A `VBoxContainer` separation of 8 would add two more.
	column.add_theme_constant_override("separation", 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(column)

	# `.flex-between { padding:8px 0 }` with `<span id="talentsPts">` as its only child, and
	# it is a SIBLING of `.talent-schools` — measured on the live pane: the pane's content
	# box holds exactly three children, `[.flex-between, .talent-schools,
	# .talents-reset-wrap]`. Nesting the header inside the schools block is what made the
	# port's tab strip sit 6px low.
	#
	# ⚠️  The reset button does NOT belong here. In the PWA the header's only child is the
	# point line and the button lives in `.talents-reset-wrap` at the BOTTOM, full width,
	# under a `border-top:1px solid #2a2a2a`. The port had it in the header — measured: the
	# head box came back `min=202x34` where the PWA's is 340x35, and the button was 167 wide
	# against the PWA's 340.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# `.flex-between { padding:8px 0 }` — measured on the live PWA as a 35px box around a
	# 19px line. Without it the port's head was 17 tall and every block below sat 18px high.
	column.add_child(UIKit.margin_box(head, 8.0, 8.0))
	# `#talentsPts { color:#f1c40f; font-weight:bold }`, 14px — the PWA's own body size.
	_points_label = UIKit.label("", 14, UIKit.GOLD)
	_points_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_points_label)

	# `.talent-schools { display:flex; flex-direction:column; gap:8px; width:100% }` holding
	# the ONE active `.talent-school`, whose `flex:1` takes the pane's slack.
	var schools := VBoxContainer.new()
	schools.name = "Schools"
	schools.add_theme_constant_override("separation", 8)
	schools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	schools.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(schools)
	_schools = schools

	_tree_row = HBoxContainer.new()
	_tree_row.add_theme_constant_override("separation", 4)
	_tree_row.alignment = BoxContainer.ALIGNMENT_CENTER
	# `.talent-tree-tabs { display:flex; gap:4px; margin-bottom:8px; justify-content:center }`
	_tree_row.add_theme_constant_override("h_separation", 4)
	schools.add_child(_tree_row)

	# `.talent-tree { margin-top:8px }` and `.talent-tree-tabs { margin-bottom:8px }` — the
	# two margins TOUCH and CSS COLLAPSES them, so the tree starts 8px under the strip, not
	# 16. Carried on the GRID's own top margin (the box below the strip), the same way the
	# inventory pane's collapsed margins are carried.
	_talent_grid = VBoxContainer.new()
	_talent_grid.add_theme_constant_override("separation", TIER_GAP)
	_talent_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	schools.add_child(UIKit.margin_box(_talent_grid, TREE_MT, 0.0))

	_skill_info = VBoxContainer.new()
	_skill_info.add_theme_constant_override("separation", 4)
	column.add_child(_skill_info)

	# `.talents-reset-wrap { margin-top:auto; padding:8px 0 0; border-top:1px solid #2a2a2a }`
	# with `.btn { width:100% }` inside. `margin-top:auto` is what pushes it to the bottom of
	# the flex column — `SIZE_SHRINK_END` on a box placed after an EXPAND_FILL sibling.
	var reset_wrap := VBoxContainer.new()
	reset_wrap.name = "ResetWrap"
	reset_wrap.add_theme_constant_override("separation", 0)
	reset_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_wrap.size_flags_vertical = Control.SIZE_SHRINK_END
	column.add_child(reset_wrap)
	var rule := ColorRect.new()
	rule.name = "ResetRule"
	rule.color = Color(UIKit.RULE_DARK)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_wrap.add_child(rule)
	var reset_pad := MarginContainer.new()
	# `padding:8px 0 0` PLUS `.btn { margin:6px 0 }` — measured, the PWA's wrap is 63 tall
	# around a 42px button: 6 + 8 + 1 (the rule) + 42 + 6.
	reset_pad.add_theme_constant_override("margin_top", 8 + 6)
	reset_pad.add_theme_constant_override("margin_bottom", 6)
	reset_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_wrap.add_child(reset_pad)
	# `.btn.btn-secondary` — full width, 8px radius, 15px bold, 42px tall.
	_reset_button = UIKit.secondary_button(_reset_text(false), 42.0)
	_reset_button.pressed.connect(_on_reset)
	reset_pad.add_child(_reset_button)
	_reset_rule = rule


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
	# `resetBtn.textContent = hasSpent ? '…(50)' : 'Žádné body k resetu'` and
	# `resetBtn.disabled = !hasSpent`. The port only dimmed a FIXED label, so a player with
	# nothing spent read the price of a reset instead of the PWA's "nothing to reset".
	var has_spent := spent > 0
	_reset_button.text = _reset_text(has_spent)
	_reset_button.disabled = not has_spent
	_reset_button.modulate = Color(1, 1, 1, 1.0) if has_spent else Color(1, 1, 1, 0.4)
	# `.talents-reset-wrap { border-top:1px solid #2a2a2a }` — the rule is part of the
	# block, and it is the only thing separating the tree area from the reset action.
	if _reset_rule != null:
		_reset_rule.visible = true

	_clear(_tree_row)
	_clear(_talent_grid)
	_clear(_skill_info)

	var trees := _talents.tree_ids(hero_class)
	if trees.is_empty():
		# `$('talentSchools').innerHTML = '<div style="text-align:center;color:#888;
		# padding:20px">Nejdřív si vyber classu</div>'` — a CENTRED message with 20px of
		# padding, not a bare left-aligned line.
		_talent_grid.add_child(UIKit.gap(20.0))
		_talent_grid.add_child(UIKit.label("Nejdriv si vyber classu.", 14, UIKit.DIM,
			HORIZONTAL_ALIGNMENT_CENTER))
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


## A tier: `.talent-tier-row { display:grid; gap:10px; width:100%;
## grid-template-columns:repeat(3, 1fr) }` — THREE EQUAL columns of `.talent-btn`.
##
## ⚠️  **There is NO tier label.** The port drew "Tier 1", "Tier 2 - odemkne se na levelu 6"
## above every row, and the PWA has none of it: `.talent-tier-label { display:none }` and
## `.talent-tier { display:none }` in its CSS, and `renderTalents()` builds only
## `<div class="talent-tier-row">` per tier — measured on the live pane,
## `.talent-tree-content`'s children are the tier ROWS and nothing else. Three invented
## labels pushed the whole tree down by 3 x (label + gap) and read as a different screen.
##
## The lock state is not lost: `.talent-btn.btn-locked { opacity:0.35;
## filter:grayscale(0.6) }` already dims every cell of a locked tier, and the PWA's
## `.talent-tier.tier-locked { opacity:0.4 }` does the same to the row.
func _tier_row(tier_idx: int, tier: Dictionary) -> Control:
	var hero_level := int(_state.hero().get("level", 1))
	var unlocked := Talents.tier_unlocked(tier_idx, hero_level)
	# `.talent-tier-row` is the whole block — no wrapper, no label.
	var row := GridContainer.new()
	row.columns = 3
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# `.talent-tier.tier-locked { opacity:0.4; filter:grayscale(0.5) }` — the ROW carries the
	# dim, and each `.talent-btn.btn-locked` carries its own `opacity:0.35` on top.
	if not unlocked:
		row.modulate = Color(1, 1, 1, 0.4)
	for choice in tier.get("choices", []):
		var key := "%s_%s" % [str(_state.data.get("heroClass", "")), str(choice.get("k", ""))]
		var cell_column := _skill_cell(key, choice, unlocked)
		cell_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cell_column)
	return row


## `.tree-tab { padding:6px 12px; border:1px solid #333; border-radius:6px; background:#111;
## color:#aaa; font-size:13px }` and `.tree-tab.active { border-color:#f1c40f;
## color:#f1c40f; background:#1a1a1a }`.
##
## The PWA sizes the tab by its CONTENT and centres the trio (`.talent-tree-tabs
## { justify-content:center }`), so the tabs are 93/83/92 wide, NOT three equal thirds —
## measured on the live pane. The port's `SIZE_EXPAND_FILL` made all three 111 and the
## strip `min=177` against the PWA's 268 (which is why the tree started too high).
##
## A Godot Button takes its width from its TEXT when nothing expands it, which is the
## `fit-content` the PWA has — but the 6px/12px padding has to be added on top, because
## a Button's minimum ignores its own stylebox content margins.
func _tree_tab(tree_id: String, label_text: String) -> Button:
	var button := UIKit.flat_button(label_text, 0.0, 29.0, TREE_TAB_FS)
	var font := button.get_theme_font("font")
	var text_w := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		TREE_TAB_FS).x if font != null else 0.0
	# `padding:6px 12px` + the 1px border on each side (a Button's border is drawn OUTSIDE
	# its minimum, and the CSS is `box-sizing:border-box` — so the border is already inside
	# the 12 in `padding:6px 12px` and only the padding is added here).
	button.custom_minimum_size = Vector2(roundf(text_w) + 24.0 + 2.0, 29.0)
	var active := tree_id == _tree_id
	var style := UIKit.panel_style(UIKit.GOLD if active else UIKit.ROW_BORDER,
		1)
	style.bg_color = Color(UIKit.ROW_BG if active else "#111111")
	style.set_corner_radius_all(TREE_TAB_RADIUS)
	_apply_all_states(button, style)
	button.add_theme_color_override("font_color",
		Color(UIKit.GOLD if active else "#aaaaaa"))
	button.pressed.connect(func(): _open_tree(tree_id))
	return button


func _skill_cell(key: String, choice: Dictionary, tier_open: bool) -> Control:
	var column := VBoxContainer.new()
	# `.talent-btn { gap:2px }` between the icon and the `/N` line.
	column.add_theme_constant_override("separation", CELL_GAP)

	var level := _talents.talent_level(_state, key)
	var maxed := level >= int(choice.get("maxLv", 1))
	var max_level := int(choice.get("maxLv", 1))
	var available := tier_open and _talents.prerequisites_met(_state, key)
	if not available:
		# `.talent-btn.btn-locked { opacity:0.35; filter:grayscale(0.6) }`. The port only
		# dimmed the ICON, which left the `/N` line at full brightness under a faded square.
		column.modulate = Color(1, 1, 1, 0.35)

	var cell := Button.new()
	# `.talent-btn-icon { width:100%; aspect-ratio:1; border:2px solid #2a2a2a;
	#                     border-radius:8px; padding:2px; background:#000 }` — the icon is
	# the whole 1fr column wide and SQUARE, and the `/N` line sits directly under it.
	#
	# ⚠️  The two 2px borders come OUT of the width, because a Godot Button draws its
	# stylebox border OUTSIDE `custom_minimum_size` while the CSS `box-sizing:border-box`
	# counts it INSIDE. Measured before this: cell 107 wide against 111 tall — a tall
	# rectangle where the PWA has a square, and every tier's row 4px over.
	cell.custom_minimum_size = Vector2(TALENT_CELL - 2.0 * ICON_BORDER,
		TALENT_CELL - 2.0 * ICON_BORDER)
	cell.focus_mode = Control.FOCUS_NONE
	var border := Color("#2a2a2a") if available else Color("#2a2a2a")
	if level > 0 and not maxed:
		border = Color(UIKit.GOLD)
	if maxed:
		border = Color("#2ecc71")
	if _selected_key == key:
		border = Color(UIKit.GOLD)
	# `.talent-btn.maxed .talent-btn-icon { border-color:#2ecc71 }` and
	# `.talent-btn.selected .talent-btn-icon { border-color:#f1c40f }` — selected wins.
	var style := UIKit.panel_style()
	style.bg_color = Color("#000000")
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
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
	# `.talent-btn-lv { font-size:10px; font-weight:bold; color:#f1c40f }` — the port drew
	# 11px and used the dim grey for an unowned skill; the PWA is gold either way.
	var lv_label := UIKit.label("%d/%d" % [level, max_level], CELL_LV_FS, UIKit.GOLD,
		HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(lv_label)
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
	# `<div class="skill-info-panel hidden" id="skillInfoPanel">` — the panel is in the
	# document from the start and `renderTalents()` ends with
	# `$('skillInfoPanel').classList.add('hidden')` when nothing is selected. The port left
	# it VISIBLE at zero height, which is a block of the pane that reports itself as shown.
	_skill_info.visible = false
	if _selected_key == "":
		return
	var s := _talents.skill(_selected_key)
	if s.is_empty():
		return
	_skill_info.visible = true
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


## `.talent-btn`-style helper: the PWA's `resetTalents()` sets the button's TEXT from
## `hasSpent` — `'🔄 Resetovat talenty (50💰)'` vs `'✅ Žádné body k resetu'`. The emoji are
## the PWA's; Jan's rule is no emoji in the GAME, and the port's UI is Czech without them,
## so the wording is kept and the glyphs are not.
func _reset_text(has_spent: bool) -> String:
	return "Resetovat talenty (50 zlata)" if has_spent else "Zadne body k resetu"


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
