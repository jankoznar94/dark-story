extends SceneTree
## tools/test_difficulty.gd — the difficulty ladder.
##
## This is the one gate in the game whose failure mode is a DEAD END rather than a wrong
## number: the town hides the Wilderness button when no act is left at the current
## difficulty, so if nothing ever advances `state.difficulty` the player finishes Normal
## and the game simply stops being playable. A test that taps through screens would not
## notice; asserting the ladder does.
##
## Run:  godot --headless --path . --script res://tools/test_difficulty.gd
## Pass: prints DIFFICULTY_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const Progression := preload("res://scripts/combat/progression.gd")

var _data: Node
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)

	_test_normal_is_the_only_unlocked_start()
	_test_clearing_normal_unlocks_nightmare()
	_test_locked_switch_is_refused_without_writing()
	_test_hell_needs_nightmare_not_just_normal()
	_test_first_uncompleted_act_is_per_difficulty()
	_test_act_ladder_is_per_difficulty()
	_test_progress_pages_are_independent()
	_test_scaling_doubles_per_difficulty()
	_test_save_clamps_an_impossible_difficulty()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("DIFFICULTY_ALL_PASS=true")
	else:
		print("DIFFICULTY_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _fresh():
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class("barbarian")
	return s


func _clear(s, difficulty: int) -> void:
	for act in GameState.ACT_COUNT:
		s.data["bossesDefeated"][difficulty][act] = true


## A new game must offer Normal and nothing else. If Nightmare started open the whole
## ladder would be decoration.
func _test_normal_is_the_only_unlocked_start() -> void:
	var s = _fresh()
	if int(s.data["difficulty"]) != 0:
		_fail("a fresh save does not start on Normal")
	if not s.is_difficulty_unlocked(0):
		_fail("Normal is not unlocked on a fresh save")
	if s.is_difficulty_unlocked(1):
		_fail("Nightmare is unlocked before Normal is cleared")
	if s.is_difficulty_unlocked(2):
		_fail("Hell is unlocked before Nightmare is cleared")
	if s.max_allowed_difficulty() != 0:
		_fail("max_allowed_difficulty is %d on a fresh save, expected 0" % s.max_allowed_difficulty())


## THE bug this file exists for: clearing every Normal boss must make Nightmare
## reachable, otherwise the game dead-ends after act 5 Normal.
func _test_clearing_normal_unlocks_nightmare() -> void:
	var s = _fresh()
	_clear(s, 0)
	if not s.difficulty_cleared(0):
		_fail("all five Normal bosses down but difficulty_cleared(0) is false")
	if not s.is_difficulty_unlocked(1):
		_fail("Nightmare is still locked with every Normal boss down")
	if s.is_difficulty_unlocked(2):
		_fail("Hell unlocked by clearing Normal alone")
	var result: Dictionary = s.set_difficulty(1)
	if not result["ok"]:
		_fail("switching to Nightmare was refused: %s" % str(result["reason"]))
		return
	if int(s.data["difficulty"]) != 1:
		_fail("set_difficulty(1) did not write the state")


## A refused switch must not half-apply: the difficulty is what every gate reads, so a
## lock that still moved it would drop the player into a difficulty they cannot enter.
func _test_locked_switch_is_refused_without_writing() -> void:
	var s = _fresh()
	var before := int(s.data["difficulty"])
	var result: Dictionary = s.set_difficulty(2)
	if result["ok"]:
		_fail("switching to a locked difficulty succeeded")
	if int(s.data["difficulty"]) != before:
		_fail("a REFUSED switch still changed the difficulty (%d -> %d)" % [before, int(s.data["difficulty"])])
	# And an out-of-range index is refused rather than written.
	if s.set_difficulty(7)["ok"]:
		_fail("an out-of-range difficulty was accepted")
	if s.set_difficulty(-1)["ok"]:
		_fail("a negative difficulty was accepted")


## Hell is sequential: it needs Nightmare CLEARED, not merely Normal.
func _test_hell_needs_nightmare_not_just_normal() -> void:
	var s = _fresh()
	_clear(s, 0)
	s.set_difficulty(1)
	_clear(s, 1)
	if not s.is_difficulty_unlocked(2):
		_fail("Hell is locked with both Normal and Nightmare cleared")
	if s.max_allowed_difficulty() != 2:
		_fail("max_allowed_difficulty is %d with everything cleared, expected 2" % s.max_allowed_difficulty())

	# Nightmare cleared but Normal not (only reachable via a hand-edited save): Hell
	# must NOT open, because its act 1 needs Nightmare act 5 and the chain reads down.
	var weird = _fresh()
	_clear(weird, 1)
	if weird.is_difficulty_unlocked(2):
		_fail("Hell unlocked with Nightmare cleared but Normal not")


## The act ladder is per difficulty — that is why `first_uncompleted_act` takes one.
func _test_first_uncompleted_act_is_per_difficulty() -> void:
	var s = _fresh()
	_clear(s, 0)
	s.set_difficulty(1)
	if s.first_uncompleted_act() != 0:
		_fail("on Nightmare with no Nightmare bosses down, the current act is %d not 0" % s.first_uncompleted_act())
	if s.first_uncompleted_act(0) != -1:
		_fail("Normal is fully cleared but first_uncompleted_act(0) is %d" % s.first_uncompleted_act(0))
	s.data["bossesDefeated"][1][0] = true
	if s.first_uncompleted_act() != 1:
		_fail("after Nightmare act 1 fell, the current act is %d not 1" % s.first_uncompleted_act())

	# A difficulty index out of range must answer -1 rather than crash or lie.
	if s.first_uncompleted_act(9) != -1:
		_fail("first_uncompleted_act for an out-of-range difficulty is not -1")


func _test_act_ladder_is_per_difficulty() -> void:
	var s = _fresh()
	_clear(s, 0)
	s.set_difficulty(1)
	if not s.act_unlocked(0):
		_fail("Nightmare act 1 is not enterable after clearing Normal")
	if s.act_unlocked(1):
		_fail("Nightmare act 2 is enterable with no Nightmare boss down")
	# And Normal's own ladder is untouched by the switch.
	s.set_difficulty(0)
	if not s.act_unlocked(4):
		_fail("Normal act 5 is not enterable after clearing Normal - the ladder reads the wrong row")


## Farming act 1 on Normal must not close Nightmare's acts again, and the two
## difficulties must keep their own zone position.
func _test_progress_pages_are_independent() -> void:
	var s = _fresh()
	s.data["bossesDefeated"][0] = [true, true, true, true, true]
	s.set_difficulty(1)
	s.set_progress(0, 3)
	s.data["areaFightProgress"][0] = 4
	if s.max_progress(0) != 3:
		_fail("Nightmare's act 1 progress is %d, expected 3" % s.max_progress(0))
	# Now switch back and rewind Normal's act 1 to zone 0 — Nightmare must not move.
	s.set_difficulty(0)
	s.set_progress(0, 0)
	if s.max_progress(0) != 3:
		_fail("farming Normal rewound Nightmare's max progress to %d" % s.max_progress(0))
	# And unlocking still counts from the max, not the current position.
	if not s.act_unlocked(4):
		_fail("rewinding Normal's act 1 locked Normal act 5 again")


## The point of unlocking Nightmare is that it is actually harder. If the tables did not
## scale, unlocking it would be a colour change.
func _test_scaling_doubles_per_difficulty() -> void:
	var prog = Progression.new(_data)
	var normal := prog.zone_mult(0, 0)
	var nightmare := prog.zone_mult(0, 1)
	var hell := prog.zone_mult(0, 2)
	if not (nightmare > normal and hell > nightmare):
		_fail("zone scaling does not rise per difficulty: %s / %s / %s" % [normal, nightmare, hell])
	# Same zone index, three difficulties: the monster LEVEL band must climb too, or
	# Nightmare would spawn level-1 monsters with a bigger health bar.
	var n_lv := prog.monster_level(0, 0, 0)
	var nm_lv := prog.monster_level(0, 0, 1)
	var h_lv := prog.monster_level(0, 0, 2)
	if not (nm_lv > n_lv and h_lv > nm_lv):
		_fail("monster level bands do not climb per difficulty: %d / %d / %d" % [n_lv, nm_lv, h_lv])


## A save is a text file a player can edit. An out-of-range difficulty would read an
## empty row at every gate and show nothing at all, so it is clamped on load.
func _test_save_clamps_an_impossible_difficulty() -> void:
	var s = _fresh()
	s.data["difficulty"] = 9
	s._repair_after_load()
	if int(s.data["difficulty"]) >= GameState.DIFF_COUNT:
		_fail("an out-of-range difficulty in a save was not clamped (%d)" % int(s.data["difficulty"]))

	# A save claiming Hell with nothing cleared is clamped to what its own flags allow.
	var w = _fresh()
	w.data["difficulty"] = 2
	w._repair_after_load()
	if w.is_difficulty_unlocked(int(w.data["difficulty"])) == false:
		_fail("a clamped save is still on a locked difficulty (%d)" % int(w.data["difficulty"]))
	if int(w.data["difficulty"]) != 0:
		_fail("a save claiming Hell with no bosses cleared clamped to %d, expected 0" % int(w.data["difficulty"]))
