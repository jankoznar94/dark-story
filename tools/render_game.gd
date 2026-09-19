extends SceneTree
## Render the ACTUAL GAME SCENE so the world's light and floor can be judged by
## numbers instead of by memory. Two settle frames between camera move and capture.
##   godot --path . --rendering-driver opengl3 --resolution 960x540 \
##         --script res://tools/render_game.gd

var t := 0.0
var scene: Node3D
var cam: Camera3D
var _shots := 0


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	scene = packed.instantiate()
	root.add_child(scene)
	cam = scene.get_node_or_null("Camera")
	# disable the follow so our framing is stable
	if cam:
		cam.set_process(false)
	print("GAME_SCENE_LOADED cam=", cam)


func _process(delta: float) -> bool:
	t += delta
	if t < 2.0:
		return false
	if _shots == 0:
		if cam:
			cam.global_position = Vector3(0, 12.5, 9.0)
			cam.look_at(Vector3(0, 0.6, 0), Vector3.UP)
		_shots = 1
		return false
	if _shots == 1:
		_shots = 2
		return false
	var img := get_root().get_texture().get_image()
	img.save_png("user://game_iso.png")
	print("CAPTURED ", ProjectSettings.globalize_path("user://game_iso.png"),
		" ", img.get_width(), "x", img.get_height())
	return true
