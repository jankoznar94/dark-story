extends SceneTree
## tools/test_zone_persistence.gd — the WIRING of zone persistence, through `main.gd` itself.
##
## `test_zone_memory` proves the model (snapshot → restore). This file proves the ROUTE: that the
## waypoint button freezes the zone, that entering the zone again puts it back, and that death
## throws the act's world away. The model passing while a button is wired to nothing is exactly
## the shape of defect this project has shipped before ("it looks right in a screenshot").
##
## Run:  godot --headless --path . --script res://tools/test_zone_persistence.gd
## Pass: prints ZONE_PERSISTENCE_ALL_PASS=true and exits 0.

const Main := preload("res://scripts/main.gd")
const ZoneMemory := preload("res://scripts/combat/zone_memory.gd")

var _main: Node = null
var _started := false
var _failures: Array[String] = []


func _initialize() -> void:
	_main = Main.new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if _main.state == null or _main._screens.get("survivor", null) == null:
			return false
		_started = true
		_run()
		quit(0 if _failures.is_empty() else 1)
		return true
	return false


func _fail(msg: String) -> void:
	_failures.append(msg)


func _run() -> void:
	_test_waypoint_freezes_and_reentry_restores()
	_test_death_rolls_the_act_again()
	for f in _failures:
		print("  FAIL: %s" % f)
	print("ZONE_PERSISTENCE_ALL_PASS=%s" % ("true" if _failures.is_empty() else "false"))


## Wakes a pack on the live run and wounds one of its monsters. Returns the id it wounded, or -1.


func _test_waypoint_freezes_and_reentry_restores() -> void:
	ZoneMemory.reset()
	_main._enter_survivor(0, 2)
	var first = _main._screens["survivor"].run
	if first == null:
		_fail("entering a zone built no run")
		return
	var pack: int = 2
	var ids: Array = []
	if pack < first.zones.size():
		first.player_pos = first.zones[pack]["centre"] as Vector2
		first._zone_tick()
		ids = (first.zones[pack]["ids"] as Array).duplicate()
	if ids.is_empty():
		_fail("no pack woke in zone 2 — the wiring case would prove nothing")
		return
	var left: int = first.monsters.size()
	first.monsters[0]["hp"] = 7
	var wounded := int(first.monsters[0]["id"])

	# The WAYPOINT stone: the only path that goes to town without a scroll.
	_main._on_zone_waypoint_used()
	if not ZoneMemory.has(0, 2):
		_fail("the waypoint did not freeze the zone — coming back would re-roll it")
	var portal: Variant = _main.state.data.get("townPortalReturn")
	if not (portal is Dictionary) or not bool((portal as Dictionary).get("zone", false)):
		_fail("the waypoint stored no ZONE return position (the town's portal card would be dead)")
	elif int((portal as Dictionary).get("zoneId", -1)) != 2:
		_fail("the waypoint stored zone %d, the player stood in 2"
			% int((portal as Dictionary).get("zoneId", -1)))

	# The town's portal card returns into the zone (not the old arena duel).
	_main._on_town_portal_return()
	var back = _main._screens["survivor"].run
	print("  waypoint -> town -> portal: %d monsters (left %d), pack awake=%s"
		% [back.monsters.size(), left, str(back.zones[pack]["active"] if pack < back.zones.size() else false)])
	if back.monsters.size() != left:
		_fail("re-entry restored %d monsters, %d were left fighting"
			% [back.monsters.size(), left])
	if pack < back.zones.size() and not bool(back.zones[pack]["active"]):
		_fail("the pack is not awake after the portal — it would spawn a second copy")
	var found := false
	for m in back.monsters:
		if int(m["id"]) == wounded:
			found = true
			if int(m["hp"]) != 7:
				_fail("the wounded monster came back at %d hp, it was left at 7" % int(m["hp"]))
	if not found:
		_fail("monster id %d was lost across the waypoint trip" % wounded)
	if back.player_pos.distance_to(back.start_point) > 1.0:
		_fail("the portal put the hero at the far end of the zone instead of its entrance")


func _test_death_rolls_the_act_again() -> void:
	_main._enter_survivor(0, 2)
	var run = _main._screens["survivor"].run
	if run.monsters.is_empty():
		_fail("the counterfactual run had no monsters — the restore is not what put them there")
	_main._end_survivor("dead")
	if ZoneMemory.has(0, 2):
		_fail("a death kept the zone snapshot — Jan's rule is that death RESETS it")
	_main._enter_survivor(0, 2)
	var fresh = _main._screens["survivor"].run
	print("  after death: %d monsters standing where %d died" % [fresh.monsters.size(), run.monsters.size()])
	if not fresh.monsters.is_empty():
		_fail("death left %d monsters from the previous run in the zone" % fresh.monsters.size())
	if int(fresh.hp) != int(fresh.max_hp):
		_fail("a fresh zone after death did not start the hero at full life")
