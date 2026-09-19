extends RefCounted
## Builds the world from data, not from hand-placed nodes.
##
## WHY: the level is where the project will change most often, and Jan has no
## time or practice to click a scene together - he is the tester and he is often
## away from a PC. So a level is a TEXT FILE (levels/*.json) that describes which
## prop goes where, and this class turns it into nodes. Changing the layout means
## editing JSON; adding a new area means adding a file.
##
## Every prop is a static body with a trimesh-collision shape, built from the
## mesh's own faces, so combat and movement respect the geometry rather than a
## guessed box. That matters because reach and spacing are the whole game here.

const LEVEL := "res://levels/training_ground.json"


static func load_level(path: String = LEVEL) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("level: cannot open %s" % path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed == null:
		push_error("level: invalid JSON in %s" % path)
		return {}
	# the file is a list so several areas can live in one document
	if parsed is Array:
		return parsed[0] if parsed.size() > 0 else {}
	return parsed


static func build(parent: Node3D, data: Dictionary) -> Array:
	## Returns the created nodes so a test can assert on them.
	var created: Array = []
	var groups: Array = data.get("groups", [])
	for g in groups:
		var prop := str(g.get("prop", ""))
		var pair := str(g.get("pair_with", ""))
		if prop == "":
			continue
		if bool(g.get("keep_existing", false)):
			continue          # e.g. the training posts, spawned by main.gd itself
		for p in g.get("placements", []):
			var pos := _vec(p.get("pos", [0, 0, 0]))
			var rot_y := float(p.get("rot_y", 0.0))
			var node := _spawn(parent, prop, pos, rot_y)
			if node != null:
				created.append(node)
				if pair != "":
					var top := _spawn(parent, pair, pos, rot_y)
					if top != null:
						created.append(top)
	return created


static func _vec(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


static func _spawn(parent: Node3D, prop: String, pos: Vector3, rot_y: float) -> Node3D:
	var path := "res://assets/props/%s.obj" % prop
	if not ResourceLoader.exists(path):
		push_warning("level: missing prop %s" % path)
		return null
	var mesh: Mesh = load(path)
	if mesh == null:
		push_warning("level: could not load %s" % path)
		return null

	var body := StaticBody3D.new()
	body.name = prop
	body.position = pos
	body.rotation_degrees = Vector3(0.0, rot_y, 0.0)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	body.add_child(mi)

	# collision from the actual triangles, not a bounding box: a wall should stop
	# you where the wall is, and a low ruin stub should be walkable around
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	cs.shape = shape
	body.add_child(cs)

	parent.add_child(body)
	return body
