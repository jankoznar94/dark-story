extends Control
class_name ArenaScreen
## ArenaScreen — the fight screen: enemy portrait, HP bars, and the damage log.
##
## Built in code, like the other screens, because everything on it is driven by the
## battle: the portrait is whichever monster the fight picked, the bars are its
## numbers, the log is its `log` array. A hand-authored .tscn would only be a second
## place for those numbers to live.
##
## Layout is portrait-first and flat: two large portraits, the enemy's HP above, the
## hero's below, and the log as plain text lines. No cards, no panels, no rounded
## corners, no hover or focus states, no emoji — the same rules as the rest of the port.
##
## This screen does NOT run the fight. `scripts/combat/battle.gd` does that and this
## renders whatever it says. The screen stays dumb on purpose.

const ItemGen := preload("res://scripts/items/item_gen.gd")
const Battle := preload("res://scripts/combat/battle.gd")

signal fight_over(won: bool)
signal leave_requested()
signal another_fight_requested()

## One rendered frame is one fight tick. Advancing by a fixed step rather than by the
## frame's real delta keeps the pace identical on every machine, and it is what lets
## a test drive the same fight by calling step() in a loop.
const TICK_MS := 100

## How many log lines stay on screen.
const LOG_LINES := 7

var _data: Node
var _gen: ItemGen
var _loot
var _state
var _find_item: Callable

var battle: Battle
var _monster_seen: Dictionary = {}

var _enemy_icon: TextureRect
var _enemy_name: Label
var _enemy_track: Control
var _enemy_fill: ColorRect
var _enemy_hp_label: Label
var _hero_icon: TextureRect
var _hero_track: Control
var _hero_fill: ColorRect
var _hero_hp_label: Label
var _location_label: Label
var _log_box: VBoxContainer
var _result_label: Label
var _next_button: Button

var _log_lines: Array = []


