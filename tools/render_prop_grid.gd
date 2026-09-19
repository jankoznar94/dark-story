extends SceneTree
## Render the whole modular prop library to one grid so the sets can be judged
## together. Reads every .obj in assets/props and lays them out in rows of 6.
##   godot --path . --rendering-driver opengl3 --resolution 1500x900 \
##         --script res://tools/render_prop_grid.gd

var t := 0.0
var cam: Camera3D
var root3: Node3D
var rows := 0
var built := false


func _boot() -> void:
	root3 = Node3D.new()
	root.add_child(root3)
	cam = Camera3D.new()
	root3.add_child(cam)
	cam.fov = 34.0

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46.0, -42.0, 0.0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.94, 0.84)
	root3.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-16.0, 145.0, 0.0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.66, 0.72, 0.9)
	root3.add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.30, 0.32, 0.36)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.44, 0.44, 0.46)
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 20)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.26, 0.28, 0.24)
	ground.material_override = gm
	root3.add_child(ground)

	# collect every obj, in a stable order
	var d := DirAccess.open("res://assets/props")
	var names: Array = []
	if d:
		d.list_dir_begin()
		while true:
			var f := d.get_next()
			if f == "":
				break
			if f.ends_with(".obj"):
				names.append(f)
		d.list_dir_end()
	names.sort()
	var COLS := 6
	var SPACING := 3.1
	for i in names.size():
		var mi := MeshInstance3D.new()
		var m = load("res://assets/props/" + names[i])
		if m == null:
			print("GRID_LOAD_FAILED ", names[i])
			continue
		mi.mesh = m
		var col := i % COLS
		var row := i / COLS
		mi.position = Vector3((col - (COLS - 1) / 2.0) * SPACING, 0.0, row * SPACING)
		mi.rotation_degrees = Vector3(0.0, 25.0, 0.0)
		root3.add_child(mi)
		if col == 0:
			print("GRID_ROW_%d starts with %s" % [row, names[i]])
	rows = int(ceil(names.size() / float(COLS)))
	print("GRID_READY items=%d rows=%d" % [names.size(), rows])


func _process(delta: float) -> bool:
	t += delta
	if not built and t > 0.8:
		_boot()
		built = true
		return false
	if not built:
		return false
	if t > 1.4 and t < 1.9:
		return false
	if t >= 1.9 and t < 2.4:
		var mid := (rows - 1) * 3.1 / 2.0
		cam.position = Vector3(0.0, 9.0 + rows * 2.4, 16.0 + rows * 2.6)
		cam.look_at(Vector3(0.0, 0.8, mid), Vector3.UP)
		return false
	if t >= 2.4:
		var img := get_root().get_texture().get_image()
		img.save_png("user://prop_grid.png")
		print("CAPTURED ", ProjectSettings.globalize_path("user://prop_grid.png"),
			" ", img.get_width(), "x", img.get_height())
		return true
	return false
