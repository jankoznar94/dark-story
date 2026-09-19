extends SceneTree
## Which prop collision shape survives a walk-in?
##
## Established by measurement:
##   * the hero STOPS correctly at the training post (a BoxShape3D prop);
##   * on the shipped `wall_segment` (a 240-face ConcavePolygonShape3D trimesh) he
##     ends up ~6 cm inside the wall and is then frozen: 0.000 m of travel in four
##     different directions over 60-90 frames each, while `velocity` still reads
##     2.600 m/s. `body_test_motion` from that pose reports the motion BLOCKED even
##     when it points away along the contact normal, and a 0.15 m teleport clear
##     releases him immediately (2.380 m walked out).
##   * safe_margin does not change it (0.001 / 0.0005 / 0.0001 / 0.0 all stuck).
##
## So the fix has to stop the body ever getting embedded. This probe rebuilds the
## WHOLE shipped level four times, once per collision shape, and runs the identical
## walk-in / escape sequence at three spots. A mode only counts if it RELEASES at
## every spot - and it must still stop the hero at the wall rather than letting him
## walk through it.
##
## Run: godot --headless --path --script res://tools/probe_fix_candidates.gd

const AXES := ["move_up", "move_down", "move_left", "move_right"]
const LEVEL := "res://levels/training_ground.json"

## name, start position, stick to walk in with, and the direction label
const SPOTS := [
	{"tag": "south wall (3.2,0,-7.0) from -Z", "start": Vector3(3.2, 0, -4.6), "push": "move_up"},
	{"tag": "north wall (-3.0,0,-6.8) from +Z", "start": Vector3(-3.0, 0, -9.4), "push": "move_down"},
	{"tag": "ruin_arch (0.4,0,-8.6) from -Z", "start": Vector3(0.4, 0, -6.2), "push": "move_up"},
	{"tag": "ruin_stub_tall (-9.5,0,-1.0) from +X", "start": Vector3(-6.6, 0, -1.0), "push": "move_right"},
]


func _init() -> void:
	call_deferred("_run")


func _release_all() -> void:
	for a in AXES:
		Input.action_release(a)


## Rebuilds the level from the same JSON the game uses, with one collision mode.
func _rebuild(main: Node, mode: String) -> int:
	for n in main._level_nodes:
		if is_instance_valid(n):
			n.queue_free()
	main._level_nodes.clear()
	await process_frame

	var f := FileAccess.open(LEVEL, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	var data: Dictionary = parsed[0] if parsed is Array else parsed

	var made := 0
	for g in data.get("groups", []):
		var prop := str(g.get("prop", ""))
		if prop == "" or bool(g.get("keep_existing", false)):
			continue
		var pair := str(g.get("pair_with", ""))
		for p in g.get("placements", []):
			var pos := Vector3(float(p["pos"][0]), float(p["pos"][1]), float(p["pos"][2]))
			var ry := float(p.get("rot_y", 0.0))
			if _spawn(main, prop, pos, ry, mode) != null:
				made += 1
			if pair != "" and _spawn(main, pair, pos, ry, mode) != null:
				made += 1
	return made


func _spawn(main: Node, prop: String, pos: Vector3, rot_y: float, mode: String) -> Node3D:
	var path := "res://assets/props/%s.obj" % prop
	if not ResourceLoader.exists(path):
		return null
	var mesh: Mesh = load(path)
	var body := StaticBody3D.new()
	body.name = prop
	body.position = pos
	body.rotation_degrees = Vector3(0, rot_y, 0)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	match mode:
		"trimesh":
			var cps := ConcavePolygonShape3D.new()
			cps.set_faces(mesh.get_faces())
			cs.shape = cps
		"trimesh_backface":
			var cps2 := ConcavePolygonShape3D.new()
			cps2.set_faces(mesh.get_faces())
			cps2.backface_collision = true
			cs.shape = cps2
		"convex":
			cs.shape = mesh.create_convex_shape()
		"box":
			var bs := BoxShape3D.new()
			bs.size = mesh.get_aabb().size
			cs.shape = bs
	body.add_child(cs)
	main.add_child(body)
	main._level_nodes.append(body)
	return body


func _phase(player: CharacterBody3D, press: String, frames: int) -> Dictionary:
	_release_all()
	if press != "":
		Input.action_press(press, 1.0)
	var start: Vector3 = player.global_position
	var prev: Vector3 = start
	var stall := 0
	for i in frames:
		await physics_frame
		var p: Vector3 = player.global_position
		if i > 4 and p.distance_to(prev) < 0.002:
			stall += 1
		prev = p
	_release_all()
	return {"travel": player.global_position.distance_to(start), "stall": stall, "frames": frames}


func _try_spot(player: CharacterBody3D, spot: Dictionary) -> bool:
	var push: String = spot["push"]
	var opposite := "move_down" if push == "move_up" else ("move_up" if push == "move_down" else ("move_left" if push == "move_right" else "move_right"))
	player.global_position = spot["start"]
	player.velocity = Vector3.ZERO
	await physics_frame
	var in_r: Dictionary = await _phase(player, push, 90)
	var blocked_at: Vector3 = player.global_position
	var out_r: Dictionary = await _phase(player, opposite, 90)
	var side_r: Dictionary = await _phase(player, "move_left" if push != "move_left" else "move_right", 60)
	var ok: bool = float(out_r["travel"]) > 0.4
	print("      %-38s walk-in %5.2f m (stalled %2d/%d)  |  escape %5.2f m -> %s  |  sidestep %5.2f m"
		% [spot["tag"], in_r["travel"], in_r["stall"], in_r["frames"],
		   out_r["travel"], "RELEASES" if ok else "**STUCK**", side_r["travel"]])
	print("        stopped at %s" % blocked_at)
	return ok


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.clear_enemies()
	var player: CharacterBody3D = main.get_node("Player")

	for mode in ["trimesh", "trimesh_backface", "convex", "box"]:
		var made: int = await _rebuild(main, mode)
		print("== collision mode: %s  (%d prop bodies rebuilt) ==" % [mode, made])
		var all_ok := true
		for spot in SPOTS:
			var ok: bool = await _try_spot(player, spot)
			all_ok = all_ok and ok
		print("    => %s at every spot: %s" % [mode, "YES" if all_ok else "NO"])
		print("")

	print("FIX_CANDIDATES_PROBE_DONE")
	quit()
