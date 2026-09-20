extends SceneTree
## THE REAL TAP ON A CORPSE, in a real window, with a real GUI hit test.
##
## The headless flow probe calls `loot.open_at_screen()` DIRECTLY, which skips the
## input path entirely - and that is where the defect lives: the tap goes through
## `_unhandled_input`, the ray then hits whatever Area3D is closest, and the walk up
## from that collider has to find a body the loot manager KNOWS. So this probe
## dispatches real `InputEventScreenTouch` events through the viewport (which a
## `--headless` run cannot do at all) and reports what the game did with them.
##
## It also dumps where the ray actually landed, so "the tap hit a phantom" is a
## printed fact rather than a theory.
##
## Run: DISPLAY=:0 godot --path . --rendering-driver opengl3 --resolution 960x540 \
##        --script res://tools/probe_loot_tap.gd

var main: Node
var cam: Camera3D
var _step := 0
var _t := 0.0
var _fails: Array[String] = []
## Set when the window turns out to be gone right after the tap that opened it -
## the defect under test.
var _was_still_open := false


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	cam = main.get_node("Camera")
	cam.set_process(false)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  OK   ", label, ("  " + detail) if detail else "")
	else:
		print("  FAIL ", label, "  ", detail)
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta
	match _step:
		0:
			if _t < 1.2:
				return false
			_setup_kill()
			_step = 1
			_t = 0.0
		1:
			if _t < 1.8:
				return false
			_frame_camera()
			_step = 2
			_t = 0.0
		2:
			if _t < 0.4:
				return false
			_report_state("BEFORE ANY TAP")
			_tap_corpse()
			_step = 3
			_t = 0.0
		3:
			if _t < 0.5:
				return false
			_report_panel("AFTER THE TAP ON THE CORPSE")
			_was_still_open = main.get_node("HUD").loot_panel.open
			_tap_corpse_again()
			_step = 4
			_t = 0.0
		4:
			if _t < 0.5:
				return false
			_report_panel("AFTER A SECOND TAP (a later tap outside MAY close it)", false)
			# The second tap lands where the corpse is, which is OUTSIDE the window,
			# and by now the open guard has expired - so closing is CORRECT here.
			# The defect was the window closing on the tap that OPENED it, and that
			# is what the guard has to prevent: the window must still be up at the
			# point the second tap is sent.
			var hud2: Node = main.get_node("HUD")
			_ok("the tap that opened the body did NOT also close it", _was_still_open)
			_ok("a later tap outside the window closes it", not hud2.loot_panel.open)
			_shot("user://tap_probe.png")
			print("TAP_PROBE_DONE fails=%d %s" % [_fails.size(), str(_fails)])
			return true
	return false


func _setup_kill() -> void:
	var player: Node = main.get_node("Player")
	var kill: Node = null
	for e in main._enemies:
		if kill == null and e.monster_name == "Ghoul":
			kill = e
		else:
			e.global_position = Vector3(e.global_position.x, 0.0,
				e.global_position.z + 200.0)
	kill.global_position = Vector3(0, 0, -1.5)
	player.global_position = Vector3(0, 0, 2.6)
	kill.take_damage(99999.0)


func _frame_camera() -> void:
	var body = main.loot.bodies()[0]
	cam.global_position = body.global_position + Vector3(0.0, 3.4, 4.4)
	cam.look_at(body.global_position + Vector3(0, 0.45, 0), Vector3.UP)


## Where the game thinks the corpse is on screen, and what the world ray finds
## there. A ray that lands on something the loot manager does not own is exactly
## the "nothing happens" report.
func _report_state(label: String) -> void:
	print("== %s" % label)
	# WHO closes the window? `closed` fires from set_open(false) and this stack shows
	# the caller - guessing here costs a whole session.
	var lp0: Control = main.get_node("HUD").loot_panel
	if not lp0.closed.is_connected(_on_panel_closed):
		lp0.closed.connect(_on_panel_closed)
	var player: Node = main.get_node("Player")
	var body = main.loot.bodies()[0]
	var at: Vector2 = cam.unproject_position(body.global_position + Vector3(0, 0.3, 0))
	print("   corpse world %s -> screen %s" % [_v(body.global_position), str(at)])
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var from: Vector3 = cam.project_ray_origin(at)
	var dir: Vector3 = cam.project_ray_normal(at)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	q.collision_mask = 1 | 4
	q.collide_with_areas = true
	var res: Dictionary = space.intersect_ray(q)
	if res.is_empty():
		print("   ray: hit NOTHING")
	else:
		var c: Object = res["collider"]
		print("   ray: hit %s (%s)  parent chain: %s"
			% [str((c as Node).name), (c as Node).get_class(), _chain(c as Node)])
	print("   bodies the loot manager knows: %d" % main.loot.body_count())
	for b in main.loot.bodies():
		print("     body %s  pos %s  items %d" % [str(b.name), _v(b.global_position),
			main.loot.items_in(b).size()])
	print("   player at %s, distance to body %.2f (OPEN_RANGE %.2f)"
		% [_v(player.global_position),
			body.global_position.distance_to(player.global_position), main.loot.OPEN_RANGE])
	# every Area3D on the corpse layer in the scene - the phantom stand-in shows up
	# here as an extra one at the same spot.
	var areas: Array = []
	_collect_areas(main, areas)
	print("   corpse-layer Area3D nodes in the scene: %d" % areas.size())
	for a in areas:
		print("     %s  world %s  owner_known=%s" % [str((a as Node).get_path()),
			_v((a as Node3D).global_position), str(main.loot.bodies().has((a as Node).get_parent()))])


