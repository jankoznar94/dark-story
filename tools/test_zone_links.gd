extends SceneTree
## tools/test_zone_links.gd — the two ends of a zone: the ENTRANCE the hero stands on and the
## EXIT that hands him one zone deeper, plus the waypoint beside the entrance.
##
## A gate that lands in rock is not "a bit off": the hero can never reach it, so the act stops
## dead at that zone and the player sees a dungeon with no way forward. And an exit that sits
## next to the entrance makes "the next zone" a two-step walk, which is the corridor Jan already
## rejected. Both are measured over many seeds, never on one lucky layout.
##
## Run:  godot --headless --path . --script res://tools/test_zone_links.gd
## Pass: prints ZONE_LINKS_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")

## ⚠️  THE JOURNEY IS THE PATH, NOT THE STRAIGHT LINE. This used to require the exit to sit at
## 55 % of the map's diagonal from the entrance, which worked while the map was barely bigger
## than the corridor. A corridor that WINDS (12800 px of walking, `PATH_TARGET`) doubles back, so
## the two endpoints can be 3 300 px apart on a 12 800 px walk — the straight line measures the
## map's aspect ratio, not whether the zone is a journey. The path length is asserted instead.
const MIN_PATH_SHARE := 0.95
## The waypoint is a checkpoint at the START, so it must be close enough to find immediately.
const MAX_WAYPOINT_DIST := 340.0

var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _state
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)
	_state = GameState.new()
	_state.bind_data(_data)
	_state.set_class("barbarian")

	var seeds := [1, 7, 42, 101, 777, 1234, 4242, 90210, 31337, 65535, 8, 9, 10, 11, 12, 13, 14, 15]
	for seed_value in seeds:
		for zone in [0, 3, 9]:
			_check_zone(int(seed_value), int(zone))

	for f in _failures:
		print("  FAIL: %s" % f)
	print("ZONE_LINKS_ALL_PASS=%s" % ("true" if _failures.is_empty() else "false"))
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _fresh(seed_value: int, zone: int) -> SurvivorRun:
	var run := SurvivorRun.new()
	run.setup(_state, _resolve, _loot, 0, seed_value, zone)
	return run


func _resolve(id) -> Dictionary:
	var item_id := str(id)
	if item_id == "":
		return {}
	var loot: Dictionary = _state.loot_item(item_id)
	if not loot.is_empty():
		return loot
	return _data.item(item_id)


func _check_zone(seed_value: int, zone: int) -> void:
	var tag := "seed %d zone %d" % [seed_value, zone]
	var run := _fresh(seed_value, zone)
	if not run.walkable(run.exit_point, 24.0):
		_fail("%s: the exit point is not on walkable floor" % tag)
	if not run.is_floor_cell(run.cell_of(run.waypoint_point).x, run.cell_of(run.waypoint_point).y):
		_fail("%s: the waypoint is not on floor" % tag)
	var total := 0.0
	var pts: Array = run.path_points
	for k in range(1, pts.size()):
		total += (pts[k - 1] as Vector2).distance_to(pts[k] as Vector2)
	var dist := total
	if dist < SurvivorRun.PATH_TARGET * MIN_PATH_SHARE:
		_fail("%s: the walked path is only %.0f px from the entrance to the exit (want >= %.0f)"
			% [tag, dist, SurvivorRun.PATH_TARGET * MIN_PATH_SHARE])
	var wp_dist: float = run.start_point.distance_to(run.waypoint_point)
	if wp_dist > MAX_WAYPOINT_DIST:
		_fail("%s: the waypoint is %.0f px from the entrance (want <= %.0f)"
			% [tag, wp_dist, MAX_WAYPOINT_DIST])
	# The exit must be REACHABLE from the entrance, not just on floor: a flood fill over the
	# grid catches a room the corridor never carved a way into.
	if not _reachable(run, run.start_point, run.exit_point):
		_fail("%s: the exit is on floor but not reachable from the entrance" % tag)


## Flood fill over the floor, four neighbours — a pocket behind the rock would make the exit a
## gate the hero can see and never walk through.
func _reachable(run, from: Vector2, to: Vector2) -> bool:
	var start: Vector2i = run.cell_of(from)
	var goal: Vector2i = run.cell_of(to)
	var seen := {start: true}
	var stack: Array = [start]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if c == goal:
			return true
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var n: Vector2i = c + d
			if seen.has(n) or not run.is_floor_cell(n.x, n.y):
				continue
			seen[n] = true
			stack.append(n)
	return false
