extends SceneTree
## Render the hero from inside the ENGINE (gl_compatibility) - this is what the
## game actually draws, unlike a Blender render.
##
## Run: godot --path . --rendering-driver opengl3 --resolution 560x840 \
##        --script res://tools/render_hero.gd
## Must NOT be --headless: headless cannot draw. In this box the GPU comes via
## OpenGL/D3D12, so force the opengl3 driver.
##
## Model axis facts measured on models/hero.glb (tools/probe_axis.gd):
##   * the model's front is -Z: the toes point -Z (Blender +Y) and player.gd
##     drives rotation.y from a -Z forward, so the visual only matches the
##     gameplay facing if the mesh front is -Z.
##   * the atlas face patch (u 0.44..0.56 in the head strip) sampled the +Z side
##     before the fix, i.e. the back of the head.
## Views are named by what they LOOK AT: "front" stands at -Z.

var t := 0.0
var shots := 0
var cam: Camera3D
var _views: Array = []
var _i := 0


func _initialize() -> void:
	var root3 := Node3D.new()
	root.add_child(root3)

	cam = Camera3D.new()
	root3.add_child(cam)
	cam.fov = 32.0

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	light.light_energy = 1.5
	light.light_color = Color(1.0, 0.94, 0.86)
	root3.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, 140.0, 0.0)
	fill.light_energy = 0.5
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
	var mi := _find_mesh(hero)
	if mi != null:
		print("RENDER material=", mi.get_active_material(0),
			" surfaces=", mi.mesh.get_surface_count())
	if anim != null:
		anim.play("Rig|Sword_Idle")
	# camera position, look-at point, output name
	_views = [
		[Vector3(0.0, 1.05, 3.4), Vector3(0.0, 1.0, 0.0), "hero_engine_back.png"],
		[Vector3(0.0, 1.05, -3.4), Vector3(0.0, 1.0, 0.0), "hero_engine_front.png"],
		[Vector3(3.4, 1.05, 0.0), Vector3(0.0, 1.0, 0.0), "hero_engine_side.png"],
		[Vector3(0.05, 1.60, -0.85), Vector3(0.0, 1.60, 0.0), "hero_engine_head.png"],
		[Vector3(1.1, 1.35, -0.75), Vector3(0.55, 1.05, -0.15), "hero_engine_hand.png"],
	]
	print("RENDER_READY")


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null


func _process(delta: float) -> bool:
	t += delta
	if shots == 0 and t > 1.0:
		shots = 1
		_shot()
	elif shots >= 1 and t > 1.0 + 0.45 * float(shots):
		_shot()
	return _i >= _views.size()


func _shot() -> void:
	if _i >= _views.size():
		return
	var v: Array = _views[_i]
	cam.position = v[0]
	cam.look_at(v[1], Vector3.UP)
	var img := get_root().get_texture().get_image()
	var path := "user://" + str(v[2])
	img.save_png(path)
	print("CAPTURED ", ProjectSettings.globalize_path(path))
	_i += 1
	if _i >= _views.size():
		quit()