func _init(game_data: Node, gen: ItemGen, loot, state, find_item: Callable) -> void:
	_data = game_data
	_gen = gen
	_loot = loot
	_state = state
	_find_item = find_item


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var enemy_box := VBoxContainer.new()
	enemy_box.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_box.add_theme_constant_override("separation", 4)
	root.add_child(enemy_box)

	_location_label = _label("", 14, Color("#888888"), HORIZONTAL_ALIGNMENT_CENTER)
	enemy_box.add_child(_location_label)

	_enemy_icon = TextureRect.new()
	_enemy_icon.custom_minimum_size = Vector2(220, 220)
	_enemy_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_enemy_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	enemy_box.add_child(_enemy_icon)

	_enemy_name = _label("", 20, Color("#e0e0e0"), HORIZONTAL_ALIGNMENT_CENTER)
	enemy_box.add_child(_enemy_name)

	var enemy_bar := _make_bar(Color("#8c2f2f"))
	_enemy_track = enemy_bar["track"]
	_enemy_fill = enemy_bar["fill"]
	enemy_box.add_child(enemy_bar["root"])

	_enemy_hp_label = _label("", 13, Color("#aaaaaa"), HORIZONTAL_ALIGNMENT_CENTER)
	enemy_box.add_child(_enemy_hp_label)

	var hero_box := VBoxContainer.new()
	hero_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_box.add_theme_constant_override("separation", 4)
	root.add_child(hero_box)

	_hero_icon = TextureRect.new()
	_hero_icon.custom_minimum_size = Vector2(140, 140)
	_hero_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero_box.add_child(_hero_icon)

	var hero_bar := _make_bar(Color("#3f7a4a"))
	_hero_track = hero_bar["track"]
	_hero_fill = hero_bar["fill"]
	hero_box.add_child(hero_bar["root"])

	_hero_hp_label = _label("", 13, Color("#aaaaaa"), HORIZONTAL_ALIGNMENT_CENTER)
	hero_box.add_child(_hero_hp_label)

	_log_box = VBoxContainer.new()
	_log_box.add_theme_constant_override("separation", 2)
	root.add_child(_log_box)

	_result_label = _label("", 22, Color("#e0e0e0"), HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_result_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	root.add_child(buttons)

	_next_button = _make_button("Dalsi souboj")
	_next_button.pressed.connect(func(): another_fight_requested.emit())
	_next_button.visible = false
	buttons.add_child(_next_button)

	var leave := _make_button("Zpet do mesta")
	leave.pressed.connect(func(): leave_requested.emit())
	buttons.add_child(leave)


func _label(text: String, size: int, colour: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.horizontal_alignment = align
	return l


## A flat two-node bar: a track and a fill whose width is set as a ratio.
func _make_bar(fill_colour: Color) -> Dictionary:
	var track := ColorRect.new()
	track.color = Color("#1a1a1a")
	track.custom_minimum_size = Vector2(400, 14)
	var fill := ColorRect.new()
	fill.color = fill_colour
	fill.position = Vector2.ZERO
	track.add_child(fill)
	return {"root": track, "track": track, "fill": fill}


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 44)
	b.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1a1a1a")
	style.border_color = Color("#333333")
	style.set_border_width_all(1)
	# One style object for every state: a tap must have no visual side effect beyond
	# the press itself. Same rule as the town tiles.
	for state_name in ["normal", "pressed", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(state_name, style)
	b.add_theme_color_override("font_color", Color("#d0d0d0"))
	b.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	return b


# --- the fight ---------------------------------------------------------------

## Start the fight at the state's current position. Returns false when there is
## nothing to fight (unknown act, or an empty monster pool).
func start(state, find_item: Callable) -> bool:
	_log_lines = []
	_log_box_clear()
	_result_label.text = ""
	_next_button.visible = false

	var seed_value := int(Time.get_ticks_usec()) & 0x7fffffff
	battle = Battle.new(_data, seed_value)
	battle.set_monster_seen(_monster_seen)
	var ok := battle.setup(state, find_item)
	_monster_seen = battle.monster_seen()
	if not ok:
		return false
	battle.apply_swing_timers(state, find_item)

	var hero: Dictionary = state.hero()
	_hero_icon.texture = _load("assets/ps/%s.png" % str(hero.get("face", "hero")))
	render()
	_append_log("Souboj zacina")
	return true


## Advance the fight one tick and re-render. The screen's _process calls this; a test
## calls it in a loop instead, which is the whole reason it is separate.
func step() -> void:
	if battle == null or battle.ended:
		return
	battle.tick(float(TICK_MS), _state, _find_item)
	_drain_log()
	render()
	if battle.ended:
		_finish_fight()


func _process(_delta: float) -> void:
	step()


func _drain_log() -> void:
	for entry in battle.log:
		var kind := str(entry.get("kind", ""))
		var amount := int(entry.get("amount", 0))
		_append_log("%s %d" % [kind, amount] if amount > 0 else kind)
	battle.log.clear()


func _append_log(text: String) -> void:
	_log_lines.append(text)
	while _log_lines.size() > LOG_LINES:
		_log_lines.pop_front()
	_log_box_clear()
	for line in _log_lines:
		_log_box.add_child(_label(str(line), 12, Color("#9a9a9a"), HORIZONTAL_ALIGNMENT_LEFT))


func _log_box_clear() -> void:
	for child in _log_box.get_children():
		_log_box.remove_child(child)
		child.queue_free()


func render() -> void:
	if battle == null:
		return
	_enemy_icon.texture = _load(battle.enemy_face)
	var elite_tag := ""
	if battle.is_elite and not battle.elite_affix.is_empty():
		elite_tag = "%s " % str(battle.elite_affix.get("name", ""))
	_enemy_name.text = elite_tag + battle.enemy_name

	var act: Dictionary = _data.act_by_id(battle.act_id)
	_location_label.text = "Act %d - %s - souboj %d/10" % [
		battle.act_id + 1, str(act.get("name", "")), battle.area_fight + 1]

	_set_bar(_enemy_track, _enemy_fill, battle.enemy_hp, battle.enemy_max_hp)
	_enemy_hp_label.text = "%d / %d" % [maxi(0, int(battle.enemy_hp)), int(battle.enemy_max_hp)]
	_set_bar(_hero_track, _hero_fill, battle.hero_hp, battle.hero_max_hp)
	_hero_hp_label.text = "%d / %d" % [maxi(0, int(battle.hero_hp)), int(battle.hero_max_hp)]


## The fill is resized rather than scaled, so the bar reads at any width.
func _set_bar(track: Control, fill: ColorRect, value: float, maximum: float) -> void:
	var width := track.size.x
	if width <= 0.0:
		width = track.custom_minimum_size.x
	if width <= 0.0:
		width = 400.0
	var ratio := clampf(value / maxf(maximum, 1.0), 0.0, 1.0)
	fill.size = Vector2(width * ratio, track.custom_minimum_size.y)


func _finish_fight() -> void:
	if battle.won:
		_append_log("Vyhrano")
		_result_label.text = "Vitezstvi"
		award_loot()
	else:
		_append_log("Porazeno")
		_result_label.text = "Porazka"
	_state.save()
	_next_button.visible = true
	fight_over.emit(battle.won)


## Loot and inventory. The battle already settled XP, kill gold and the fight
## counters; this adds the item drops, which need the loot system, and then levels.
func award_loot() -> void:
	var mf := _gen.magic_find(_state.equip(), _find_item)
	var gf := _gen.gold_find(_state.equip(), _find_item)
	var result: Dictionary = battle.roll_loot(_loot, _state, _find_item, mf, gf)
	var bagged := 0
	for item in result["items"]:
		_state.register_loot_item(item)
		var item_id := str(item.get("id", ""))
		_gen.add_to_inventory(_state.inventory(), item_id, item)
		bagged += 1
	_state.hero()["gold"] = int(_state.hero().get("gold", 0)) + int(result["gold"])
	_state.data["townPortalCount"] = int(_state.data.get("townPortalCount", 0)) + int(result["portals"])
	if bagged > 0:
		_append_log("Predmety: %d" % bagged)
	if int(result["gold"]) > 0:
		_append_log("Zlato: %d" % int(result["gold"]))
	apply_levels()
	_state.save()


## applyLevelUp — 40 XP for level 2, then 80 per level, cap 60. Every level refills
## HP, grants 5 attribute points and a talent point.
func apply_levels() -> void:
	var hero: Dictionary = _state.hero()
	var levelled := false
	var safety := 0
	while safety < 100:
		safety += 1
		if int(hero["level"]) >= 60:
			hero["xp"] = 0
			break
		var need := int(hero["level"]) * 40 if int(hero["level"]) <= 2 else int(hero["level"]) * 80
		if int(hero.get("xp", 0)) < need:
			break
		hero["xp"] = int(hero["xp"]) - need
		hero["level"] = int(hero["level"]) + 1
		hero["maxHp"] = _gen.hero_max_hp(hero, _state.equip(), _find_item)
		hero["hp"] = hero["maxHp"]
		hero["attrPoints"] = int(hero.get("attrPoints", 0)) + 5
		_state.data["talentPoints"] = int(_state.data.get("talentPoints", 0)) + 1
		levelled = true
	if levelled:
		_append_log("Novy level: %d" % int(hero["level"]))


## Advance the stop when the zone is finished, then start the next fight.
func another_fight() -> bool:
	if battle == null:
		return false
	battle.advance_stop(_state)
	_state.save()
	return start(_state, _find_item)


func _load(path: String) -> Texture2D:
	if path == "":
		return null
	var full := path if path.begins_with("res://") else "res://" + path
	if not ResourceLoader.exists(full):
		return null
	return load(full)
