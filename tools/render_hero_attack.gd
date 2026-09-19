extends SceneTree
## Render the hero at chosen moments of Rig|Sword_Attack so a stray object
## carried by the attack clip can be located. Run WITHOUT --headless:
##   godot --path . --rendering-driver opengl3 --resolution 640x640 \
##         --script res://tools/render_hero_attack.gd
## The clip is paused and seek()ed per shot - relying on _process timing gave
## whichever frame the capture happened to land on, which is not repeatable.

var t := 0.0
var cam: Camera3D
var anim: AnimationPlayer
var _shots: Array = []
var _i := 0
var _settle := 0
var _pending := -1.0


func _initialize() -> void:
	var root3 := Node3D.new()
	root.add_child(root3)

	cam = Camera3D.new()
	root3.add_child(cam)
	cam.fov = 30.0

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, -35.0, 0.0)
	light.light_energy = 1.7
	light.light_color = Color(1.0, 0.94, 0.86)
	root3.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, 150.0, 0.0)
	fill.light_energy = 0.8
	fill.light_color = Color(0.78, 0.82, 1.0)
	root3.add_child(fill)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.40, 0.38)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)

	root3.add_child(_make_grid())

	var packed: PackedScene = load("res://models/hero.glb")
	var hero: Node = packed.instantiate()
	root3.add_child(hero)
	anim = _find_anim(hero)
	if anim != null:
		anim.play("Rig|Sword_Attack")
		anim.pause()

	# [clip time, camera position, look-at, file]
	_shots = [
		[0.00, Vector3(3.0, 1.5, -0.4), Vector3(0.45, 1.45, 0.0), "atk_t000_side.png"],
		[0.30, Vector3(3.0, 1.5, -0.4), Vector3(0.45, 1.45, 0.0), "atk_t030_side.png"],
		[0.60, Vector3(3.0, 1.5, -0.4), Vector3(0.45, 1.45, 0.0), "atk_t060_side.png"],
		[0.84, Vector3(3.0, 1.5, -0.4), Vector3(0.45, 1.45, 0.0), "atk_t084_side.png"],
		[1.00, Vector3(3.0, 1.5, -0.4), Vector3(0.45, 1.45, 0.0), "atk_t100_side.png"],
		[1.30, Vector3(3.0, 1.5, -0.4), Vector3(0.45, 1.45, 0.0), "atk_t130_side.png"],
		[0.60, Vector3(2.4, 1.5, -2.2), Vector3(0.45, 1.45, 0.0), "atk_t060_tq.png"],
		[0.84, Vector3(2.4, 1.5, -2.2), Vector3(0.45, 1.45, 0.0), "atk_t084_tq.png"],
		[0.60, Vector3(0.0, 1.5, -3.0), Vector3(0.35, 1.45, 0.0), "atk_t060_front.png"],
		[0.60, Vector3(1.5, 1.8, -1.0), Vector3(0.7, 1.35, 0.0), "atk_t060_hand.png"],
		[0.84, Vector3(1.5, 1.8, -1.0), Vector3(0.7, 1.35, 0.0), "atk_t084_hand.png"],
	]
	print("ATK_READY")


func _make_grid() -> Node3D:
	var g := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.40, 0.38, 0.34)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in range(-4, 5):
		var a := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.010, 0.010, 8.0)
		a.mesh = bm
		a.position = Vector3(float(i), 0.0, 0.0)
		a.material_override = mat
		g.add_child(a)
		var b := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(8.0, 0.010, 0.010)
		b.mesh = bm2
		b.position = Vector3(0.0, 0.0, float(i))
		b.material_override = mat
		g.add_child(b)
	return g


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null


func _process(_delta: float) -> bool:
	t += _delta
	if t < 1.5:
		return false
	if _i >= _shots.size():
		quit()
		return true
	if _settle == 0:
		var s: Array = _shots[_i]
		if anim != null:
			anim.pause()
			anim.seek(float(s[0]), true)
		cam.position = s[1]
		cam.look_at(s[2], Vector3.UP)
		print("SHOT %s clip_t=%.2f cam=%s" % [str(s[3]), float(s[0]), str(s[1])])
		_settle = 1
		return false
	if _settle == 1:
		_settle = 2
		return false
	var img := get_root().get_texture().get_image()
	var path := "user://" + str(_shots[_i][3])
	img.save_png(path)
	print("CAPTURED ", ProjectSettings.globalize_path(path))
	_i += 1
	_settle = 0
	t = 1.5
	return false
