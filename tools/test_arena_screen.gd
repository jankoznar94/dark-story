extends SceneTree
## tools/test_arena_screen.gd — the arena screen, driven headlessly.
##
## `battle.gd` owns every rule and `tools/test_player_spells.gd` already asserts them.
## What that test CANNOT see is the wiring between the two: whether the screen actually
## builds a button per learned spell, whether tapping it reaches the rules, and whether
## the mana bar the barbarian pays from is on screen at all.
##
## Those are exactly the failures that look like working features:
##   - a spell bar that is built but never clickable (buttons freed and recreated every
##     render tick, so the tap lands on a node that no longer exists),
##   - a bar built once and never refreshed, so a spell stays greyed out after its
##     cooldown has expired,
##   - the hero's mana bar hidden for a class that does use mana, which is what the port
##     used to do for the barbarian on a false belief about rage.
##
## Run:  godot --headless --path . --script res://tools/test_arena_screen.gd
## Pass: prints ARENA_SCREEN_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const Battle := preload("res://scripts/combat/battle.gd")
const ArenaScreen := preload("res://scripts/ui/arena_screen.gd")

var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)

	_test_barbarian_has_a_mana_bar()
	_test_spell_bar_builds_one_button_per_learned_spell()
	_test_cast_through_the_screen_changes_the_battle()
	_test_the_bar_refreshes_when_a_cooldown_expires()
	_test_buttons_survive_a_render_tick()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("ARENA_SCREEN_ALL_PASS=true")
	else:
		print("ARENA_SCREEN_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _resolve(state) -> Callable:
	return func(id):
		var item_id := str(id)
		if item_id == "":
			return {}
		var static_item: Dictionary = _data.item(item_id)
		if not static_item.is_empty():
			return static_item
		return state.loot_item(item_id)


func _hero(class_id: String = "barbarian", talents: Dictionary = {}, level: int = 20):
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class(class_id)
	s.hero()["level"] = level
	s.hero()["mana"] = 60
	s.hero()["maxMana"] = 100
	s.hero()["attrStr"] = 40
	var levels := {}
	for key in talents:
		levels["%s_%s" % [class_id, key]] = int(talents[key])
	s.data["talentLevels"] = levels
	var sword: Dictionary = _data.item("blade_shortSword")
	if not sword.is_empty():
		s.equip()["weapon"] = "blade_shortSword"
	return s


## An arena built the way main.gd builds it, with a fight already running.
func _arena(state, hp: float = 100000.0) -> ArenaScreen:
	var screen: ArenaScreen = ArenaScreen.new(_data, _gen, _loot, state, _resolve(state))
	root.add_child(screen)
	# A SceneTree script's _initialize() runs before the first frame, so _ready() has
	# not fired for the freshly added node and the UI does not exist yet. Building it
	# here is what an actual frame would have done.
	if screen._mana_track == null:
		screen._build()
	# start() picks a real monster out of the act tables; the fight itself is not what
	# is under test here, so a high enough enemy HP keeps it alive across the ticks.
	if not screen.start(state, _resolve(state)):
		_fail("the arena could not start a fight")
		return screen
	screen.battle.enemy_hp = hp
	screen.battle.enemy_max_hp = hp
	screen.battle.hero_hp = 100000.0
	screen.battle.hero_max_hp = 100000.0
	return screen


## The spell buttons are the only thing on the row that is tappable, so count Buttons.
func _spell_buttons(screen: ArenaScreen) -> Array:
	var out: Array = []
	for child in screen._spell_row.get_children():
		if child is Button:
			out.append(child)
	return out


## The barbarian pays for his warcries out of MANA, exactly like the other two classes.
## The port used to hide his bar on the belief that he ran on rage, which hid the pool
## his own spells are billed against.
func _test_barbarian_has_a_mana_bar() -> void:
	var s = _hero("barbarian", {}, 20)
	var screen = _arena(s)
	if screen._mana_track == null or screen._mana_label == null:
		_fail("the arena has no mana bar nodes")
		return
	if not screen._mana_track.visible:
		_fail("the barbarian's mana bar is hidden")
	if not screen._mana_label.text.begins_with("Mana"):
		_fail("the mana label does not read as mana: '%s'" % screen._mana_label.text)
	# And it shows the hero's real pool, not a placeholder.
	var text: String = screen._mana_label.text
	if not text.contains("/ %d" % int(s.hero()["maxMana"])) and not text.contains("/ 1"):
		_fail("the mana label does not carry the pool: '%s'" % text)


## A spell is on the bar only once a talent point is in it — and then it is a real,
## enabled Button.
func _test_spell_bar_builds_one_button_per_learned_spell() -> void:
	var fresh = _hero("barbarian", {}, 20)
	var screen_fresh = _arena(fresh)
	if not _spell_buttons(screen_fresh).is_empty():
		_fail("a barbarian with no talents has spell buttons on the bar")

	var s = _hero("barbarian", {"heroicStrike": 1, "thunderClap": 1}, 20)
	var screen = _arena(s)
	var buttons := _spell_buttons(screen)
	if buttons.size() != 2:
		_fail("the bar built %d spell buttons, expected 2" % buttons.size())
		return
	var enabled := 0
	for b in buttons:
		if not (b as Button).disabled:
			enabled += 1
	if enabled != 2:
		_fail("%d of 2 fresh spells are disabled" % (2 - enabled))


## A tap has to reach the RULES. This is the wiring the spell test cannot see: the
## screen could build perfect buttons that do nothing at all.
func _test_cast_through_the_screen_changes_the_battle() -> void:
	var s = _hero("barbarian", {"heroicStrike": 1}, 20)
	var screen = _arena(s)
	var battle = screen.battle
	var mana_before: int = int(s.hero()["mana"])
	# The button's own callback is what a player's finger reaches.
	var result: Dictionary = screen.cast_spell("heroicStrike")
	if not bool(result["ok"]):
		_fail("casting heroicStrike through the screen failed: %s" % str(result["message"]))
		return
	if not battle.heroic_strike_queued:
		_fail("the cast through the screen did not queue the spell on the battle")
	if int(s.hero()["mana"]) >= mana_before:
		_fail("the cast through the screen spent no mana (%d -> %d)" % [mana_before, int(s.hero()["mana"])])
	# A refused cast must be refused, not silently accepted.
	var refused: Dictionary = screen.cast_spell("whirlwind")
	if bool(refused["ok"]):
		_fail("the screen accepted whirlwind, which is deliberately not ported")


## The bar is rebuilt when its contents change — a spell that comes off cooldown must
## become clickable again rather than staying greyed out forever.
func _test_the_bar_refreshes_when_a_cooldown_expires() -> void:
	var s = _hero("barbarian", {"thunderClap": 1}, 20)
	var screen = _arena(s)
	screen.cast_spell("thunderClap")
	if int(screen.battle.spell_cooldowns.get("thunderClap", 0)) <= 0:
		_fail("thunderClap set no cooldown through the screen")
		return
	screen.render()
	var blocked := 0
	for b in _spell_buttons(screen):
		if (b as Button).disabled:
			blocked += 1
	if blocked != 1:
		_fail("the spell on cooldown is not shown as blocked (%d disabled)" % blocked)
	# Tick the cooldown out (15 s) and render again: the button must come back.
	for _i in 200:
		screen.step()
	screen.render()
	var still_blocked := 0
	for b in _spell_buttons(screen):
		if (b as Button).disabled:
			still_blocked += 1
	if still_blocked != 0:
		_fail("the spell stayed blocked after its cooldown expired")


## render() runs ten times a second. If the bar were rebuilt every time, the node under
## the player's finger would be freed before the tap is delivered and the spell would
## never fire — so the buttons must SURVIVE a render.
func _test_buttons_survive_a_render_tick() -> void:
	var s = _hero("barbarian", {"heroicStrike": 1}, 20)
	var screen = _arena(s)
	screen.render()
	var buttons := _spell_buttons(screen)
	if buttons.is_empty():
		_fail("no spell buttons to check across a render tick")
		return
	var first: Button = buttons[0]
	screen.render()
	screen.render()
	var after := _spell_buttons(screen)
	if after.is_empty():
		_fail("the spell row was emptied by render()")
		return
	# Same instance, still alive: a freed button would not be identical to itself. The
	# `is_inside_tree()` check cannot be used here — a SceneTree test runs before the
	# loop starts, so no node reports being in the tree — but `is_queued_for_deletion()`
	# is exactly the failure mode: render() freeing the node under the player's finger.
	if after[0] != first:
		_fail("render() replaced the spell buttons instead of leaving them alone")
	if first.is_queued_for_deletion():
		_fail("render() queued the spell button for deletion")
