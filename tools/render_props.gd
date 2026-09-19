extends SceneTree
## Render the modular prop set to a contact sheet so "does a tree look like a
## tree" is checkable instead of asserted.
##   godot --path . --rendering-driver opengl3 --resolution 1200x420 \
##         --script res://tools/render_props.gd

var t := 0.0
var shots := 0
var cam: Camera3D
var root3: Node3D


func _initialize() -> void:
	print("PROPS_RENDER_INIT")


func _boot() -> void:
	root3 = Node3D.new()
	root.add_child(root3)

	cam = Camera3D.new()
	root3.add_child(cam)
	cam.fov = 30.0

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46.0, -40.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.94, 0.84)
	root3.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, 140.0, 0.0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.66, 0.72, 0.9)
	root3.add_child(fill)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.34, 0.36, 0.40)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.42, 0.44)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)

	# a checkerboard ground so scale is readable
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 12)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.31, 0.28)
	ground.material_override = gm
	root3.add_child(ground)

	var files := [
		"res://assets/props/tree_conifer_trunk.obj",
		"res://assets/props/tree_conifer_canopy.obj",
		"res://assets/props/tree_dead.obj",
		"res://assets/props/rock_boulder.obj",
		"res://assets/props/rock_small.obj",
		"res://assets/props/wall_segment.obj",
		"res://assets/props/pillar.obj",
	]
	var x := -9.0
	for f in files:
		var mi := MeshInstance3D.new()
		var m = load(f)
		if m == null:
			print("PROPS_LOAD_FAILED ", f)
			continue
		mi.mesh = m
		mi.position = Vector3(x, 0.0, 0.0)
		root3.add_child(mi)
		print("PROPS_PLACED %s at x=%.1f" % [f.get_file(), x])
		x += 3.0
	print("PROPS_READY")


func _process(delta: float) -> bool:
	t += delta
	if shots == 0 and t > 0.8:
		_boot()
		shots = 1
		return false
	if shots == 1 and t > 1.2:
		shots = 2
		return false
	if shots == 2 and t > 1.6:
		shots = 3
		cam.position = Vector3(0.0, 6.5, 15.5)
		cam.look_at(Vector3(0.0, 1.6, 0.0), Vector3.UP)
		return false
	if shots == 3 and t > 2.4:
		var img := get_root().get_texture().get_image()
		img.save_png("user://props_sheet.png")
		print("CAPTURED ", ProjectSettings.globalize_path("user://props_sheet.png"),
			" ", img.get_width(), "x", img.get_height())
		# a second, closer pass on the tree only, to judge the silhouette
		cam.position = Vector3(-9.0, 3.0, 8.0)
		cam.look_at(Vector3(-9.0, 2.0, 0.0), Vector3.UP)
		shots = 4
		return false
	if shots == 4 and t > 3.2:
		var img2 := get_root().get_texture().get_image()
		img2.save_png("user://props_tree.png")
		print("CAPTURED ", ProjectSettings.globalize_path("user://props_tree.png"))
		return true
	return false
