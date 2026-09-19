extends SceneTree
## Check that the locomotion clips are re-timed to the ground speed.
## The animation must cover exactly as much ground per second as the character
## actually moves, i.e. speed_scale * <clip ground speed> == ground speed.
##
## The API changed: hero.gd no longer exposes `walk_speed_scale` (which hung this
## test the first time - the old property read aborted the script BEFORE quit(),
## so the engine sat there instead of failing). It is now
## `play_locomotion(ground_speed, running)` and the clip + its rate are both
## derived inside hero.gd.
##
## Ground speeds are MEASURED, not guessed: tools/blender/measure_gait.py.
##   Rig|Walk   1.267 m / 1.333 s = 0.951 m/s
##   Rig|Sprint 1.110 m / 0.667 s = 1.666 m/s

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# instantiate the real player scene so hero.gd's _ready() runs with a parent
	var ps: PackedScene = load("res://scenes/player.tscn")
	var player: Node = ps.instantiate()
	root.add_child(player)
	var h: Node3D = player.get_node("Hero")
	await process_frame
	await process_frame
	if h.anim == null:
		print("NO ANIMATION PLAYER - abort")
		quit()
		return
	var ok := true

	print("== WALK ==")
	for gs in [0.5, 0.951, 1.5, 2.6]:
		h.play_locomotion(gs, false)
		var got: float = h.anim.speed_scale
		var implied: float = got * h.WALK_GROUND_SPEED
		var err: float = abs(implied - gs)
		var clip_ok: bool = h.current_clip() == h.CLIP_WALK
		print("ground %.3f m/s -> %s speed_scale %.3f -> implied %.3f m/s | error %.4f | %s"
			% [gs, h.current_clip(), got, implied, err,
			   "OK" if (err < 0.002 and clip_ok) else "FAIL"])
		if err >= 0.002 or not clip_ok:
			ok = false

	print("== RUN ==")
	for gs in [2.6, 4.4, 5.2]:
		h.play_locomotion(gs, true)
		var got: float = h.anim.speed_scale
		var implied: float = got * h.RUN_GROUND_SPEED
		var err: float = abs(implied - gs)
		var clip_ok: bool = h.current_clip() == h.CLIP_RUN
		print("ground %.3f m/s -> %s speed_scale %.3f -> implied %.3f m/s | error %.4f | %s"
			% [gs, h.current_clip(), got, implied, err,
			   "OK" if (err < 0.002 and clip_ok) else "FAIL"])
		if err >= 0.002 or not clip_ok:
			ok = false

	# the idle must not be retimed, and the walk must come down from a run rate
	h.play_idle()
	var idle_ok: bool = abs(h.anim.speed_scale - 1.0) < 1e-6 and h.current_clip() == h.CLIP_IDLE
	print("idle after a run: clip %s speed_scale %.3f (must be 1.0) | %s"
		% [h.current_clip(), h.anim.speed_scale, "OK" if idle_ok else "FAIL"])
	if not idle_ok:
		ok = false

	# walk and run must be DIFFERENT clips (that is the whole "he can only walk now")
	var dist: bool = h.CLIP_WALK != h.CLIP_RUN
	print("walk and run are different clips: %s vs %s | %s"
		% [h.CLIP_WALK, h.CLIP_RUN, "OK" if dist else "FAIL"])
	if not dist:
		ok = false

	print("LOCOMOTION_RETIME_ALL_PASS=%s" % str(ok))
	quit()
