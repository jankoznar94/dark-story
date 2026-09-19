extends SceneTree
## Measure the CLIP's true playback rate (clip-seconds per wall-second) for the
## walk, for a run started from standing, and for a run switched into from a walk.
##
## Jan's report: the run is fine when started from standing, but after switching
## from walk to run it is "extremely accelerated" until he stops and starts again.
##
## The decisive question: is the effective rate `speed_scale` (as intended) or
## `speed_scale^2`? hero.gd calls BOTH `anim.play(clip, -1.0, speed)` (the custom
## speed argument) AND `anim.speed_scale = speed`, and in Godot 4 those are two
## separate multipliers on the AnimationMixer: playback.speed_scale (custom_speed)
## and AnimationMixer.speed_scale. If both apply, every locomotion clip runs at
## speed_scale SQUARED - the walk at 7.5x and the run at 7.0x.
##
## The test also compares the CURRENT code against the corrected form (play at 1.0
## and let speed_scale carry the retime), so the answer is a number, not a theory.
##
## Run: godot --headless --path . --script res://tools/probe_clip_rate.gd

var _pos := 0.0
var _usec := 0


func _init() -> void:
	call_deferred("_run")


func _sync(h: Node) -> void:
	var a: AnimationPlayer = h.anim
	_pos = a.current_animation_position
	_usec = Time.get_ticks_usec()


## clip seconds per wall second since the last _sync()
func _rate(h: Node) -> float:
	var a: AnimationPlayer = h.anim
	var p: float = a.current_animation_position
	var u: int = Time.get_ticks_usec()
	var d: float = p - _pos
	if d < -0.01:
		d += a.current_animation_length
	var dt: float = float(u - _usec) / 1000000.0
	_pos = p
	_usec = u
	if dt <= 0.0:
		return -1.0
	return d / dt


func _settle(n: int) -> void:
	for i in n:
		await process_frame


func _report(tag: String, player: Node, h: Node, expect: float) -> void:
	var a: AnimationPlayer = h.anim
	# average the rate over 40 process frames to kill per-frame jitter
	_sync(h)
	await _settle(40)
	var r := _rate(h)
	print("%-26s clip=%-14s speed_scale=%.3f | measured rate %.3f | expected %.3f | ratio %.2f"
		% [tag, h.current_clip(), a.speed_scale, r, expect, r / maxf(0.0001, expect)])


func _run() -> void:
	var ps: PackedScene = load("res://scenes/player.tscn")
	var player: Node = ps.instantiate()
	root.add_child(player)
	var h: Node3D = player.get_node("Hero")
	await _settle(4)

	print("== A. the code as it ships (play(clip, -1, s) AND speed_scale = s) ==")
	Input.action_press("move_up")
	await _settle(40)
	await _report("walk from standing", player, h, 2.6)
	player.set_run(true)
	await _settle(30)
	await _report("run switched from walk", player, h, 4.4)
	player.set_run(false)
	await _settle(40)
	await _report("walk again (from run)", player, h, 2.6)
	Input.action_release("move_up")
	await _settle(40)
	player.set_run(true)
	Input.action_press("move_up")
	await _settle(60)
	await _report("run from standing", player, h, 4.4)
	Input.action_release("move_up")
	player.set_run(false)
	await _settle(40)

	print("")
	print("== B. the corrected form (play(clip) at 1.0, retime only via speed_scale) ==")
	h.use_custom_speed = false
	Input.action_press("move_up")
	await _settle(40)
	await _report("walk from standing", player, h, 2.6)
	player.set_run(true)
	await _settle(30)
	await _report("run switched from walk", player, h, 4.4)
	player.set_run(false)
	await _settle(40)
	await _report("walk again (from run)", player, h, 2.6)
	Input.action_release("move_up")
	await _settle(40)
	player.set_run(true)
	Input.action_press("move_up")
	await _settle(60)
	await _report("run from standing", player, h, 4.4)
	Input.action_release("move_up")
	player.set_run(false)
	print("PROBE_CLIP_RATE_DONE")
	quit()
