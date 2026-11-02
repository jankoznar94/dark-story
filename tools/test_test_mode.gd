extends SceneTree
## tools/test_test_mode.gd — the nav bar's test button, carried over from the PWA.
##
## Jan, Nov 2026: "Toto tlačítko musí odemknout všechny možnosti. Všechny SKILL pointy,
## atribut pointy, atd. Zkrátka jak to bylo v původní hře Dungeon recall."
##
## So the bar is the PWA's `toggleTestMode()` numbers, asserted one by one: 100 000 gold,
## 50 talent points, 150 attribute points, level 50, every boss dead in every difficulty,
## every stop of every act at 999, and the whole bestiary seen.
##
## Three things this test exists to catch, all of them invisible on a screenshot:
##   1. the button is wired to a message instead of to the state (the port's old behaviour —
##      "Testovaci rezim neni v portu preneseny");
##   2. the DERIVED pools are not recomputed, so a level-50 hero still has level-1 HP;
##   3. turning it off leaves the player in the test save instead of a new game.
##
## Run:  godot --headless --path . --script res://tools/test_test_mode.gd
## Pass: prints TEST_MODE_ALL_PASS=true

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const TownScreen := preload("res://scripts/ui/town_screen.gd")

var _data: Node
var _gen: ItemGen
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)

	_test_unlocks_everything()
	_test_pools_are_recomputed()
	_test_town_offers_the_map()
	_test_off_is_a_new_game()
	# The WIRING lives in Main (the nav entry -> the toggle), so the last section has to run
	# against the real game on a real frame.
	process_frame.connect(_main_phase, CONNECT_ONE_SHOT)


