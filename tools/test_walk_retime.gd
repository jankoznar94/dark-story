extends SceneTree
## Locomotion retime test: the clip must cover as much ground per second as the
## character actually moves.
##
## It asserts TWO things, and the second one is the one that matters:
##   1. speed_scale * <clip ground speed> == ground speed
##   2. the clip's REAL playback rate (clip seconds per WALL second) == the ratio
##      it should play at, i.e. ground_speed / clip_ground_speed
##
## Why (2) exists: assertion (1) alone passed while the game was broken. `_play()`
## called `anim.play(clip, -1.0, s)` AND `anim.speed_scale = s`, and Godot 4
## MULTIPLIES those two, so every locomotion clip ran at s^2 - the walk at 7.5x and
## the run at 7.0x. speed_scale was correct the whole time, which is why this test
## reported PASS while Jan saw "the animation is extremely fast". A test that reads
## the property you just set is not a test of the thing that moves.
##
## The player's own _physics_process must be OFF for the measurement: the real
## player calls play_idle()/play_locomotion() from inside it every frame, which
## overwrites the very clip the test is sampling. Measured with it left on, every
## sample came back as Rig|Sword_Idle at rate ~0.99 no matter what was asked for.
## With set_physics_process(false) nothing touches the AnimationPlayer between
## samples.
##
## Rate measurement: sample `current_animation_position` over a window short enough
## that the clip cannot loop inside it, and DISCARD any frame the clip wrapped in.
##
## Ground speeds are MEASURED, not guessed: tools/blender/measure_gait.py.
##   Rig|Walk   1.267 m / 1.333 s = 0.951 m/s
##   Rig|Sprint 1.110 m / 0.667 s = 1.666 m/s
##
## Run: godot --headless --path . --script res://tools/test_walk_retime.gd

const RATE_TOLERANCE := 0.12


func _init() -> void:
	call_deferred("_run")


## clip seconds per wall second, wrapping-safe
func _measure_rate(anim: AnimationPlayer) -> float:
	for i in 4:
		await process_frame
	var prev: float = anim.current_animation_position
	var t_prev: int = Time.get_ticks_usec()
	var moved := 0.0
	var elapsed := 0.0
	for i in 10:
		await process_frame
		var p: float = anim.current_animation_position
		var t: int = Time.get_ticks_usec()
		var d: float = p - prev
		if d >= 0.0:                      # drop the frame the clip wrapped in
			moved += d
			elapsed += float(t - t_prev) / 1000000.0
		prev = p
		t_prev = t
	return -1.0 if elapsed <= 0.0 else moved / elapsed


func _run() -> void:
	var ps: PackedScene = load("res://scenes/player.tscn")
	var player: Node = ps.instantiate()
	root.add_child(player)
	await process_frame
	await process_frame
	var h: Node3D = player.get_node("Hero")
	if h.anim == null:
		print("NO ANIMATION PLAYER - abort")
		quit()
		return
	# take the player out of the loop: its _physics_process drives the animation
	# every frame and would overwrite whatever this test just asked for.
	player.set_physics_process(false)
	var ok := true

	print("== WALK: retime scale AND real clip rate ==")
	for gs in [0.5, 0.951, 1.5, 2.6]:
		h.play_locomotion(gs, false)
		var got: float = h.anim.speed_scale
		var implied: float = got * h.WALK_GROUND_SPEED
		var err: float = abs(implied - gs)
		var want_rate: float = gs / h.WALK_GROUND_SPEED
		var rate: float = await _measure_rate(h.anim)
		var rate_err: float = abs(rate - want_rate)
		var clip_ok: bool = h.current_clip() == h.CLIP_WALK
		var pass_ok: bool = (err < 0.002 and clip_ok
			and rate_err < RATE_TOLERANCE * maxf(0.3, want_rate))
		print("ground %.3f m/s -> %s scale %.3f -> implied %.3f (err %.4f) | RATE want %.3f got %.3f (err %.3f) | %s"
			% [gs, h.current_clip(), got, implied, err, want_rate, rate, rate_err,
			   "OK" if pass_ok else "FAIL"])
		if not pass_ok:
			ok = false

	print("== RUN: retime scale AND real clip rate ==")
	for gs in [2.6, 4.4, 5.2]:
		h.play_locomotion(gs, true)
		var got: float = h.anim.speed_scale
		var implied: float = got * h.RUN_GROUND_SPEED
		var err: float = abs(implied - gs)
		var want_rate: float = gs / h.RUN_GROUND_SPEED
		var rate: float = await _measure_rate(h.anim)
		var rate_err: float = abs(rate - want_rate)
		var clip_ok: bool = h.current_clip() == h.CLIP_RUN
		var pass_ok: bool = (err < 0.002 and clip_ok
			and rate_err < RATE_TOLERANCE * maxf(0.3, want_rate))
		print("ground %.3f m/s -> %s scale %.3f -> implied %.3f (err %.4f) | RATE want %.3f got %.3f (err %.3f) | %s"
			% [gs, h.current_clip(), got, implied, err, want_rate, rate, rate_err,
			   "OK" if pass_ok else "FAIL"])
		if not pass_ok:
			ok = false

	# the walk -> run SWITCH is the case Jan reported: it must not spike the rate
	print("== the walk -> run switch (Jan's report) ==")
	h.play_locomotion(2.6, false)
	await _measure_rate(h.anim)
	h.play_locomotion(4.4, true)
	var switch_rate: float = await _measure_rate(h.anim)
	var want_switch: float = 4.4 / h.RUN_GROUND_SPEED
	var sw_ok: bool = abs(switch_rate - want_switch) < RATE_TOLERANCE * maxf(0.3, want_switch)
	print("switch to run: RATE want %.3f got %.3f | %s"
		% [want_switch, switch_rate, "OK" if sw_ok else "FAIL"])
	if not sw_ok:
		ok = false

	# the idle must not be retimed, and the walk must come down from a run rate
	h.play_idle()
	var idle_ok: bool = abs(h.anim.speed_scale - 1.0) < 1e-6 and h.current_clip() == h.CLIP_IDLE
	print("idle after a run: clip %s speed_scale %.3f (must be 1.0) | %s"
		% [h.current_clip(), h.anim.speed_scale, "OK" if idle_ok else "FAIL"])
	if not idle_ok:
		ok = false
	var idle_rate: float = await _measure_rate(h.anim)
	var idle_rate_ok: bool = abs(idle_rate - 1.0) < RATE_TOLERANCE
	print("idle real clip rate %.3f (must be ~1.0) | %s"
		% [idle_rate, "OK" if idle_rate_ok else "FAIL"])
	if not idle_rate_ok:
		ok = false

	# walk and run must be DIFFERENT clips (that is the whole "he can only walk now")
	var dist: bool = h.CLIP_WALK != h.CLIP_RUN
	print("walk and run are different clips: %s vs %s | %s"
		% [h.CLIP_WALK, h.CLIP_RUN, "OK" if dist else "FAIL"])
	if not dist:
		ok = false

	print("LOCOMOTION_RETIME_ALL_PASS=%s" % str(ok))
	quit()
