extends SceneTree
## Decides HOW Godot combines AnimationPlayer.play(clip, custom_blend, custom_speed)
## with AnimationPlayer.speed_scale - by measuring, not by reading docs.
##
## Method: measure the clip's true playback rate (clip seconds per WALL second) from
## `current_animation_position` over a window SHORT enough that the clip cannot loop
## inside it, discarding any frame that wrapped. Then run a matrix of
## (custom_speed, speed_scale) and print the rate.
##
##   rate == custom_speed * speed_scale  -> they MULTIPLY (the shipped code then
##                                          double-applies the retime)
##   rate == speed_scale                 -> speed_scale wins, custom_speed is ignored
##   rate == custom_speed                -> custom_speed wins
##
## Run: godot --headless --path . --script res://tools/probe_clip_rate2.gd


func _init() -> void:
	call_deferred("_run")


func _measure(anim: AnimationPlayer, clip: String, cs: float, ss: float) -> float:
	anim.play(clip, -1.0, cs)
	anim.speed_scale = ss
	# let it settle for a few frames, then integrate over a short window
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
		if d >= 0.0:                      # discard the frame the clip wrapped in
			moved += d
			elapsed += float(t - t_prev) / 1000000.0
		prev = p
		t_prev = t
	if elapsed <= 0.0:
		return -1.0
	return moved / elapsed


func _run() -> void:
	var ps: PackedScene = load("res://scenes/player.tscn")
	var player: Node = ps.instantiate()
	root.add_child(player)
	var h: Node3D = player.get_node("Hero")
	for i in 4:
		await process_frame
	var anim: AnimationPlayer = h.anim
	print("clip lengths: %s %.4f s | %s %.4f s"
		% [h.CLIP_WALK, anim.get_animation(h.CLIP_WALK).length,
		   h.CLIP_RUN, anim.get_animation(h.CLIP_RUN).length])
	print("")
	print("%-14s %6s %6s | measured rate | cs*ss | ss    | cs" % ["clip", "cs", "ss"])
	for clip in [h.CLIP_WALK, h.CLIP_RUN]:
		for combo in [[1.0, 1.0], [2.0, 1.0], [1.0, 2.0], [2.0, 3.0], [2.734, 2.734],
					  [1.0, 2.734], [2.734, 1.0]]:
			var cs: float = combo[0]
			var ss: float = combo[1]
			var r: float = await _measure(anim, clip, cs, ss)
			var verdict := "?"
			if absf(r - cs * ss) < 0.15 * maxf(0.5, cs * ss):
				verdict = "cs*ss"
			elif absf(r - ss) < 0.15 * maxf(0.5, ss):
				verdict = "ss"
			elif absf(r - cs) < 0.15 * maxf(0.5, cs):
				verdict = "cs"
			print("%-14s %6.3f %6.3f | %13.3f | %6.3f | %6.3f | %6.3f   -> %s"
				% [clip, cs, ss, r, cs * ss, ss, cs, verdict])
	print("PROBE_CLIP_RATE2_DONE")
	quit()