func _collect_areas(n: Node, out: Array) -> void:
	if n is Area3D and (n as Area3D).collision_layer == 4:
		out.append(n)
	for c in n.get_children():
		_collect_areas(c, out)


func _chain(n: Node) -> String:
	var parts: Array[String] = []
	var cur: Node = n
	while cur != null:
		parts.append(str(cur.name))
		cur = cur.get_parent()
	return " < ".join(parts)


## A REAL touch event through the viewport. Index 1: on a phone the first finger
## belongs to the joystick, and main.gd only accepts a world tap from an extra one.
func _tap_corpse() -> void:
	var body = main.loot.bodies()[0]
	var at: Vector2 = cam.unproject_position(body.global_position + Vector3(0, 0.3, 0))
	_dispatch(at, 1)


func _tap_corpse_again() -> void:
	var body = main.loot.bodies()[0]
	var at: Vector2 = cam.unproject_position(body.global_position + Vector3(0, 0.3, 0))
	_dispatch(at, 1)


func _dispatch(at: Vector2, index: int) -> void:
	var hud: Node = main.get_node("HUD")
	print("   dispatching touch idx=%d at %s (panel_open before=%s)"
		% [index, str(at), str(hud.panel_open())])
	# 1. the whole input pipeline, as the OS would do it
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.pressed = pressed
		ev.index = index
		ev.position = at
		Input.parse_input_event(ev)
	if not hud.loot_panel.open:
		# 2. the same event handed straight to the handler, to separate "the event
		# never arrives" (an X11 run has no touchscreen, so the engine may drop it)
		# from "the handler does nothing with it".
		print("   pipeline did not open it - calling main._unhandled_input directly")
		var direct := InputEventScreenTouch.new()
		direct.pressed = true
		direct.index = index
		direct.position = at
		main._unhandled_input(direct)
		print("   direct call -> panel_open=%s" % str(hud.panel_open()))


func _report_panel(label: String, expect_open: bool = true) -> void:
	var hud: Node = main.get_node("HUD")
	var lp: Control = hud.loot_panel
	print("== %s" % label)
	print("   panel_open=%s  loot.open=%s  loot.visible=%s  size=%s"
		% [str(hud.panel_open()), str(lp.open), str(lp.visible), str(lp.size)])
	print("   rows=%d  body=%s" % [lp._rows.size(),
		str(lp._body.name) if lp._body != null else "null"])
	print("   joystick.visible=%s  attack(btn down).visible=%s  loot_button.visible=%s"
		% [str(hud.joystick.visible), str(hud._buttons["down"].visible),
			str(hud.loot_button.visible)])
	if not expect_open:
		return
	_ok("a tap on the corpse opens the loot window", lp.open)
	_ok("the loot window is VISIBLE", lp.visible)
	if lp.open:
		_ok("the window has a rect on screen", lp.size.x > 100.0 and lp.size.y > 60.0)


func _shot(path: String) -> void:
	var img := get_root().get_texture().get_image()
	img.save_png(path)
	print("CAPTURED ", ProjectSettings.globalize_path(path))


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


## Called from loot_panel's `closed` signal: print the call stack so the code that
## dismissed the window is named rather than guessed.
func _on_panel_closed() -> void:
	print("   !! loot panel CLOSED. stack:")
	for l in get_stack():
		print("      %s:%d  %s()" % [str(l.get("source", "?")), int(l.get("line", 0)),
			str(l.get("function", "?"))])
