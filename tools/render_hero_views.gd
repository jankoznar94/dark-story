extends SceneTree
## Purpose-built views for checking the hero after the texture/face/sword rebuild.
## Front is -Z (tools/render_hero.gd). Run WITHOUT --headless.
##   godot --path . --rendering-driver opengl3 --resolution 720x720 \
##         --script res://tools/render_hero_views.gd
## Each view waits two frames between moving the camera and reading the
## viewport texture: capturing in the same frame as the camera move returned an
## empty image for the first view.

var t := 0.0
var cam: Camera3D
var _views: Array = []
var _i := 0
var _settle := 0


func _initialize() -> void:
	var root3 := Node3D.new()
	root.add_child(root3)

	cam = Camera3D.new()
	root3.add_child(cam)
	cam.fov = 34.0

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, -35.0, 0.0)
	light.light_energy = 1.6
	light.light_color = Color(1.0, 0.94, 0.86)
	root3.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, 150.0, 0.0)
	fill.light_energy = 0.6
	fill.light_color = Color(0.78, 0.82, 1.0)
	root3.add_child(fill)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.045, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.30, 0.28, 0.26)
	env.ambient_light_energy = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)

	var packed: PackedScene = load("res://models/hero.glb")
	var hero: Node = packed.instantiate()
	root3.add_child(hero)
	var anim := _find_anim(hero)
	if anim != null:
		anim.play("Rig|Sword_Idle")

	_views = [
		[Vector3(0.0, 1.60, -1.15), Vector3(0.0, 1.60, 0.0), "chk_face_front.png"],
		[Vector3(0.0, 1.00, -3.3), Vector3(0.0, 1.00, 0.0), "chk_body_front.png"],
		[Vector3(1.9, 1.62, -1.9), Vector3(0.75, 1.36, -0.05), "chk_hand.png"],
		[Vector3(3.3, 1.00, -0.5), Vector3(0.0, 1.00, 0.0), "chk_side.png"],
	]
	print("VIEWS_READY")


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
	if t < 2.0:
		return false
	if _settle == 0:
		var v: Array = _views[_i]
		cam.position = v[0]
		cam.look_at(v[1], Vector3.UP)
		_settle = 1
		return false
	if _settle == 1:
		_settle = 2
		return false
	var img := get_root().get_texture().get_image()
	var path := "user://" + str(_views[_i][2])
	img.save_png(path)
	print("CAPTURED ", ProjectSettings.globalize_path(path), " ", img.get_width(), "x", img.get_height())
	_i += 1
	_settle = 0
	t = 0.0
	return _i >= _views.size()
