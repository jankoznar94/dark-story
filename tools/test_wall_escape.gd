extends SceneTree
## Jan's report: "whenever the hero hits an object he gets stuck in it and cannot
## move."
##
## Measured cause (tools/probe_stuck_*.gd): against a prop whose collision is a
## ConcavePolygonShape3D trimesh WITHOUT `backface_collision`, the hero ends up
## ~6 cm INSIDE the wall and is then frozen - 0.000 m of travel over 60-90 frames in
## four different directions while `velocity` still reads the full run speed, and
## `body_test_motion` reports the motion blocked even pointed away from the wall
## along the contact normal. He is not stopped BY the wall, he is trapped IN it.
## A 0.15 m teleport clear releases him instantly, so it is a penetration state.
##
## This test walks the hero into the props that ship and requires him to get OFF
## again. Stopping when you push into a wall is correct and is not what is asserted
## - the assertion is the ESCAPE.
##
## The three bars that matter, and why each is a number rather than a feeling:
##   * a wall must STOP him (a little travel, not a lot) - otherwise the fix would
##     be "let him walk through walls", which passes an escape-only test;
##   * he must then escape (>= 0.4 m);
##   * and he must keep escaping from every direction, not only the one he came in
##     by.
##
## Run: godot --headless --path --script res://tools/test_wall_escape.gd

const AXES := ["move_up", "move_down", "move_left", "move_right"]

## tag, start position, the stick to walk in with. Every start is 1.8-2.4 m clear of
## the prop so the walk-in itself is unobstructed.
const SPOTS := [
	{"tag": "training post (0,0,-3.2)", "start": Vector3(0, 0, -1.4), "push": "move_up"},
	{"tag": "south wall (3.2,0,-7.0)", "start": Vector3(3.2, 0, -4.6), "push": "move_up"},
	{"tag": "north wall (-3.0,0,-6.8)", "start": Vector3(-3.0, 0, -9.4), "push": "move_down"},
	# the arch is approached from the FAR side: from +Z the walk-in is blocked by the
	# south wall_segment at (3.2,0,-7.0) first (its rot_y 6 swings a 5.66 m span over
	# x = 0.4), so the approach line measured only 0.25 m of run-up. Computing the
	# blocking span from the level JSON and the prop AABBs is what settled it - do not
	# eyeball a start position here.
	{"tag": "ruin_arch (0.4,0,-8.6)", "start": Vector3(0.4, 0, -10.6), "push": "move_down"},
	{"tag": "ruin_stub_tall (-9.5,0,-1.0)", "start": Vector3(-6.6, 0, -1.0), "push": "move_right"},
]

var fails: Array[String] = []
var checks_run: int = 0


func _init() -> void:
	call_deferred("_run")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	checks_run += 1
	if cond:
		print("  OK   ", label, ("  " + detail) if detail else "")
	else:
		print("  FAIL ", label, "  ", detail)
		fails.append(label)


func _release_all() -> void:
	for a in AXES:
		Input.action_release(a)


func _walk(player: CharacterBody3D, press: String, frames: int) -> float:
	_release_all()
	if press != "":
		Input.action_press(press, 1.0)
	var start: Vector3 = player.global_position
	for i in frames:
		await physics_frame
	_release_all()
	return player.global_position.distance_to(start)


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	# geometry test: a walking body in the measurement space is the classic false
	# result here, and the level is what is under test
	main.clear_enemies()
	var player: CharacterBody3D = main.get_node("Player")

	var props: Array = []
	for c in main.get_children():
		if c is StaticBody3D and c.name != "FloorBody":
			props.append(c)
	print("level bodies in the scene: %d" % props.size())
	_ok("the level really built its props (a missing level would pass this test vacuously)",
		props.size() >= 40, "%d prop bodies" % props.size())

	# every built prop must use a trimesh WITH backface_collision - this is the
	# assertion that names the actual defect
	var missing_backface: Array = []
	var trimesh_props := 0
	for c in props:
		for ch in c.get_children():
			if ch is CollisionShape3D and ch.shape is ConcavePolygonShape3D:
				trimesh_props += 1
				if not ch.shape.backface_collision:
					missing_backface.append(c.name)
	print("props with a trimesh collision shape: %d" % trimesh_props)
	_ok("every trimesh prop has backface_collision on",
		missing_backface.is_empty(),
		"" if missing_backface.is_empty() else "missing on: %s" % str(missing_backface))
	_ok("the check actually saw trimesh props (not zero of them)",
		trimesh_props >= 20, "%d shapes inspected" % trimesh_props)

	for spot in SPOTS:
		var push: String = spot["push"]
		var opposite := "move_down" if push == "move_up" else (
			"move_up" if push == "move_down" else (
			"move_left" if push == "move_right" else "move_right"))
		var side := "move_left" if push != "move_left" else "move_right"
		print("== %s ==" % spot["tag"])
		player.global_position = spot["start"]
		player.velocity = Vector3.ZERO
		await physics_frame

		var in_travel: float = await _walk(player, push, 90)
		var stopped_at: Vector3 = player.global_position
		_ok("%s: the walk-in was unobstructed" % spot["tag"], in_travel > 0.3,
			"walked %.2f m in" % in_travel)
		_ok("%s: the prop STOPS him (he does not pass through it)" % spot["tag"],
			in_travel < 5.0, "walked %.2f m in" % in_travel)

		var out_travel: float = await _walk(player, opposite, 90)
		_ok("%s: he comes OFF the prop (backwards)" % spot["tag"], out_travel > 0.4,
			"escaped %.2f m from %s" % [out_travel, stopped_at])

		# and from a direction he did not arrive by
		player.global_position = spot["start"]
		player.velocity = Vector3.ZERO
		await physics_frame
		await _walk(player, push, 90)
		var side_travel: float = await _walk(player, side, 60)
		_ok("%s: he comes OFF it sideways too (not a one-way trap)" % spot["tag"],
			side_travel > 0.4, "sidestepped %.2f m" % side_travel)
		print("")

	# the hero must be back on the floor, not riding on top of a prop
	_ok("the hero is on the floor at the end, not on top of a prop",
		player.is_on_floor() or player.global_position.y < 0.05,
		"y %.3f on_floor %s" % [player.global_position.y, str(player.is_on_floor())])

	print("")
	print("checks executed: ", checks_run)
	if fails.is_empty() and checks_run >= 24:
		print("WALL_ESCAPE_ALL_PASS=true")
	else:
		for f in fails:
			print("FAIL: ", f)
		if checks_run < 24:
			print("FAIL: only %d checks ran - not everything was exercised" % checks_run)
		print("WALL_ESCAPE_ALL_PASS=false")
	quit()
