extends SceneTree
## Does the MOVE INPUT stay a unit vector at every stick deflection?
##
## Jan's report: "the run speed seems to increase the more I pull the stick to
## the side, but the run speed should be constant."
##
## player.gd does `target_vel = want * current_speed(iv)` with `want` = the RAW
## Input.get_vector() output - it normalises `want` only for `facing`. So if
## get_vector can return a length > 1, the character really does move faster than
## walk_speed/run_speed, and because hero.play_locomotion() re-times the clip to
## the ACTUAL ground speed, the run animation gets faster at the same time.
##
## This presses the four move actions with explicit strengths (which is what a
## virtual joystick does) and prints the resulting length of Input.get_vector.
##
## Run: godot --headless --path . --script res://tools/probe_move_vector.gd

const AXES := ["move_up", "move_down", "move_left", "move_right"]


func _init() -> void:
	call_deferred("_run")


func _release() -> void:
	for a in AXES:
		Input.action_release(a)


func _show(tag: String, presses: Array) -> Vector2:
	_release()
	for p in presses:
		Input.action_press(p[0], p[1])
	var kv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var raw := Vector2(
		Input.get_action_raw_strength("move_right") - Input.get_action_raw_strength("move_left"),
		Input.get_action_raw_strength("move_down") - Input.get_action_raw_strength("move_up"))
	print("%-34s raw len %.3f -> get_vector len %.4f   (x %.3f y %.3f)"
		% [tag, raw.length(), kv.length(), kv.x, kv.y])
	return kv


func _run() -> void:
	var ps: PackedScene = load("res://scenes/player.tscn")
	var player: Node = ps.instantiate()
	root.add_child(player)
	await process_frame
	await process_frame

	print("== Input.get_vector length at various deflections ==")
	_show("straight ahead, full", [["move_up", 1.0]])
	_show("straight ahead, half", [["move_up", 0.5]])
	_show("straight ahead, 0.75", [["move_up", 0.75]])
	_show("sideways, full", [["move_left", 1.0]])
	_show("sideways, 0.75", [["move_left", 0.75]])
	_show("diagonal, full+full", [["move_up", 1.0], ["move_left", 1.0]])
	_show("diagonal, 0.75+0.75", [["move_up", 0.75], ["move_left", 0.75]])
	_show("diagonal, 0.9+0.9", [["move_up", 0.9], ["move_left", 0.9]])
	_show("diagonal, 0.6+0.6", [["move_up", 0.6], ["move_left", 0.6]])
	_show("diagonal, 0.5+0.5", [["move_up", 0.5], ["move_left", 0.5]])
	_show("near-full diagonal 0.95+0.95", [["move_up", 0.95], ["move_left", 0.95]])
	_release()

	print("")
	print("== resulting SPEED and retime scale (run latched) ==")
	player.set_run(true)
	var combo := [["move_up", 1.0], ["move_left", 1.0]]
	_release()
	for p in combo:
		Input.action_press(p[0], p[1])
	for i in 120:
		await physics_frame
	var h: Node = player.get_node("Hero")
	print("full diagonal run : velocity %.3f m/s | clip %s | speed_scale %.3f"
		% [player.velocity.length(), h.current_clip(), h.anim.speed_scale])
	_release()
	for i in 60:
		await physics_frame
	Input.action_press("move_up", 1.0)
	for i in 120:
		await physics_frame
	print("straight run      : velocity %.3f m/s | clip %s | speed_scale %.3f"
		% [player.velocity.length(), h.current_clip(), h.anim.speed_scale])
	_release()
	print("PROBE_MOVE_VECTOR_DONE")
	quit()
