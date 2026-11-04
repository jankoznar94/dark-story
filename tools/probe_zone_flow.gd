extends SceneTree
## tools/probe_zone_flow.gd — the act's chain end to end, through the REAL entry points.
##
## The unit tests pin `ActRun` and the generator; this walks what a player does:
##   map area 2 -> its zone (survivor run, zone_index 2)
##   walk out of the exit -> zone 3, area 2 marked cleared
##   tap the waypoint -> back to the result page (the town path), act still remembering zone 3
##
## Run: godot --headless --path . --script res://tools/probe_zone_flow.gd
## Pass: prints ZONE_FLOW_PASS=true

const Main := preload("res://scripts/main.gd")
const ActRun := preload("res://scripts/combat/act_run.gd")
const ToolHelpers := preload("res://tools/tool_helpers.gd")

var _main: Node = null
var _started := false
var _failures: Array[String] = []


func _initialize() -> void:
	_main = Main.new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if _main._nav_bar == null:
			return false
		_started = true
		_run()
		return false
	return false


func _fail(msg: String) -> void:
	_failures.append(msg)


func _drive() -> void:
	var tr = _main._transition
	if tr != null and tr.is_transitioning():
		tr._process(tr.HOLD_MS / 1000.0 + 0.01)


func _run() -> void:
	_main.state.set_class("barbarian")
	var total: int = int(_main.data.act_by_id(0).get("zones", 10))

	# --- area 2 of the act -----------------------------------------------
	_main._on_stop_selected(0, 2)
	_drive()
	if str(_main._current) != "survivor":
		_fail("tapping area 2 opened '%s', not its zone" % str(_main._current))
		_finish()
		return
	var screen = _main._screens["survivor"]
	if screen.run == null:
		_fail("area 2 did not create a run")
		_finish()
		return
	print("zone=%d boss=%s exit=%s waypoint=%s" % [
		screen.run.zone_index, str(screen.run.is_boss),
		str(screen.run.exit_point), str(screen.run.waypoint_point)])
	if screen.run.zone_index != 2:
		_fail("the run is zone %d, expected 2" % screen.run.zone_index)
	if int(ActRun.current_zone(_main.state, 0, total)) != 2:
		_fail("the act's record is at zone %d, expected 2"
			% int(ActRun.current_zone(_main.state, 0, total)))

	# --- walking out of the exit -----------------------------------------
	_main._on_zone_exited()
	_drive()
	if int(ActRun.current_zone(_main.state, 0, total)) != 3:
		_fail("the exit did not move the act to zone 3 (it is %d)"
			% int(ActRun.current_zone(_main.state, 0, total)))
	var cleared: Array = ActRun.get_run(_main.state, 0, total).get("cleared", [])
	if not cleared.has(2):
		_fail("zone 2 was not marked cleared after its exit")
	var screen2 = _main._screens["survivor"]
	if screen2.run == null or screen2.run.zone_index != 3:
		_fail("after the exit the run is not zone 3")

	# --- the waypoint: out to town, act keeps the checkpoint --------------
	screen2.waypoint_requested.emit()
	print("after waypoint: zone=%d last=%d wps=%s" % [
		int(ActRun.current_zone(_main.state, 0, total)),
		int(ActRun.last_waypoint(_main.state, 0, total)),
		str(ActRun.waypoints(_main.state, 0, total))])
	if int(ActRun.last_waypoint(_main.state, 0, total)) != 3:
		_fail("the waypoint trip lost the act's checkpoint")

	for f in _failures:
		print("  FAIL: %s" % f)
	print("ZONE_FLOW_PASS=%s" % ("true" if _failures.is_empty() else "false"))
	quit(0 if _failures.is_empty() else 1)


func _finish() -> void:
	for f in _failures:
		print("  FAIL: %s" % f)
	print("ZONE_FLOW_PASS=false")
	quit(1)
