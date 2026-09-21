extends SceneTree
## Renders JUST the HUD, with the 3D world culled, onto a transparent framebuffer.
## The plate is then alpha-composited over a 2D painted mockup so the result reads
## as a real game screenshot in the new style.
##
##   godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##         --script res://tools/render_hud_plate.gd

const OUT := "/tmp/ds_look"
var t := 0.0
var scene: Node3D
var cam: Camera3D
var _done := false
var _frames := 0


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	scene = packed.instantiate()
	root.add_child(scene)
	cam = scene.get_node_or_null("Camera")
	if cam:
		cam.set_process(false)
	root.transparent_bg = true
	DirAccess.make_dir_recursive_absolute(OUT)


func _process(delta: float) -> bool:
	t += delta
	if t < 1.5:
		return false
	if not _done:
		# cut every 3D visual layer: the HUD is a CanvasLayer and is not affected
		if cam:
			cam.cull_mask = 0
		_done = true
		_frames = 0
		return false
	_frames += 1
	if _frames < 3:
		return false
	var img := get_root().get_texture().get_image()
	img.save_png("%s/hud_plate.png" % OUT)
	print("HUD_PLATE /tmp/ds_look/hud_plate.png %dx%d" % [img.get_width(), img.get_height()])
	return true
