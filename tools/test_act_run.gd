extends SceneTree
## tools/test_act_run.gd — the act as a chain of real zones with waypoints.
##
## Jan: "Každá oblast v mapě v rámci aktu by měla mít svoji reálnou zónu ve hře. Úplně tím
## nahradíme mapový systém. Jednotlivé oblasti aktu budou použity jako waypointy."
##
## Everything here is invisible when it breaks: a checkpoint that silently resets to zone 0
## after a death looks exactly like a working one until the player loses four zones of work.
##
## Run:  godot --headless --path . --script res://tools/test_act_run.gd
## Pass: prints ACT_RUN_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const ActRun := preload("res://scripts/combat/act_run.gd")

var _data: Node
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_test_a_new_act_starts_at_zone_zero()
	_test_entering_a_zone_unlocks_its_waypoint()
	_test_clearing_steps_deeper_and_the_last_zone_ends_the_act()
	_test_state_survives_a_json_round_trip()
	_test_zone_seeds_are_stable_and_distinct()
	for f in _failures:
		print("  FAIL: %s" % f)
	print("ACT_RUN_ALL_PASS=%s" % ("true" if _failures.is_empty() else "false"))
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _fresh() -> GameState:
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class("barbarian")
	return s


func _test_a_new_act_starts_at_zone_zero() -> void:
	var s := _fresh()
	var e := ActRun.get_run(s, 0, 10)
	if int(e.get("zone", -1)) != 0:
		_fail("a new act starts at zone %d, expected 0" % int(e.get("zone", -1)))
	if not (e.get("waypoints", []) as Array).has(0):
		_fail("a new act has no waypoint at its first zone")
	if int(e.get("seed", 0)) == 0:
		_fail("a new act has no seed — its layout would not be reproducible")


func _test_entering_a_zone_unlocks_its_waypoint() -> void:
	var s := _fresh()
	ActRun.enter_zone(s, 0, 3, 10)
	if ActRun.current_zone(s, 0, 10) != 3:
		_fail("entering zone 3 left the act at zone %d" % ActRun.current_zone(s, 0, 10))
	if not ActRun.is_unlocked(s, 0, 3, 10):
		_fail("arriving in zone 3 did not unlock its waypoint")
	if ActRun.is_unlocked(s, 0, 5, 10):
		_fail("zone 5 is unlocked without ever arriving there")
	if ActRun.last_waypoint(s, 0, 10) != 3:
		_fail("last waypoint is %d, expected 3" % ActRun.last_waypoint(s, 0, 10))


func _test_clearing_steps_deeper_and_the_last_zone_ends_the_act() -> void:
	var s := _fresh()
	ActRun.enter_zone(s, 0, 0, 10)
	var nxt := ActRun.clear_zone(s, 0, 0, 10)
	if nxt != 1:
		_fail("clearing zone 0 returned %d, expected 1" % nxt)
	if ActRun.current_zone(s, 0, 10) != 1:
		_fail("clearing zone 0 did not move the act to zone 1")
	if not ActRun.is_unlocked(s, 0, 1, 10):
		_fail("the next zone's waypoint was not unlocked by walking in")
	ActRun.enter_zone(s, 0, 9, 10)
	if ActRun.clear_zone(s, 0, 9, 10) != -1:
		_fail("the last zone's exit did not end the act")


func _test_state_survives_a_json_round_trip() -> void:
	var s := _fresh()
	ActRun.enter_zone(s, 0, 4, 10)
	ActRun.clear_zone(s, 0, 3, 10)
	var parsed: Variant = JSON.parse_string(JSON.stringify(s.data))
	if not (parsed is Dictionary):
		_fail("the save did not serialise")
		return
	var reloaded := _fresh()
	reloaded.data = parsed
	if ActRun.last_waypoint(reloaded, 0, 10) != 4:
		_fail("after a reload the last waypoint is %d, expected 4"
			% ActRun.last_waypoint(reloaded, 0, 10))
	if int((ActRun.get_run(reloaded, 0, 10).get("cleared", []) as Array).size()) != 1:
		_fail("after a reload the cleared list was lost")


func _test_zone_seeds_are_stable_and_distinct() -> void:
	var s := _fresh()
	var e := ActRun.get_run(s, 0, 10)
	var a := ActRun.zone_seed(e, 3)
	var b := ActRun.zone_seed(e, 3)
	if a != b:
		_fail("the same zone got two different seeds (%d, %d)" % [a, b])
	if ActRun.zone_seed(e, 3) == ActRun.zone_seed(e, 4):
		_fail("two zones share a seed — the act would repeat one map")
