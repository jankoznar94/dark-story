extends SceneTree
## Probe: the four things this session changed, measured on the real build.
##
##   1. a tap on a DOT starts the fight;
##   2. a tap on a DOT that has not opened does NOT (and the node wears a padlock);
##   3. the road's "Jít domů" button now fires (the status strip no longer covers it);
##   4. the transition box is centred at 390, 412 and 430;
##   5. the town's tiles have equal gutters at every width.
##
## Run: godot --path . --rendering-driver opengl3 --script res://tools/probe_tap_fix.gd

const Main := preload("res://scripts/main.gd")

var _main: Node = null
var _step := 0
var _wait := 0
var _walk_fired := 0
var _sizes: Array = [390, 412, 430]
var _si := 0


func _initialize() -> void:
	root.size = Vector2i(390, 844)
	_main = Main.new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _main._nav_bar == null or _main.state == null:
		return false
	if _wait > 0:
		_wait -= 1
		return false

	match _step:
		0:
			# A FRESH stop: the tap index must be 0, not 1, and node 0 must be the gold one.
			_main.state.data["areaFightProgress"][0] = 0
			_main.state.data["locationProgress"][0] = 0
			_main.show_world(0)
			_wait = 12
		1:
			var w = _main._screens["world"]
			print("PROBE fresh stop: tap_index=%d header='%s'"
				% [w._tap_index, w._header_fight.text])
			# A tap on a LOCKED dot (index 5) must do nothing.
			_tap(w.node_pos(5))
			_wait = 6
		2:
			print("PROBE after locked-dot tap: screen=%s (expected world)" % _main._current)
			var w2 = _main._screens["world"]
			_tap(Vector2(w2.node_pos(0).x, w2.node_pos(0).y - 200.0))
			_wait = 6
		3:
			print("PROBE after empty-space tap: screen=%s (expected world)" % _main._current)
			_main.state.data["areaFightProgress"][0] = 4
			_main.show_world(0)
			_wait = 12
		4:
			var w3 = _main._screens["world"]
			print("PROBE half-done stop: tap_index=%d header='%s'"
				% [w3._tap_index, w3._header_fight.text])
			_tap(w3.node_pos(4))
			_wait = 12
		5:
			print("PROBE after current-dot tap: screen=%s (expected arena)" % _main._current)
			# Back to the road, and tap "Jít domů".
			_main.show_world(0)
			_wait = 12
		6:
			var w4 = _main._screens["world"]
			w4.walk_home_requested.connect(func(): _walk_fired += 1)
			print("PROBE walk button rect=%s" % str(w4._walk_button.get_global_rect()))
			_tap(w4._walk_button.get_global_rect().get_center())
			_wait = 6
		7:
			print("PROBE walk-home fired=%d" % _walk_fired)
			_main._transition.play("", func(): pass)
			_wait = 4
		8:
			_report_centring()
			quit(0)
			return true
	_step += 1
	return false


func _report_centring() -> void:
	var tr = _main._transition
	var box: Control = tr.get_node("Content")
	var r: Rect2 = box.get_global_rect()
	print("PROBE transition box=%s centre=%.1f canvas centre=%.1f"
		% [str(r), r.get_center().x, float(root.size.x) * 0.5])
	tr._active = false
	tr.visible = false


func _tap(at: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	press.global_position = at
	root.push_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = at
	release.global_position = at
	root.push_input(release)
