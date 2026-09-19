extends SceneTree
## Top-down render of the level, so the whole layout is visible at once and the
## arena can be judged as a playable SPACE rather than from one oblique view.
##   godot --path . --rendering-driver opengl3 --resolution 1000x1000 \
##         --script res://tools/render_level_topdown.gd

var t := 0.0
var cam: Camera3D
var scene: Node3D
var built := false


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	scene = packed.instantiate()
	root.add_child(scene)
	cam = scene.get_node_or_null("Camera")
	if cam:
		cam.set_process(false)
	print("TOPDOWN_READY")


func _process(delta: float) -> bool:
	t += delta
	if not built and t > 0.9:
		_boot()
		built = true
		return false
	if not built:
		return false
	if t > 1.5 and t < 2.0:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 40.0
		cam.position = Vector3(0.0, 40.0, 0.02)
		cam.look_at(Vector3(0, 0, 0), Vector3.UP)
		return false
	if t >= 2.0 and t < 2.5:
		return false
	if t >= 2.5:
		var img := get_root().get_texture().get_image()
		img.save_png("user://level_topdown.png")
		print("CAPTURED ", ProjectSettings.globalize_path("user://level_topdown.png"),
			" ", img.get_width(), "x", img.get_height())
		return true
	return false
