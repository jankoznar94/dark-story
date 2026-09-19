extends SceneTree
## Renders the arena from directly above with a marker over EVERY monster, so the
## composition of the pack can be judged as a SPACE instead of as six coordinates.
## Numbers cannot show "the weak ones are spread around the player and the heavy
## one is down the far lane" - that is a property of the picture.
##
## Run (NOT --headless: headless draws nothing, so the capture is blank):
##   ~/tools/godot/godot4 --path . --rendering-driver opengl3 \
##     --resolution 900x600 --script res://tools/render_pack_topdown.gd
##
## The output path is printed; run it through tools/render_metrics.py --expect-fg
## before believing the frame (a blank capture still prints CAPTURED).

const OUT := "user://pack_topdown.png"
## The camera sits this high so the whole 34 m floor fits in one frame.
const CAM_HEIGHT := 26.0
## Wait this many process frames after moving the camera before reading the
## viewport texture. Reading it in the SAME frame as the camera move returns a
## pure-background image while still reporting success.
const SETTLE_FRAMES := 3

var scene: Node3D
var _frames: int = 0


func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)


func _process(_delta: float) -> bool:
	_frames += 1
	# let the monsters spawn, the level build and the first physics steps settle
	if _frames < 40:
		return false
	_mark_monsters()
	var cam: Camera3D = scene.get_node("Camera")
	cam.set_process(false)
	cam.global_position = Vector3(0, CAM_HEIGHT, 0.02)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	cam.fov = 60.0
	_frames = 0
	call_deferred("_capture")
	return false


## One sphere above each monster. Red marks the fragile kinds, blue the baseline,
## yellow the heavy - so the sheet shows WHICH kind stands where, not just that
## something is there.
func _mark_monsters() -> void:
	for e in scene._enemies:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.55
		sm.height = 1.1
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		match e.monster_name:
			"Ghoul": mat.albedo_color = Color(0.85, 0.20, 0.14)
			"Ravager": mat.albedo_color = Color(0.20, 0.45, 0.85)
			"Brute": mat.albedo_color = Color(0.90, 0.75, 0.20)
			_: mat.albedo_color = Color(0.8, 0.8, 0.8)
		mi.material_override = mat
		mi.position = e.global_position + Vector3(0, 1.7, 0)
		scene.add_child(mi)
		print("MARKER %-16s %-8s %s" % [e.name, e.monster_name, e.global_position])


func _capture() -> void:
	for i in SETTLE_FRAMES:
		await process_frame
	var img: Image = get_root().get_texture().get_image()
	img.save_png(OUT)
	print("CAPTURED ", ProjectSettings.globalize_path(OUT),
		" ", img.get_width(), "x", img.get_height())
	quit()
