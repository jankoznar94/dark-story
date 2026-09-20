extends SceneTree
## WHAT IS ACTUALLY STANDING AT A CORPSE AFTER A KILL.
##
## Jan's report (Sept 2026): "when an enemy dies, apart from its dead body a black
## object appears as well. We do not want that." The headless flow probe says the
## corpse is the monster's own model and that nothing else is spawned, so the extra
## object is NOT a new node - it is something already inside the monster's own
## subtree that only becomes visible once the rig is tipped over (a corpse lies at
## eye height, where a standing rig never showed it).
##
## So this probe dumps the WHOLE subtree of the dead monster: every node, its class,
## its world transform, its visibility, and for every MeshInstance3D its material
## colour, its AABB and whether it is skinned. A mesh nobody expected shows up here
## as a line with an albedo colour, which is exactly what "a black object" is.
##
## Run: godot --headless --path . --script res://tools/probe_corpse_visual.gd

const DARK_LIMIT := 0.12   ## albedo below this reads as black against the ground

var main: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame

	var player: Node = main.get_node("Player")
	var loot: Node = main.loot
	var kill: Node = null
	for e in main._enemies:
		if kill == null and e.monster_name == "Ghoul":
			kill = e
		else:
			e.global_position = Vector3(e.global_position.x, 0.0,
				e.global_position.z + 200.0)
	kill.global_position = Vector3(0, 0, -1.5)
	player.global_position = Vector3(0, 0, 1.5)

	# --- BEFORE: the living monster, for a baseline
	for i in 3:
		await physics_frame
	print("=== LIVING %s (hp %.0f) ===" % [kill.monster_name, kill.hp])
	_dump(kill, 0)

	# --- KILL IT and let the death clip freeze, the tip-over settle, and the
	# corpse exist for as long as the player needs to walk up to it.
	kill.take_damage(99999.0)
	for i in 90:
		await physics_frame
	print("\n=== AFTER DEATH, %d physics frames later ===" % 90)
	print("dead=%s  hp=%.0f  clip=%s  speed_scale=%.2f"
		% [str(kill.is_dead()), kill.hp, kill.current_clip(),
			kill.anim.speed_scale if kill.anim else -1.0])
	_dump(kill, 0)

	# --- the corpse bundle loot_body put on the monster
	if loot.body_count() > 0:
		print("\n=== CORPSE BUNDLE (loot_body) ===")
		_dump(loot.bodies()[0], 0)

	# --- EVERYTHING dark in the whole scene, so a black object that is NOT under
	# the monster (a leftover, a shadow mesh, a stray) is caught too.
	print("\n=== DARK MESHES IN THE WHOLE SCENE (albedo < %.2f) ===" % DARK_LIMIT)
	_scan_dark(main)

	print("\n=== BOUNDS OF THE DEAD MONSTER'S MESHES ===")
	var bb := _mesh_bounds(kill)
	print("  y: %.2f .. %.2f   x: %.2f .. %.2f   z: %.2f .. %.2f"
		% [bb.position.y, bb.end.y, bb.position.x, bb.end.x, bb.position.z, bb.end.z])

	# --- can the player SEE it? a ray from the hero's eye to the corpse
	var cam: Camera3D = main.get_node("Camera")
	var at: Vector2 = cam.unproject_position(kill.global_position + Vector3(0, 0.3, 0))
	print("\nscreen position of the corpse: %s (viewport %s)"
		% [str(at), str(get_root().get_visible_rect().size)])
	print("PROBE_CORPSE_VISUAL_DONE")
	quit()


func _dump(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var line := pad + "- " + str(n.name) + "  [" + n.get_class() + "]"
	if n is Node3D:
		var t := (n as Node3D).global_transform
		line += "  pos=%s rot=%s scale=%s" % [_v(t.origin),
			_v((n as Node3D).global_rotation_degrees), _v((n as Node3D).scale)]
	if n is Node3D and not (n as Node3D).visible:
		line += "  VISIBLE=false"
	if n is MeshInstance3D:
		var m := n as MeshInstance3D
		var aabb := m.get_aabb()
		line += "  mesh=%s aabb_pos=%s aabb_size=%s" % [
			m.mesh.get_class() if m.mesh else "null", _v(aabb.position), _v(aabb.size)]
		var mat: Material = m.material_override if m.material_override != null \
			else (m.mesh.surface_get_material(0) if m.mesh and m.mesh.get_surface_count() > 0 else null)
		if mat is StandardMaterial3D:
			line += "  albedo=%s" % str((mat as StandardMaterial3D).albedo_color)
		else:
			line += "  material=%s" % (mat.get_class() if mat != null else "none")
	print(line)
	for c in n.get_children():
		_dump(c, depth + 1)


## Every mesh in the scene whose material reads as black. A corpse-shaped defect
## that is NOT part of the monster shows up here and nowhere else.
func _scan_dark(n: Node) -> void:
	var found := 0
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		if cur is MeshInstance3D:
			var m := cur as MeshInstance3D
			var mat: Material = m.material_override
			if mat == null and m.mesh != null and m.mesh.get_surface_count() > 0:
				mat = m.mesh.surface_get_material(0)
			if mat is StandardMaterial3D:
				var a: Color = (mat as StandardMaterial3D).albedo_color
				if a.r < DARK_LIMIT and a.g < DARK_LIMIT and a.b < DARK_LIMIT:
					found += 1
					print("  DARK %s  albedo=%s  world_pos=%s  parent=%s" % [
						str(m.get_path()), str(a), _v(m.global_transform.origin),
						str(m.get_parent().name)])
	print("  total dark meshes: %d" % found)


func _mesh_bounds(node: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		if cur is MeshInstance3D:
			var m := cur as MeshInstance3D
			if m.mesh == null:
				continue
			var w: AABB = m.global_transform * m.get_aabb()
			if first:
				out = w
				first = false
			else:
				out = out.merge(w)
	return out


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
