extends SceneTree
## Headless test for the bindable d-pad cross.
## Run: godot --headless --path . --script res://tools/test_controls.gd
##
## Checks the BINDING MODEL (defaults, swap, persistence) and the LAYOUT at the
## real landscape resolutions the game will actually run at. Headless always
## reports a square viewport, so the layout is driven with explicit sizes - the
## landscape phone case is the one that matters and must not go untested.

const ControlBindings := preload("res://scripts/controls.gd")

## width x height in landscape, as real devices report them
const DEVICES := [
	["landscape phone 1080p", Vector2(1920, 1080)],
	["modern phone 2400x1080", Vector2(2400, 1080)],
	["tall phone 2340x1080", Vector2(2340, 1080)],
	["small phone 16:9", Vector2(1280, 720)],
	["tablet 16:10", Vector2(2560, 1600)],
]

var fails: Array[String] = []
var checks_run: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_bindings()
	await _test_layout()
	print("")
	print("checks executed: ", checks_run)
	if fails.is_empty() and checks_run >= 25:
		print("CONTROLS_ALL_PASS=true")
	else:
		for f in fails:
			print("FAIL: ", f)
		if checks_run < 25:
			print("FAIL: only %d checks ran - not everything was exercised" % checks_run)
		print("CONTROLS_ALL_PASS=false")
	quit()


func _ok(label: String, cond: bool, detail: String = "") -> void:
	checks_run += 1
	if cond:
		print("  OK   ", label, ("  " + detail) if detail else "")
	else:
		print("  FAIL ", label, "  ", detail)
		fails.append(label)


func _test_bindings() -> void:
	print("== binding model ==")
	var b := ControlBindings.new()
	b.reset_to_defaults()

	_ok("default down = attack", b.action_for("down") == "attack")
	_ok("default up = potion", b.action_for("up") == "potion")
	_ok("default left = skill_1", b.action_for("left") == "skill_1")
	_ok("default right = skill_2", b.action_for("right") == "skill_2")

	# remap: attack to the up button. Up's old occupant must land on down,
	# otherwise a button would silently go dead.
	b.assign("up", "attack")
	_ok("attack moved to up", b.action_for("up") == "attack")
	_ok("old slot swapped instead of dying", b.action_for("down") == "potion",
		"down=%s" % b.action_for("down"))
	var occupied: Array = []
	for s in ControlBindings.SLOTS:
		occupied.append(b.action_for(s))
	var distinct: Array = []
	for v in occupied:
		if not distinct.has(v):
			distinct.append(v)
	_ok("no action appears twice", occupied.size() == distinct.size(), str(occupied))

	b.assign("left", "teleport_home")
	_ok("unknown action rejected", b.action_for("left") == "skill_1")

	b.assign("right", "none")
	_ok("slot can be emptied", b.action_for("right") == "none")
	b.reset_to_defaults()
	_ok("reset restores the cross", b.action_for("right") == "skill_2")

	b.assign("left", "potion")
	var b2 := ControlBindings.new()
	_ok("binding survives a reload", b2.action_for("left") == "potion",
		"reloaded left=%s" % b2.action_for("left"))
	b2.reset_to_defaults()


func _test_layout() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var hud: Node = main.get_node("HUD")
	var slots: Array = ControlBindings.SLOTS

	for device in DEVICES:
		var name: String = device[0]
		var vs: Vector2 = device[1]
		hud._layout(vs)
		await process_frame

		print("== %s  (%d x %d) ==" % [name, int(vs.x), int(vs.y)])

		var pos: Dictionary = {}
		var sizes: Array = []
		for s in slots:
			var btn: Button = hud._buttons[s]
			pos[s] = btn.position + btn.size * 0.5
			sizes.append(btn.size)

		_ok("%s: four buttons" % name, pos.size() == 4)
		_ok("%s: all the same size" % name,
			absf(sizes[0].x - sizes[1].x) < 0.01 and absf(sizes[0].x - sizes[2].x) < 0.01,
			str(sizes[0]))
		_ok("%s: round (not oval)" % name, absf(sizes[0].x - sizes[0].y) < 0.01)

		var cx: float = (pos["left"].x + pos["right"].x) * 0.5
		var cy: float = (pos["up"].y + pos["down"].y) * 0.5
		_ok("%s: forms a cross" % name,
			absf(pos["up"].x - cx) < 0.01 and absf(pos["down"].x - cx) < 0.01 and
			absf(pos["left"].y - cy) < 0.01 and absf(pos["right"].y - cy) < 0.01,
			"up=(%.0f,%.0f) down=(%.0f,%.0f) left=(%.0f,%.0f) right=(%.0f,%.0f)"
			% [pos["up"].x, pos["up"].y, pos["down"].x, pos["down"].y,
			   pos["left"].x, pos["left"].y, pos["right"].x, pos["right"].y])
		_ok("%s: attack is the bottom button" % name, pos["down"].y > pos["up"].y)
		_ok("%s: buttons in lower-right thumb zone" % name,
			pos["left"].x > vs.x * 0.55 and pos["up"].y > vs.y * 0.45)
		_ok("%s: nothing in the screen centre" % name, pos["up"].x > vs.x * 0.6)
		_ok("%s: buttons >= 60 px" % name, sizes[0].x >= 60.0, "%.0f px" % sizes[0].x)

		var overlap_pair := ""
		for a in range(slots.size()):
			for b in range(a + 1, slots.size()):
				var ra := Rect2(hud._buttons[slots[a]].position, hud._buttons[slots[a]].size)
				var rb := Rect2(hud._buttons[slots[b]].position, hud._buttons[slots[b]].size)
				if ra.intersects(rb):
					overlap_pair = "%s/%s" % [slots[a], slots[b]]
		_ok("%s: no two buttons overlap" % name, overlap_pair == "", overlap_pair)

		var offscreen := ""
		for s in slots:
			var r := Rect2(hud._buttons[s].position, hud._buttons[s].size)
			if r.position.x < 0.0 or r.position.y < 0.0 or r.end.x > vs.x or r.end.y > vs.y:
				offscreen += "%s " % s
		_ok("%s: every button fully on screen" % name, offscreen == "", offscreen)

		var joy: Control = hud.joystick
		_ok("%s: joystick lower-left" % name,
			joy.position.x < vs.x * 0.3 and joy.position.y > vs.y * 0.4, str(joy.position))

		var joy_rect := Rect2(joy.position, joy.size)
		var ov := false
		for s in slots:
			if joy_rect.intersects(Rect2(hud._buttons[s].position, hud._buttons[s].size)):
				ov = true
		_ok("%s: joystick does not overlap buttons" % name, not ov)
		_ok("%s: joystick is not in the button zone" % name,
			joy.position.x + joy.size.x < pos["left"].x - sizes[0].x * 0.5,
			"joy ends %.0f, buttons start %.0f" % [joy.position.x + joy.size.x, pos["left"].x])

	print("")
	print("== input wiring ==")
	var down: Button = hud._buttons["down"]
	var act: String = hud.bindings.action_for("down")
	down.button_down.emit()
	var after_down: bool = Input.is_action_pressed(act)
	down.button_up.emit()
	var after_up: bool = Input.is_action_pressed(act)
	_ok("button press drives the Input Map action", after_down, act)
	_ok("button release clears it", not after_up)
