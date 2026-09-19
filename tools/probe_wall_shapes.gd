extends SceneTree
## WHICH PART of the trimesh makes the hero stick?
##
## probe_wall_escape.gd reproduced Jan's report exactly, and only on the trimesh
## props: pushed against `wall_segment` the hero stays at the same position for
## every later frame while `velocity` reads the full 2.600 m/s. The box-shaped
## training post releases normally.
##
## So this builds THREE copies of the same wall with three collision shapes and
## runs the identical walk-in / reverse-stick sequence against each:
##   A  ConcavePolygonShape3D          - what ships today
##   B  ConcavePolygonShape3D + backface_collision - one flag different
##   C  BoxShape3D from the mesh AABB  - a solid convex shape
##
## If only A sticks, the shape is the cause and B/C say which property fixes it.
##
## Run: godot --headless --path --script res://tools/probe_wall_shapes.gd

const AXES := ["move_up", "move_down", "move_left", "move_right"]
const WALL := "res://assets/props/wall_segment.obj"
## INSIDE the 34 x 34 floor. The first version of this probe put the copies at
## z = -30, i.e. off the floor, so the hero was FALLING while he walked and every
## copy "released" - a control that measured the wrong thing. Keep them on the
## floor: the shipped arena spans -17..+17 in x and z.
const BASE := Vector3(0.0, 0.0, -12.0)


func _init() -> void:
	call_deferred("_run")


func _mk_wall(main: Node, tag: String, kind: String, x: float) -> Node3D:
	var mesh: Mesh = load(WALL)
	var body := StaticBody3D.new()
	body.name = "Probe_" + tag
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	if kind == "box":
		var bs := BoxShape3D.new()
		bs.size = mesh.get_aabb().size
		cs.shape = bs
	else:
		var cps := ConcavePolygonShape3D.new()
		cps.set_faces(mesh.get_faces())
		# the flag under test: without it a trimesh only collides from its
		# front face, so a body that has entered it may find no exit contact
		cps.backface_collision = kind == "trimesh_backface"
		cs.shape = cps
	body.add_child(cs)
	body.position = Vector3(x, BASE.y, BASE.z)
	main.add_child(body)
	print("  built %s at %s  aabb size %s  faces %d  backface %s"
		% [tag, body.position, mesh.get_aabb().size, mesh.get_faces().size() / 3,
		   str(cs.shape.backface_collision) if cs.shape is ConcavePolygonShape3D else "n/a"])
	return body


func _phase(player: CharacterBody3D, tag: String, presses: Array, frames: int) -> float:
	for a in AXES:
		Input.action_release(a)
	for p in presses:
		Input.action_press(p[0], p[1])
	var start: Vector3 = player.global_position
	var prev: Vector3 = start
	var stall := 0
	for i in frames:
		await physics_frame
		var p: Vector3 = player.global_position
		if i > 5 and p.distance_to(prev) < 0.002:
			stall += 1
		prev = p
	var travelled: float = player.global_position.distance_to(start)
	print("    %-22s travelled %6.3f m  stalled %3d/%d  end (%.2f, %.2f)  v %.3f  on_wall %s"
		% [tag, travelled, stall, frames, player.global_position.x, player.global_position.z,
		   player.velocity.length(), str(player.is_on_wall())])
	return travelled


func _try(player: CharacterBody3D, tag: String, x: float) -> void:
	print("== %s ==" % tag)
	player.global_position = Vector3(x, BASE.y, BASE.z + 1.9)
	player.velocity = Vector3.ZERO
	player.facing = Vector3(0, 0, -1)
	await physics_frame
	var in_travel: float = await _phase(player, "walk in", [["move_up", 1.0]], 90)
	var out_travel: float = await _phase(player, "reverse (escape)", [["move_down", 1.0]], 90)
	var verdict := "RELEASES" if out_travel > 0.5 else "STUCK"
	print("    -> walked in %.3f m, escaped %.3f m   %s" % [in_travel, out_travel, verdict])
	print("")
	for a in AXES:
		Input.action_release(a)


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.clear_enemies()
	var player: CharacterBody3D = main.get_node("Player")

	print("wall_segment mesh aabb: %s" % str((load(WALL) as Mesh).get_aabb()))
	print("")
	_mk_wall(main, "A trimesh (ships today)", "trimesh", -8.0)
	_mk_wall(main, "B trimesh + backface", "trimesh_backface", 0.0)
	_mk_wall(main, "C box shape", "box", 8.0)
	await physics_frame

	await _try(player, "A  ConcavePolygonShape3D  (what ships)", -8.0)
	await _try(player, "B  ConcavePolygonShape3D + backface_collision", 0.0)
	await _try(player, "C  BoxShape3D from the AABB", 8.0)

	print("WALL_SHAPES_PROBE_DONE")
	quit()