func _verdict() -> void:
	for f in _failures:
		print("  FAIL: %s" % f)
	print("TEST_MODE_ALL_PASS=%s" % ("true" if _failures.is_empty() else "false"))
	quit(0 if _failures.is_empty() else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _find_item(id: Variant) -> Dictionary:
	var item: Dictionary = _data.item(str(id))
	if item.is_empty():
		return {}
	return item


func _fresh():
	var s = GameState.new()
	s.bind_data(_data)
	s.reset()
	s.set_class("barbarian")
	s.hero()["level"] = 3
	s.hero()["gold"] = 55
	s.data["talentPoints"] = 0
	return s


# ============================================================================ the unlock

func _test_unlocks_everything() -> void:
	var state = _fresh()
	_check(not state.test_mode, "a fresh state must not start in test mode")
	state.enable_test_mode()

	_check(state.test_mode, "enable_test_mode must set the flag")
	# The PWA's own numbers, one by one.
	_check(int(state.hero()["gold"]) == 100000, "gold must be 100000, got %d" % int(state.hero()["gold"]))
	_check(int(state.data["talentPoints"]) == 50, "talentPoints must be 50, got %d" % int(state.data["talentPoints"]))
	_check(int(state.hero()["attrPoints"]) == 150, "attrPoints must be 150, got %d" % int(state.hero()["attrPoints"]))
	_check(int(state.hero()["level"]) == 50, "level must be 50, got %d" % int(state.hero()["level"]))
	_check(int(state.hero()["xp"]) == 0, "xp must be reset to 0, got %d" % int(state.hero()["xp"]))

	# Every act, every difficulty: no boss left alive anywhere.
	var bosses_ok := true
	for difficulty in (state.data["bossesDefeated"] as Array):
		for defeated in (difficulty as Array):
			if not bool(defeated):
				bosses_ok = false
	_check(bosses_ok, "every boss must be defeated in every difficulty")
	_check(state.first_uncompleted_act() < 0,
		"with every boss dead there must be no uncompleted act left")

	# Every stop open. `_maxLocationProgress` carries the unlock, `locationProgress` the cursor.
	var stops_ok := true
	var max_ok := true
	for i in GameState.ACT_COUNT:
		if int(state.data["locationProgress"][i]) != 999:
			stops_ok = false
		if int(state.data["_maxLocationProgress"][i]) != 999:
			max_ok = false
	_check(stops_ok, "locationProgress must be 999 for every act")
	_check(max_ok, "_maxLocationProgress must be 999 for every act")

	# The bestiary: every monster face of every theme, plus every boss face.
	var seen: Array = state.data["encounteredMonsters"]
	var missing: Array = []
	for bucket in _data.table("MONSTER_DB", []):
		for row in bucket:
			var face := str(row.get("face", ""))
			if face != "" and not seen.has(face):
				missing.append(face)
	for act in _data.acts():
		var face := str((act.get("boss", {}) as Dictionary).get("face", ""))
		if face != "" and not seen.has(face):
			missing.append(face)
	_check(missing.is_empty(), "the bestiary must be fully unlocked, missing=%s" % str(missing))
	print("  unlocked: %d monster faces, gold %d, talent %d, attr %d, level %d"
		% [seen.size(), int(state.hero()["gold"]), int(state.data["talentPoints"]),
		int(state.hero()["attrPoints"]), int(state.hero()["level"])])


## The pools are DERIVED from the level by ItemGen. A test hero at level 50 with level-3 HP is
## the exact bug the port already had once (a level-20 hero on level-1 pools), so it is asserted
## on numbers, not on the call being made.
func _test_pools_are_recomputed() -> void:
	var state = _fresh()
	var low_hp: int = _gen.hero_max_hp(state.hero(), state.equip(), _find_item)
	var low_mana: int = _gen.hero_max_mana(state.hero(), state.equip(), "barbarian", _find_item)
	state.enable_test_mode()
	var high_hp: int = _gen.hero_max_hp(state.hero(), state.equip(), _find_item)
	var high_mana: int = _gen.hero_max_mana(state.hero(), state.equip(), "barbarian", _find_item)
	_check(high_hp > low_hp, "level 50 must raise max HP (%d vs %d)" % [high_hp, low_hp])
	print("  pools: hp %d -> %d, mana %d -> %d" % [low_hp, high_hp, low_mana, high_mana])
	# ⚠️  The recompute itself lives in Main (it owns ItemGen); what is asserted here is that the
	# LEVEL the pools are computed from really moved, which is the half GameState owns.
	_check(int(state.hero()["level"]) == 50, "the level the pools derive from must be 50")


## The town hides the Wilderness tile when no act is uncompleted. In test mode every act IS
## completed, so without the escape hatch the button that leads to the unlocked map disappears.
func _test_town_offers_the_map() -> void:
	var state = _fresh()
	state.enable_test_mode()
	var town = TownScreen.new(_data, _gen, state, _find_item)
	root.add_child(town)
	if town._update_check == null:
		town._build()
	town.refresh()
	_check(town._wilderness_button.visible,
		"test mode must keep the Wilderness tile, it is the only way to the map")
	town.queue_free()


## Off = a NEW GAME, exactly as the PWA's `defaultState()`. A toggle that leaves the test save
## behind turns one mistap into a corrupted game.
func _test_off_is_a_new_game() -> void:
	var state = _fresh()
	state.enable_test_mode()
	state.disable_test_mode()
	_check(not state.test_mode, "disable must clear the flag")
	_check(int(state.hero()["level"]) == 1, "disable must reset the level, got %d" % int(state.hero()["level"]))
	_check(int(state.hero()["gold"]) == 0, "disable must reset the gold, got %d" % int(state.hero()["gold"]))
	_check(int(state.data["talentPoints"]) == 0, "disable must reset the talent points")
	_check(str(state.data["heroClass"]) == "", "disable must leave an empty class for the caller to seed")
	_check(not state.is_boss_defeated(0), "disable must lock the acts again")
	_check(int(state.data["encounteredMonsters"].size()) == 0, "disable must empty the bestiary")


## THE WIRING. Everything above tests GameState; this tests the thing Jan actually taps — the
## nav entry in the running game. It is the half that was broken for the whole port ("Testovaci
## rezim neni v portu preneseny") and no state test could ever see it.
func _main_phase() -> void:
	print("== the nav entry reaches the toggle ==")
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	await process_frame
	if main._screens.is_empty():
		_failures.append("Main built no screens")
		_verdict()
		return

	main._on_nav_selected("testmode")
	_check(bool(main.state.test_mode), "the nav entry did not switch test mode on")
	_check(int(main.state.hero()["level"]) == 50,
		"the running game is not at level 50, got %d" % int(main.state.hero()["level"]))
	# The pools are recomputed by Main, and this is the assertion that catches the level-50
	# hero with level-1 HP: the hero must be FULL, not merely a higher maximum.
	_check(int(main.state.hero()["hp"]) == int(main.state.hero()["maxHp"]),
		"test mode must leave the hero at full HP (%d/%d)"
		% [int(main.state.hero()["hp"]), int(main.state.hero()["maxHp"])])
	_check(int(main.state.hero()["maxHp"]) > 100,
		"a level-50 hero must have more than the starting 100 HP, got %d" % int(main.state.hero()["maxHp"]))
	print("  running game: level %d, hp %d/%d, gold %d, talents %d, attr points %d"
		% [int(main.state.hero()["level"]), int(main.state.hero()["hp"]),
		int(main.state.hero()["maxHp"]), int(main.state.hero()["gold"]),
		int(main.state.data["talentPoints"]), int(main.state.hero()["attrPoints"])])

	# And off again, through the same entry: a new game, with a class (a save with no class has
	# no skills and no mana pool).
	main._on_nav_selected("testmode")
	_check(not bool(main.state.test_mode), "the nav entry did not switch test mode off")
	_check(int(main.state.hero()["level"]) == 1,
		"switching off must start a new game, level %d" % int(main.state.hero()["level"]))
	_check(str(main.state.data["heroClass"]) != "",
		"a new game after test mode must still have a class")
	main.queue_free()
	_verdict()
